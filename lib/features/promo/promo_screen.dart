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

  // Track which card's CRUD buttons are slid open
  int? _openCardId;

  @override
  void initState() {
    super.initState();
    _load();
  }

  void _closeOpenCard() {
    if (_openCardId != null) {
      setState(() => _openCardId = null);
    }
  }

  Future<void> _load() async {
    final repo = PromoRepository(ref.read(databaseProvider));
    final all = await repo.getPromos();
    if (mounted) setState(() { _promos = all; _loading = false; });
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
    return ScreenScaffold(
      'Promo',
      _loading
          ? const SkeletonList()
          : GestureDetector(
              // Tap on empty area closes any open card
              onTap: _closeOpenCard,
              behavior: HitTestBehavior.translucent,
              child: _promos.isEmpty
                  ? _buildEmptyState(Theme.of(context).brightness == Brightness.dark)
                  : ListView.separated(
                      padding: const EdgeInsets.all(16),
                      itemCount: _promos.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 12),
                      itemBuilder: (_, i) => _PromoTile(
                        promo: _promos[i],
                        isOpen: _openCardId == _promos[i].id,
                        onTap: () {
                          _closeOpenCard();
                          _showForm(existing: _promos[i]);
                        },
                        onOpen: () => setState(() => _openCardId = _promos[i].id),
                        onClose: _closeOpenCard,
                        onEdit: () {
                          _closeOpenCard();
                          _showForm(existing: _promos[i]);
                        },
                        onDelete: () => _confirmDelete(_promos[i]),
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

  Widget _buildEmptyState(bool isDark) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          const SizedBox(height: 24),
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
            _promos.isEmpty ? 'Belum ada promo' : 'Tidak ada promo',
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

// ────────────────────────────────────────────────────────────────────────────
// Slide-to-reveal promo tile
// ────────────────────────────────────────────────────────────────────────────

class _PromoTile extends StatefulWidget {
  final Promo promo;
  final bool isOpen;
  final VoidCallback onTap;
  final VoidCallback onOpen;
  final VoidCallback onClose;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  const _PromoTile({
    required this.promo,
    required this.isOpen,
    required this.onTap,
    required this.onOpen,
    required this.onClose,
    required this.onEdit,
    required this.onDelete,
  });

  @override
  State<_PromoTile> createState() => _PromoTileState();
}

class _PromoTileState extends State<_PromoTile> with SingleTickerProviderStateMixin {
  static const double _actionWidth = 130; // combined width of edit + delete buttons

  late AnimationController _slideCtrl;
  late Animation<Offset> _slideAnim;

  double _dragStartX = 0;
  double _dragOffset = 0;

  @override
  void initState() {
    super.initState();
    _slideCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 250),
    );
    _slideAnim = Tween<Offset>(
      begin: Offset.zero,
      end: const Offset(-_actionWidth / 200, 0), // normalized to card width via FractionalTranslation
    ).animate(CurvedAnimation(parent: _slideCtrl, curve: Curves.easeOutCubic));
    _slideCtrl.addListener(() {
      if (mounted) setState(() {});
    });
  }

  @override
  void didUpdateWidget(_PromoTile oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isOpen && !oldWidget.isOpen) {
      _slideCtrl.forward();
    } else if (!widget.isOpen && oldWidget.isOpen) {
      _slideCtrl.reverse();
    }
  }

  @override
  void dispose() {
    _slideCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final active = widget.promo.status == 'Aktif';
    final expired = widget.promo.endDate != null &&
        widget.promo.endDate!.isBefore(DateTime.now());
    final quotaUsed = widget.promo.maxUses != null && widget.promo.maxUses! > 0
        ? widget.promo.usedCount / widget.promo.maxUses!
        : -1.0;
    final quotaColor = quotaUsed < 0
        ? NusaConfig.accentGreen
        : quotaUsed < 0.5
            ? NusaConfig.accentGreen
            : quotaUsed < 0.75
                ? Colors.orange
                : Colors.red;

    final translateX = -_actionWidth * _slideCtrl.value;
    final isSlideOpen = _slideCtrl.value > 0.1;

    return Opacity(
      opacity: expired ? 0.55 : 1.0,
      child: SizedBox(
        height: 160, // fixed height to avoid layout jumps
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            // ── Action buttons (behind, revealed on slide) ──
            Positioned(
              right: 0, top: 0, bottom: 0,
              width: _actionWidth,
              child: Row(
                children: [
                  // Edit button
                  Expanded(
                    child: GestureDetector(
                      onTap: isSlideOpen ? widget.onEdit : null,
                      child: Container(
                        decoration: BoxDecoration(
                          color: NusaConfig.primaryColor.withValues(alpha: 0.9),
                          borderRadius: const BorderRadius.only(
                            topRight: Radius.circular(20),
                            bottomRight: Radius.circular(20),
                          ),
                        ),
                        child: const Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.edit_rounded, color: Colors.white, size: 22),
                            SizedBox(height: 4),
                            Text('Edit',
                                style: TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w600)),
                          ],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                  // Delete button
                  Expanded(
                    child: GestureDetector(
                      onTap: isSlideOpen ? widget.onDelete : null,
                      child: Container(
                        decoration: BoxDecoration(
                          color: Colors.red.withValues(alpha: 0.85),
                          borderRadius: const BorderRadius.only(
                            topRight: Radius.circular(20),
                            bottomRight: Radius.circular(20),
                          ),
                        ),
                        child: const Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.delete_rounded, color: Colors.white, size: 22),
                            SizedBox(height: 4),
                            Text('Hapus',
                                style: TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w600)),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),

            // ── Sliding card ──
            AnimatedContainer(
              duration: const Duration(milliseconds: 250),
              curve: Curves.easeOutCubic,
              transform: Matrix4.translationValues(
                // When animated open: slide left to reveal actions
                // When dragged: use drag offset
                _slideCtrl.isAnimating || widget.isOpen
                    ? -_actionWidth * _slideCtrl.value
                    : _dragOffset,
                0, 0,
              ),
              child: GestureDetector(
                onHorizontalDragStart: (details) {
                  _dragStartX = details.localPosition.dx;
                  _dragOffset = widget.isOpen || isSlideOpen ? -_actionWidth : 0;
                },
                onHorizontalDragUpdate: (details) {
                  final newOffset = _dragOffset + details.localPosition.dx - _dragStartX;
                  // Clamp: 0 (closed) to -_actionWidth (fully open)
                  _dragOffset = newOffset.clamp(-_actionWidth, 0.0);
                  _dragStartX = details.localPosition.dx;
                  setState(() {});
                },
                onHorizontalDragEnd: (details) {
                  // Snap: if dragged past halfway, open; else close
                  final shouldOpen = _dragOffset < -_actionWidth * 0.35;
                  if (shouldOpen) {
                    _dragOffset = 0; // reset drag, let controller animate
                    widget.onOpen();
                  } else {
                    _dragOffset = 0;
                    widget.onClose();
                    setState(() {});
                  }
                },
                onTap: widget.onTap,
                child: _buildCard(isDark, active, expired, quotaUsed, quotaColor),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCard(bool isDark, bool active, bool expired, double quotaUsed, Color quotaColor) {
    final textPri = isDark ? NusaConfig.darkTextPrimary : NusaConfig.textPrimary;
    final textSec = isDark ? NusaConfig.darkTextSecondary : NusaConfig.textSecondary;
    final textTer = isDark ? NusaConfig.darkTextTertiary : NusaConfig.textTertiary;
    final surf = isDark ? NusaConfig.darkSurface : Colors.white;
    final borderClr = isDark ? NusaConfig.darkBorder : NusaConfig.borderColor;

    return Container(
      decoration: BoxDecoration(
        color: surf,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: borderClr),
        boxShadow: [
          BoxShadow(
            color: isDark ? Colors.transparent : Colors.black.withValues(alpha: 0.05),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Row 1: Icon + Name + Discount badge ──
          Row(children: [
            Container(
              width: 36, height: 36,
              decoration: BoxDecoration(
                color: active && !expired
                    ? NusaConfig.accentGreen.withValues(alpha: 0.12)
                    : Colors.grey.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(Icons.local_offer,
                  size: 18,
                  color: active && !expired ? NusaConfig.accentGreen : Colors.grey),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(widget.promo.name,
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: textPri),
                  maxLines: 1, overflow: TextOverflow.ellipsis),
            ),
            const SizedBox(width: 8),
            // Discount value badge
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: NusaConfig.primaryColor.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                widget.promo.type == 'persen'
                    ? '${widget.promo.value}%'
                    : formatRupiah(widget.promo.value),
                style: const TextStyle(
                    fontSize: 14, fontWeight: FontWeight.w800, color: NusaConfig.primaryColor),
              ),
            ),
          ]),

          const SizedBox(height: 10),

          // ── Row 2: Code card-in-card ──
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: isDark ? NusaConfig.darkSurface2 : Colors.grey.shade50,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: isDark ? NusaConfig.darkBorder : Colors.grey.shade200,
              ),
            ),
            child: Row(children: [
              Icon(Icons.code, size: 14, color: textTer),
              const SizedBox(width: 6),
              Expanded(
                child: Text(widget.promo.code,
                    style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        fontFamily: 'monospace',
                        letterSpacing: 1.2,
                        color: textPri)),
              ),
              GestureDetector(
                onTap: () {
                  Clipboard.setData(ClipboardData(text: widget.promo.code));
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('Kode "${widget.promo.code}" disalin'),
                      behavior: SnackBarBehavior.floating,
                      duration: const Duration(seconds: 1),
                      width: 280,
                    ),
                  );
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: NusaConfig.primaryColor.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.copy, size: 13, color: NusaConfig.primaryColor),
                      const SizedBox(width: 3),
                      Text('Salin',
                          style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: NusaConfig.primaryColor)),
                    ],
                  ),
                ),
              ),
            ]),
          ),

          const SizedBox(height: 10),

          // ── Row 3: Details ──
          Row(children: [
            Icon(Icons.shopping_cart_outlined, size: 13, color: textTer),
            const SizedBox(width: 4),
            Text('Min ${formatRupiah(widget.promo.minBelanja)}',
                style: TextStyle(fontSize: 12, color: textSec)),
            const SizedBox(width: 12),
            Icon(Icons.calendar_today_outlined, size: 13, color: textTer),
            const SizedBox(width: 4),
            Expanded(
              child: Text('${_fmtDate(widget.promo.startDate)} – ${_fmtDate(widget.promo.endDate)}',
                  style: TextStyle(fontSize: 12, color: textSec),
                  maxLines: 1, overflow: TextOverflow.ellipsis),
            ),
          ]),

          const SizedBox(height: 6),

          // ── Row 4: Quota bar ──
          Row(children: [
            Text('Kuota: ${widget.promo.maxUses == null ? 'Tanpa batas' : '${widget.promo.usedCount}/${widget.promo.maxUses}'}',
                style: TextStyle(fontSize: 11, color: textTer)),
            if (quotaUsed >= 0) ...[
              const SizedBox(width: 8),
              Expanded(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(3),
                  child: LinearProgressIndicator(
                    value: quotaUsed.clamp(0.0, 1.0),
                    backgroundColor: quotaColor.withValues(alpha: 0.15),
                    valueColor: AlwaysStoppedAnimation(quotaColor),
                    minHeight: 4,
                  ),
                ),
              ),
            ],
          ]),

          const Spacer(),

          // ── Hint: slide left for actions ──
          Align(
            alignment: Alignment.centerRight,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('Geser untuk edit/hapus',
                    style: TextStyle(fontSize: 10, color: textTer.withValues(alpha: 0.5))),
                const SizedBox(width: 2),
                Icon(Icons.chevron_left, size: 12, color: textTer.withValues(alpha: 0.5)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

String _discountLabel(Promo p) =>
    p.type == 'persen' ? 'Diskon ${p.value}%' : 'Potongan ${formatRupiah(p.value)}';

String _fmtDate(DateTime? d) =>
    d == null ? '-' : '${d.day}/${d.month}/${d.year}';
