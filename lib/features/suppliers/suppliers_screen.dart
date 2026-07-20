import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:nusa_kasir/core/providers.dart';
import 'package:nusa_kasir/core/config/nusa_config.dart';
import 'package:nusa_kasir/data/database/app_database.dart';
import 'package:nusa_kasir/data/repositories/supplier_repository.dart';
import 'package:nusa_kasir/shared/widgets/nusa_button.dart';
import 'package:nusa_kasir/shared/widgets/nusa_card.dart';
import 'package:nusa_kasir/shared/widgets/nusa_input.dart';
import 'package:nusa_kasir/shared/widgets/screen_scaffold.dart';
import 'package:nusa_kasir/shared/widgets/skeleton_list.dart';
import 'package:nusa_kasir/shared/widgets/empty_state.dart';

class SuppliersScreen extends ConsumerStatefulWidget {
  const SuppliersScreen({super.key});
  @override
  ConsumerState<SuppliersScreen> createState() => _SuppliersScreenState();
}

class _SuppliersScreenState extends ConsumerState<SuppliersScreen> {
  List<Supplier> _list = [];
  bool _loading = true;
  String _query = '';
  final _searchC = TextEditingController();

  @override
  void initState() {
    super.initState();
    _searchC.addListener(() => setState(() => _query = _searchC.text));
    _load();
  }

  @override
  void dispose() {
    _searchC.dispose();
    super.dispose();
  }

  List<Supplier> get _filtered => _query.isEmpty
      ? _list
      : _list.where((s) => s.name.toLowerCase().contains(_query.toLowerCase()) || (s.phone?.contains(_query) ?? false)).toList();

  Future<void> _load() async {
    final repo = SupplierRepository(ref.read(databaseProvider));
    final all = await repo.getSuppliers();
    if (mounted) setState(() { _list = all; _loading = false; });
  }

  void _showForm({Supplier? existing}) {
    final isEdit = existing != null;
    final nameC = TextEditingController(text: existing?.name ?? '');
    final phoneC = TextEditingController(text: existing?.phone ?? '');
    final addrC = TextEditingController(text: existing?.address ?? '');
    final cpC = TextEditingController(text: existing?.contactPerson ?? '');
    final noteC = TextEditingController(text: existing?.note ?? '');

    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(isEdit ? 'Edit Supplier' : 'Tambah Supplier'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              NusaInput('Nama', controller: nameC),
              const SizedBox(height: 12),
              NusaInput('Telepon', controller: phoneC, type: TextInputType.phone),
              const SizedBox(height: 12),
              NusaInput('Alamat', controller: addrC),
              const SizedBox(height: 12),
              NusaInput('Kontak Person', controller: cpC),
              const SizedBox(height: 12),
              NusaInput('Catatan', controller: noteC),
            ],
          ),
        ),
        actions: [
          if (isEdit)
            TextButton(
              onPressed: () {
                Navigator.of(context).pop();
                _confirmDelete(existing);
              },
              child: const Text('Hapus', style: TextStyle(color: Colors.red)),
            ),
          TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Batal')),
          NusaButton(isEdit ? 'Simpan' : 'Tambah', fullWidth: false,
              onPressed: () async {
            final name = nameC.text.trim();
            if (name.isEmpty) return;
            final repo = SupplierRepository(ref.read(databaseProvider));
            if (isEdit) {
              await repo.updateSupplier(existing.id,
                  name: name,
                  phone: phoneC.text.trim(),
                  address: addrC.text.trim(),
                  contactPerson: cpC.text.trim(),
                  note: noteC.text.trim());
            } else {
              await repo.addSupplier(
                name: name,
                phone: phoneC.text.trim(),
                address: addrC.text.trim(),
                contactPerson: cpC.text.trim(),
                note: noteC.text.trim(),
              );
            }
            if (mounted) Navigator.of(context).pop();
            _load();
          }),
        ],
      ),
    );
  }

  void _confirmDelete(Supplier s) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Hapus Supplier'),
        content: Text('Yakin hapus "${s.name}"?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Batal')),
          NusaButton('Hapus', fullWidth: false, onPressed: () async {
            final repo = SupplierRepository(ref.read(databaseProvider));
            await repo.deleteSupplier(s.id);
            if (mounted) Navigator.of(context).pop();
            _load();
          }),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return ScreenScaffold(
      'Supplier',
      Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
            child: TextField(
              controller: _searchC,
              decoration: InputDecoration(
                hintText: 'Cari supplier...',
                prefixIcon: const Icon(Icons.search),
                filled: true,
                fillColor: Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide: BorderSide.none,
                ),
                contentPadding: const EdgeInsets.symmetric(vertical: 0, horizontal: 16),
              ),
            ),
          ),
          Expanded(
            child: _loading
                ? const SkeletonList()
                : _list.isEmpty
                    ? const EmptyState(
                        icon: Icons.local_shipping_outlined,
                        message: 'Belum ada supplier',
                      )
                    : RefreshIndicator(
                        onRefresh: _load,
                        child: _filtered.isEmpty
                            ? ListView(
                                children: const [
                                  SizedBox(height: 80),
                                  EmptyState(
                                    icon: Icons.search_off,
                                    message: 'Supplier tidak ditemukan',
                                  ),
                                ],
                              )
                            : ListView.separated(
                                padding: const EdgeInsets.all(16),
                                itemCount: _filtered.length,
                                separatorBuilder: (_, __) => const SizedBox(height: 12),
                                itemBuilder: (_, i) => _SupplierTile(
                                  supplier: _filtered[i],
                                  onTap: () => _showForm(existing: _filtered[i]),
                                ),
                              ),
                      ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: NusaConfig.primaryColor,
        foregroundColor: Colors.white,
        icon: const Icon(Icons.add),
        label: const Text('Tambah Supplier'),
        onPressed: () => _showForm(),
      ),
    );
  }
}

class _SupplierTile extends StatelessWidget {
  final Supplier supplier;
  final VoidCallback onTap;
  const _SupplierTile({required this.supplier, required this.onTap});

  static const _avatarColors = [Colors.blue, Colors.green, Colors.orange, Colors.purple, Colors.teal];

  Color _avatarColor() => _avatarColors[supplier.name.hashCode.abs() % _avatarColors.length];

  Future<void> _launchPhone(String phone) async {
    final uri = Uri.parse('tel:$phone');
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri);
    }
  }

  Future<void> _launchWhatsApp(String phone) async {
    final clean = phone.replaceAll(RegExp(r'[^0-9+]'), '');
    final uri = Uri.parse('https://wa.me/$clean');
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final hasPhone = supplier.phone != null && supplier.phone!.isNotEmpty;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: NusaCard(
        Row(
          children: [
            CircleAvatar(
              radius: 24,
              backgroundColor: _avatarColor(),
              child: Text(
                supplier.name.isNotEmpty ? supplier.name[0].toUpperCase() : '?',
                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 18),
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(supplier.name,
                      style: const TextStyle(
                          fontSize: 16, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 4),
                  if (hasPhone)
                    Text(supplier.phone!,
                        style: TextStyle(
                            fontSize: 13, color: isDark ? NusaConfig.darkTextSecondary : NusaConfig.textSecondary)),
                  if (supplier.contactPerson != null &&
                      supplier.contactPerson!.isNotEmpty)
                    Text('CP: ${supplier.contactPerson}',
                        style: TextStyle(
                            fontSize: 13, color: isDark ? NusaConfig.darkTextSecondary : NusaConfig.textSecondary)),
                ],
              ),
            ),
            if (hasPhone)
              PopupMenuButton<String>(
                icon: const Icon(Icons.phone_outlined, color: NusaConfig.primaryColor),
                onSelected: (v) {
                  if (v == 'tel') _launchPhone(supplier.phone!);
                  if (v == 'wa') _launchWhatsApp(supplier.phone!);
                },
                itemBuilder: (_) => [
                  const PopupMenuItem(value: 'tel', child: Text('Telepon')),
                  const PopupMenuItem(value: 'wa', child: Text('WhatsApp')),
                ],
              ),
          ],
        ),
      ),
    );
  }
}
