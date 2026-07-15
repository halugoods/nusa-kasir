import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nusa_kasir/core/providers.dart';
import 'package:nusa_kasir/core/config/nusa_config.dart';
import 'package:nusa_kasir/data/database/app_database.dart';
import 'package:nusa_kasir/data/repositories/branch_repository.dart';
import 'package:nusa_kasir/shared/widgets/nusa_button.dart';
import 'package:nusa_kasir/shared/widgets/nusa_card.dart';
import 'package:nusa_kasir/shared/widgets/nusa_input.dart';
import 'package:nusa_kasir/shared/widgets/screen_scaffold.dart';
import 'package:nusa_kasir/shared/widgets/empty_state.dart';

/// Local extended branch info (address/phone/status are not in DB schema).
class _BranchInfo {
  final String address;
  final String phone;
  final String status; // 'Aktif' or 'Tutup'
  const _BranchInfo({required this.address, required this.phone, required this.status});
}

class BranchScreen extends ConsumerStatefulWidget {
  const BranchScreen({super.key});
  @override
  ConsumerState<BranchScreen> createState() => _BranchScreenState();
}

class _BranchScreenState extends ConsumerState<BranchScreen> {
  List<Branche> _list = [];
  bool _loading = true;
  final _searchCtrl = TextEditingController();
  String _query = '';

  // Mock branch info since not in DB
  final _mockInfo = <int, _BranchInfo>{};

  @override
  void initState() {
    super.initState();
    _searchCtrl.addListener(() => setState(() => _query = _searchCtrl.text.toLowerCase()));
    _load();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final repo = BranchRepository(ref.read(databaseProvider));
    final list = await repo.getAll();
    // Generate mock info for each branch that doesn't have one
    final rng = Random(42);
    for (final b in list) {
      _mockInfo.putIfAbsent(b.id, () {
        final streets = ['Jl. Merdeka No.${b.id * 7}', 'Jl. Sudirman No.${b.id * 3 + 2}', 'Jl. Ahmad Yani No.${b.id * 5}'];
        final phones = ['08${100000000 + b.id * 123456}'];
        final status = rng.nextDouble() > 0.25 ? 'Aktif' : 'Tutup';
        return _BranchInfo(address: streets[b.id % streets.length], phone: phones[0], status: status);
      });
    }
    if (mounted) setState(() { _list = list; _loading = false; });
  }

  List<Branche> get _filtered => _query.isEmpty
      ? _list
      : _list.where((b) => b.name.toLowerCase().contains(_query)).toList();

  void _showForm({Branche? existing}) {
    final isEdit = existing != null;
    final info = existing != null ? _mockInfo[existing.id] : null;
    final ctrl = TextEditingController(text: existing?.name ?? '');
    final addrCtrl = TextEditingController(text: info?.address ?? '');
    final phoneCtrl = TextEditingController(text: info?.phone ?? '');

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(isEdit ? 'Edit Cabang' : 'Tambah Cabang'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              NusaInput('Nama cabang', controller: ctrl),
              const SizedBox(height: 12),
              NusaInput('Alamat', controller: addrCtrl),
              const SizedBox(height: 12),
              NusaInput('Telepon', controller: phoneCtrl, type: TextInputType.phone),
            ],
          ),
        ),
        actions: [
          if (isEdit)
            TextButton(
              onPressed: () {
                Navigator.of(ctx).pop();
                _confirmDelete(existing);
              },
              child: const Text('Hapus', style: TextStyle(color: Colors.red)),
            ),
          TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('Batal')),
          NusaButton(isEdit ? 'Simpan' : 'Tambah', fullWidth: false,
              onPressed: () async {
                final name = ctrl.text.trim();
                if (name.isEmpty) return;
                final repo = BranchRepository(ref.read(databaseProvider));
                if (isEdit) {
                  await repo.update(existing.id, name);
                  _mockInfo[existing.id] = _BranchInfo(
                    address: addrCtrl.text.trim(),
                    phone: phoneCtrl.text.trim(),
                    status: _mockInfo[existing.id]?.status ?? 'Aktif',
                  );
                } else {
                  final id = await repo.add(name);
                  _mockInfo[id] = _BranchInfo(
                    address: addrCtrl.text.trim(),
                    phone: phoneCtrl.text.trim(),
                    status: 'Aktif',
                  );
                }
                Navigator.of(ctx).pop();
                _load();
              }),
        ],
      ),
    );
  }

  void _confirmDelete(Branche b) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Hapus Cabang'),
        content: Text('Hapus "${b.name}"?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('Batal')),
          TextButton(
            onPressed: () async {
              await BranchRepository(ref.read(databaseProvider)).delete(b.id);
              _mockInfo.remove(b.id);
              Navigator.of(ctx).pop();
              _load();
            },
            child: const Text('Hapus', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final filtered = _filtered;
    return ScreenScaffold(
      'Cabang',
      Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: TextField(
              controller: _searchCtrl,
              decoration: InputDecoration(
                hintText: 'Cari cabang...',
                prefixIcon: const Icon(Icons.search, color: NusaConfig.textSecondary),
                filled: true,
                fillColor: Theme.of(context).brightness == Brightness.dark
                    ? NusaConfig.darkSurface
                    : NusaConfig.surfaceColor,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: BorderSide.none,
                ),
                contentPadding: const EdgeInsets.symmetric(vertical: 14),
              ),
            ),
          ),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : filtered.isEmpty
                    ? const EmptyState(
                        icon: Icons.storefront_outlined,
                        message: 'Belum ada cabang',
                      )
                    : RefreshIndicator(
                        onRefresh: _load,
                        child: ListView.separated(
                          padding: const EdgeInsets.all(16),
                          itemCount: filtered.length,
                          separatorBuilder: (_, __) => const SizedBox(height: 12),
                          itemBuilder: (_, i) {
                            final b = filtered[i];
                            final info = _mockInfo[b.id];
                            final isActive = info?.status == 'Aktif';
                            return GestureDetector(
                              onTap: () => _showForm(existing: b),
                              child: Container(
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(16),
                                  border: const Border(
                                    left: BorderSide(
                                      color: NusaConfig.accentPurple,
                                      width: 4,
                                    ),
                                  ),
                                ),
                                child: NusaCard(
                                  Row(
                                    children: [
                                      Container(
                                        width: 44,
                                        height: 44,
                                        decoration: BoxDecoration(
                                          color: NusaConfig.accentPurple.withValues(alpha: 0.12),
                                          borderRadius: BorderRadius.circular(12),
                                        ),
                                        child: const Icon(
                                          Icons.storefront,
                                          color: NusaConfig.accentPurple,
                                          size: 22,
                                        ),
                                      ),
                                      const SizedBox(width: 14),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Text(b.name,
                                                style: const TextStyle(
                                                    fontSize: 16, fontWeight: FontWeight.w600)),
                                            if (info != null) ...[
                                              const SizedBox(height: 4),
                                              Text(info.address,
                                                  style: const TextStyle(
                                                      fontSize: 13, color: NusaConfig.textSecondary)),
                                            ],
                                          ],
                                        ),
                                      ),
                                      if (info != null)
                                        Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                          decoration: BoxDecoration(
                                            color: isActive
                                                ? NusaConfig.accentGreen.withValues(alpha: 0.12)
                                                : NusaConfig.textTertiary.withValues(alpha: 0.15),
                                            borderRadius: BorderRadius.circular(10),
                                          ),
                                          child: Text(
                                            info.status,
                                            style: TextStyle(
                                              fontSize: 12,
                                              fontWeight: FontWeight.w600,
                                              color: isActive ? NusaConfig.accentGreen : NusaConfig.textSecondary,
                                            ),
                                          ),
                                        ),
                                      const SizedBox(width: 4),
                                      const Icon(Icons.chevron_right, color: NusaConfig.textSecondary),
                                    ],
                                  ),
                                ),
                              ),
                            );
                          },
                        ),
                      ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        icon: const Icon(Icons.add),
        label: const Text('Tambah Cabang'),
        onPressed: () => _showForm(),
      ),
    );
  }
}
