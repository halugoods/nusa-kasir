import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nusa_kasir/core/providers.dart';
import 'package:nusa_kasir/data/database/app_database.dart';
import 'package:nusa_kasir/data/repositories/branch_repository.dart';
import 'package:nusa_kasir/shared/widgets/nusa_button.dart';
import 'package:nusa_kasir/shared/widgets/nusa_card.dart';
import 'package:nusa_kasir/shared/widgets/nusa_input.dart';
import 'package:nusa_kasir/shared/widgets/screen_scaffold.dart';

class BranchScreen extends ConsumerStatefulWidget {
  const BranchScreen({super.key});
  @override
  ConsumerState<BranchScreen> createState() => _BranchScreenState();
}

class _BranchScreenState extends ConsumerState<BranchScreen> {
  List<Branche> _list = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final repo = BranchRepository(ref.read(databaseProvider));
    final list = await repo.getAll();
    if (mounted) setState(() { _list = list; _loading = false; });
  }

  void _showForm({Branche? existing}) {
    final isEdit = existing != null;
    final ctrl = TextEditingController(text: existing?.name ?? '');

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(isEdit ? 'Edit Cabang' : 'Tambah Cabang'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            NusaInput('Nama cabang', controller: ctrl),
          ],
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
                } else {
                  await repo.add(name);
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
    return ScreenScaffold(
      'Cabang',
      _loading
          ? const Center(child: CircularProgressIndicator())
          : _list.isEmpty
              ? const Center(
                  child: Text('Belum ada cabang',
                      style: TextStyle(color: Color(0xFF6B7280))))
              : ListView.separated(
                  padding: const EdgeInsets.all(16),
                  itemCount: _list.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 12),
                  itemBuilder: (_, i) {
                    final b = _list[i];
                    return GestureDetector(
                      onTap: () => _showForm(existing: b),
                      child: NusaCard(
                        Row(
                          children: [
                            Expanded(
                              child: Text(b.name,
                                  style: const TextStyle(
                                      fontSize: 16, fontWeight: FontWeight.w600)),
                            ),
                            const Icon(Icons.chevron_right,
                                color: Color(0xFF6B7280)),
                          ],
                        ),
                      ),
                    );
                  },
                ),
      floatingActionButton: FloatingActionButton.extended(
        icon: const Icon(Icons.add),
        label: const Text('Tambah Cabang'),
        onPressed: () => _showForm(),
      ),
    );
  }
}
