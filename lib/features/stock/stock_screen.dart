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
  int? _inProductId;
  int? _outProductId;
  final _inQty = TextEditingController();
  final _outQty = TextEditingController();
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _inQty.dispose();
    _outQty.dispose();
    super.dispose();
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

  Future<void> _addStock() async {
    if (_inProductId == null) {
      TopToast.error(context, 'Pilih produk terlebih dahulu');
      return;
    }
    final qty = int.tryParse(_inQty.text.trim());
    if (qty == null || qty <= 0) {
      TopToast.error(context, 'Jumlah stok harus lebih dari 0');
      return;
    }
    final db = ref.read(databaseProvider);
    final repo = ProductRepository(db);
    await repo.adjustStock(_inProductId!, qty);
    await db.into(db.stockMovements).insert(StockMovementsCompanion.insert(
          productId: _inProductId!,
          type: 'in',
          qty: qty,
        ));
    _inQty.clear();
    if (mounted) {
      TopToast.success(context, 'Stok berhasil ditambah');
      await _load();
    }
  }

  Future<void> _removeStock() async {
    if (_outProductId == null) {
      TopToast.error(context, 'Pilih produk terlebih dahulu');
      return;
    }
    final qty = int.tryParse(_outQty.text.trim());
    if (qty == null || qty <= 0) {
      TopToast.error(context, 'Jumlah stok harus lebih dari 0');
      return;
    }
    final db = ref.read(databaseProvider);
    final repo = ProductRepository(db);
    final product = await repo.byId(_outProductId!);
    if (product == null || product.stock < qty) {
      TopToast.error(context,
          'Stok tidak cukup (tersedia: ${product?.stock ?? 0})');
      return;
    }
    await repo.adjustStock(_outProductId!, -qty);
    await db.into(db.stockMovements).insert(StockMovementsCompanion.insert(
          productId: _outProductId!,
          type: 'out',
          qty: qty,
        ));
    _outQty.clear();
    if (mounted) {
      TopToast.success(context, 'Stok berhasil dikurangi');
      await _load();
    }
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
      _loading
          ? const SkeletonList()
          : DefaultTabController(
              length: 4,
              child: Column(
                children: [
                  const TabBar(
                    labelColor: NusaConfig.primaryColor,
                    unselectedLabelColor: NusaConfig.textSecondary,
                    indicatorColor: NusaConfig.primaryColor,
                    tabs: const [
                      Tab(icon: Icon(Icons.warning_amber_rounded),
                          text: 'Stok Menipis'),
                      Tab(icon: Icon(Icons.add_circle_outline), text: 'Masuk'),
                      Tab(icon: Icon(Icons.remove_circle_outline),
                          text: 'Keluar'),
                      Tab(icon: Icon(Icons.history), text: 'Riwayat'),
                    ],
                  ),
                  Expanded(
                    child: TabBarView(
                      children: [
                        _LowStockTab(
                            products: _lowStock,
                            onRefresh: _load,
                            onTap: (p) {
                              context.push('/produk/edit/${p.id}');
                            }),
                        _InTab(
                          products: _products,
                          qtyController: _inQty,
                          selectedId: _inProductId,
                          onChanged: (id) =>
                              setState(() => _inProductId = id),
                          onSave: _addStock,
                        ),
                        _InTab(
                          products: _products,
                          qtyController: _outQty,
                          selectedId: _outProductId,
                          onChanged: (id) =>
                              setState(() => _outProductId = id),
                          onSave: _removeStock,
                          hint: 'Jumlah stok keluar',
                          buttonLabel: 'Kurangi Stok',
                        ),
                        _HistoryTab(
                            movements: _movements,
                            products: _products,
                            onRefresh: _load),
                      ],
                    ),
                  ),
                ],
              ),
            ),
    );
  }
}

// ═══════════════════════════════════════════
//  Tab: Stok Menipis
// ═══════════════════════════════════════════

class _LowStockTab extends StatelessWidget {
  final List<Product> products;
  final void Function(Product) onTap;
  final Future<void> Function()? onRefresh;

  const _LowStockTab(
      {required this.products, required this.onTap, this.onRefresh});

  @override
  Widget build(BuildContext context) {
    if (products.isEmpty) {
      return const EmptyState(
        icon: Icons.inventory_outlined,
        message: 'Tidak ada stok menipis',
      );
    }
    return RefreshIndicator(
      onRefresh: onRefresh ?? () async {},
      child: ListView.separated(
        padding: const EdgeInsets.all(16),
        itemCount: products.length,
        separatorBuilder: (_, __) => const SizedBox(height: 12),
        itemBuilder: (_, i) => _LowStockCard(product: products[i], onTap: () => onTap(products[i])),
      ),
    );
  }
}

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
//  Tab: Masuk / Keluar
// ═══════════════════════════════════════════

class _InTab extends StatelessWidget {
  final List<Product> products;
  final TextEditingController qtyController;
  final int? selectedId;
  final ValueChanged<int?> onChanged;
  final VoidCallback onSave;
  final String hint;
  final String buttonLabel;

  const _InTab({
    required this.products,
    required this.qtyController,
    required this.selectedId,
    required this.onChanged,
    required this.onSave,
    this.hint = 'Jumlah stok masuk',
    this.buttonLabel = 'Tambah Stok',
  });

  @override
  Widget build(BuildContext context) => RefreshIndicator(
        onRefresh: () async {},
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              NusaDropdownField<int>(
                label: 'Produk',
                value: selectedId,
                items: products
                    .map((p) => DropdownMenuItem(
                        value: p.id, child: Text(p.name)))
                    .toList(),
                onChanged: onChanged,
              ),
              const SizedBox(height: 12),
              NusaInput(hint,
                  controller: qtyController, type: TextInputType.number),
              const SizedBox(height: 20),
              NusaButton(buttonLabel, onPressed: onSave),
            ],
          ),
        ),
      );
}

// ═══════════════════════════════════════════
//  Tab: Riwayat
// ═══════════════════════════════════════════

class _HistoryTab extends StatelessWidget {
  final List<StockMovement> movements;
  final List<Product> products;
  final Future<void> Function()? onRefresh;

  const _HistoryTab(
      {required this.movements, required this.products, this.onRefresh});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final nameOf = {for (final p in products) p.id: p.name};

    if (movements.isEmpty) {
      return const EmptyState(icon: Icons.history, message: 'Belum ada riwayat');
    }

    return RefreshIndicator(
      onRefresh: onRefresh ?? () async {},
      child: ListView.separated(
        padding: const EdgeInsets.all(16),
        itemCount: movements.length,
        separatorBuilder: (_, __) => const SizedBox(height: 10),
        itemBuilder: (_, i) {
          final m = movements[i];
          final name = nameOf[m.productId] ?? '#${m.productId}';
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
            dateStr =
                '${date.day}/${date.month}/${date.year}';
          }

          return Material(
            color: Colors.transparent,
            borderRadius: BorderRadius.circular(NusaConfig.radiusMD),
            child: Container(
              decoration: BoxDecoration(
                color: isDark ? NusaConfig.darkSurface : NusaConfig.surfaceColor,
                borderRadius: BorderRadius.circular(NusaConfig.radiusMD),
                border: Border.all(
                    color: isDark
                        ? NusaConfig.darkBorder
                        : NusaConfig.dividerColor),
                boxShadow: [
                  BoxShadow(
                      color: Colors.black.withValues(
                          alpha: isDark ? 0.15 : 0.04),
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
                              Text(name,
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
        },
      ),
    );
  }
}
