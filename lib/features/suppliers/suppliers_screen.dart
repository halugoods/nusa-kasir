import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nusa_kasir/app.dart';
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

  @override
  void initState() {
    super.initState();
    _load();
  }

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
    return ScreenScaffold(
      'Supplier',
      _loading
          ? const SkeletonList()
          : _list.isEmpty
              ? const EmptyState(
                  icon: Icons.local_shipping_outlined,
                  message: 'Belum ada supplier',
                )
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView.separated(
                    padding: const EdgeInsets.all(16),
                    itemCount: _list.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 12),
                    itemBuilder: (_, i) => _SupplierTile(
                      supplier: _list[i],
                      onTap: () => _showForm(existing: _list[i]),
                    ),
                  ),
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
                  Text(supplier.name,
                      style: const TextStyle(
                          fontSize: 16, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 4),
                  if (supplier.phone != null && supplier.phone!.isNotEmpty)
                    Text(supplier.phone!,
                        style: const TextStyle(
                            fontSize: 13, color: NusaConfig.textSecondary)),
                  if (supplier.contactPerson != null &&
                      supplier.contactPerson!.isNotEmpty)
                    Text('CP: ${supplier.contactPerson}',
                        style: const TextStyle(
                            fontSize: 13, color: NusaConfig.textSecondary)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
