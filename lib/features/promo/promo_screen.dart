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
  String _filter = 'Aktif'; // 'Aktif' | 'Nonaktif' | 'Kadaluarsa'

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

  List<Promo> get _filtered {
    final now = DateTime.now();
    return _promos.where((p) {
      if (_filter == 'Aktif') return p.status == 'Aktif' && (p.endDate == null || p.endDate!.isAfter(now));
      if (_filter == 'Nonaktif') return p.status == 'Nonaktif';
      // Kadaluarsa
      return p.endDate != null && p.endDate!.isBefore(now);
    }).toList();
  }

  int get _activeCount => _promos.where((p) => p.status == 'Aktif' && (p.endDate == null || p.endDate!.isAfter(DateTime.now()))).length;
  int get _inactiveCount => _promos.where((p) => p.status == 'Nonaktif').length;
  int get _expiredCount => _promos.where((p) => p.endDate != null && p.endDate!.isBefore(DateTime.now())).length;
  int get _totalClaims => _promos.fold<int>(0, (sum, p) => sum + p.usedCount);

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
                      NusaInput('Nama Promo', controller: nameC, hint: 'Cth: Diskon Spesial'),
                      const SizedBox(height: 12),
                      NusaInput('Kode', controller: codeC, hint: 'Cth: HEMAT10'),
                      const SizedBox(height: 12),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text('Tipe Diskon',
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                color: isDark ? NusaConfig.darkTextSecondary : NusaConfig.textSecondary,
                              )),
                          const SizedBox(height: 6),
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                            decoration: BoxDecoration(
                              color: isDark ? NusaConfig.darkInputFill : NusaConfig.inputFill,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: isDark ? NusaConfig.darkInputBorder : NusaConfig.inputBorder,
                              ),
                            ),
                            child: DropdownButtonHideUnderline(
                              child: DropdownButton<String>(
                                value: type,
                                isExpanded: true,
                                isDense: true,
                                icon: Icon(Icons.expand_more, size: 20,
                                    color: isDark ? NusaConfig.darkTextSecondary : NusaConfig.textSecondary),
                                style: TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w500,
                                  color: isDark ? NusaConfig.darkTextPrimary : NusaConfig.textPrimary,
                                ),
                                dropdownColor: isDark ? NusaConfig.darkSurface : Colors.white,
                                borderRadius: BorderRadius.circular(14),
                                underline: const SizedBox.shrink(),
                                items: const [
                                  DropdownMenuItem(value: 'persen', child: Text('Persen (%)')),
                                  DropdownMenuItem(value: 'nominal', child: Text('Nominal (Rp)')),
                                ],
                                onChanged: (v) => setSt(() => type = v!),
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      NusaInput(type == 'persen' ? 'Nilai (%)' : 'Nilai (Rp)',
                          controller: valueC, type: TextInputType.number, hint: 'Cth: 10'),
                      const SizedBox(height: 12),
                      NusaInput('Min. Belanja (Rp)',
                          controller: minC, type: TextInputType.number, hint: 'Cth: 50000'),
                      const SizedBox(height: 12),
                      NusaInput('Kuota (kosong = tanpa batas)',
                          controller: maxC, type: TextInputType.number, hint: 'Cth: 100'),
                      const SizedBox(height: 12),
                      Text('Periode Promo',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: isDark ? NusaConfig.darkTextSecondary : NusaConfig.textSecondary,
                          )),
                      const SizedBox(height: 6),
                      GestureDetector(
                        onTap: () async {
                          final picked = await showDateRangePicker(
                            context: ctx,
                            initialDateRange: start != null && end != null
                                ? DateTimeRange(start: start!, end: end!)
                                : null,
                            firstDate: DateTime(2020),
                            lastDate: DateTime(2035),
                            helpText: 'Pilih Periode Promo',
                            cancelText: 'BATAL',
                            confirmText: 'PILIH',
                          );
                          if (picked != null) {
                            setSt(() { start = picked.start; end = picked.end; });
                          }
                        },
                        child: Container(
                          width: double.infinity,
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                          decoration: BoxDecoration(
                            color: isDark ? NusaConfig.darkInputFill : NusaConfig.inputFill,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: isDark ? NusaConfig.darkInputBorder : NusaConfig.inputBorder,
                            ),
                          ),
                          child: Row(
                            children: [
                              Icon(Icons.calendar_today_rounded, size: 18,
                                  color: isDark ? NusaConfig.darkTextSecondary : NusaConfig.textSecondary),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Text(
                                  start != null && end != null
                                      ? '${_fmtDate(start)} – ${_fmtDate(end)}'
                                      : 'Pilih tanggal mulai – selesai',
                                  style: TextStyle(
                                    fontSize: 15,
                                    color: start != null
                                        ? (isDark ? NusaConfig.darkTextPrimary : NusaConfig.textPrimary)
                                        : (isDark ? NusaConfig.darkTextTertiary : NusaConfig.textTertiary),
                                  ),
                                ),
                              ),
                              if (start != null)
                                GestureDetector(
                                  onTap: () => setSt(() { start = null; end = null; }),
                                  child: Icon(Icons.close, size: 18,
                                      color: isDark ? NusaConfig.darkTextTertiary : NusaConfig.textTertiary),
                                ),
                            ],
                          ),
                        ),
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
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return ScreenScaffold(
      'Promo',
      _loading
          ? const SkeletonList()
          : Column(
              children: [
                // ── Stats cards ──
                if (_promos.isNotEmpty) _buildStatsBar(isDark),
                // ── Filter tabs ──
                _buildFilterTabs(isDark),
                // ── Content ──
                Expanded(
                  child: _filtered.isEmpty
                      ? _buildEmptyState(isDark)
                      : RefreshIndicator(
                          onRefresh: _load,
                          child: ListView.separated(
                            padding: const EdgeInsets.all(16),
                            itemCount: _filtered.length,
                            separatorBuilder: (_, __) => const SizedBox(height: 12),
                            itemBuilder: (_, i) => _PromoTile(
                              promo: _filtered[i],
                              onTap: () => _showForm(existing: _filtered[i]),
                              onToggle: () => _toggle(_filtered[i]),
                              onEdit: () => _showForm(existing: _filtered[i]),
                              onDelete: () => _confirmDelete(_filtered[i]),
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
        label: const Text('Tambah Promo'),
        onPressed: () => _showForm(),
      ),
    );
  }

  Widget _buildStatsBar(bool isDark) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      child: Row(
        children: [
          _statCard('Aktif', _activeCount, NusaConfig.accentGreen, isDark),
          const SizedBox(width: 10),
          _statCard('Nonaktif', _inactiveCount, Colors.orange, isDark),
          const SizedBox(width: 10),
          _statCard('Klaim', _totalClaims, NusaConfig.primaryColor, isDark),
        ],
      ),
    );
  }

  Widget _statCard(String label, int value, Color color, bool isDark) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 10),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: color.withValues(alpha: 0.2)),
        ),
        child: Column(
          children: [
            Text('$value',
                style: TextStyle(
                    fontSize: 22, fontWeight: FontWeight.w800, color: color)),
            const SizedBox(height: 2),
            Text(label,
                style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: isDark ? NusaConfig.darkTextSecondary : NusaConfig.textSecondary)),
          ],
        ),
      ),
    );
  }

  Widget _buildFilterTabs(bool isDark) {
    const tabs = [
      ('Aktif', Icons.check_circle_outline),
      ('Nonaktif', Icons.pause_circle_outline),
      ('Kadaluarsa', Icons.event_busy_outlined),
    ];
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
      child: Row(
        children: tabs.map((t) {
          final selected = _filter == t.$1;
          return Expanded(
            child: Padding(
              padding: EdgeInsets.only(right: t.$1 != 'Kadaluarsa' ? 8 : 0),
              child: GestureDetector(
                onTap: () => setState(() => _filter = t.$1),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  decoration: BoxDecoration(
                    color: selected
                        ? NusaConfig.primaryColor.withValues(alpha: isDark ? 0.2 : 0.1)
                        : (isDark ? NusaConfig.darkSurface2 : Colors.grey.shade100),
                    borderRadius: BorderRadius.circular(12),
                    border: selected
                        ? Border.all(color: NusaConfig.primaryColor.withValues(alpha: 0.4))
                        : null,
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(t.$2, size: 14,
                          color: selected
                              ? NusaConfig.primaryColor
                              : (isDark ? NusaConfig.darkTextTertiary : NusaConfig.textTertiary)),
                      const SizedBox(width: 5),
                      Text(t.$1,
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: selected
                                ? NusaConfig.primaryColor
                                : (isDark ? NusaConfig.darkTextSecondary : NusaConfig.textSecondary),
                          )),
                    ],
                  ),
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildEmptyState(bool isDark) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          const SizedBox(height: 24),
          // Illustration icon
          Container(
            width: 80, height: 80,
            decoration: BoxDecoration(
              color: NusaConfig.primaryColor.withValues(alpha: 0.08),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.local_offer_outlined,
                size: 36, color: NusaConfig.primaryColor),
          ),
          const SizedBox(height: 16),
          Text(
            _promos.isEmpty ? 'Belum ada promo' : 'Tidak ada promo $_filter',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: isDark ? NusaConfig.darkTextPrimary : NusaConfig.textPrimary,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            _promos.isEmpty
                ? 'Buat promo pertama untuk menarik pelanggan dengan diskon spesial.'
                : 'Coba ubah filter atau buat promo baru.',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 13,
              color: isDark ? NusaConfig.darkTextSecondary : NusaConfig.textSecondary,
            ),
          ),
          const SizedBox(height: 20),
          if (_promos.isEmpty) ...[
            // Quick templates
            Text('Template Cepat',
                style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: isDark ? NusaConfig.darkTextTertiary : NusaConfig.textTertiary)),
            const SizedBox(height: 10),
            _quickTemplate(isDark, 'Diskon 10%', 'HEMAT10', 'persen', 10, 50000),
            const SizedBox(height: 8),
            _quickTemplate(isDark, 'Potongan 5rb', 'FLASH5', 'nominal', 5000, 30000),
            const SizedBox(height: 8),
            _quickTemplate(isDark, 'Beli 2 Gratis 1', 'B2G1', 'persen', 50, 0),
          ] else ...[
            // Button to add promo
            ElevatedButton.icon(
              onPressed: () => _showForm(),
              icon: const Icon(Icons.add, size: 18),
              label: const Text('Buat Promo Baru'),
              style: ElevatedButton.styleFrom(
                backgroundColor: NusaConfig.primaryColor,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
          ],
          const SizedBox(height: 32),
        ],
      ),
    );
  }

  Widget _quickTemplate(bool isDark, String title, String code, String type, int value, int minBelanja) {
    return GestureDetector(
      onTap: () async {
        final repo = PromoRepository(ref.read(databaseProvider));
        await repo.addPromo(
          name: title, code: code, type: type, value: value,
          minBelanja: minBelanja, maxUses: 100,
        );
        _load();
        if (mounted) TopToast.success(context, 'Promo "$title" dibuat!');
      },
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: isDark ? NusaConfig.darkSurface2 : NusaConfig.surfaceColor,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
              color: isDark ? NusaConfig.darkBorder : NusaConfig.borderColor),
        ),
        child: Row(
          children: [
            Container(
              width: 36, height: 36,
              decoration: BoxDecoration(
                color: NusaConfig.primaryColor.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(Icons.bolt, size: 18, color: NusaConfig.primaryColor),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 2),
                  Text(
                    'Kode: $code • ${type == 'persen' ? '$value%' : formatRupiah(value)} • Min: ${formatRupiah(minBelanja)}',
                    style: TextStyle(
                        fontSize: 11,
                        color: isDark ? NusaConfig.darkTextTertiary : NusaConfig.textTertiary),
                  ),
                ],
              ),
            ),
            Icon(Icons.add_circle_outline, size: 20,
                color: isDark ? NusaConfig.darkTextSecondary : NusaConfig.textSecondary),
          ],
        ),
      ),
    );
  }
}

class _PromoTile extends StatelessWidget {
  final Promo promo;
  final VoidCallback onTap;
  final VoidCallback onToggle;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  const _PromoTile(
      {required this.promo, required this.onTap, required this.onToggle,
      required this.onEdit, required this.onDelete});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
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
                          style: TextStyle(
                              fontSize: 13,
                              color: isDark ? NusaConfig.darkTextSecondary : NusaConfig.textSecondary)),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                    'Kuota: ${_quotaLabel(promo)}',
                                    style: TextStyle(
                                        fontSize: 12,
                                        color: isDark ? NusaConfig.darkTextSecondary : NusaConfig.textSecondary)),
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
                                style: TextStyle(
                                    fontSize: 12,
                                    color: isDark ? NusaConfig.darkTextSecondary : NusaConfig.textSecondary)),
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
                            child: Padding(
                              padding: EdgeInsets.all(4),
                              child: Icon(Icons.copy,
                                  size: 16, color: isDark ? NusaConfig.darkTextSecondary : NusaConfig.textSecondary),
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
                // Edit & Delete action buttons
                Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    InkWell(
                      onTap: onEdit,
                      borderRadius: BorderRadius.circular(8),
                      child: Padding(
                        padding: const EdgeInsets.all(6),
                        child: Icon(Icons.edit_outlined, size: 18,
                            color: isDark ? NusaConfig.darkTextSecondary : NusaConfig.textSecondary),
                      ),
                    ),
                    InkWell(
                      onTap: onDelete,
                      borderRadius: BorderRadius.circular(8),
                      child: Padding(
                        padding: const EdgeInsets.all(6),
                        child: Icon(Icons.delete_outline, size: 18,
                            color: Colors.red.withValues(alpha: isDark ? 0.8 : 0.6)),
                      ),
                    ),
                  ],
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
