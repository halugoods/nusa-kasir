import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:nusa_kasir/core/providers.dart';
import 'package:nusa_kasir/core/config/nusa_config.dart';
import 'package:nusa_kasir/core/utils/format_rupiah.dart';
import 'package:nusa_kasir/data/database/app_database.dart';
import 'package:nusa_kasir/data/repositories/customer_repository.dart';
import 'package:nusa_kasir/shared/widgets/nusa_button.dart';
import 'package:nusa_kasir/shared/widgets/nusa_card.dart';
import 'package:nusa_kasir/shared/widgets/nusa_input.dart';
import 'package:nusa_kasir/shared/widgets/screen_scaffold.dart';
import 'package:nusa_kasir/shared/widgets/skeleton_list.dart';
import 'package:nusa_kasir/shared/widgets/empty_state.dart';

/// 6 random avatar colors picked from hash of customer name.
const _avatarColors = [
  Color(0xFFE63946),
  Color(0xFF3B82F6),
  Color(0xFF10B981),
  Color(0xFF8B5CF6),
  Color(0xFFF59E0B),
  Color(0xFFEC4899),
];
const _levelFilters = ['Semua', 'Regular', 'Gold', 'Platinum'];

class CustomersScreen extends ConsumerStatefulWidget {
  const CustomersScreen({super.key});
  @override
  ConsumerState<CustomersScreen> createState() => _CustomersScreenState();
}

class _CustomersScreenState extends ConsumerState<CustomersScreen> {
  final _search = TextEditingController();
  List<Customer> _customers = [];
  bool _loading = true;
  String _levelFilter = 'Semua';

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
    var filtered = q.isEmpty
        ? all
        : all.where((c) =>
            c.name.toLowerCase().contains(q) ||
            (c.phone?.toLowerCase().contains(q) ?? false)).toList();
    if (_levelFilter != 'Semua') {
      // Map filter names to DB level values
      final levelKey = _levelFilter == 'Regular' ? 'Silver' : _levelFilter;
      filtered = filtered.where((c) => c.level == levelKey).toList();
    }
    if (mounted) setState(() { _customers = filtered; _loading = false; });
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
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => Padding(
        padding: const EdgeInsets.fromLTRB(24, 16, 24, 40),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40, height: 4,
                decoration: BoxDecoration(
                  color: NusaConfig.dividerColor,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 20),
            Row(
              children: [
                CircleAvatar(
                  radius: 28,
                  backgroundColor: _avatarColor(c.name),
                  child: Text(
                    c.name.isNotEmpty ? c.name[0].toUpperCase() : '?',
                    style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700, color: Colors.white),
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(c.name,
                          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
                      const SizedBox(height: 4),
                      _levelBadge(c.level),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            _detailRow(Icons.phone_outlined, 'Telepon', phone.isEmpty ? '-' : phone),
            _detailRow(Icons.location_on_outlined, 'Alamat', c.address?.isEmpty ?? true ? '-' : c.address!),
            _detailRow(Icons.attach_money, 'Total Belanja', formatRupiah(c.totalSpent)),
            _detailRow(Icons.star_outline, 'Poin', '${c.points}'),
            const SizedBox(height: 20),
            if (phone.isNotEmpty)
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: () => _openWhatsApp(phone),
                  icon: const Icon(Icons.chat, size: 18),
                  label: const Text('Kirim WA'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: const Color(0xFF25D366),
                    side: const BorderSide(color: Color(0xFF25D366)),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _detailRow(IconData icon, String label, String value) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 8),
    child: Row(
      children: [
        Icon(icon, size: 18, color: NusaConfig.textSecondary),
        const SizedBox(width: 10),
        Text('$label: ', style: const TextStyle(fontSize: 14, color: NusaConfig.textSecondary)),
        Expanded(
          child: Text(value, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
        ),
      ],
    ),
  );

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

  Future<void> _deleteCustomer(Customer c) async {
    final repo = CustomerRepository(ref.read(databaseProvider));
    await repo.deleteCustomer(c.id);
    _load();
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
          SizedBox(
            height: 44,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              itemCount: _levelFilters.length,
              separatorBuilder: (_, __) => const SizedBox(width: 8),
              itemBuilder: (_, i) {
                final label = _levelFilters[i];
                final selected = _levelFilter == label;
                return FilterChip(
                  label: Text(label),
                  selected: selected,
                  showCheckmark: false,
                  selectedColor: NusaConfig.primaryColor,
                  labelStyle: TextStyle(
                    color: selected ? Colors.white : NusaConfig.textPrimary,
                    fontWeight: FontWeight.w600,
                  ),
                  backgroundColor: NusaConfig.surfaceColor,
                  onSelected: (_) {
                    setState(() => _levelFilter = label);
                    _load();
                  },
                );
              },
            ),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: _loading
                ? const SkeletonList()
                : _customers.isEmpty
                    ? const EmptyState(
                        icon: Icons.people_outline,
                        message: 'Belum ada pelanggan',
                      )
                    : RefreshIndicator(
                        onRefresh: _load,
                        child: ListView.separated(
                          padding: const EdgeInsets.all(16),
                          itemCount: _customers.length,
                          separatorBuilder: (_, __) => const SizedBox(height: 12),
                          itemBuilder: (_, i) {
                            final c = _customers[i];
                            return Dismissible(
                              key: ValueKey(c.id),
                              direction: DismissDirection.endToStart,
                              background: Container(
                                alignment: Alignment.centerRight,
                                padding: const EdgeInsets.only(right: 20),
                                decoration: BoxDecoration(
                                  color: Colors.red.shade400,
                                  borderRadius: BorderRadius.circular(16),
                                ),
                                child: const Icon(Icons.delete, color: Colors.white),
                              ),
                              confirmDismiss: (_) async {
                                return await showDialog<bool>(
                                  context: context,
                                  builder: (ctx) => AlertDialog(
                                    title: const Text('Hapus Pelanggan'),
                                    content: Text('Hapus "${c.name}"?'),
                                    actions: [
                                      TextButton(
                                        onPressed: () => Navigator.pop(ctx, false),
                                        child: const Text('Batal'),
                                      ),
                                      TextButton(
                                        onPressed: () => Navigator.pop(ctx, true),
                                        child: const Text('Hapus', style: TextStyle(color: Colors.red)),
                                      ),
                                    ],
                                  ),
                                );
                              },
                              onDismissed: (_) => _deleteCustomer(c),
                              child: _CustomerTile(
                                customer: c,
                                onTap: () => _showDetail(c),
                              ),
                            );
                          },
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

Color _avatarColor(String name) {
  final hash = name.runes.fold(0, (a, b) => a + b);
  return _avatarColors[hash % _avatarColors.length];
}

Widget _levelBadge(String level) {
  final displayLevel = level == 'Silver' ? 'Regular' : level;
  final Color color;
  switch (level) {
    case 'Platinum':
      color = Colors.purple;
    case 'Gold':
      color = Colors.amber.shade700;
    default:
      color = Colors.grey;
  }
  return Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
    decoration: BoxDecoration(
      color: color.withOpacity(0.15),
      borderRadius: BorderRadius.circular(12),
    ),
    child: Text(
      displayLevel,
      style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: color),
    ),
  );
}

class _CustomerTile extends StatelessWidget {
  final Customer customer;
  final VoidCallback onTap;
  const _CustomerTile({required this.customer, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: NusaCard(
        Row(
          children: [
            CircleAvatar(
              radius: 24,
              backgroundColor: _avatarColor(customer.name),
              child: Text(
                customer.name.isNotEmpty ? customer.name[0].toUpperCase() : '?',
                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: Colors.white),
              ),
            ),
            const SizedBox(width: 14),
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
            const SizedBox(width: 8),
            _levelBadge(customer.level),
            const SizedBox(width: 4),
            const Icon(Icons.chevron_right, color: NusaConfig.textSecondary),
          ],
        ),
      ),
    );
  }
}
