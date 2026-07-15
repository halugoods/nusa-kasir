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

// ─── Cart Model (local to storefront) ────────────────────────────────

class _StoreItem {
  final Product product;
  int qty;
  _StoreItem({required this.product, this.qty = 1});
  int get subtotal => product.sellPrice * qty;
}

// ─── State ───────────────────────────────────────────────────────────

class _StorefrontScreenState extends ConsumerState<StorefrontScreen> {
  List<Product> _allProducts = [];
  bool _loading = true;
  String _category = 'Semua';
  final _search = TextEditingController();
  final List<_StoreItem> _cart = [];
  bool _showCart = false;

  // Checkout fields
  final _nameCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  String _paymentMethod = 'Tunai';
  String _branch = 'Pusat';
  String? _storeName;
  String? _storePhone;
  bool _showCheckout = false;

  final _scrollCtrl = ScrollController();

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _search.dispose();
    _nameCtrl.dispose();
    _phoneCtrl.dispose();
    _scrollCtrl.dispose();
    super.dispose();
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

  List<Product> _filteredProducts() {
    final q = _search.text.toLowerCase();
    return _allProducts.where((p) {
      if (_category != 'Semua' && p.category != _category) return false;
      if (q.isNotEmpty && !p.name.toLowerCase().contains(q)) return false;
      return true;
    }).toList();
  }

  void _toggleCartItem(Product p) {
    final idx = _cart.indexWhere((c) => c.product.id == p.id);
    if (idx >= 0) {
      if (_cart[idx].qty <= 1) {
        _cart.removeAt(idx);
      } else {
        _cart[idx].qty--;
      }
    } else {
      _cart.add(_StoreItem(product: p));
    }
    setState(() {});
  }

  void _removeCartItem(int idx) {
    _cart.removeAt(idx);
    setState(() {});
  }

  int get _totalItems => _cart.fold(0, (s, e) => s + e.qty);
  int get _totalPrice => _cart.fold(0, (s, e) => s + e.subtotal);

  Future<void> _sendWhatsApp() async {
    final name = _nameCtrl.text.trim();
    final phone = _phoneCtrl.text.trim();
    if (name.isEmpty || phone.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Nama dan WhatsApp wajib diisi')),
      );
      return;
    }

    final itemsText = _cart.map((c) =>
      '• ${c.product.name} x${c.qty} — ${formatRupiah(c.subtotal)}'
    ).join('\n');

    final msg = Uri.encodeComponent(
      '🛒 *Pesanan Baru*\n\n'
      '👤 ${name}\n'
      '📱 ${phone}\n'
      '🏪 ${_branch}\n'
      '💳 ${_paymentMethod}\n\n'
      '*Item:*\n${itemsText}\n\n'
      '*Total: ${formatRupiah(_totalPrice)}*'
    );

    final targetPhone = _storePhone ?? '';
    final waUrl = Uri.parse('https://wa.me/$targetPhone?text=$msg');
    if (await canLaunchUrl(waUrl)) {
      await launchUrl(waUrl, mode: LaunchMode.externalApplication);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final products = _filteredProducts();
    final cats = ['Semua', ...NusaConfig.categories];

    return Scaffold(
      backgroundColor: isDark ? NusaConfig.darkBackground : const Color(0xFFF8FAFC),
      body: SafeArea(
        child: Column(
          children: [
            // ── Sticky Header ──
            Container(
              color: isDark ? NusaConfig.darkSurface : Colors.white,
              child: Column(children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                  child: Row(children: [
                    Container(
                      width: 40, height: 40,
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(colors: [NusaConfig.primaryColor, NusaConfig.primaryDark]),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      alignment: Alignment.center,
                      child: const Text('N', style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w800)),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(_storeName ?? 'NUSA Toko', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: isDark ? NusaConfig.darkTextPrimary : NusaConfig.textPrimary)),
                        Text('Online Order', style: TextStyle(fontSize: 11, color: isDark ? NusaConfig.darkTextTertiary : NusaConfig.textTertiary)),
                      ]),
                    ),
                    GestureDetector(
                      onTap: () => setState(() => _showCart = true),
                      child: Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: isDark ? NusaConfig.darkSurface2 : const Color(0xFFF1F5F9),
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: Stack(
                          clipBehavior: Clip.none,
                          children: [
                            Icon(Icons.shopping_bag_outlined, size: 22, color: isDark ? NusaConfig.darkTextPrimary : NusaConfig.textPrimary),
                            if (_totalItems > 0)
                              Positioned(
                                right: -4, top: -4,
                                child: Container(
                                  padding: const EdgeInsets.all(4),
                                  decoration: const BoxDecoration(color: NusaConfig.primaryColor, shape: BoxShape.circle),
                                  child: Text('$_totalItems', style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w700)),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    GestureDetector(
                      onTap: () => context.pop(),
                      child: Icon(Icons.close, size: 22, color: isDark ? NusaConfig.darkTextSecondary : NusaConfig.textSecondary),
                    ),
                  ]),
                ),
                // Search
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                  child: Container(
                    height: 42,
                    decoration: BoxDecoration(
                      color: isDark ? NusaConfig.darkSurface2 : const Color(0xFFF1F5F9),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: TextField(
                      controller: _search,
                      onChanged: (_) => setState(() {}),
                      style: TextStyle(fontSize: 14, color: isDark ? NusaConfig.darkTextPrimary : NusaConfig.textPrimary),
                      decoration: InputDecoration(
                        hintText: 'Cari menu...',
                        hintStyle: TextStyle(fontSize: 14, color: isDark ? NusaConfig.darkTextTertiary : NusaConfig.textTertiary),
                        prefixIcon: const Icon(Icons.search_rounded, size: 20, color: NusaConfig.textSecondary),
                        border: InputBorder.none,
                        contentPadding: const EdgeInsets.symmetric(vertical: 11),
                      ),
                    ),
                  ),
                ),
                // Category pills
                SizedBox(
                  height: 44,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
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
                            color: active ? NusaConfig.primaryColor : (isDark ? NusaConfig.darkSurface2 : const Color(0xFFF1F5F9)),
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
                      ? Center(
                          child: Column(mainAxisSize: MainAxisSize.min, children: [
                            Icon(Icons.inventory_2_outlined, size: 56, color: NusaConfig.textTertiary.withValues(alpha: 0.5)),
                            const SizedBox(height: 12),
                            const Text('Belum ada produk', style: TextStyle(color: NusaConfig.textSecondary, fontSize: 15)),
                          ]),
                        )
                      : RefreshIndicator(
                          onRefresh: _load,
                          child: GridView.builder(
                            controller: _scrollCtrl,
                            padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
                            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 2, crossAxisSpacing: 12, mainAxisSpacing: 12, childAspectRatio: 0.72),
                            itemCount: products.length,
                            itemBuilder: (_, i) => _ProductCard(
                              product: products[i],
                              isDark: isDark,
                              inCart: _cart.any((c) => c.product.id == products[i].id),
                              cartQty: _cart.firstWhere((c) => c.product.id == products[i].id, orElse: () => _StoreItem(product: products[i])).qty,
                              onToggle: () => _toggleCartItem(products[i]),
                            ),
                          ),
                        ),
            ),
          ],
        ),
      ),
      // ── Cart Bottom Sheet ──
      bottomSheet: _showCart && _cart.isNotEmpty
          ? _buildCartSheet(isDark)
          : null,
    );
  }

  Widget _buildCartSheet(bool isDark) {
    return GestureDetector(
      onVerticalDragEnd: (d) { if (d.primaryVelocity! > 500) setState(() => _showCart = false); },
      child: Container(
        constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.6),
        decoration: BoxDecoration(
          color: isDark ? NusaConfig.darkSurface : Colors.white,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
          boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.1), blurRadius: 20, offset: const Offset(0, -5))],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
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
                const Text('🛒 Keranjang Anda', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: NusaConfig.textPrimary)),
                const Spacer(),
                TextButton(onPressed: () { _cart.clear(); setState(() { _showCart = false; }); }, child: const Text('Kosongkan', style: TextStyle(color: NusaConfig.primaryColor, fontWeight: FontWeight.w600))),
              ]),
            ),
            const Divider(height: 1),
            // Items
            Flexible(
              child: ListView.builder(
                shrinkWrap: true,
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                itemCount: _cart.length,
                itemBuilder: (_, i) {
                  final item = _cart[i];
                  return Container(
                    margin: const EdgeInsets.only(bottom: 8),
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: isDark ? NusaConfig.darkBackground : const Color(0xFFF8FAFC),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Row(children: [
                      Expanded(
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text(item.product.name, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: isDark ? NusaConfig.darkTextPrimary : NusaConfig.textPrimary)),
                          const SizedBox(height: 2),
                          Text(formatRupiah(item.product.sellPrice), style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: NusaConfig.primaryColor)),
                        ]),
                      ),
                      // Qty stepper
                      Container(
                        height: 32,
                        decoration: BoxDecoration(
                          border: Border.all(color: NusaConfig.primaryColor, width: 1.5),
                          borderRadius: BorderRadius.circular(10),
                          color: NusaConfig.primarySoft,
                        ),
                        child: Row(children: [
                          GestureDetector(
                            onTap: () {
                              if (item.qty <= 1) { _cart.removeAt(i); } else { item.qty--; }
                              setState(() {});
                              if (_cart.isEmpty) setState(() => _showCart = false);
                            },
                            child: const SizedBox(width: 28, height: 32, child: Icon(Icons.remove, size: 16, color: NusaConfig.primaryColor)),
                          ),
                          Text('${item.qty}', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: NusaConfig.primaryColor)),
                          GestureDetector(
                            onTap: () { item.qty++; setState(() {}); },
                            child: const SizedBox(width: 28, height: 32, child: Icon(Icons.add, size: 16, color: NusaConfig.primaryColor)),
                          ),
                        ]),
                      ),
                    ]),
                  );
                },
              ),
            ),
            // Total + Checkout
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
                    onPressed: () {
                      setState(() { _showCart = false; _showCheckout = true; });
                      Future.microtask(() => _showCheckoutSheet(context, isDark));
                    },
                    style: ElevatedButton.styleFrom(backgroundColor: NusaConfig.primaryColor, foregroundColor: Colors.white, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)), textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                    child: const Text('Lanjutkan Pesanan'),
                  ),
                ),
              ]),
            ),
          ],
        ),
      ),
    );
  }

  void _showCheckoutSheet(BuildContext ctx, bool isDark) {
    showModalBottomSheet(
      context: ctx,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (bCtx) => StatefulBuilder(
        builder: (bCtx, setSheetState) => Container(
          padding: EdgeInsets.only(bottom: MediaQuery.of(bCtx).viewInsets.bottom),
          constraints: BoxConstraints(maxHeight: MediaQuery.of(bCtx).size.height * 0.85),
          child: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              // Handle
              Center(
                child: Container(
                  margin: const EdgeInsets.symmetric(vertical: 10),
                  width: 40, height: 4,
                  decoration: BoxDecoration(color: NusaConfig.dividerColor, borderRadius: BorderRadius.circular(2)),
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  const Text('Selesaikan Pembayaran', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: NusaConfig.textPrimary)),
                  const SizedBox(height: 6),
                  Text(formatRupiah(_totalPrice), style: const TextStyle(fontSize: 32, fontWeight: FontWeight.w800, color: NusaConfig.primaryColor, letterSpacing: -1)),
                  const SizedBox(height: 20),

                  // Data Pemesan
                  const Text('DATA PEMESAN', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: NusaConfig.textSecondary, letterSpacing: 0.5)),
                  const SizedBox(height: 8),
                  _checkoutField('Nama', _nameCtrl, 'Nama Anda', Icons.person_outline),
                  const SizedBox(height: 8),
                  _checkoutField('WhatsApp', _phoneCtrl, '0812-3456-7890', Icons.phone_outlined, keyboard: TextInputType.phone),
                  const SizedBox(height: 16),

                  // Cabang
                  const Text('CABANG', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: NusaConfig.textSecondary, letterSpacing: 0.5)),
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14),
                    decoration: BoxDecoration(color: const Color(0xFFF9FAFB), borderRadius: BorderRadius.circular(12), border: Border.all(color: NusaConfig.dividerColor)),
                    child: DropdownButtonHideUnderline(
                      child: DropdownButton<String>(
                        value: _branch,
                        isExpanded: true,
                        style: const TextStyle(fontSize: 14, color: NusaConfig.textPrimary),
                        items: ['Pusat', 'Cabang 1', 'Cabang 2'].map((b) => DropdownMenuItem(value: b, child: Text(b))).toList(),
                        onChanged: (v) { if (v == null) return; _branch = v; setSheetState(() {}); },
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Payment Method
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

                  // Send CTA
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
      decoration: BoxDecoration(color: const Color(0xFFF9FAFB), borderRadius: BorderRadius.circular(12), border: Border.all(color: NusaConfig.dividerColor)),
      child: TextField(
        controller: ctrl,
        keyboardType: keyboard,
        style: const TextStyle(fontSize: 14, color: NusaConfig.textPrimary),
        decoration: InputDecoration(
          labelText: label,
          labelStyle: const TextStyle(fontSize: 12, color: NusaConfig.textSecondary),
          hintText: hint,
          hintStyle: const TextStyle(fontSize: 13, color: NusaConfig.textTertiary),
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
            color: active ? NusaConfig.primarySoft : const Color(0xFFF9FAFB),
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

// ── Product Card ─────────────────────────────────────────────────────

class _ProductCard extends StatelessWidget {
  final Product product;
  final bool isDark;
  final bool inCart;
  final int cartQty;
  final VoidCallback onToggle;

  const _ProductCard({
    required this.product, required this.isDark,
    required this.inCart, required this.cartQty, required this.onToggle,
  });

  @override
  Widget build(BuildContext context) {
    final outOfStock = product.stock <= 0;

    return GestureDetector(
      onTap: outOfStock ? null : onToggle,
      child: Container(
        decoration: BoxDecoration(
          color: isDark ? NusaConfig.darkSurface : Colors.white,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: isDark ? NusaConfig.darkBorder : const Color(0xFFF1F5F9)),
          boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 8, offset: const Offset(0, 2))],
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          // Image area
          Expanded(
            child: Stack(
              children: [
                ClipRRect(
                  borderRadius: const BorderRadius.vertical(top: Radius.circular(18)),
                  child: product.imagePath != null && product.imagePath!.isNotEmpty
                      ? Image.asset(product.imagePath!, fit: BoxFit.cover, width: double.infinity, errorBuilder: (_, __, ___) => _placeholder(isDark))
                      : _placeholder(isDark),
                ),
                // Badges
                if (outOfStock)
                  Positioned(top: 8, left: 8, child: Container(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4), decoration: BoxDecoration(color: const Color(0xFF1E293B), borderRadius: BorderRadius.circular(6)), child: const Text('HABIS', style: TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w700)))),
                // Price badge
                Positioned(
                  bottom: 6, right: 6,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(10), boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.08), blurRadius: 4)]),
                    child: Text(formatRupiah(product.sellPrice), style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: NusaConfig.primaryColor)),
                  ),
                ),
              ],
            ),
          ),
          // Info + action
          Padding(
            padding: const EdgeInsets.fromLTRB(10, 10, 10, 8),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(product.name, maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, height: 1.2, color: outOfStock ? NusaConfig.textTertiary : (isDark ? NusaConfig.darkTextPrimary : NusaConfig.textPrimary))),
              const SizedBox(height: 3),
              Text(product.category, style: TextStyle(fontSize: 11, color: isDark ? NusaConfig.darkTextTertiary : NusaConfig.textTertiary)),
              const SizedBox(height: 8),
              // Action button
              if (outOfStock)
                const SizedBox(height: 34)
              else if (inCart)
                _InlineStepper(qty: cartQty, onToggle: onToggle)
              else
                SizedBox(
                  width: double.infinity, height: 34,
                  child: ElevatedButton(
                    onPressed: onToggle,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: NusaConfig.primarySoft, foregroundColor: NusaConfig.primaryColor,
                      elevation: 0, padding: EdgeInsets.zero,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
                    ),
                    child: const Text('+ Tambah'),
                  ),
                ),
            ]),
          ),
        ]),
      ),
    );
  }

  Widget _placeholder(bool isDark) {
    final emoji = _catEmojiMap[product.category] ?? '📦';
    return Container(
      color: isDark ? NusaConfig.darkSurface2 : const Color(0xFFF1F5F9),
      alignment: Alignment.center,
      child: Text(emoji, style: const TextStyle(fontSize: 36)),
    );
  }
}

const _catEmojiMap = <String, String>{'Makanan':'🍜','Minuman':'🥤','Sembako':'📦','Lainnya':'🧴'};

// ── Inline Qty Stepper (on product card) ─────────────────────────────

class _InlineStepper extends StatelessWidget {
  final int qty;
  final VoidCallback onToggle;
  const _InlineStepper({required this.qty, required this.onToggle});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 34,
      decoration: BoxDecoration(
        color: NusaConfig.primaryColor,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(children: [
        GestureDetector(
          onTap: onToggle,
          child: const SizedBox(width: 32, height: 34, child: Center(child: Icon(Icons.remove, size: 16, color: Colors.white))),
        ),
        Container(
          constraints: const BoxConstraints(minWidth: 24),
          child: Text('$qty', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: Colors.white), textAlign: TextAlign.center),
        ),
        GestureDetector(
          onTap: onToggle,
          child: const SizedBox(width: 32, height: 34, child: Center(child: Icon(Icons.add, size: 16, color: Colors.white))),
        ),
      ]),
    );
  }
}
