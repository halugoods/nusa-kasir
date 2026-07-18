import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:nusa_kasir/core/config/nusa_config.dart';
import 'package:nusa_kasir/core/providers.dart';
import 'package:nusa_kasir/core/utils/format_rupiah.dart';
import 'package:nusa_kasir/data/database/app_database.dart';
import 'package:nusa_kasir/data/repositories/product_repository.dart';
import 'package:nusa_kasir/data/repositories/settings_repository.dart';

/// Customer-facing online store screen.
/// Route: /toko
class StorefrontScreen extends ConsumerStatefulWidget {
  const StorefrontScreen({super.key});
  @override
  ConsumerState<StorefrontScreen> createState() => _StorefrontScreenState();
}

class _StoreItem {
  final Product product;
  int qty;
  _StoreItem({required this.product, this.qty = 1});
  int get subtotal => product.sellPrice * qty;
}

class _StorefrontScreenState extends ConsumerState<StorefrontScreen> {
  List<Product> _allProducts = [];
  bool _loading = true;
  String _category = 'Semua';
  final _search = TextEditingController();
  final List<_StoreItem> _cart = [];
  bool _showCart = false;

  final _nameCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  String _paymentMethod = 'Tunai';
  String _branch = 'Pusat';
  String? _storeName;
  String? _storePhone;

  final _scrollCtrl = ScrollController();

  // Wishlist state
  final Set<int> _wishlist = {};
  // Cart popup state
  bool _showCartPopup = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _search.dispose(); _nameCtrl.dispose(); _phoneCtrl.dispose();
    _scrollCtrl.dispose(); super.dispose();
  }

  Future<void> _load() async {
    final db = ref.read(databaseProvider);
    final repo = ProductRepository(db);
    final all = await repo.getProducts();
    final settingsRepo = SettingsRepository(db);
    final storeName = await settingsRepo.getStoreName();
    if (mounted) {
      setState(() {
        _allProducts = all;
        _loading = false;
        _storeName = storeName.isNotEmpty ? storeName : 'NUSA Toko';
        _storePhone = '';
      });
    }
  }

  // ── Product initials helper ──
  String _initials(String name) {
    final parts = name.trim().split(RegExp(r'\s+'));
    if (parts.length >= 2) {
      return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
    }
    return name.isNotEmpty ? name.substring(0, name.length >= 2 ? 2 : 1).toUpperCase() : '??';
  }

  List<Product> _filtered() {
    final q = _search.text.toLowerCase();
    return _allProducts.where((p) {
      if (_category != 'Semua' && p.category != _category) return false;
      if (q.isNotEmpty && !p.name.toLowerCase().contains(q)) return false;
      return true;
    }).toList();
  }

  void _toggleCartItem(Product p) {
    setState(() {
      final idx = _cart.indexWhere((c) => c.product.id == p.id);
      if (idx >= 0) {
        if (_cart[idx].qty <= 1) {
          _cart.removeAt(idx);
        } else {
          _cart[idx].qty--;
        }
      } else {
        _cart.add(_StoreItem(product: p));
        // Show cart popup
        _showCartPopup = true;
        Future.delayed(const Duration(seconds: 4), () {
          if (mounted) setState(() => _showCartPopup = false);
        });
      }
    });
  }

  void _toggleWishlist(int productId) {
    setState(() {
      if (_wishlist.contains(productId)) {
        _wishlist.remove(productId);
      } else {
        _wishlist.add(productId);
      }
    });
  }

  int get _totalItems => _cart.fold(0, (s, e) => s + e.qty);
  int get _totalPrice => _cart.fold(0, (s, e) => s + e.subtotal);

  Future<void> _sendWhatsApp() async {
    final name = _nameCtrl.text.trim();
    final phone = _phoneCtrl.text.trim();
    if (name.isEmpty || phone.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Nama dan WhatsApp wajib diisi')));
      return;
    }
    final itemsText = _cart.map((c) =>
      '• ${c.product.name} x${c.qty} — ${formatRupiah(c.subtotal)}'
    ).join('\n');
    final msg = Uri.encodeComponent(
      '🛒 *Pesanan Baru*\n\n'
      '👤 $name\n📱 $phone\n🏪 $_branch\n💳 $_paymentMethod\n\n'
      '*Item:*\n$itemsText\n\n'
      '*Total: ${formatRupiah(_totalPrice)}*');
    final targetPhone = _storePhone ?? '';
    final waUrl = Uri.parse('https://wa.me/$targetPhone?text=$msg');
    if (await canLaunchUrl(waUrl)) {
      await launchUrl(waUrl, mode: LaunchMode.externalApplication);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final products = _filtered();
    final cats = ['Semua', ...NusaConfig.categories];

    return Scaffold(
      backgroundColor: isDark ? NusaConfig.darkBackground : NusaConfig.backgroundColor,
      body: SafeArea(
        child: Stack(children: [
          Column(children: [
            // ── Header ──
            Container(
              decoration: BoxDecoration(
                color: isDark ? NusaConfig.darkSurface : NusaConfig.surfaceColor,
                boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 10, offset: const Offset(0, 2))],
              ),
              child: Column(children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
                  child: Row(children: [
                    Container(
                      width: 44, height: 44,
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(colors: [NusaConfig.primaryColor, NusaConfig.primaryDark]),
                        borderRadius: BorderRadius.circular(NusaConfig.radiusMD),
                        boxShadow: [BoxShadow(color: NusaConfig.primaryColor.withValues(alpha: 0.3), blurRadius: 8, offset: const Offset(0, 4))],
                      ),
                      alignment: Alignment.center,
                      child: const Text('N', style: TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.w800)),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(_storeName ?? 'NUSA Toko', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: isDark ? NusaConfig.darkTextPrimary : NusaConfig.textPrimary)),
                        const SizedBox(height: 1),
                        Row(children: [
                          Container(width: 6, height: 6, decoration: const BoxDecoration(color: NusaConfig.success, shape: BoxShape.circle)),
                          const SizedBox(width: 4),
                          Text('Buka • Online Order', style: TextStyle(fontSize: 11, color: isDark ? NusaConfig.darkTextTertiary : NusaConfig.textTertiary)),
                        ]),
                      ]),
                    ),
                    GestureDetector(
                      onTap: () => setState(() => _showCart = true),
                      child: Container(
                        padding: const EdgeInsets.all(11),
                        decoration: BoxDecoration(
                          color: isDark ? NusaConfig.darkSurface2 : NusaConfig.inputFill,
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: Stack(clipBehavior: Clip.none, children: [
                          Icon(Icons.shopping_bag_outlined, size: 24, color: isDark ? NusaConfig.darkTextPrimary : NusaConfig.textPrimary),
                          if (_totalItems > 0)
                            Positioned(right: -5, top: -5,
                              child: Container(
                                padding: const EdgeInsets.all(4),
                                decoration: const BoxDecoration(color: NusaConfig.primaryColor, shape: BoxShape.circle),
                                child: Text('$_totalItems', style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w800)),
                              ),
                            ),
                        ]),
                      ),
                    ),
                    const SizedBox(width: 8),
                    GestureDetector(
                      onTap: () => context.pop(),
                      child: Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(color: NusaConfig.errorSoft, borderRadius: BorderRadius.circular(12)),
                        child: const Icon(Icons.close, size: 20, color: NusaConfig.error),
                      ),
                    ),
                  ]),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                  child: Container(
                    height: 44,
                    decoration: BoxDecoration(
                      color: isDark ? NusaConfig.darkSurface2 : NusaConfig.inputFill,
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: TextField(
                      controller: _search, onChanged: (_) => setState(() {}),
                      style: TextStyle(fontSize: 14, color: isDark ? NusaConfig.darkTextPrimary : NusaConfig.textPrimary),
                      decoration: InputDecoration(
                        hintText: 'Cari menu...',
                        hintStyle: TextStyle(fontSize: 14, color: isDark ? NusaConfig.darkTextTertiary : NusaConfig.textTertiary),
                        prefixIcon: const Icon(Icons.search_rounded, size: 20, color: NusaConfig.textSecondary),
                        border: InputBorder.none, contentPadding: const EdgeInsets.symmetric(vertical: 11),
                      ),
                    ),
                  ),
                ),
                SizedBox(
                  height: 46,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
                    itemCount: cats.length,
                    separatorBuilder: (_, __) => const SizedBox(width: 8),
                    itemBuilder: (_, i) {
                      final cat = cats[i];
                      final active = cat == _category;
                      return GestureDetector(
                        onTap: () => setState(() => _category = cat),
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 200),
                          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 9),
                          decoration: BoxDecoration(
                            color: active ? NusaConfig.primaryColor : (isDark ? NusaConfig.darkSurface2 : NusaConfig.dividerColor),
                            borderRadius: BorderRadius.circular(22),
                            boxShadow: active ? [BoxShadow(color: NusaConfig.primaryColor.withValues(alpha: 0.25), blurRadius: 8, offset: const Offset(0, 2))] : [],
                          ),
                          child: Text(cat, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: active ? Colors.white : (isDark ? NusaConfig.darkTextSecondary : NusaConfig.textSecondary))),
                        ),
                      );
                    },
                  ),
                ),
              ]),
            ),
            // ── Product Grid ──
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator(color: NusaConfig.primaryColor))
                  : products.isEmpty
                      ? Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
                          Icon(Icons.inventory_2_outlined, size: 56, color: NusaConfig.textTertiary.withValues(alpha: 0.5)),
                          const SizedBox(height: 12),
                          const Text('Belum ada produk', style: TextStyle(color: NusaConfig.textSecondary, fontSize: 15)),
                        ]))
                      : RefreshIndicator(
                          onRefresh: _load,
                          child: GridView.builder(
                            controller: _scrollCtrl,
                            padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
                            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                              crossAxisCount: 2, crossAxisSpacing: 12, mainAxisSpacing: 12, childAspectRatio: 0.72),
                            itemCount: products.length,
                            itemBuilder: (_, i) => _ProductCard(
                              product: products[i], isDark: isDark,
                              inCart: _cart.any((c) => c.product.id == products[i].id),
                              cartQty: _cart.firstWhere((c) => c.product.id == products[i].id, orElse: () => _StoreItem(product: products[i])).qty,
                              isWishlisted: _wishlist.contains(products[i].id),
                              onToggle: () => _toggleCartItem(products[i]),
                              onWishlist: () => _toggleWishlist(products[i].id),
                              initials: _initials(products[i].name),
                            ),
                          ),
                        ),
            ),
          ]),

          // ── Cart popup ──
          if (_showCartPopup && _totalItems > 0)
            Positioned(
              bottom: 16, left: 16, right: 16,
              child: GestureDetector(
                onTap: () { setState(() { _showCartPopup = false; _showCart = true; }); },
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                  decoration: BoxDecoration(
                    color: NusaConfig.primaryColor,
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: [BoxShadow(color: NusaConfig.primaryColor.withValues(alpha: 0.4), blurRadius: 16, offset: const Offset(0, 6))],
                  ),
                  child: Row(children: [
                    const Icon(Icons.shopping_bag, color: Colors.white, size: 20),
                    const SizedBox(width: 10),
                    const Expanded(
                      child: Text('Lihat Keranjang', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: Colors.white)),
                    ),
                    Text('$_totalItems item · ${formatRupiah(_totalPrice)}',
                      style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Colors.white.withValues(alpha: 0.9))),
                    const SizedBox(width: 8),
                    const Icon(Icons.arrow_forward, color: Colors.white, size: 18),
                  ]),
                ),
              ),
            ),
        ]),
      ),
      bottomSheet: _showCart && _cart.isNotEmpty ? _buildCartSheet(isDark) : null,
    );
  }

  Widget _buildCartSheet(bool isDark) {
    return SafeArea(
      child: GestureDetector(
        onVerticalDragEnd: (d) { if (d.primaryVelocity! > 500) setState(() => _showCart = false); },
        child: Container(
          constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.6),
          decoration: BoxDecoration(
            color: isDark ? NusaConfig.darkSurface : NusaConfig.surfaceColor,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
            boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.12), blurRadius: 20, offset: const Offset(0, -5))],
          ),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Center(child: Container(margin: const EdgeInsets.symmetric(vertical: 10), width: 40, height: 4,
              decoration: BoxDecoration(color: NusaConfig.dividerColor, borderRadius: BorderRadius.circular(2)))),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(children: [
                const Text('🛒  Keranjang', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: NusaConfig.textPrimary)),
                const Spacer(),
                TextButton(onPressed: () { _cart.clear(); setState(() => _showCart = false); },
                  child: const Text('Kosongkan', style: TextStyle(color: NusaConfig.primaryColor, fontWeight: FontWeight.w600))),
              ]),
            ),
            const Divider(height: 1),
            Flexible(
              child: ListView.builder(
                shrinkWrap: true, padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                itemCount: _cart.length,
                itemBuilder: (_, i) {
                  final item = _cart[i];
                  return Container(
                    margin: const EdgeInsets.only(bottom: 8), padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: isDark ? NusaConfig.darkBackground : NusaConfig.backgroundColor,
                      borderRadius: BorderRadius.circular(14)),
                    child: Row(children: [
                      Expanded(
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text(item.product.name, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: isDark ? NusaConfig.darkTextPrimary : NusaConfig.textPrimary)),
                          const SizedBox(height: 2),
                          Text(formatRupiah(item.product.sellPrice), style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: NusaConfig.primaryColor)),
                        ]),
                      ),
                      Container(
                        height: 34,
                        decoration: BoxDecoration(border: Border.all(color: NusaConfig.primaryColor, width: 1.5), borderRadius: BorderRadius.circular(10), color: NusaConfig.primarySoft),
                        child: Row(children: [
                          GestureDetector(
                            onTap: () { if (item.qty <= 1) { _cart.removeAt(i); } else { item.qty--; } setState(() {}); if (_cart.isEmpty) setState(() => _showCart = false); },
                            child: const SizedBox(width: 30, height: 34, child: Icon(Icons.remove, size: 16, color: NusaConfig.primaryColor)),
                          ),
                          Text('${item.qty}', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: NusaConfig.primaryColor)),
                          GestureDetector(
                            onTap: () { item.qty++; setState(() {}); },
                            child: const SizedBox(width: 30, height: 34, child: Icon(Icons.add, size: 16, color: NusaConfig.primaryColor)),
                          ),
                        ]),
                      ),
                    ]),
                  );
                },
              ),
            ),
            Container(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
              decoration: BoxDecoration(color: isDark ? NusaConfig.darkBackground : NusaConfig.backgroundColor, border: Border(top: BorderSide(color: isDark ? NusaConfig.darkBorder : NusaConfig.dividerColor))),
              child: Column(children: [
                Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                  Text('$_totalItems item', style: TextStyle(fontSize: 13, color: isDark ? NusaConfig.darkTextSecondary : NusaConfig.textSecondary)),
                  Text(formatRupiah(_totalPrice), style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: NusaConfig.primaryColor, letterSpacing: -0.5)),
                ]),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity, height: 50,
                  child: ElevatedButton(
                    onPressed: () { setState(() => _showCart = false); _showCheckoutSheet(context, isDark); },
                    style: ElevatedButton.styleFrom(backgroundColor: NusaConfig.primaryColor, foregroundColor: Colors.white, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)), textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                    child: const Text('Lanjutkan Pesanan'),
                  ),
                ),
              ]),
            ),
          ]),
        ),
      ),
    );
  }

  void _showCheckoutSheet(BuildContext ctx, bool isDark) {
    showModalBottomSheet(
      context: ctx, isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (bCtx) => StatefulBuilder(
        builder: (bCtx, setSheetState) => Container(
          padding: EdgeInsets.only(bottom: MediaQuery.of(bCtx).viewInsets.bottom),
          constraints: BoxConstraints(maxHeight: MediaQuery.of(bCtx).size.height * 0.85),
          child: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Center(child: Container(margin: const EdgeInsets.symmetric(vertical: 10), width: 40, height: 4,
                decoration: BoxDecoration(color: NusaConfig.dividerColor, borderRadius: BorderRadius.circular(2)))),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  const Text('Selesaikan Pembayaran', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: NusaConfig.textPrimary)),
                  const SizedBox(height: 6),
                  Text(formatRupiah(_totalPrice), style: const TextStyle(fontSize: 32, fontWeight: FontWeight.w800, color: NusaConfig.primaryColor, letterSpacing: -1)),
                  const SizedBox(height: 20),
                  const Text('DATA PEMESAN', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: NusaConfig.textSecondary, letterSpacing: 0.5)),
                  const SizedBox(height: 8),
                  _checkoutField('Nama', _nameCtrl, 'Nama Anda', Icons.person_outline),
                  const SizedBox(height: 8),
                  _checkoutField('WhatsApp', _phoneCtrl, '0812-3456-7890', Icons.phone_outlined, keyboard: TextInputType.phone),
                  const SizedBox(height: 16),
                  const Text('CABANG', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: NusaConfig.textSecondary, letterSpacing: 0.5)),
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14),
                    decoration: BoxDecoration(color: NusaConfig.inputFill, borderRadius: BorderRadius.circular(NusaConfig.radiusMD), border: Border.all(color: NusaConfig.dividerColor)),
                    child: DropdownButtonHideUnderline(
                      child: DropdownButton<String>(
                        value: _branch, isExpanded: true,
                        style: const TextStyle(fontSize: 14, color: NusaConfig.textPrimary),
                        items: ['Pusat', 'Cabang 1', 'Cabang 2'].map((b) => DropdownMenuItem(value: b, child: Text(b))).toList(),
                        onChanged: (v) { if (v == null) return; _branch = v; setSheetState(() {}); },
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  const Text('METODE PEMBAYARAN', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: NusaConfig.textSecondary, letterSpacing: 0.5)),
                  const SizedBox(height: 8),
                  Row(children: [
                    _paymentOption('Tunai', Icons.money, setSheetState: setSheetState),
                    const SizedBox(width: 10),
                    _paymentOption('QRIS', Icons.qr_code, setSheetState: setSheetState),
                    const SizedBox(width: 10),
                    _paymentOption('Transfer', Icons.account_balance, setSheetState: setSheetState),
                  ]),
                  const SizedBox(height: 24),
                  SizedBox(
                    width: double.infinity, height: 52,
                    child: ElevatedButton.icon(
                      onPressed: () { Navigator.pop(bCtx); _sendWhatsApp(); },
                      icon: const Icon(Icons.chat, size: 20),
                      label: const Text('Kirim Pesanan via WhatsApp', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
                      style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF25D366), foregroundColor: Colors.white, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14))),
                    ),
                  ),
                  const SizedBox(height: 20),
                ]),
              ),
            ]),
          ),
        ),
      ),
    );
  }

  Widget _checkoutField(String label, TextEditingController ctrl, String hint, IconData icon, {TextInputType keyboard = TextInputType.text}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14),
      decoration: BoxDecoration(color: NusaConfig.inputFill, borderRadius: BorderRadius.circular(NusaConfig.radiusMD), border: Border.all(color: NusaConfig.dividerColor)),
      child: TextField(
        controller: ctrl, keyboardType: keyboard,
        style: const TextStyle(fontSize: 14, color: NusaConfig.textPrimary),
        decoration: InputDecoration(
          labelText: label, labelStyle: const TextStyle(fontSize: 12, color: NusaConfig.textSecondary),
          hintText: hint, hintStyle: const TextStyle(fontSize: 13, color: NusaConfig.textTertiary),
          prefixIcon: Icon(icon, size: 18, color: NusaConfig.textSecondary),
          border: InputBorder.none,
        ),
      ),
    );
  }

  Widget _paymentOption(String method, IconData icon, {required void Function(void Function()) setSheetState}) {
    final active = _paymentMethod == method;
    return Expanded(
      child: GestureDetector(
        onTap: () { _paymentMethod = method; setSheetState(() {}); },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(vertical: 14),
          decoration: BoxDecoration(
            color: active ? NusaConfig.primarySoft : NusaConfig.inputFill,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: active ? NusaConfig.primaryColor : NusaConfig.dividerColor, width: active ? 2 : 1),
          ),
          child: Column(children: [
            Icon(icon, size: 24, color: active ? NusaConfig.primaryColor : NusaConfig.textSecondary),
            const SizedBox(height: 4),
            Text(method, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: active ? NusaConfig.primaryColor : NusaConfig.textSecondary)),
          ]),
        ),
      ),
    );
  }
}

// ── Product Card (storefront) ──

class _ProductCard extends StatelessWidget {
  final Product product;
  final bool isDark;
  final bool inCart;
  final int cartQty;
  final VoidCallback onToggle;
  final bool isWishlisted;
  final VoidCallback onWishlist;
  final String initials;
  const _ProductCard({
    required this.product, required this.isDark,
    required this.inCart, required this.cartQty, required this.onToggle,
    required this.isWishlisted, required this.onWishlist,
    required this.initials,
  });

  @override
  Widget build(BuildContext context) {
    final outOfStock = product.stock <= 0;
    final gradient = NusaConfig.catGradientFor(product.category);
    final hasImage = product.imagePath != null && product.imagePath!.isNotEmpty && File(product.imagePath!).existsSync();

    return GestureDetector(
      onTap: outOfStock ? null : () { if (cartQty == 0) onToggle(); },
      child: Container(
        decoration: BoxDecoration(
          color: isDark ? NusaConfig.darkSurface : NusaConfig.surfaceColor,
          borderRadius: BorderRadius.circular(NusaConfig.radiusLG),
          boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: isDark ? 0.15 : 0.10), blurRadius: 10, offset: const Offset(0, 3))],
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          // ── Image area (4:3) ──
          AspectRatio(
            aspectRatio: 4 / 3,
            child: ClipRRect(
              borderRadius: BorderRadius.vertical(top: Radius.circular(NusaConfig.radiusLG)),
              child: Stack(children: [
                // Background: photo or gradient + initials
                if (hasImage)
                  Image.file(File(product.imagePath!), fit: BoxFit.cover, width: double.infinity)
                else
                  Container(
                    decoration: BoxDecoration(gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: gradient)),
                    alignment: Alignment.center,
                    child: Text(initials, style: const TextStyle(fontSize: 32, fontWeight: FontWeight.w800, color: Colors.white, letterSpacing: 0.5)),
                  ),
                // Wishlist button
                Positioned(top: 8, right: 8,
                  child: GestureDetector(
                    onTap: onWishlist,
                    child: Container(
                      width: 32, height: 32,
                      decoration: BoxDecoration(
                        color: isWishlisted ? NusaConfig.primaryColor : Colors.black.withValues(alpha: 0.25),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(isWishlisted ? Icons.favorite : Icons.favorite_border, size: 16, color: Colors.white),
                    ),
                  ),
                ),
                // HABIS badge
                if (outOfStock)
                  Positioned(top: 10, left: 10,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                      decoration: BoxDecoration(color: NusaConfig.primaryColor, borderRadius: BorderRadius.circular(NusaConfig.radiusSM)),
                      child: const Text('HABIS', style: TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w800, letterSpacing: 0.5)),
                    ),
                  ),
                // Price tag
                Positioned(bottom: 10, right: 8,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(color: NusaConfig.surfaceColor.withValues(alpha: 0.95), borderRadius: BorderRadius.circular(NusaConfig.radiusFull), boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.08), blurRadius: 4)]),
                    child: Text(formatRupiah(product.sellPrice), style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: NusaConfig.primaryColor)),
                  ),
                ),
                if (outOfStock) Container(color: Colors.white.withValues(alpha: 0.35)),
              ]),
            ),
          ),
          // ── Info ──
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(product.name, maxLines: 2, overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, height: 1.3,
                  color: outOfStock ? NusaConfig.textTertiary : (isDark ? NusaConfig.darkTextPrimary : NusaConfig.textPrimary))),
              const SizedBox(height: 3),
              Text(product.category, style: TextStyle(fontSize: 11, color: isDark ? NusaConfig.darkTextTertiary : NusaConfig.textTertiary)),
            ]),
          ),
          // ── Single action button ──
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 6, 16, 12),
            child: outOfStock
                ? const SizedBox(height: 32)
                : cartQty == 0
                    ? Center(
                        child: SizedBox(
                          height: 32,
                          child: OutlinedButton(
                            onPressed: onToggle,
                            style: OutlinedButton.styleFrom(
                              foregroundColor: NusaConfig.primaryColor,
                              side: const BorderSide(color: NusaConfig.primaryColor, width: 1.5),
                              padding: const EdgeInsets.symmetric(horizontal: 24),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                              textStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
                            ),
                            child: const Text('+ Tambah'),
                          ),
                        ),
                      )
                    : Center(
                        child: Container(
                          height: 32,
                          decoration: BoxDecoration(color: NusaConfig.primaryColor, borderRadius: BorderRadius.circular(10)),
                          child: Row(mainAxisSize: MainAxisSize.min, children: [
                            GestureDetector(onTap: onToggle, child: const SizedBox(width: 32, height: 32, child: Center(child: Icon(Icons.remove, size: 16, color: Colors.white)))),
                            Container(constraints: const BoxConstraints(minWidth: 24), child: Text('$cartQty', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: Colors.white), textAlign: TextAlign.center)),
                            GestureDetector(onTap: onToggle, child: const SizedBox(width: 32, height: 32, child: Center(child: Icon(Icons.add, size: 16, color: Colors.white)))),
                          ]),
                        ),
                      ),
          ),
        ]),
      ),
    );
  }
}
