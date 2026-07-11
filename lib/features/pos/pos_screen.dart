import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:nusa_kasir/app.dart';
import 'package:nusa_kasir/core/config/nusa_config.dart';
import 'package:nusa_kasir/core/utils/format_rupiah.dart';
import 'package:nusa_kasir/data/database/app_database.dart';
import 'package:nusa_kasir/data/repositories/cashier_session_repository.dart';
import 'package:nusa_kasir/data/repositories/product_repository.dart';
import 'package:nusa_kasir/features/pos/cart.dart';
import 'package:nusa_kasir/shared/widgets/nusa_card.dart';
import "package:nusa_kasir/shared/widgets/top_toast.dart";

class PosScreen extends ConsumerStatefulWidget {
  final int? sessionId;
  const PosScreen({super.key, this.sessionId});
  @override
  ConsumerState<PosScreen> createState() => _PosScreenState();
}

class _PosScreenState extends ConsumerState<PosScreen> {
  final _search = TextEditingController();
  final _searchFocus = FocusNode();
  String _category = 'Semua';
  String _cashierName = '';
  bool _searching = false;

  static const _chipIcons = <String, IconData>{
    'Semua': Icons.grid_view_rounded,
    'Makanan': Icons.restaurant_rounded,
    'Minuman': Icons.local_drink_rounded,
    'Sembako': Icons.shopping_basket_rounded,
    'Lainnya': Icons.category_rounded,
  };

  List<String> get _chips => ['Semua', ...NusaConfig.categories];

  @override
  void initState() {
    super.initState();
    _loadCashier();
    _searchFocus.addListener(() {
      if (mounted) setState(() => _searching = _searchFocus.hasFocus);
    });
  }

  @override
  void dispose() {
    _search.dispose();
    _searchFocus.dispose();
    super.dispose();
  }

  Future<void> _loadCashier() async {
    if (widget.sessionId == null) return;
    final repo = CashierSessionRepository(ref.read(databaseProvider));
    final session = await repo.getLast();
    if (session != null && mounted) {
      final emps = await (ref.read(databaseProvider).select(
              ref.read(databaseProvider).employees)
            ..where((t) => t.id.equals(session.employeeId)))
          .get();
      if (emps.isNotEmpty) {
        setState(() => _cashierName = emps.first.name);
      }
    }
  }

  Future<List<Product>> _loadProducts() async {
    final repo = ProductRepository(ref.read(databaseProvider));
    final all = await repo.getProducts(
      category: _category == 'Semua' ? null : _category,
    );
    final q = _search.text.toLowerCase();
    if (q.isEmpty) return all;
    return all.where((p) => p.name.toLowerCase().contains(q)).toList();
  }

  Future<void> _scanBarcode(BuildContext context) async {
    final ctx = context;
    String? scannedCode;
    final controller = MobileScannerController();
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Pindai Barcode'),
        contentPadding: const EdgeInsets.all(8),
        content: SizedBox(
          width: double.maxFinite,
          height: 320,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: MobileScanner(
              controller: controller,
              onDetect: (capture) {
                if (scannedCode != null) return;
                final code = capture.barcodes.firstWhere(
                  (b) => b.rawValue != null,
                  orElse: () => capture.barcodes.first,
                ).rawValue;
                if (code == null || code.isEmpty) return;
                scannedCode = code;
                Navigator.of(dialogContext).pop(code);
              },
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Batal'),
          ),
        ],
      ),
    );
    await controller.dispose();
    if (scannedCode == null || !ctx.mounted) return;

    final db = ref.read(databaseProvider);
    final product = await ProductRepository(db).byBarcode(scannedCode!);
    if (product != null) {
      ref.read(cartProvider.notifier).addProduct(
            product.id,
            product.name,
            product.sellPrice,
          );
      TopToast.success(ctx, '${product.name} ditambahkan');
    } else if (ctx.mounted) {
      TopToast.error(ctx, 'Produk tidak ditemukan');
    }
  }

  Future<void> _closeKasir() async {
    if (widget.sessionId == null) {
      if (mounted) context.go('/home');
      return;
    }
    final repo = CashierSessionRepository(ref.read(databaseProvider));
    await repo.close(widget.sessionId!);
    if (mounted) {
      context.go('/home');
      TopToast.success(context, 'Kasir ditutup. Sampai jumpa! 👋');
    }
  }

  @override
  Widget build(BuildContext context) {
    final cart = ref.watch(cartProvider);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final totalItems = cart.fold(0, (s, e) => s + e.qty);
    final totalPrice = cart.fold(0, (s, e) => s + e.subtotal);

    return Scaffold(
      backgroundColor: isDark ? NusaConfig.darkBackground : const Color(0xFFF5F5F7),
      body: SafeArea(
        child: Column(
          children: [
            // ── Top bar: cashier chip + close button ──
            _buildTopBar(isDark),

            // ── Search pill ──
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: _buildSearchBar(isDark),
            ),

            // ── Category chips ──
            SizedBox(
              height: 48,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.fromLTRB(16, 10, 16, 4),
                itemCount: _chips.length,
                separatorBuilder: (_, __) => const SizedBox(width: 8),
                itemBuilder: (_, i) {
                  final chip = _chips[i];
                  final selected = chip == _category;
                  return GestureDetector(
                    onTap: () => setState(() => _category = chip),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                      decoration: BoxDecoration(
                        color: selected
                            ? NusaConfig.primaryColor
                            : (isDark ? NusaConfig.darkSurface2 : Colors.white),
                        borderRadius: BorderRadius.circular(20),
                        boxShadow: selected
                            ? [BoxShadow(color: NusaConfig.primaryColor.withValues(alpha: 0.3), blurRadius: 8, offset: const Offset(0, 2))]
                            : [],
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            _chipIcons[chip] ?? Icons.circle,
                            size: 16,
                            color: selected ? Colors.white : NusaConfig.textSecondary,
                          ),
                          const SizedBox(width: 6),
                          Text(
                            chip,
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: selected ? Colors.white : (isDark ? NusaConfig.darkTextSecondary : NusaConfig.textSecondary),
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),

            // ── Product grid ──
            Expanded(
              child: FutureBuilder<List<Product>>(
                key: ValueKey('$_category|${_search.text}'),
                future: _loadProducts(),
                builder: (context, snap) {
                  if (snap.connectionState != ConnectionState.done) {
                    return const Center(
                      child: CircularProgressIndicator(color: NusaConfig.primaryColor),
                    );
                  }
                  final products = snap.data ?? [];
                  if (products.isEmpty) {
                    return Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.inventory_2_outlined,
                              size: 56, color: isDark ? NusaConfig.darkTextTertiary : NusaConfig.textTertiary),
                          const SizedBox(height: 8),
                          Text('Produk tidak ditemukan',
                              style: TextStyle(color: isDark ? NusaConfig.darkTextSecondary : NusaConfig.textSecondary, fontSize: 15)),
                        ],
                      ),
                    );
                  }
                  return GridView.builder(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                    gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 3,
                      crossAxisSpacing: 10,
                      mainAxisSpacing: 10,
                      childAspectRatio: 0.78,
                    ),
                    itemCount: products.length,
                    itemBuilder: (_, i) => _ProductCard(
                      product: products[i],
                      isDark: isDark,
                      onTap: () => ref
                          .read(cartProvider.notifier)
                          .addProduct(products[i].id, products[i].name, products[i].sellPrice),
                    ),
                  );
                },
              ),
            ),

            // ── Cart bar ──
            _buildCartBar(isDark, totalItems, totalPrice),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton(
        backgroundColor: NusaConfig.primaryColor,
        foregroundColor: Colors.white,
        elevation: 4,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        tooltip: 'Pindai Barcode',
        onPressed: () => _scanBarcode(context),
        child: const Icon(Icons.qr_code_2_rounded),
      ),
    );
  }

  Widget _buildTopBar(bool isDark) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 12, 12),
      child: Row(
        children: [
          const Icon(Icons.shopping_cart_rounded, color: NusaConfig.primaryColor, size: 22),
          const SizedBox(width: 10),
          const Text('Kasir',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: NusaConfig.textPrimary)),
          const Spacer(),
          if (_cashierName.isNotEmpty) ...[
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: NusaConfig.primarySoft,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.person, size: 14, color: NusaConfig.primaryColor),
                  const SizedBox(width: 4),
                  Text(_cashierName,
                      style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: NusaConfig.primaryColor)),
                ],
              ),
            ),
            const SizedBox(width: 8),
            GestureDetector(
              onTap: _closeKasir,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: const Color(0xFFFEE2E2),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.close, size: 14, color: NusaConfig.primaryColor),
                    SizedBox(width: 4),
                    Text('Tutup',
                        style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: NusaConfig.primaryColor)),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildSearchBar(bool isDark) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 250),
      decoration: BoxDecoration(
        color: isDark ? NusaConfig.darkSurface : Colors.white,
        borderRadius: BorderRadius.circular(24),
        boxShadow: _searching
            ? [BoxShadow(color: NusaConfig.primaryColor.withValues(alpha: 0.2), blurRadius: 12, offset: const Offset(0, 3))]
            : [BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 4, offset: const Offset(0, 2))],
      ),
      child: TextField(
        controller: _search,
        focusNode: _searchFocus,
        style: TextStyle(fontSize: 15, color: isDark ? NusaConfig.darkTextPrimary : NusaConfig.textPrimary),
        decoration: InputDecoration(
          hintText: 'Cari produk...',
          hintStyle: TextStyle(color: isDark ? NusaConfig.darkTextTertiary : NusaConfig.textTertiary),
          prefixIcon: const Icon(Icons.search_rounded, color: NusaConfig.textSecondary, size: 22),
          suffixIcon: _search.text.isNotEmpty
              ? GestureDetector(
                  onTap: () {
                    _search.clear();
                    setState(() {});
                  },
                  child: const Icon(Icons.clear_rounded, color: NusaConfig.textSecondary, size: 20),
                )
              : null,
          border: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        ),
        onChanged: (_) => setState(() {}),
      ),
    );
  }

  Widget _buildCartBar(bool isDark, int totalItems, int totalPrice) {
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 4, 12, 68), // extra bottom to avoid FAB overlap
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        gradient: const LinearGradient(
          colors: [NusaConfig.primaryColor, NusaConfig.primaryDark],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        boxShadow: [
          BoxShadow(
            color: NusaConfig.primaryColor.withValues(alpha: 0.35),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Row(
        children: [
          // Item count
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('$totalItems item',
                  style: TextStyle(fontSize: 12, color: Colors.white.withValues(alpha: 0.85))),
              const SizedBox(height: 2),
              Text(formatRupiah(totalPrice),
                  style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: Colors.white, letterSpacing: -0.5)),
            ],
          ),
          const Spacer(),
          // Pay button
          SizedBox(
            child: ElevatedButton(
              onPressed: totalItems == 0
                  ? null
                  : () => context.push('/checkout?sessionId=${widget.sessionId ?? ''}'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.white,
                foregroundColor: NusaConfig.primaryColor,
                disabledBackgroundColor: Colors.white38,
                disabledForegroundColor: Colors.white54,
                elevation: 0,
                padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
              ),
              child: const Text('Bayar'),
            ),
          ),
        ],
      ),
    );
  }
}

/// Premium product card with stock badge and price emphasis.
class _ProductCard extends StatelessWidget {
  final Product product;
  final bool isDark;
  final VoidCallback onTap;

  const _ProductCard({required this.product, required this.isDark, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final outOfStock = product.stock <= 0;

    return GestureDetector(
      onTap: outOfStock ? null : onTap,
      child: Container(
        decoration: BoxDecoration(
          color: isDark ? NusaConfig.darkSurface : Colors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: isDark ? 0.08 : 0.04),
              blurRadius: 6,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Product icon + stock badge
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: outOfStock
                          ? NusaConfig.textTertiary.withValues(alpha: 0.15)
                          : NusaConfig.primaryColor.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    alignment: Alignment.center,
                    child: Icon(
                      Icons.inventory_2_outlined,
                      size: 18,
                      color: outOfStock ? NusaConfig.textTertiary : NusaConfig.primaryColor,
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: outOfStock
                          ? const Color(0xFFFEE2E2)
                          : NusaConfig.primarySoft,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      outOfStock ? 'Habis' : '${product.stock}x',
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        color: outOfStock ? NusaConfig.primaryColor : NusaConfig.primaryColor,
                      ),
                    ),
                  ),
                ],
              ),
              const Spacer(),
              // Product name
              Text(
                product.name,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  height: 1.2,
                  color: outOfStock
                      ? NusaConfig.textTertiary
                      : (isDark ? NusaConfig.darkTextPrimary : NusaConfig.textPrimary),
                ),
              ),
              const SizedBox(height: 6),
              // Price
              Text(
                formatRupiah(product.sellPrice),
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w800,
                  color: outOfStock ? NusaConfig.textTertiary : NusaConfig.primaryColor,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
