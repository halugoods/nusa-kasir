import 'dart:io';

import 'package:drift/drift.dart' hide Column;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:nusa_kasir/core/providers.dart';
import 'package:nusa_kasir/core/config/nusa_config.dart';
import 'package:nusa_kasir/data/database/app_database.dart';
import 'package:nusa_kasir/data/repositories/product_repository.dart';
import 'package:nusa_kasir/shared/widgets/nusa_button.dart';
import 'package:nusa_kasir/shared/widgets/nusa_form_field.dart';
import 'package:nusa_kasir/shared/widgets/nusa_input.dart';
import 'package:nusa_kasir/shared/widgets/top_toast.dart';
import 'package:nusa_kasir/shared/widgets/screen_scaffold.dart';
import 'package:nusa_kasir/shared/widgets/skeleton_list.dart';
import 'package:nusa_kasir/shared/widgets/empty_state.dart';

class StockScreen extends ConsumerStatefulWidget {
  const StockScreen({super.key});
  @override
  ConsumerState<StockScreen> createState() => _StockScreenState();
}

class _StockScreenState extends ConsumerState<StockScreen> {
  List<Product> _products = [];
  List<StockMovement> _movements = [];
  bool _loading = true;
  String _filter = 'all'; // all | in | out

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final db = ref.read(databaseProvider);
    final repo = ProductRepository(db);
    final products = await repo.getProducts();
    final movements = await (db.select(db.stockMovements)
          ..orderBy([
            (t) => OrderingTerm(expression: t.date, mode: OrderingMode.desc)
          ]))
        .get();
    if (mounted) {
      setState(() {
        _products = products;
        _movements = movements;
        _loading = false;
      });
    }
  }

  List<Product> get _lowStock =>
      _products.where((p) => p.stock <= p.minStock).toList();

  List<StockMovement> get _filteredMovements => _filter == 'all'
      ? _movements
      : _movements.where((m) => m.type == _filter).toList();

  // ── Stock adjustment (Masuk / Keluar) ──
  Future<void> _submitAdjust(String mode, int productId, int qty) async {
    final db = ref.read(databaseProvider);
    final repo = ProductRepository(db);
    if (mode == 'out') {
      final product = await repo.byId(productId);
      if (product == null || product.stock < qty) {
        if (mounted) {
          TopToast.error(context,
              'Stok tidak cukup (tersedia: ${product?.stock ?? 0})');
        }
        return;
      }
      await repo.adjustStock(productId, -qty);
      await db.into(db.stockMovements).insert(StockMovementsCompanion.insert(
            productId: productId,
            type: 'out',
            qty: qty,
          ));
      if (mounted) TopToast.success(context, 'Stok berhasil dikurangi');
    } else {
      await repo.adjustStock(productId, qty);
      await db.into(db.stockMovements).insert(StockMovementsCompanion.insert(
            productId: productId,
            type: 'in',
            qty: qty,
          ));
      if (mounted) TopToast.success(context, 'Stok berhasil ditambah');
    }
    await _load();
  }

  void _openAdjustSheet(String mode) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _AdjustSheet(
        mode: mode,
        products: _products,
        onSubmit: _submitAdjust,
      ),
    );
  }

  // ── helpers ──
  static String _initials(String name) {
    if (name.isEmpty) return '??';
    final parts = name.split(' ');
    if (parts.length >= 2) {
      return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
    }
    return name.length >= 2
        ? name.substring(0, 2).toUpperCase()
        : name[0].toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    return ScreenScaffold(
      'Stok',
      _loading ? const SkeletonList() : _buildBody(),
    );
  }

  Widget _buildBody() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final filtered = _filteredMovements;
    final total = _products.length;
    final menipis =
        _products.where((p) => p.stock > 0 && p.stock <= p.minStock).length;
    final habis = _products.where((p) => p.stock <= 0).length;

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // ── Summary tiles ──
          Row(children: [
            Expanded(
              child: _StatTile(
                label: 'Total Produk',
                value: total.toString(),
                color: NusaConfig.primaryColor,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _StatTile(
                label: 'Stok Menipis',
                value: menipis.toString(),
                color: NusaConfig.warning,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _StatTile(
                label: 'Stok Habis',
                value: habis.toString(),
                color: NusaConfig.error,
              ),
            ),
          ]),
          const SizedBox(height: 16),

          // ── Quick actions ──
          Row(children: [
            Expanded(
              child: _QuickAction(
                icon: Icons.add_rounded,
                label: 'Stok Masuk',
                color: NusaConfig.accentGreen,
                onTap: () => _openAdjustSheet('in'),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _QuickAction(
                icon: Icons.remove_rounded,
                label: 'Stok Keluar',
                color: NusaConfig.primaryColor,
                onTap: () => _openAdjustSheet('out'),
              ),
            ),
          ]),
          const SizedBox(height: 24),

          // ── Stok Menipis section ──
          _SectionHeader(
            title: 'Stok Menipis',
            subtitle: _lowStock.isEmpty
                ? 'Semua stok aman'
                : '${_lowStock.length} produk perlu restok',
            icon: Icons.warning_amber_rounded,
          ),
          const SizedBox(height: 12),
          if (_lowStock.isEmpty)
            const EmptyState(
              icon: Icons.inventory_2_outlined,
              message: 'Tidak ada stok menipis',
            )
          else
            ..._lowStock
                .map((p) => Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: _LowStockCard(
                        product: p,
                        onTap: () => context.push('/produk/edit/${p.id}'),
                      ),
                    )),
          const SizedBox(height: 24),

          // ── Aktivitas section ──
          _SectionHeader(
            title: 'Aktivitas Stok',
            icon: Icons.history_rounded,
            trailing: _buildFilterChips(isDark),
          ),
          const SizedBox(height: 12),
          if (filtered.isEmpty)
            const EmptyState(
              icon: Icons.history_rounded,
              message: 'Belum ada riwayat',
            )
          else
            ...filtered.map((m) {
              final name = _nameOf(m.productId);
              return Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: _HistoryCard(movement: m, productName: name),
              );
            }),
          const SizedBox(height: 8),
        ],
      ),
    );
  }

  String _nameOf(int id) {
    final p = _products.where((e) => e.id == id).firstOrNull;
    return p?.name ?? '#$id';
  }

  Widget _buildFilterChips(bool isDark) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _FilterChip(
          label: 'Semua',
          active: _filter == 'all',
          onTap: () => setState(() => _filter = 'all'),
        ),
        const SizedBox(width: 6),
        _FilterChip(
          label: 'Masuk',
          active: _filter == 'in',
          activeColor: NusaConfig.accentGreen,
          onTap: () => setState(() => _filter = 'in'),
        ),
        const SizedBox(width: 6),
        _FilterChip(
          label: 'Keluar',
          active: _filter == 'out',
          activeColor: NusaConfig.primaryColor,
          onTap: () => setState(() => _filter = 'out'),
        ),
      ],
    );
  }
}

// ═══════════════════════════════════════════
//  Summary tile
// ═══════════════════════════════════════════

class _StatTile extends StatelessWidget {
  final String label;
  final String value;
  final Color color;

  const _StatTile(
      {required this.label, required this.value, required this.color});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 12),
      decoration: BoxDecoration(
        color: isDark ? NusaConfig.darkSurface : NusaConfig.surfaceColor,
        borderRadius: BorderRadius.circular(NusaConfig.radiusMD),
        border: Border.all(
            color: isDark ? NusaConfig.darkBorder : NusaConfig.dividerColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(_iconFor(label), size: 16, color: color),
          ),
          const SizedBox(height: 10),
          Text(
            value,
            style: GoogleFonts.plusJakartaSans(
              fontSize: 22,
              fontWeight: FontWeight.w800,
              color: isDark ? NusaConfig.darkTextPrimary : NusaConfig.textPrimary,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w500,
              color: isDark
                  ? NusaConfig.darkTextTertiary
                  : NusaConfig.textTertiary,
            ),
          ),
        ],
      ),
    );
  }

  IconData _iconFor(String label) {
    if (label.contains('Total')) return Icons.inventory_2_outlined;
    if (label.contains('Menipis')) return Icons.warning_amber_rounded;
    return Icons.error_outline_rounded;
  }
}

// ═══════════════════════════════════════════
//  Quick action
// ═══════════════════════════════════════════

class _QuickAction extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  const _QuickAction({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(NusaConfig.radiusMD),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(NusaConfig.radiusMD),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 16),
          decoration: BoxDecoration(
            color: color.withValues(alpha: isDark ? 0.14 : 0.08),
            borderRadius: BorderRadius.circular(NusaConfig.radiusMD),
            border: Border.all(color: color.withValues(alpha: 0.25)),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: color,
                  borderRadius: BorderRadius.circular(9),
                ),
                child: Icon(icon, size: 20, color: Colors.white),
              ),
              const SizedBox(width: 10),
              Text(
                label,
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: color,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════
//  Section header
// ═══════════════════════════════════════════

class _SectionHeader extends StatelessWidget {
  final String title;
  final String? subtitle;
  final IconData icon;
  final Widget? trailing;

  const _SectionHeader({
    required this.title,
    this.subtitle,
    required this.icon,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Row(
      children: [
        Icon(icon, size: 18, color: NusaConfig.primaryColor),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                  color: isDark
                      ? NusaConfig.darkTextPrimary
                      : NusaConfig.textPrimary,
                ),
              ),
              if (subtitle != null)
                Text(
                  subtitle!,
                  style: TextStyle(
                    fontSize: 11,
                    color: isDark
                        ? NusaConfig.darkTextTertiary
                        : NusaConfig.textTertiary,
                  ),
                ),
            ],
          ),
        ),
        if (trailing != null) trailing!,
      ],
    );
  }
}

// ═══════════════════════════════════════════
//  Filter chip
// ═══════════════════════════════════════════

class _FilterChip extends StatelessWidget {
  final String label;
  final bool active;
  final Color activeColor;
  final VoidCallback onTap;

  const _FilterChip({
    required this.label,
    required this.active,
    this.activeColor = NusaConfig.primaryColor,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: active
              ? activeColor
              : (isDark
                  ? NusaConfig.darkSurface2
                  : NusaConfig.inputFill),
          borderRadius: BorderRadius.circular(NusaConfig.radiusFull),
          border: active
              ? null
              : Border.all(
                  color: isDark
                      ? NusaConfig.darkBorder
                      : NusaConfig.dividerColor),
        ),
        child: Text(
          label,
          style: GoogleFonts.plusJakartaSans(
            fontSize: 12,
            fontWeight: FontWeight.w700,
            color: active
                ? Colors.white
                : (isDark
                    ? NusaConfig.darkTextSecondary
                    : NusaConfig.textSecondary),
          ),
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════
//  Low stock card
// ═══════════════════════════════════════════

class _LowStockCard extends StatelessWidget {
  final Product product;
  final VoidCallback onTap;

  const _LowStockCard({required this.product, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final outOfStock = product.stock <= 0;
    final hasImage = product.imagePath != null &&
        product.imagePath!.isNotEmpty &&
        File(product.imagePath!).existsSync();
    final gradient = NusaConfig.catGradientFor(product.category);

    final ratio = product.minStock > 0
        ? (product.stock / product.minStock).clamp(0.0, 1.5)
        : 0.0;
    final barColor = ratio < 0.25
        ? Colors.red
        : ratio < 0.5
            ? Colors.orange
            : ratio < 1.0
                ? Colors.amber
                : NusaConfig.accentGreen;

    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(NusaConfig.radiusLG),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(NusaConfig.radiusLG),
        child: Container(
          decoration: BoxDecoration(
            color: isDark ? NusaConfig.darkSurface : NusaConfig.surfaceColor,
            borderRadius: BorderRadius.circular(NusaConfig.radiusLG),
            border: Border.all(
                color: isDark ? NusaConfig.darkBorder : NusaConfig.dividerColor),
            boxShadow: [
              BoxShadow(
                  color: Colors.black.withValues(
                      alpha: isDark ? 0.15 : 0.06),
                  blurRadius: 10,
                  offset: const Offset(0, 3))
            ],
          ),
          padding: const EdgeInsets.all(10),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              // ── Thumbnail ──
              ClipRRect(
                borderRadius: BorderRadius.circular(NusaConfig.radiusSM),
                child: SizedBox(
                  width: 72,
                  height: 72,
                  child: Stack(children: [
                    if (hasImage)
                      Image.file(File(product.imagePath!),
                          fit: BoxFit.cover, width: 72, height: 72)
                    else
                      Container(
                        decoration: BoxDecoration(
                            gradient: LinearGradient(
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                                colors: gradient)),
                        alignment: Alignment.center,
                        child: Text(
                          _StockScreenState._initials(product.name),
                          style: const TextStyle(
                              fontSize: 22,
                              fontWeight: FontWeight.w800,
                              color: Colors.white,
                              letterSpacing: 0.5),
                        ),
                      ),
                    // Stock badge
                    Positioned(
                      top: 4,
                      left: 4,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: outOfStock
                              ? NusaConfig.stockOut
                              : NusaConfig.surfaceColor
                                  .withValues(alpha: 0.92),
                          borderRadius:
                              BorderRadius.circular(NusaConfig.radiusFull),
                        ),
                        child: Text(
                          outOfStock ? 'Habis' : '${product.stock}x',
                          style: TextStyle(
                              fontSize: 9,
                              fontWeight: FontWeight.w700,
                              color: outOfStock
                                  ? NusaConfig.stockOutText
                                  : NusaConfig.primaryColor),
                        ),
                      ),
                    ),
                    if (outOfStock)
                      Container(color: Colors.white.withValues(alpha: 0.35)),
                  ]),
                ),
              ),
              const SizedBox(width: 12),
              // ── Info ──
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(product.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.plusJakartaSans(
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                            height: 1.2,
                            color: isDark
                                ? NusaConfig.darkTextPrimary
                                : NusaConfig.textPrimary)),
                    const SizedBox(height: 3),
                    Text(product.category,
                        style: TextStyle(
                            fontSize: 11,
                            color: isDark
                                ? NusaConfig.darkTextTertiary
                                : NusaConfig.textTertiary)),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Text(
                          'Stok: ${product.stock}/${product.minStock}',
                          style: GoogleFonts.plusJakartaSans(
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              color: barColor),
                        ),
                        const Spacer(),
                        Icon(Icons.chevron_right,
                            size: 18, color: NusaConfig.textTertiary),
                      ],
                    ),
                    const SizedBox(height: 6),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: LinearProgressIndicator(
                        value: (ratio / 1.5).clamp(0.0, 1.0),
                        backgroundColor: barColor.withValues(alpha: 0.15),
                        valueColor: AlwaysStoppedAnimation(barColor),
                        minHeight: 5,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════
//  History card
// ═══════════════════════════════════════════

class _HistoryCard extends StatelessWidget {
  final StockMovement movement;
  final String productName;

  const _HistoryCard(
      {required this.movement, required this.productName});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final m = movement;
    final isIn = m.type == 'in';
    final accent = isIn ? NusaConfig.accentGreen : NusaConfig.primaryColor;

    final date = m.date;
    final now = DateTime.now();
    String dateStr;
    if (date.year == now.year &&
        date.month == now.month &&
        date.day == now.day) {
      dateStr =
          'Hari ini, ${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
    } else if (date.year == now.year &&
        date.month == now.month &&
        date.day == now.day - 1) {
      dateStr = 'Kemarin';
    } else {
      dateStr = '${date.day}/${date.month}/${date.year}';
    }

    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(NusaConfig.radiusMD),
      child: Container(
        decoration: BoxDecoration(
          color: isDark ? NusaConfig.darkSurface : NusaConfig.surfaceColor,
          borderRadius: BorderRadius.circular(NusaConfig.radiusMD),
          border: Border.all(
              color: isDark ? NusaConfig.darkBorder : NusaConfig.dividerColor),
          boxShadow: [
            BoxShadow(
                color: Colors.black.withValues(alpha: isDark ? 0.15 : 0.04),
                blurRadius: 8,
                offset: const Offset(0, 2))
          ],
        ),
        child: IntrinsicHeight(
          child: Row(children: [
            // ── Left accent bar ──
            Container(
              width: 4,
              decoration: BoxDecoration(
                color: accent,
                borderRadius: BorderRadius.horizontal(
                    left: Radius.circular(NusaConfig.radiusMD)),
              ),
            ),
            // ── Content ──
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 12, 16, 12),
                child: Row(children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(productName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: GoogleFonts.plusJakartaSans(
                                fontSize: 14,
                                fontWeight: FontWeight.w700,
                                height: 1.2,
                                color: isDark
                                    ? NusaConfig.darkTextPrimary
                                    : NusaConfig.textPrimary)),
                        const SizedBox(height: 3),
                        Text(
                          '${isIn ? 'Masuk' : 'Keluar'}  •  $dateStr',
                          style: TextStyle(
                              fontSize: 12,
                              color: isDark
                                  ? NusaConfig.darkTextTertiary
                                  : NusaConfig.textTertiary),
                        ),
                      ],
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(
                      color: accent.withValues(alpha: 0.1),
                      borderRadius:
                          BorderRadius.circular(NusaConfig.radiusSM),
                    ),
                    child: Text(
                      '${isIn ? '+' : '-'}${m.qty}',
                      style: GoogleFonts.plusJakartaSans(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: accent),
                    ),
                  ),
                ]),
              ),
            ),
          ]),
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════
//  Adjust sheet (Stok Masuk / Keluar)
// ═══════════════════════════════════════════

class _AdjustSheet extends StatefulWidget {
  final String mode; // in | out
  final List<Product> products;
  final Future<void> Function(String mode, int productId, int qty) onSubmit;

  const _AdjustSheet({
    required this.mode,
    required this.products,
    required this.onSubmit,
  });

  @override
  State<_AdjustSheet> createState() => _AdjustSheetState();
}

class _AdjustSheetState extends State<_AdjustSheet> {
  int? _selectedId;
  final _qty = TextEditingController();
  bool _saving = false;

  @override
  void dispose() {
    _qty.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final id = _selectedId;
    final n = int.tryParse(_qty.text.trim());
    if (id == null) {
      TopToast.error(context, 'Pilih produk terlebih dahulu');
      return;
    }
    if (n == null || n <= 0) {
      TopToast.error(context, 'Jumlah stok harus lebih dari 0');
      return;
    }
    setState(() => _saving = true);
    await widget.onSubmit(widget.mode, id, n);
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final isIn = widget.mode == 'in';
    final color = isIn ? NusaConfig.accentGreen : NusaConfig.primaryColor;

    return Container(
      decoration: BoxDecoration(
        color: isDark ? NusaConfig.darkSurface : NusaConfig.surfaceColor,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: EdgeInsets.fromLTRB(
        20,
        10,
        20,
        MediaQuery.of(context).viewInsets.bottom + 20,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            margin: const EdgeInsets.symmetric(vertical: 8),
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: NusaConfig.dividerColor,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          Row(children: [
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(
                isIn ? Icons.add_rounded : Icons.remove_rounded,
                color: color,
                size: 20,
              ),
            ),
            const SizedBox(width: 12),
            Text(
              isIn ? 'Stok Masuk' : 'Stok Keluar',
              style: GoogleFonts.plusJakartaSans(
                fontSize: 17,
                fontWeight: FontWeight.w800,
                color: isDark
                    ? NusaConfig.darkTextPrimary
                    : NusaConfig.textPrimary,
              ),
            ),
          ]),
          const SizedBox(height: 18),
          NusaDropdownField<int>(
            label: 'Produk',
            value: _selectedId,
            items: widget.products
                .map((p) => DropdownMenuItem(value: p.id, child: Text(p.name)))
                .toList(),
            onChanged: (v) => setState(() => _selectedId = v),
          ),
          const SizedBox(height: 12),
          NusaInput(
            isIn ? 'Jumlah stok masuk' : 'Jumlah stok keluar',
            controller: _qty,
            type: TextInputType.number,
          ),
          const SizedBox(height: 20),
          NusaButton(
            isIn ? 'Tambah Stok' : 'Kurangi Stok',
            onPressed: _saving ? null : _save,
          ),
          const SizedBox(height: 4),
        ],
      ),
    );
  }
}
