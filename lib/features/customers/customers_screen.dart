import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:nusa_kasir/app.dart';
import 'package:nusa_kasir/core/config/nusa_config.dart';
import 'package:nusa_kasir/core/utils/format_rupiah.dart';
import 'package:nusa_kasir/data/database/app_database.dart';
import 'package:nusa_kasir/data/repositories/customer_repository.dart';
import 'package:nusa_kasir/shared/widgets/nusa_button.dart';
import 'package:nusa_kasir/shared/widgets/nusa_card.dart';
import 'package:nusa_kasir/shared/widgets/nusa_input.dart';
import 'package:nusa_kasir/shared/widgets/screen_scaffold.dart';
import 'package:nusa_kasir/shared/widgets/staggered_list.dart';

class CustomersScreen extends ConsumerStatefulWidget {
  const CustomersScreen({super.key});
  @override
  ConsumerState<CustomersScreen> createState() => _CustomersScreenState();
}

class _CustomersScreenState extends ConsumerState<CustomersScreen> {
  final _search = TextEditingController();
  List<Customer> _customers = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _search.addListener(_load);
    _load();
  }

  @override
  void dispose() {
    _search.removeListener(_load);
    _search.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final repo = CustomerRepository(ref.read(databaseProvider));
    final all = await repo.getCustomers();
    final q = _search.text.toLowerCase();
    final filtered = q.isEmpty
        ? all
        : all.where((c) =>
            c.name.toLowerCase().contains(q) ||
            (c.phone?.toLowerCase().contains(q) ?? false)).toList();
    if (mounted) setState(() => _customers = filtered);
  }

  void _showAddDialog() {
    final nameController = TextEditingController();
    final phoneController = TextEditingController();
    final addressController = TextEditingController();
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Tambah Pelanggan'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              NusaInput('Nama', controller: nameController),
              const SizedBox(height: 12),
              NusaInput('Telepon', controller: phoneController, type: TextInputType.phone),
              const SizedBox(height: 12),
              NusaInput('Alamat', controller: addressController),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Batal'),
          ),
          NusaButton(
            'Simpan',
            fullWidth: false,
            onPressed: () async {
              final name = nameController.text.trim();
              if (name.isEmpty) return;
              final repo = CustomerRepository(ref.read(databaseProvider));
              await repo.addCustomer(
                name: name,
                phone: phoneController.text.trim(),
                address: addressController.text.trim(),
              );
              if (mounted) Navigator.of(context).pop();
              _load();
            },
          ),
        ],
      ),
    );
  }

  void _showDetail(Customer c) {
    final phone = c.phone ?? '';
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(c.name),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Telepon: ${phone.isEmpty ? '-' : phone}'),
            const SizedBox(height: 4),
            Text('Alamat: ${c.address?.isEmpty ?? true ? '-' : c.address}'),
            const SizedBox(height: 4),
            Text('Total: ${formatRupiah(c.totalSpent)}'),
            const SizedBox(height: 4),
            Text('Poin: ${c.points}'),
            const SizedBox(height: 4),
            Text('Level: ${c.level}'),
          ],
        ),
        actions: [
          if (phone.isNotEmpty)
            TextButton(
              onPressed: () => _openWhatsApp(phone),
              child: const Text('Kirim WA'),
            ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Tutup'),
          ),
        ],
      ),
    );
  }

  Future<void> _openWhatsApp(String phone) async {
    final digits = phone.replaceAll(RegExp(r'\D'), '');
    final normalized = digits.startsWith('0')
        ? '62${digits.substring(1)}'
        : digits.startsWith('62')
            ? digits
            : '62$digits';
    final uri = Uri.parse('https://wa.me/$normalized');
    if (await canLaunchUrl(uri)) await launchUrl(uri);
  }

  @override
  Widget build(BuildContext context) {
    return ScreenScaffold(
      'Pelanggan',
      Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: NusaInput('Cari pelanggan...',
                controller: _search, type: TextInputType.text),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _customers.isEmpty
                    ? const Center(
                        child: Text('Belum ada pelanggan',
                            style: TextStyle(color: Colors.grey)),
                      )
                    : ListView.separated(
                        padding: const EdgeInsets.all(16),
                        itemCount: _customers.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 12),
                        itemBuilder: (_, i) => _CustomerTile(
                          customer: _customers[i],
                          onTap: () => _showDetail(_customers[i]),
                        ),
                      ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: NusaConfig.primaryColor,
        foregroundColor: Colors.white,
        icon: const Icon(Icons.add),
        label: const Text('Tambah Pelanggan'),
        onPressed: _showAddDialog,
      ),
    );
  }
}

class _CustomerTile extends StatelessWidget {
  final Customer customer;
  final VoidCallback onTap;
  const _CustomerTile({required this.customer, required this.onTap});

  Color _levelColor(String level) {
    switch (level) {
      case 'Platinum':
        return Colors.purple;
      case 'Gold':
        return Colors.amber.shade700;
      default:
        return Colors.grey;
    }
  }

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: NusaCard(
        Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(customer.name,
                      style: const TextStyle(
                          fontSize: 16, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 4),
                  if (customer.phone != null && customer.phone!.isNotEmpty)
                    Text(customer.phone!,
                        style: const TextStyle(
                            fontSize: 13, color: NusaConfig.textSecondary)),
                  const SizedBox(height: 4),
                  Text('Total: ${formatRupiah(customer.totalSpent)}',
                      style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          color: NusaConfig.primaryColor)),
                ],
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: _levelColor(customer.level).withOpacity(0.15),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                customer.level,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: _levelColor(customer.level),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
