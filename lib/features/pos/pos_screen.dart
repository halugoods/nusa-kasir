import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:nusa_kasir/core/providers.dart';
import 'package:nusa_kasir/core/config/nusa_config.dart';
import 'package:nusa_kasir/core/utils/format_rupiah.dart';
import 'package:nusa_kasir/data/database/app_database.dart';
import 'package:nusa_kasir/data/repositories/cashier_session_repository.dart';
import 'package:nusa_kasir/data/repositories/product_repository.dart';
import 'package:nusa_kasir/features/pos/cart.dart';
import "package:nusa_kasir/shared/widgets/top_toast.dart";

class PosScreen extends ConsumerStatefulWidget {
  final int? sessionId;
  const PosScreen({super.key, this.sessionId});
  @override
  ConsumerState<PosScreen> createState() => _PosScreenState();
}

class _PosScreenState extends ConsumerState<PosScreen> with SingleTickerProviderStateMixin {
  final _search = TextEditingController();
  final _searchFocus = FocusNode();
  String _category = 'Semua';
  String _cashierName = '';
  bool _searching = false;
  bool _cartExpanded = false;

  // Cached product list for instant filtering
  List<Product>? _allProducts;
  bool _productsLoading = true;

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
    _preloadProducts();
    _searchFocus.addListener(() {
      if (mounted) setState(() => _searching = _searchFocus.hasFocus);
    });
  }

  Future<void> _preloadProducts() async {
    final repo = ProductRepository(ref.read(databaseProvider));
    final all = await repo.getProducts();
    if (mounted) setState(() { _allProducts = all; _productsLoading = false; });
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
      if (emps.isNotEmpty) setState(() => _cashierName = emps.first.name);
    }
  }

  List<Product> _filteredProducts() {
    final all = _allProducts ?? [];
    final q = _search.text.toLowerCase();
    return all.where((p) {
      if (_category != 'Semua' && p.category != _category) return false;
      if (q.isNotEmpty && !p.name.toLowerCase().contains(q)) return false;
      return true;
    }).toList();
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
          TextButton(onPressed: () => Navigator.of(dialogContext).pop(), child: const Text('Batal')),
        ],
      ),
    );
    await controller.dispose();
    if (scannedCode == null || !ctx.mounted) return;

    final db = ref.read(databaseProvider);
    final product = await ProductRepository(db).byBarcode(scannedCode!);
    if (product != null) {
      ref.read(cartProvider.notifier).addProduct(product.id, product.name, product.sellPrice);
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
    final screenWidth = MediaQuery.of(context).size.width;
    final isWide = screenWidth > 720;

    return Scaffold(
      backgroundColor: isDark ? NusaConfig.darkBackground : const Color(0xFFF5F5F7),
      body: SafeArea(
        child: isWide
            ? _buildWideLayout(isDark, cart, totalItems, totalPrice, screenWidth)
            : _buildNarrowLayout(isDark, cart, totalItems, totalPrice),
      ),
    );
  }

  /// Narrow layout (phone) — grid + bottom cart bar + expandable sheet
  Widget _buildNarrowLayout(bool isDark, List<CartItem> cart, int totalItems, int totalPrice) {
    return Stack(
      children: [
        Column(
          children: [
            _buildTopBar(isDark),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: _buildSearchBar(isDark),
            ),
            // Category chips
            SizedBox(
              height: 48,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.fromLTRB(16, 10, 16, 4),
                itemCount: _chips.length,
                separatorBuilder: (_, __) => const SizedBox(width: 8),
                itemBuilder: (_, i) => _chipBuild(context, isDark, i),
              ),
            ),
            // Product grid
            Expanded(child: _buildProductGrid(isDark)),
            // Bottom cart bar
            if (!_cartExpanded) _buildCartBar(isDark, totalItems, totalPrice),
          ],
        ),
        // Expandable cart sheet
        if (_cartExpanded)
          _buildCartSheet(isDark, cart, totalItems, totalPrice),
      ],
    );
  }

  /// Wide layout (tablet) — 2-column: grid left, cart sidebar right
  Widget _buildWideLayout(bool isDark, List<CartItem> cart, int totalItems, int totalPrice, double screenWidth) {
    return Column(
      children: [
        _buildTopBar(isDark),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
          child: _buildSearchBar(isDark),
        ),
        SizedBox(
          height: 48,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 4),
            itemCount: _chips.length,
            separatorBuilder: (_, __) => const SizedBox(width: 8),
            itemBuilder: (_, i) => _chipBuild(context, isDark, i),
          ),
        ),
        Expanded(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Product grid (flex 3)
              Expanded(flex: 3, child: _buildProductGrid(isDark)),
              // Cart sidebar (fixed width)
              SizedBox(
                width: 380,
                child: _buildCartSidebar(isDark, cart, totalItems, totalPrice),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _chipBuild(BuildContext context, bool isDark, int i) {
    final chip = _chips[i];
    final selected = chip == _category;
    return GestureDetector(
      onTap: () => setState(() => _category = chip),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: selected ? NusaConfig.primaryColor : (isDark ? NusaConfig.darkSurface2 : Colors.white),
          borderRadius: BorderRadius.circular(20),
          boxShadow: selected ? [BoxShadow(color: NusaConfig.primaryColor.withValues(alpha: 0.3), blurRadius: 8, offset: const Offset(0, 2))] : [],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(_chipIcons[chip] ?? Icons.circle, size: 16, color: selected ? Colors.white : NusaConfig.textSecondary),
            const SizedBox(width: 6),
            Text(chip, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: selected ? Colors.white : (isDark ? NusaConfig.darkTextSecondary : NusaConfig.textSecondary))),
          ],
        ),
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
          const Text('Kasir', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: NusaConfig.textPrimary)),
          const Spacer(),
          if (_cashierName.isNotEmpty) ...[
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(color: NusaConfig.primarySoft, borderRadius: BorderRadius.circular(20)),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                const Icon(Icons.person, size: 14, color: NusaConfig.primaryColor),
                const SizedBox(width: 4),
                Text(_cashierName, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: NusaConfig.primaryColor)),
              ]),
            ),
            const SizedBox(width: 8),
            GestureDetector(
              onTap: _closeKasir,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(color: const Color(0xFFFEE2E2), borderRadius: BorderRadius.circular(20)),
                child: const Row(mainAxisSize: MainAxisSize.min, children: [
                  Icon(Icons.close, size: 14, color: NusaConfig.primaryColor),
                  SizedBox(width: 4),
                  Text('Tutup', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: NusaConfig.primaryColor)),
                ]),
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
        boxShadow: _searching ? [BoxShadow(color: NusaConfig.primaryColor.withValues(alpha: 0.2), blurRadius: 12, offset: const Offset(0, 3))] : [BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 4, offset: const Offset(0, 2))],
      ),
      child: TextField(
        controller: _search,
        focusNode: _searchFocus,
        style: TextStyle(fontSize: 15, color: isDark ? NusaConfig.darkTextPrimary : NusaConfig.textPrimary),
        decoration: InputDecoration(
          hintText: 'Cari produk...',
          hintStyle: TextStyle(color: isDark ? NusaConfig.darkTextTertiary : NusaConfig.textTertiary),
          prefixIcon: const Icon(Icons.search_rounded, color: NusaConfig.textSecondary, size: 22),
          suffixIcon: Row(mainAxisSize: MainAxisSize.min, children: [
            GestureDetector(
              onTap: () => _scanBarcode(context),
              child: Container(padding: const EdgeInsets.symmetric(horizontal: 8), child: const Icon(Icons.qr_code_scanner, color: NusaConfig.textSecondary, size: 22)),
            ),
            if (_search.text.isNotEmpty)
              GestureDetector(
                onTap: () { _search.clear(); setState(() {}); },
                child: const Icon(Icons.clear_rounded, color: NusaConfig.textSecondary, size: 20),
              ),
          ]),
          border: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        ),
        onChanged: (_) => setState(() {}),
      ),
    );
  }

  Widget _buildProductGrid(bool isDark) {
    if (_productsLoading) {
      return const Center(child: CircularProgressIndicator(color: NusaConfig.primaryColor));
    }
    final products = _filteredProducts();
    if (products.isEmpty) {
      return Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.inventory_2_outlined, size: 56, color: isDark ? NusaConfig.darkTextTertiary : NusaConfig.textTertiary),
          const SizedBox(height: 8),
          Text('Produk tidak ditemukan', style: TextStyle(color: isDark ? NusaConfig.darkTextSecondary : NusaConfig.textSecondary, fontSize: 15)),
        ]),
      );
    }
    final cart = ref.watch(cartProvider);
    return GridView.builder(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 3, crossAxisSpacing: 10, mainAxisSpacing: 10, childAspectRatio: 0.78),
          itemCount: products.length,
          itemBuilder: (_, i) {
            final product = products[i];
            final cartItem = cart.cast<CartItem?>().firstWhere((c) => c?.productId == product.id, orElse: () => null);
            final qtyInCart = cartItem?.qty ?? 0;
            return _ProductCard(
              product: product,
              isDark: isDark,
              qtyInCart: qtyInCart,
              onAdd: () => ref.read(cartProvider.notifier).addProduct(product.id, product.name, product.sellPrice),
              onDecrement: () => ref.read(cartProvider.notifier).changeQty(product.id, -1),
              onIncrement: () => ref.read(cartProvider.notifier).addProduct(product.id, product.name, product.sellPrice),
            );
          },
        );
  }

  Widget _buildCartBar(bool isDark, int totalItems, int totalPrice) {
    return GestureDetector(
      onTap: totalItems > 0 ? () => setState(() => _cartExpanded = true) : null,
      child: Container(
        margin: const EdgeInsets.fromLTRB(12, 4, 12, 12),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20),
          gradient: const LinearGradient(colors: [NusaConfig.primaryColor, NusaConfig.primaryDark], begin: Alignment.topLeft, end: Alignment.bottomRight),
          boxShadow: [BoxShadow(color: NusaConfig.primaryColor.withValues(alpha: 0.35), blurRadius: 16, offset: const Offset(0, 6))],
        ),
        child: Row(
          children: [
            Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('$totalItems item', style: TextStyle(fontSize: 12, color: Colors.white.withValues(alpha: 0.85))),
              const SizedBox(height: 2),
              Text(formatRupiah(totalPrice), style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: Colors.white, letterSpacing: -0.5)),
            ]),
            const Spacer(),
            if (totalItems > 0)
              const Icon(Icons.keyboard_arrow_up, color: Colors.white70, size: 28),
            const SizedBox(width: 8),
            SizedBox(
              child: ElevatedButton(
                onPressed: totalItems == 0 ? null : () => context.push('/checkout?sessionId=${widget.sessionId ?? ''}'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.white, foregroundColor: NusaConfig.primaryColor,
                  disabledBackgroundColor: Colors.white38, disabledForegroundColor: Colors.white54,
                  elevation: 0, padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
                ),
                child: const Text('Bayar'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Full-height cart sheet overlay for narrow screens.
  Widget _buildCartSheet(bool isDark, List<CartItem> cart, int totalItems, int totalPrice) {
    return Positioned.fill(
      top: MediaQuery.of(context).padding.top + 80,
      child: GestureDetector(
        onVerticalDragEnd: (details) {
          if (details.primaryVelocity! > 500) setState(() => _cartExpanded = false);
        },
        child: Container(
          decoration: BoxDecoration(
            color: isDark ? NusaConfig.darkBackground : Colors.white,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
            boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.15), blurRadius: 20, offset: const Offset(0, -5))],
          ),
          child: Column(
            children: [
              // Handle
              Center(
                child: Container(
                  margin: const EdgeInsets.symmetric(vertical: 10),
                  width: 40, height: 4,
                  decoration: BoxDecoration(color: NusaConfig.dividerColor, borderRadius: BorderRadius.circular(2)),
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Row(children: [
                  const Text('Keranjang', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: NusaConfig.textPrimary)),
                  const Spacer(),
                  TextButton(onPressed: () => ref.read(cartProvider.notifier).clear(), child: const Text('Kosongkan', style: TextStyle(color: NusaConfig.primaryColor, fontWeight: FontWeight.w600))),
                  IconButton(onPressed: () => setState(() => _cartExpanded = false), icon: const Icon(Icons.keyboard_arrow_down, color: NusaConfig.textSecondary)),
                ]),
              ),
              const Divider(height: 1),
              // Cart items
              Expanded(
                child: cart.isEmpty
                    ? Center(
                        child: Column(mainAxisSize: MainAxisSize.min, children: [
                          Icon(Icons.receipt_long_outlined, size: 48, color: NusaConfig.textTertiary.withValues(alpha: 0.5)),
                          const SizedBox(height: 8),
                          const Text('Keranjang masih kosong', style: TextStyle(color: NusaConfig.textTertiary)),
                        ]),
                      )
                    : Consumer(
                        builder: (_, ref, __) => ListView.builder(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                          itemCount: cart.length,
                          itemBuilder: (_, i) => _CartItemTile(
                            item: cart[i], isDark: isDark,
                            onDecrement: () => ref.read(cartProvider.notifier).changeQty(cart[i].productId, -1),
                            onIncrement: () => ref.read(cartProvider.notifier).addProduct(cart[i].productId, cart[i].name, cart[i].price),
                          ),
                        ),
                      ),
              ),
              // Summary + checkout
              Container(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
                decoration: BoxDecoration(color: isDark ? NusaConfig.darkSurface : NusaConfig.backgroundColor, border: Border(top: BorderSide(color: isDark ? NusaConfig.darkBorder : NusaConfig.dividerColor))),
                child: Column(children: [
                  Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                    Text('$totalItems item', style: TextStyle(fontSize: 13, color: isDark ? NusaConfig.darkTextSecondary : NusaConfig.textSecondary)),
                    Text(formatRupiah(totalPrice), style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: NusaConfig.primaryColor)),
                  ]),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: totalItems == 0 ? null : () => context.push('/checkout?sessionId=${widget.sessionId ?? ''}'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: NusaConfig.primaryColor, foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                        textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                      ),
                      child: const Text('Bayar'),
                    ),
                  ),
                ]),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Persistent cart sidebar for wide screens.
  Widget _buildCartSidebar(bool isDark, List<CartItem> cart, int totalItems, int totalPrice) {
    return Container(
      decoration: BoxDecoration(
        color: isDark ? NusaConfig.darkSurface : Colors.white,
        border: Border(left: BorderSide(color: isDark ? NusaConfig.darkBorder : NusaConfig.dividerColor)),
      ),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
            child: Row(children: [
              const Icon(Icons.shopping_basket_outlined, color: NusaConfig.primaryColor, size: 20),
              const SizedBox(width: 8),
              const Expanded(child: Text('Keranjang', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: NusaConfig.textPrimary))),
              TextButton(onPressed: cart.isEmpty ? null : () => ref.read(cartProvider.notifier).clear(), child: const Text('Kosongkan', style: TextStyle(fontSize: 12, color: NusaConfig.primaryColor, fontWeight: FontWeight.w600))),
            ]),
          ),
          const Divider(height: 1),
          Expanded(
            child: cart.isEmpty
                ? Center(
                    child: Column(mainAxisSize: MainAxisSize.min, children: [
                      Icon(Icons.receipt_long_outlined, size: 48, color: NusaConfig.textTertiary.withValues(alpha: 0.4)),
                      const SizedBox(height: 8),
                      const Text('Keranjang masih kosong', style: TextStyle(color: NusaConfig.textTertiary)),
                    ]),
                  )
                : Consumer(
                    builder: (_, ref, __) => ListView.builder(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                      itemCount: cart.length,
                      itemBuilder: (_, i) => _CartItemTile(
                        item: cart[i], isDark: isDark,
                        onDecrement: () => ref.read(cartProvider.notifier).changeQty(cart[i].productId, -1),
                        onIncrement: () => ref.read(cartProvider.notifier).addProduct(cart[i].productId, cart[i].name, cart[i].price),
                      ),
                    ),
                  ),
          ),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(color: isDark ? NusaConfig.darkBackground : NusaConfig.backgroundColor, border: Border(top: BorderSide(color: isDark ? NusaConfig.darkBorder : NusaConfig.dividerColor))),
            child: Column(children: [
              Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                Text('$totalItems item', style: TextStyle(fontSize: 13, color: isDark ? NusaConfig.darkTextSecondary : NusaConfig.textSecondary)),
                Text(formatRupiah(totalPrice), style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: NusaConfig.primaryColor)),
              ]),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: totalItems == 0 ? null : () => context.push('/checkout?sessionId=${widget.sessionId ?? ''}'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: NusaConfig.primaryColor, foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                  ),
                  child: const Text('Bayar'),
                ),
              ),
            ]),
          ),
        ],
      ),
    );
  }
}

/// Mapping category → emoji for placeholder.
const _catEmoji = <String, String>{
  'Makanan': '🍜',
  'Minuman': '🥤',
  'Sembako': '📦',
  'Lainnya': '🧴',
};

String _catEmojiFor(String cat) => _catEmoji[cat] ?? '📦';

/// Premium product card matching NUSA component #05 (Etalase Online).
/// Two states: + button when qty=0, inline qty stepper when qty>0.
class _ProductCard extends StatelessWidget {
  final Product product;
  final bool isDark;
  final int qtyInCart;
  final VoidCallback onAdd;
  final VoidCallback onDecrement;
  final VoidCallback onIncrement;
  const _ProductCard({
    required this.product, required this.isDark,
    required this.qtyInCart,
    required this.onAdd, required this.onDecrement, required this.onIncrement,
  });

  @override
  Widget build(BuildContext context) {
    final outOfStock = product.stock <= 0;
    final lowStock = !outOfStock && product.stock <= product.minStock;

    return GestureDetector(
      onTap: outOfStock ? null : () { if (qtyInCart == 0) onAdd(); },
      child: _CardShell(
        isDark: isDark,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: _ProductImage(
                imagePath: product.imagePath, category: product.category,
                outOfStock: outOfStock, lowStock: lowStock,
                stock: product.stock, price: formatRupiah(product.sellPrice), isDark: isDark,
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 10, 10, 4),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(product.name, maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, height: 1.2, letterSpacing: -0.01, color: outOfStock ? NusaConfig.textTertiary : (isDark ? NusaConfig.darkTextPrimary : NusaConfig.textPrimary))),
                const SizedBox(height: 2),
                Text(product.category, style: TextStyle(fontSize: 11, color: isDark ? NusaConfig.darkTextTertiary : NusaConfig.textTertiary, letterSpacing: -0.01)),
              ]),
            ),
            const Spacer(),
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 0, 10, 10),
              child: Align(
                alignment: Alignment.centerRight,
                child: outOfStock
                    ? const SizedBox(width: 28, height: 28)
                    : qtyInCart == 0
                        ? _AddButton(onTap: onAdd, disabled: outOfStock)
                        : _QtyStepper(qty: qtyInCart, onDecrement: onDecrement, onIncrement: onIncrement),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Inline quantity stepper: [-] [qty] [+]
class _QtyStepper extends StatelessWidget {
  final int qty;
  final VoidCallback onDecrement;
  final VoidCallback onIncrement;
  const _QtyStepper({required this.qty, required this.onDecrement, required this.onIncrement});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 28,
      decoration: BoxDecoration(
        border: Border.all(color: NusaConfig.primaryColor, width: 1.5),
        borderRadius: BorderRadius.circular(14),
        color: NusaConfig.primarySoft,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          GestureDetector(
            onTap: onDecrement,
            behavior: HitTestBehavior.opaque,
            child: const SizedBox(width: 24, height: 28, child: Center(child: Icon(Icons.remove, size: 16, color: NusaConfig.primaryColor))),
          ),
          Container(
            constraints: const BoxConstraints(minWidth: 20),
            child: Text('$qty', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: NusaConfig.primaryColor), textAlign: TextAlign.center),
          ),
          GestureDetector(
            onTap: onIncrement,
            behavior: HitTestBehavior.opaque,
            child: const SizedBox(width: 24, height: 28, child: Center(child: Icon(Icons.add, size: 16, color: NusaConfig.primaryColor))),
          ),
        ],
      ),
    );
  }
}

/// Cart item tile used in the expanded cart sheet and sidebar.
class _CartItemTile extends StatelessWidget {
  final CartItem item;
  final bool isDark;
  final VoidCallback? onDecrement;
  final VoidCallback? onIncrement;
  const _CartItemTile({required this.item, required this.isDark, this.onDecrement, this.onIncrement});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: isDark ? NusaConfig.darkSurface : Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: isDark ? NusaConfig.darkBorder : NusaConfig.borderColor),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(item.name, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: isDark ? NusaConfig.darkTextPrimary : NusaConfig.textPrimary), maxLines: 1, overflow: TextOverflow.ellipsis),
              const SizedBox(height: 2),
              Text(formatRupiah(item.price), style: const TextStyle(fontSize: 12, color: NusaConfig.textSecondary)),
            ]),
          ),
          // Qty stepper
          Container(
            height: 32,
            decoration: BoxDecoration(
              border: Border.all(color: isDark ? NusaConfig.darkBorder : NusaConfig.dividerColor),
              borderRadius: BorderRadius.circular(10),
              color: isDark ? NusaConfig.darkBackground : NusaConfig.backgroundColor,
            ),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              GestureDetector(
                onTap: onDecrement,
                behavior: HitTestBehavior.opaque,
                child: const SizedBox(width: 30, height: 32, child: Center(child: Icon(Icons.remove, size: 16, color: NusaConfig.textSecondary))),
              ),
              Text('${item.qty}', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: NusaConfig.textPrimary)),
              GestureDetector(
                onTap: onIncrement,
                behavior: HitTestBehavior.opaque,
                child: const SizedBox(width: 30, height: 32, child: Center(child: Icon(Icons.add, size: 16, color: NusaConfig.textSecondary))),
              ),
            ]),
          ),
          const SizedBox(width: 8),
          Text(formatRupiah(item.subtotal), style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: NusaConfig.primaryColor)),
        ],
      ),
    );
  }
}

/// Outer card shell with touch feedback (scale + shadow).
class _CardShell extends StatefulWidget {
  final Widget child;
  final bool isDark;
  const _CardShell({required this.child, required this.isDark});
  @override
  State<_CardShell> createState() => _CardShellState();
}

class _CardShellState extends State<_CardShell> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) => setState(() => _pressed = true),
      onTapUp: (_) => setState(() => _pressed = false),
      onTapCancel: () => setState(() => _pressed = false),
      child: AnimatedScale(
        scale: _pressed ? 0.96 : 1.0,
        duration: const Duration(milliseconds: 150),
        curve: Curves.easeOutCubic,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          decoration: BoxDecoration(
            color: widget.isDark ? NusaConfig.darkSurface : Colors.white,
            borderRadius: BorderRadius.circular(16),
            boxShadow: _pressed ? [] : [BoxShadow(color: Colors.black.withValues(alpha: widget.isDark ? 0.10 : 0.05), blurRadius: 8, offset: const Offset(0, 3))],
          ),
          child: widget.child,
        ),
      ),
    );
  }
}

/// Image area with gradient placeholder, rounded corners, and overlay badges.
class _ProductImage extends StatelessWidget {
  final String? imagePath;
  final String category;
  final bool outOfStock;
  final bool lowStock;
  final int stock;
  final String price;
  final bool isDark;

  const _ProductImage({required this.imagePath, required this.category, required this.outOfStock, required this.lowStock, required this.stock, required this.price, required this.isDark});

  @override
  Widget build(BuildContext context) {
    final hasImage = imagePath != null && imagePath!.isNotEmpty && File(imagePath!).existsSync();
    final emoji = _catEmojiFor(category);

      return Stack(
        clipBehavior: Clip.none,
        children: [
          ClipRRect(
            borderRadius: const BorderRadius.vertical(top: Radius.circular(14)),
            child: SizedBox(
              height: 95, width: double.infinity,
              child: Stack(fit: StackFit.expand, children: [
                if (hasImage) Image.file(File(imagePath!), fit: BoxFit.cover) else _CategoryGradient(category: category, emoji: emoji),
                if (outOfStock) Container(color: Colors.white.withValues(alpha: 0.5)),
              ]),
            ),
          ),
        Positioned(top: 8, left: 8, child: _StockBadge(outOfStock: outOfStock, lowStock: lowStock, stock: stock)),
        Positioned(
          bottom: 2, right: 6,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(30), boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.08), blurRadius: 6, offset: const Offset(0, 2))]),
            child: Text(price, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: NusaConfig.primaryColor, letterSpacing: -0.03)),
          ),
        ),
      ],
    );
  }
}

class _CategoryGradient extends StatelessWidget {
  final String category;
  final String emoji;
  const _CategoryGradient({required this.category, required this.emoji});

  static const _gradients = <String, List<Color>>{
    'Makanan': [Color(0xFFFEF3C7), Color(0xFFFDE68A), Color(0xFFFEF9C3)],
    'Minuman': [Color(0xFFDBEAFE), Color(0xFFBFDBFE), Color(0xFFEFF6FF)],
    'Sembako': [Color(0xFFFEE2E2), Color(0xFFFECACA), Color(0xFFFEF2F2)],
    'Lainnya': [Color(0xFFF3E8FF), Color(0xFFE9D5FF), Color(0xFFFAF5FF)],
  };

  @override
  Widget build(BuildContext context) {
    final colors = _gradients[category] ?? _gradients['Lainnya']!;
    return Container(
      decoration: BoxDecoration(gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: colors)),
      child: Center(child: Opacity(opacity: 0.3, child: Text(emoji, style: const TextStyle(fontSize: 40)))),
    );
  }
}

class _StockBadge extends StatelessWidget {
  final bool outOfStock;
  final bool lowStock;
  final int stock;
  const _StockBadge({required this.outOfStock, required this.lowStock, required this.stock});

  @override
  Widget build(BuildContext context) {
    final label = outOfStock ? 'Habis' : '${stock}x';
    final bg = outOfStock ? const Color(0xFFFEE2E2) : (lowStock ? const Color(0xFFFFF3E0) : Colors.white.withValues(alpha: 0.9));
    final fg = outOfStock ? NusaConfig.primaryColor : (lowStock ? const Color(0xFFE65100) : NusaConfig.primaryColor);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(20), boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.06), blurRadius: 4, offset: const Offset(0, 1))]),
      child: Text(label, style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: fg, letterSpacing: -0.01)),
    );
  }
}

class _AddButton extends StatefulWidget {
  final VoidCallback onTap;
  final bool disabled;
  const _AddButton({required this.onTap, required this.disabled});
  @override
  State<_AddButton> createState() => _AddButtonState();
}

class _AddButtonState extends State<_AddButton> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: widget.disabled ? null : (_) => setState(() => _pressed = true),
      onTapUp: widget.disabled ? null : (_) { setState(() => _pressed = false); widget.onTap(); },
      onTapCancel: () => setState(() => _pressed = false),
      child: AnimatedScale(
        scale: _pressed ? 0.85 : 1.0,
        duration: const Duration(milliseconds: 100),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          width: 28, height: 28,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: widget.disabled ? NusaConfig.textTertiary : NusaConfig.primaryColor,
            boxShadow: widget.disabled ? [] : [BoxShadow(color: NusaConfig.primaryColor.withValues(alpha: 0.35), blurRadius: 6, offset: const Offset(0, 2))],
          ),
          child: const Icon(Icons.add, color: Colors.white, size: 18),
        ),
      ),
    );
  }
}
