import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        final isDark = Theme.of(ctx).brightness == Brightness.dark;
        return StatefulBuilder(
          builder: (ctx, setSt) => Container(
            decoration: BoxDecoration(
              color: isDark ? NusaConfig.darkSurface : NusaConfig.surfaceColor,
              borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
            ),
            padding: EdgeInsets.fromLTRB(
              20, 10, 20,
              MediaQuery.of(ctx).viewInsets.bottom + 20,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Drag handle
                Container(
                  margin: const EdgeInsets.symmetric(vertical: 8),
                  width: 40, height: 4,
                  decoration: BoxDecoration(
                    color: NusaConfig.dividerColor,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                // Header with icon
                Row(children: [
                  Container(
                    width: 38, height: 38,
                    decoration: BoxDecoration(
                      color: NusaConfig.primaryColor.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(Icons.local_offer_outlined,
                        color: NusaConfig.primaryColor, size: 20),
                  ),
                  const SizedBox(width: 12),
                  Text(isEdit ? 'Edit Promo' : 'Tambah Promo',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                        color: isDark ? NusaConfig.darkTextPrimary : NusaConfig.textPrimary,
                      )),
                ]),
                const SizedBox(height: 16),
                // Form content
                SingleChildScrollView(
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
                      const SizedBox(height: 20),
                      // Bottom actions
                      Row(
                        children: [
                          Expanded(
                            child: TextButton(
                              onPressed: () => Navigator.of(ctx).pop(),
                              child: const Text('Batal'),
                            ),
                          ),
                          if (isEdit)
                            TextButton(
                              onPressed: () {
                                Navigator.of(ctx).pop();
                                _confirmDelete(existing);
                              },
                              child: const Text('Hapus', style: TextStyle(color: Colors.red)),
                            ),
                          Expanded(
                            child: NusaButton(
                              isEdit ? 'Simpan' : 'Tambah',
                              fullWidth: false,
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
                                if (mounted) Navigator.of(ctx).pop();
                                _load();
                              },
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
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
    final expired = promo.endDate != null &&
        promo.endDate!.isBefore(DateTime.now());
    final quotaUsed = promo.maxUses != null && promo.maxUses! > 0
        ? promo.usedCount / promo.maxUses!
        : -1.0;
    final quotaColor = quotaUsed < 0
        ? NusaConfig.accentGreen
        : quotaUsed < 0.5
            ? NusaConfig.accentGreen
            : quotaUsed < 0.75
                ? Colors.orange
                : Colors.red;
    return Opacity(
      opacity: expired ? 0.55 : 1.0,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: NusaCard(
          Container(
            decoration: active && !expired
                ? const BoxDecoration(
                    border: Border(
                      left: BorderSide(
                        color: NusaConfig.accentGreen,
                        width: 4,
                      ),
                    ),
                  )
                : null,
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Icon(Icons.local_offer,
                              size: 18, color: NusaConfig.primaryColor),
                          const SizedBox(width: 4),
                          Expanded(
                            child: Text(promo.name,
                                style: const TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w600)),
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
                              fontSize: 13,
                              color: NusaConfig.textSecondary)),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                    'Kuota: ${_quotaLabel(promo)}',
                                    style: const TextStyle(
                                        fontSize: 12,
                                        color: NusaConfig.textSecondary)),
                                if (quotaUsed >= 0) ...[
                                  const SizedBox(height: 4),
                                  ClipRRect(
                                    borderRadius: BorderRadius.circular(3),
                                    child: LinearProgressIndicator(
                                      value: quotaUsed.clamp(0.0, 1.0),
                                      backgroundColor:
                                          quotaColor.withValues(alpha: 0.15),
                                      valueColor:
                                          AlwaysStoppedAnimation(quotaColor),
                                      minHeight: 4,
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          Expanded(
                            child: Text('Kode: ${promo.code}',
                                style: const TextStyle(
                                    fontSize: 12,
                                    color: NusaConfig.textSecondary)),
                          ),
                          InkWell(
                            onTap: () {
                              Clipboard.setData(ClipboardData(text: promo.code));
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text('Kode disalin'),
                                  behavior: SnackBarBehavior.floating,
                                  duration: Duration(seconds: 1),
                                ),
                              );
                            },
                            borderRadius: BorderRadius.circular(8),
                            child: const Padding(
                              padding: EdgeInsets.all(4),
                              child: Icon(Icons.copy,
                                  size: 16, color: NusaConfig.textSecondary),
                            ),
                          ),
                        ],
                      ),
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
