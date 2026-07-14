import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nusa_kasir/core/providers.dart';
import 'package:nusa_kasir/core/config/nusa_config.dart';
import 'package:nusa_kasir/core/utils/format_rupiah.dart';
import 'package:nusa_kasir/data/database/app_database.dart';
import 'package:nusa_kasir/data/repositories/promo_repository.dart';
import 'package:nusa_kasir/shared/widgets/nusa_button.dart';
import 'package:nusa_kasir/shared/widgets/nusa_card.dart';
import 'package:nusa_kasir/shared/widgets/nusa_input.dart';
import "package:nusa_kasir/shared/widgets/top_toast.dart";
import 'package:nusa_kasir/shared/widgets/screen_scaffold.dart';
import 'package:nusa_kasir/shared/widgets/skeleton_list.dart';
import 'package:nusa_kasir/shared/widgets/empty_state.dart';

class PromoScreen extends ConsumerStatefulWidget {
  const PromoScreen({super.key});
  @override
  ConsumerState<PromoScreen> createState() => _PromoScreenState();
}

class _PromoScreenState extends ConsumerState<PromoScreen> {
  List<Promo> _promos = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final repo = PromoRepository(ref.read(databaseProvider));
    final all = await repo.getPromos();
    if (mounted) setState(() { _promos = all; _loading = false; });
  }

  Future<void> _toggle(Promo p) async {
    final repo = PromoRepository(ref.read(databaseProvider));
    final next = p.status == 'Aktif' ? 'Nonaktif' : 'Aktif';
    await repo.updateStatus(p.id, next);
    _load();
  }

  Future<void> _delete(Promo p) async {
    final repo = PromoRepository(ref.read(databaseProvider));
    await repo.deletePromo(p.id);
    if (mounted) TopToast.success(context, 'Promo "${p.name}" dihapus');
    _load();
  }

  void _confirmDelete(Promo p) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Hapus Promo'),
        content: Text('Yakin hapus promo "${p.name}"?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Batal')),
          NusaButton('Hapus', fullWidth: false, onPressed: () {
            Navigator.of(context).pop();
            _delete(p);
          }),
        ],
      ),
    );
  }

  void _showForm({Promo? existing}) {
    final isEdit = existing != null;
    final nameC = TextEditingController(text: existing?.name ?? '');
    final codeC = TextEditingController(text: existing?.code ?? '');
    final valueC =
        TextEditingController(text: existing != null ? existing.value.toString() : '');
    final minC = TextEditingController(
        text: existing != null ? existing.minBelanja.toString() : '0');
    final maxC = TextEditingController(
        text: existing?.maxUses?.toString() ?? '');
    String type = existing?.type ?? 'persen';
    DateTime? start = existing?.startDate;
    DateTime? end = existing?.endDate;

    Future<void> pickDate(StateSetter setSt, bool isStart) async {
      final picked = await showDatePicker(
        context: context,
        initialDate: (isStart ? start : end) ?? DateTime.now(),
        firstDate: DateTime(2020),
        lastDate: DateTime(2035),
      );
      if (picked != null) {
        setSt(() => isStart ? start = picked : end = picked);
      }
    }

    showDialog(
      context: context,
      builder: (_) => StatefulBuilder(
        builder: (ctx, setSt) => AlertDialog(
          title: Text(isEdit ? 'Edit Promo' : 'Tambah Promo'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                NusaInput('Nama Promo', controller: nameC),
                const SizedBox(height: 12),
                NusaInput('Kode', controller: codeC),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  value: type,
                  decoration: const InputDecoration(
                    labelText: 'Tipe Diskon',
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.all(Radius.circular(14))),
                  ),
                  items: const [
                    DropdownMenuItem(value: 'persen', child: Text('Persen (%)')),
                    DropdownMenuItem(value: 'nominal', child: Text('Nominal (Rp)')),
                  ],
                  onChanged: (v) => setSt(() => type = v!),
                ),
                const SizedBox(height: 12),
                NusaInput(type == 'persen' ? 'Nilai (%)' : 'Nilai (Rp)',
                    controller: valueC, type: TextInputType.number),
                const SizedBox(height: 12),
                NusaInput('Min. Belanja (Rp)',
                    controller: minC, type: TextInputType.number),
                const SizedBox(height: 12),
                NusaInput('Kuota (kosong = tanpa batas)',
                    controller: maxC, type: TextInputType.number),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => pickDate(setSt, true),
                        child: Text('Mulai: ${_fmtDate(start)}'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => pickDate(setSt, false),
                        child: Text('Selesai: ${_fmtDate(end)}'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Batal')),
            if (isEdit)
              TextButton(
                onPressed: () {
                  Navigator.of(context).pop();
                  _confirmDelete(existing);
                },
                child: const Text('Hapus', style: TextStyle(color: Colors.red)),
              ),
            NusaButton(isEdit ? 'Simpan' : 'Tambah', fullWidth: false,
                onPressed: () async {
              final name = nameC.text.trim();
              final code = codeC.text.trim();
              final value = int.tryParse(valueC.text.trim());
              if (name.isEmpty) {
                TopToast.error(context, 'Nama promo wajib diisi');
                return;
              }
              if (code.isEmpty) {
                TopToast.error(context, 'Kode promo wajib diisi');
                return;
              }
              if (value == null) {
                TopToast.error(context, 'Nilai diskon wajib diisi');
                return;
              }
              final repo = PromoRepository(ref.read(databaseProvider));
              final min = int.tryParse(minC.text.trim()) ?? 0;
              final max = maxC.text.trim().isEmpty
                  ? null
                  : int.tryParse(maxC.text.trim());
              if (isEdit) {
                await repo.updatePromo(existing.id,
                    name: name,
                    code: code,
                    type: type,
                    value: value,
                    minBelanja: min,
                    startDate: start,
                    endDate: end,
                    maxUses: max);
              } else {
                await repo.addPromo(
                  name: name,
                  code: code,
                  type: type,
                  value: value,
                  minBelanja: min,
                  startDate: start,
                  endDate: end,
                  maxUses: max,
                );
              }
              if (mounted) Navigator.of(context).pop();
              _load();
            }),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ScreenScaffold(
      'Promo',
      _loading
          ? const SkeletonList()
          : _promos.isEmpty
              ? const EmptyState(
                  icon: Icons.local_offer_outlined,
                  message: 'Belum ada promo',
                )
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView.separated(
                    padding: const EdgeInsets.all(16),
                    itemCount: _promos.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 12),
                    itemBuilder: (_, i) => _PromoTile(
                      promo: _promos[i],
                      onTap: () => _showForm(existing: _promos[i]),
                      onToggle: () => _toggle(_promos[i]),
                    ),
                  ),
                ),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: NusaConfig.primaryColor,
        foregroundColor: Colors.white,
        icon: const Icon(Icons.add),
        label: const Text('Tambah Promo'),
        onPressed: () => _showForm(),
      ),
    );
  }
}

class _PromoTile extends StatelessWidget {
  final Promo promo;
  final VoidCallback onTap;
  final VoidCallback onToggle;
  const _PromoTile(
      {required this.promo, required this.onTap, required this.onToggle});

  @override
  Widget build(BuildContext context) {
    final active = promo.status == 'Aktif';
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
                  Row(
                    children: [
                      const Text('🏷️ ', style: TextStyle(fontSize: 16)),
                      Expanded(
                        child: Text(promo.name,
                            style: const TextStyle(
                                fontSize: 16, fontWeight: FontWeight.w600)),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(_discountLabel(promo),
                      style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          color: NusaConfig.primaryColor)),
                  const SizedBox(height: 4),
                  Text(
                      'Min. belanja ${formatRupiah(promo.minBelanja)} • Aktif: ${_fmtDate(promo.startDate)}–${_fmtDate(promo.endDate)}',
                      style: const TextStyle(
                          fontSize: 13, color: NusaConfig.textSecondary)),
                  const SizedBox(height: 4),
                  Text('Kuota: ${_quotaLabel(promo)} • Kode: ${promo.code}',
                      style: const TextStyle(
                          fontSize: 12, color: NusaConfig.textSecondary)),
                ],
              ),
            ),
            Switch(
              value: active,
              activeColor: NusaConfig.primaryColor,
              onChanged: (_) => onToggle(),
            ),
          ],
        ),
      ),
    );
  }
}

String _discountLabel(Promo p) =>
    p.type == 'persen' ? 'Diskon ${p.value}%' : 'Potongan ${formatRupiah(p.value)}';

String _fmtDate(DateTime? d) =>
    d == null ? '-' : '${d.day}/${d.month}/${d.year}';

String _quotaLabel(Promo p) =>
    p.maxUses == null ? 'Tanpa batas' : '${p.usedCount}/${p.maxUses}';
