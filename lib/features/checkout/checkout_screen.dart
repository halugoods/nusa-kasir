import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:qr_flutter/qr_flutter.dart';

import 'package:nusa_kasir/core/providers.dart';
import 'package:nusa_kasir/core/config/nusa_config.dart';
import 'package:nusa_kasir/core/utils/format_rupiah.dart';
import 'package:nusa_kasir/data/database/app_database.dart';
import 'package:nusa_kasir/data/repositories/customer_repository.dart';
import 'package:nusa_kasir/data/repositories/product_repository.dart';
import 'package:nusa_kasir/data/repositories/promo_repository.dart';
import 'package:nusa_kasir/data/repositories/settings_repository.dart';
import 'package:nusa_kasir/features/auth/employee_session_provider.dart';
import 'package:nusa_kasir/features/pos/cart.dart';
import 'package:nusa_kasir/shared/widgets/top_toast.dart';
import 'package:nusa_kasir/shared/widgets/screen_scaffold.dart';
import 'package:nusa_kasir/features/checkout/receipt_sheet.dart';

/// Shared section card style used across all checkout cards.
BoxDecoration _sectionCard(bool isDark) => BoxDecoration(
  color: isDark ? NusaConfig.darkSurface : NusaConfig.surfaceColor,
  borderRadius: BorderRadius.circular(18),
  border: Border.all(color: isDark ? NusaConfig.darkBorder : NusaConfig.dividerColor),
  boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.03), blurRadius: 8, offset: const Offset(0, 2))],
);

class CheckoutScreen extends ConsumerStatefulWidget {
  final int? sessionId;
  const CheckoutScreen({super.key, this.sessionId});
  @override
  ConsumerState<CheckoutScreen> createState() => _CheckoutScreenState();
}

class _CheckoutScreenState extends ConsumerState<CheckoutScreen> {
  final _discountCtrl = TextEditingController();
  final _cashCtrl = TextEditingController();
  final _promoCtrl = TextEditingController();
  String _paymentMethod = 'Tunai';
  bool _loading = false;
  int? _cashGiven;
  String? _qrisString;
  String? _bankName;
  String? _bankAccount;
  String? _bankHolder;
  Customer? _selectedCustomer;
  Promo? _appliedPromo;
  int _promoDiscount = 0; // computed from applied promo
  int _pointsUsed = 0; // poin yang ditukar (1 poin = Rp 1)

  int get _subtotal => ref.watch(cartProvider).fold(0, (s, e) => s + e.subtotal);
  int get _manualDiscount => int.tryParse(_discountCtrl.text) ?? 0;
  int get _tierDiscount {
    if (_selectedCustomer == null) return 0;
    final pct = CustomerRepository.tierDiscountPercent(_selectedCustomer!.level);
    return (_subtotal * pct / 100).round();
  }
  int get _totalDiscount =>
      (_manualDiscount + _promoDiscount + _tierDiscount + _pointsUsed).clamp(0, _subtotal);
  int get _total => (_subtotal - _totalDiscount).clamp(0, _subtotal);
  int? get _kembalian =>
      _cashGiven != null && _cashGiven! >= _total ? _cashGiven! - _total : null;

  @override
  void initState() {
    super.initState();
    _loadPaymentSettings();
  }

  Future<void> _loadPaymentSettings() async {
    final repo = ref.read(settingsRepoProvider);
    final qris = await repo.getQris();
    final bankName = await repo.getBankName();
    final bankAccount = await repo.getBankAccount();
    final bankHolder = await repo.getBankHolder();
    if (mounted) setState(() {
      _qrisString = qris;
      _bankName = bankName;
      _bankAccount = bankAccount;
      _bankHolder = bankHolder;
    });
  }

  @override
  void dispose() {
    _discountCtrl.dispose();
    _cashCtrl.dispose();
    _promoCtrl.dispose();
    super.dispose();
  }

  Future<void> _applyPromo() async {
    final code = _promoCtrl.text.trim();
    if (code.isEmpty) {
      TopToast.error(context, 'Masukkan kode promo');
      return;
    }
    final repo = PromoRepository(ref.read(databaseProvider));
    final promos = await repo.getPromos();
    final match = promos.cast<Promo?>().firstWhere(
          (p) => p!.code.toUpperCase() == code.toUpperCase() && p.status == 'Aktif',
          orElse: () => null,
        );
    if (match == null) {
      TopToast.error(context, 'Kode promo tidak valid atau tidak aktif');
      return;
    }

    // Check min belanja
    if (_subtotal < match.minBelanja) {
      TopToast.error(context, 'Min. belanja ${formatRupiah(match.minBelanja)}');
      return;
    }

    // Check kuota
    if (match.maxUses != null && match.usedCount >= match.maxUses!) {
      TopToast.error(context, 'Kuota promo sudah habis');
      return;
    }

    // Calculate discount
    int discount;
    if (match.type == 'persen') {
      discount = (_subtotal * match.value / 100).round();
    } else {
      discount = match.value;
    }
    discount = discount.clamp(0, _subtotal);

    setState(() {
      _appliedPromo = match;
      _promoDiscount = discount;
    });
    TopToast.success(context, 'Promo "${match.name}" diterapkan!');
  }

  void _clearPromo() {
    setState(() {
      _appliedPromo = null;
      _promoDiscount = 0;
      _promoCtrl.clear();
    });
  }

  Future<void> _pickCustomer() async {
    final repo = CustomerRepository(ref.read(databaseProvider));
    final customers = await repo.getCustomers();
    if (!mounted) return;
    if (customers.isEmpty) {
      TopToast.info(context, 'Belum ada pelanggan. Tambah di menu Pelanggan.');
      return;
    }
    final c = await showDialog<Customer>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Pilih Pelanggan'),
        content: SizedBox(
          width: double.maxFinite,
          child: ListView.builder(
            shrinkWrap: true,
            itemCount: customers.length,
            itemBuilder: (_, i) => ListTile(
              title: Text(customers[i].name,
                  style: const TextStyle(fontWeight: FontWeight.w600)),
              subtitle: Text(
                  '${formatRupiah(customers[i].totalSpent)} • ${customers[i].level}'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.pop(ctx, customers[i]),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Batal'),
          ),
        ],
      ),
    );
    if (c != null && mounted) {
      setState(() {
        _selectedCustomer = c;
        _pointsUsed = 0; // reset when switching customer
      });
      TopToast.success(context, 'Pelanggan: ${c.name}');
    }
  }

  Future<void> _confirmPayment() async {
    final cart = ref.read(cartProvider);
    if (cart.isEmpty) {
      TopToast.error(context, 'Keranjang kosong');
      return;
    }

    if (_paymentMethod == 'Tunai') {
      final given = int.tryParse(_cashCtrl.text) ?? 0;
      if (given < _total) {
        TopToast.error(context, 'Jumlah dibayarkan kurang');
        return;
      }
    }

    // Validate stock before deducting
    final db = ref.read(databaseProvider);
    final productRepo = ProductRepository(db);
    for (final item in cart) {
      final product = await productRepo.byId(item.productId);
      if (product == null || product.stock < item.qty) {
        final name = product?.name ?? item.name;
        if (mounted) {
          TopToast.error(context, 'Stok "$name" tidak cukup (tersedia: ${product?.stock ?? 0})');
        }
        return;
      }
    }

    setState(() => _loading = true);

    try {
      final transactionRepo = ref.read(transactionRepoProvider);
      final session = ref.read(employeeSessionProvider);
      final cashierName = session?.name;
      final cashGiven = int.tryParse(_cashCtrl.text);
      final cashReturn = cashGiven != null && cashGiven >= _total
          ? cashGiven - _total
          : null;

      // Wrap all DB writes (stock, transaction, loyalty, promo) in a single transaction.
      // If any step fails, it all rolls back — no partial state.
      await db.transaction(() async {
        // Deduct stock for each item
        for (final item in cart) {
          await productRepo.adjustStock(item.productId, -item.qty);
        }

        // Save transaction
        await transactionRepo.saveTransaction(
          items: cart,
          total: _total,
          discount: _totalDiscount,
          paymentMethod: _paymentMethod,
          cashGiven: cashGiven,
          cashReturn: cashReturn,
          cashierName: cashierName,
          customerId: _selectedCustomer?.id,
          branchId: ref.read(activeBranchProvider)?.id,
        );

        // Update customer loyalty
        if (_selectedCustomer != null) {
          final pointConfig = await SettingsRepository(db).getPointConfig();
          await CustomerRepository(db).addSpent(
            _selectedCustomer!.id, _total,
            pointsPerRupiah: pointConfig['pointsPerRupiah']!,
            goldThreshold: pointConfig['goldThreshold']!,
            platinumThreshold: pointConfig['platinumThreshold']!,
          );
        }

        // Increment promo usage
        if (_appliedPromo != null) {
          await PromoRepository(db).incrementUsed(_appliedPromo!.id);
        }

        // Redeem loyalty points
        if (_selectedCustomer != null && _pointsUsed > 0) {
          await CustomerRepository(db).redeemPoints(
              _selectedCustomer!.id, _pointsUsed);
        }
      });

      // Clear cart
      ref.read(cartProvider.notifier).clear();

      if (!mounted) return;

      // Build receipt data
      final now = DateTime.now();
      final dateStr = '${now.day.toString().padLeft(2, '0')}/${now.month.toString().padLeft(2, '0')}/${now.year} '
          '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}';
      final invoice = 'INV${now.year}${now.month.toString().padLeft(2, '0')}${now.day.toString().padLeft(2, '0')}'
          '${now.hour.toString().padLeft(2, '0')}${now.minute.toString().padLeft(2, '0')}${now.second.toString().padLeft(2, '0')}';

      // Show receipt as centered dialog (GAS thermal style)
      if (mounted) {
        await ReceiptSheet.show(
          context,
          sheet: ReceiptSheet.fromCart(
            cartItems: cart,
            total: _total,
            discount: _totalDiscount,
            paymentMethod: _paymentMethod,
            cashGiven: cashGiven,
            cashReturn: cashReturn,
            cashierName: cashierName,
            customerName: _selectedCustomer?.name,
            customerPhone: _selectedCustomer?.phone,
            invoice: invoice,
            dateStr: dateStr,
            pointsUsed: _pointsUsed,
          ),
          onDismiss: () {
            // Return to POS screen after receipt is dismissed
            if (mounted && widget.sessionId != null) {
              context.go('/kasir?sessionId=${widget.sessionId}');
            } else if (mounted) {
              context.go('/home');
            }
          },
        );
      } else {
        // Return to POS screen if not mounted
        if (widget.sessionId != null) {
          context.go('/kasir?sessionId=${widget.sessionId}');
        } else {
          context.go('/home');
        }
      }
    } catch (e) {
      if (mounted) {
        TopToast.error(context, 'Gagal memproses pembayaran: $e');
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    ref.watch(cartProvider);
    final subtotal = _subtotal;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return ScreenScaffold(
      'Pembayaran',
      ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // ── Customer Card ──
          _buildCustomerCard(isDark),
          const SizedBox(height: 14),

          // ── Ringkasan Belanja Card ──
          _buildSummaryCard(isDark, subtotal),
          const SizedBox(height: 14),

          // ── Metode Pembayaran Card ──
          _buildPaymentMethodCard(isDark),
          const SizedBox(height: 14),

          // ── Detail Pembayaran Card ──
          if (_paymentMethod == 'Tunai') _buildTunaiCard(isDark),
          if (_paymentMethod == 'QRIS') _buildQrisCard(isDark),
          if (_paymentMethod == 'Transfer') _buildTransferCard(isDark),

          const SizedBox(height: 24),

          // ── Konfirmasi Button ──
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 20),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [NusaConfig.primaryColor, NusaConfig.primaryDark],
              ),
              boxShadow: [
                BoxShadow(
                  color: NusaConfig.primaryColor.withValues(alpha: 0.3),
                  blurRadius: 12, offset: const Offset(0, 4)),
              ],
            ),
            child: GestureDetector(
              onTap: _loading ? null : _confirmPayment,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  if (_loading)
                    const SizedBox(width: 20, height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  else ...[
                    const Icon(Icons.check_circle_outline, color: Colors.white, size: 22),
                    const SizedBox(width: 10),
                    const Text('Konfirmasi Pembayaran',
                        style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: Colors.white)),
                  ],
                ],
              ),
            ),
          ),
          const SizedBox(height: 10),
          Center(
            child: TextButton(
              onPressed: _loading ? null : () => context.pop(),
              child: Text('← Kembali ke Kasir',
                  style: TextStyle(color: isDark ? NusaConfig.darkTextSecondary : NusaConfig.textSecondary, fontWeight: FontWeight.w500)),
            ),
          ),
        ],
      ),
    );
  }

  // ── Card Builders ────────────────────────────────────────────────

  Widget _buildCustomerCard(bool isDark) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: _sectionCard(isDark),
      child: InkWell(
        onTap: _pickCustomer,
        borderRadius: BorderRadius.circular(12),
        child: Row(children: [
          Container(
            width: 44, height: 44,
            decoration: BoxDecoration(
              color: NusaConfig.primaryColor.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(Icons.person_outline, color: NusaConfig.primaryColor, size: 22),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(_selectedCustomer != null ? _selectedCustomer!.name : 'Pilih Pelanggan',
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600,
                      color: isDark ? NusaConfig.darkTextPrimary : NusaConfig.textPrimary)),
              const SizedBox(height: 2),
              Text(_selectedCustomer != null
                  ? 'Level: ${_selectedCustomer!.level} • Rp ${formatRupiah(_selectedCustomer!.totalSpent)}'
                  : 'Opsional — dapatkan diskon member',
                  style: TextStyle(fontSize: 12, color: isDark ? NusaConfig.darkTextTertiary : NusaConfig.textTertiary)),
            ]),
          ),
          if (_selectedCustomer != null)
            GestureDetector(
              onTap: () => setState(() => _selectedCustomer = null),
              child: Container(
                width: 32, height: 32,
                decoration: BoxDecoration(color: Colors.grey.shade100, borderRadius: BorderRadius.circular(8)),
                child: Icon(Icons.close, size: 16, color: isDark ? NusaConfig.darkTextSecondary : NusaConfig.textSecondary),
              ),
            ),
        ]),
      ),
    );
  }

  Widget _buildSummaryCard(bool isDark, int subtotal) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: _sectionCard(isDark),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        // Header
        Row(children: [
          Container(
            width: 32, height: 32,
            decoration: BoxDecoration(color: NusaConfig.success.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(8)),
            child: const Icon(Icons.receipt_long_outlined, color: NusaConfig.success, size: 18),
          ),
          const SizedBox(width: 10),
          const Text('Ringkasan Belanja', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
        ]),
        const SizedBox(height: 14),

        _summaryRow('Subtotal', formatRupiah(subtotal), isDark),
        if (_selectedCustomer != null) ...[
          const SizedBox(height: 6),
          _summaryRow('Diskon ${_selectedCustomer!.level}',
              '-${formatRupiah(_tierDiscount)}', isDark, isDiscount: true),
        ],
        if (_appliedPromo != null) ...[
          const SizedBox(height: 6),
          _summaryRow('Promo ${_appliedPromo!.name}',
              '-${formatRupiah(_promoDiscount)}', isDark, isDiscount: true),
        ],
        if (_pointsUsed > 0) ...[
          const SizedBox(height: 6),
          _summaryRow('Tukar Poin', '-${formatRupiah(_pointsUsed)}', isDark, isDiscount: true),
        ],

        // ── Disc / Promo / Points Row ──
        const SizedBox(height: 12),
        Row(children: [
          // Promo code
          Expanded(
            flex: 2,
            child: SizedBox(
              height: 42,
              child: TextField(
                controller: _promoCtrl,
                style: TextStyle(fontSize: 13, color: isDark ? NusaConfig.darkTextPrimary : NusaConfig.textPrimary),
                decoration: InputDecoration(
                  hintText: _appliedPromo != null ? _appliedPromo!.name : 'Kode promo...',
                  hintStyle: TextStyle(fontSize: 12, color: isDark ? NusaConfig.darkTextTertiary : NusaConfig.textTertiary),
                  prefixIcon: Icon(Icons.local_offer_outlined, size: 16, color: isDark ? NusaConfig.darkTextSecondary : NusaConfig.textSecondary),
                  filled: true, fillColor: isDark ? NusaConfig.darkSurface2 : const Color(0xFFF9FAFB),
                  contentPadding: const EdgeInsets.symmetric(vertical: 0),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          if (_appliedPromo != null)
            SizedBox(
              height: 42,
              child: ElevatedButton(
                onPressed: _clearPromo,
                style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFEF4444), foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)), padding: const EdgeInsets.symmetric(horizontal: 14)),
                child: const Text('Hapus', style: TextStyle(fontSize: 12)),
              ),
            )
          else
            SizedBox(
              height: 42,
              child: ElevatedButton(
                onPressed: _applyPromo,
                style: ElevatedButton.styleFrom(backgroundColor: NusaConfig.primaryColor, foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)), padding: const EdgeInsets.symmetric(horizontal: 14)),
                child: const Text('Pakai', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
              ),
            ),
        ]),

        // Diskon manual
        const SizedBox(height: 10),
        Row(children: [
          Icon(Icons.discount_outlined, size: 16, color: isDark ? NusaConfig.darkTextTertiary : NusaConfig.textTertiary),
          const SizedBox(width: 8),
          SizedBox(
            width: 100,
            child: TextField(
              controller: _discountCtrl,
              keyboardType: TextInputType.number,
              style: TextStyle(fontSize: 13, color: isDark ? NusaConfig.darkTextPrimary : NusaConfig.textPrimary),
              decoration: InputDecoration(
                hintText: 'Diskon Rp',
                hintStyle: TextStyle(fontSize: 12, color: isDark ? NusaConfig.darkTextTertiary : NusaConfig.textTertiary),
                isDense: true, contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                filled: true, fillColor: isDark ? NusaConfig.darkSurface2 : const Color(0xFFF9FAFB),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
              ),
            ),
          ),
          const Spacer(),
          // Poin tukar
          if (_selectedCustomer != null && _selectedCustomer!.points > 0) ...[
            _buildPointsBadge(isDark),
            const SizedBox(width: 6),
            Container(
              height: 32,
              child: ElevatedButton(
                onPressed: _pointsUsed > 0 ? () => setState(() => _pointsUsed = 0) : _showRedeemPoints,
                style: ElevatedButton.styleFrom(
                  backgroundColor: _pointsUsed > 0 ? const Color(0xFFEF4444) : Colors.amber,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  elevation: 0,
                  minimumSize: Size.zero,
                ),
                child: Text(
                  _pointsUsed > 0 ? 'Batal' : 'Tukar',
                  style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700),
                ),
              ),
            ),
          ],
        ]),

        const SizedBox(height: 12),
        Divider(color: Colors.grey.withValues(alpha: 0.2)),
        const SizedBox(height: 8),
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          Text('TOTAL', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: isDark ? NusaConfig.darkTextSecondary : NusaConfig.textSecondary, letterSpacing: 1)),
          Text(formatRupiah(_total),
              style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w800, color: NusaConfig.primaryColor, letterSpacing: -0.5)),
        ]),
      ]),
    );
  }

  Widget _summaryRow(String label, String value, bool isDark, {bool isDiscount = false}) {
    return Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
      Text(label, style: TextStyle(fontSize: 13, color: isDark ? NusaConfig.darkTextSecondary : NusaConfig.textSecondary)),
      Text(value, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600,
          color: isDiscount ? const Color(0xFF10B981) : (isDark ? NusaConfig.darkTextPrimary : NusaConfig.textPrimary))),
    ]);
  }

  Widget _buildPaymentMethodCard(bool isDark) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: _sectionCard(isDark),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Container(
            width: 32, height: 32,
            decoration: BoxDecoration(color: NusaConfig.accentPurple.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(8)),
            child: const Icon(Icons.payment_outlined, color: NusaConfig.accentPurple, size: 18),
          ),
          const SizedBox(width: 10),
          const Text('Metode Pembayaran', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
        ]),
        const SizedBox(height: 14),
        Row(children: [
          _payCard('Tunai', Icons.money, isDark),
          const SizedBox(width: 10),
          _payCard('QRIS', Icons.qr_code_2, isDark),
          const SizedBox(width: 10),
          _payCard('Transfer', Icons.account_balance, isDark),
        ]),
      ]),
    );
  }

  Widget _payCard(String method, IconData icon, bool isDark) {
    final active = _paymentMethod == method;
    return Expanded(
      child: GestureDetector(
        onTap: () => setState(() => _paymentMethod = method),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(vertical: 16),
          decoration: BoxDecoration(
            color: active ? NusaConfig.primarySoft : (isDark ? NusaConfig.darkSurface2 : const Color(0xFFF9FAFB)),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: active ? NusaConfig.primaryColor : NusaConfig.dividerColor, width: active ? 2 : 1),
          ),
          child: Column(children: [
            Icon(icon, size: 28, color: active ? NusaConfig.primaryColor : isDark ? NusaConfig.darkTextTertiary : NusaConfig.textTertiary),
            const SizedBox(height: 6),
            Text(method, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700,
                color: active ? NusaConfig.primaryColor : isDark ? NusaConfig.darkTextSecondary : NusaConfig.textSecondary)),
          ]),
        ),
      ),
    );
  }

  Widget _buildTunaiCard(bool isDark) {
    const denoms = [100000, 50000, 20000, 10000, 5000, 2000, 1000];
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark ? NusaConfig.darkSurface : Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: isDark ? NusaConfig.darkBorder : const Color(0xFFF1F5F9)),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.03), blurRadius: 8, offset: const Offset(0, 2))],
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Container(
            width: 32, height: 32,
            decoration: BoxDecoration(color: NusaConfig.accentGreen.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(8)),
            child: const Icon(Icons.money, color: NusaConfig.accentGreen, size: 18),
          ),
          const SizedBox(width: 10),
          const Text('Pembayaran Tunai', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
        ]),
        const SizedBox(height: 14),
        TextField(
          controller: _cashCtrl,
          keyboardType: TextInputType.number,
          autofocus: true,
          style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: isDark ? NusaConfig.darkTextPrimary : NusaConfig.textPrimary),
          decoration: InputDecoration(
            hintText: 'Rp 0',
            hintStyle: TextStyle(color: isDark ? NusaConfig.darkTextTertiary : NusaConfig.textTertiary, fontSize: 20),
            filled: true, fillColor: isDark ? NusaConfig.darkSurface2 : const Color(0xFFF9FAFB),
            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
            focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: NusaConfig.primaryColor, width: 2)),
          ),
          onChanged: (v) => setState(() => _cashGiven = int.tryParse(v)),
        ),
        const SizedBox(height: 10),
        // Quick-action denomination chips
        Wrap(
          spacing: 6, runSpacing: 6,
          children: [
            for (final d in denoms)
              GestureDetector(
                onTap: () {
                  final prev = int.tryParse(_cashCtrl.text) ?? 0;
                  final newVal = prev + d;
                  _cashCtrl.text = newVal.toString();
                  setState(() => _cashGiven = newVal);
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: isDark ? NusaConfig.darkSurface2 : const Color(0xFFF0FDF4),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: isDark ? NusaConfig.darkBorder : const Color(0xFFBBF7D0)),
                  ),
                  child: Text(formatRupiah(d), style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: Color(0xFF166534))),
                ),
              ),
            // Reset button
            GestureDetector(
              onTap: () {
                _cashCtrl.clear();
                setState(() => _cashGiven = null);
              },
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                decoration: BoxDecoration(
                  color: const Color(0xFFFEF2F2),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: const Color(0xFFFECACA)),
                ),
                child: const Row(mainAxisSize: MainAxisSize.min, children: [
                  Icon(Icons.refresh, size: 12, color: Color(0xFFDC2626)),
                  SizedBox(width: 4),
                  Text('Reset', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: Color(0xFFDC2626))),
                ]),
              ),
            ),
          ],
        ),
        if (_kembalian != null) ...[
          const SizedBox(height: 12),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(color: const Color(0xFFECFDF5), borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFFA7F3D0))),
            child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
              const Text('Kembalian', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: Color(0xFF065F46))),
              Text(formatRupiah(_kembalian!),
                  style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: Color(0xFF059669))),
            ]),
          ),
        ],
      ]),
    );
  }

  Widget _buildQrisCard(bool isDark) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: isDark ? NusaConfig.darkSurface : Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: isDark ? NusaConfig.darkBorder : const Color(0xFFF1F5F9)),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.03), blurRadius: 8, offset: const Offset(0, 2))],
      ),
      child: Column(children: [
        Container(
          width: 32, height: 32,
          decoration: BoxDecoration(color: const Color(0xFF6366F1).withValues(alpha: 0.1), borderRadius: BorderRadius.circular(8)),
          child: const Icon(Icons.qr_code_2, color: Color(0xFF6366F1), size: 18),
        ),
        const SizedBox(height: 14),
        if (_qrisString != null && _qrisString!.isNotEmpty) ...[
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16),
                border: Border.all(color: NusaConfig.dividerColor)),
            child: QrImageView(data: _qrisString!, version: QrVersions.auto, size: 180),
          ),
          const SizedBox(height: 12),
          Text('Scan QRIS untuk membayar',
              style: TextStyle(fontSize: 13, color: isDark ? NusaConfig.darkTextSecondary : NusaConfig.textSecondary)),
        ] else ...[
          Icon(Icons.qr_code, size: 64, color: isDark ? NusaConfig.darkTextSecondary : Colors.grey),
          const SizedBox(height: 8),
              Text('Set QRIS di Pengaturan',
                style: TextStyle(color: isDark ? NusaConfig.darkTextSecondary : Colors.grey, fontSize: 15)),
        ],
      ]),
    );
  }

  Widget _buildTransferCard(bool isDark) {
    final bankName = _bankName ?? '';
    final bankAccount = _bankAccount ?? '';
    final bankHolder = _bankHolder ?? '';
    final hasBankInfo = bankName.isNotEmpty || bankAccount.isNotEmpty;
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: isDark ? NusaConfig.darkSurface : Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: isDark ? NusaConfig.darkBorder : const Color(0xFFF1F5F9)),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.03), blurRadius: 8, offset: const Offset(0, 2))],
      ),
      child: Column(children: [
        Container(
          width: 48, height: 48,
          decoration: BoxDecoration(color: const Color(0xFF6366F1).withValues(alpha: 0.1), borderRadius: BorderRadius.circular(14)),
          child: const Icon(Icons.account_balance, size: 26, color: Color(0xFF6366F1)),
        ),
        const SizedBox(height: 12),
        if (hasBankInfo) ...[
          Text('Transfer ke rekening', style: TextStyle(fontSize: 13, color: isDark ? NusaConfig.darkTextSecondary : NusaConfig.textSecondary)),
          const SizedBox(height: 6),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(color: isDark ? NusaConfig.darkSurface2 : const Color(0xFFF9FAFB),
                borderRadius: BorderRadius.circular(12)),
            child: Column(children: [
              if (bankName.isNotEmpty)
                Text(bankName, style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: isDark ? NusaConfig.darkTextPrimary : NusaConfig.textPrimary)),
              if (bankAccount.isNotEmpty) ...[
                const SizedBox(height: 2),
                Text(bankAccount, style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700,
                    fontFamily: 'monospace', letterSpacing: 1, color: isDark ? NusaConfig.darkTextPrimary : NusaConfig.textPrimary)),
              ],
              if (bankHolder.isNotEmpty) ...[
                const SizedBox(height: 4),
                Text('a.n. $bankHolder', style: TextStyle(fontSize: 13, color: isDark ? NusaConfig.darkTextSecondary : NusaConfig.textSecondary)),
              ],
            ]),
          ),
        ] else ...[
          Icon(Icons.account_balance_wallet_outlined, size: 48, color: isDark ? NusaConfig.darkTextSecondary : Colors.grey),
          const SizedBox(height: 8),
              Text('Atur rekening di Pengaturan',
                style: TextStyle(color: isDark ? NusaConfig.darkTextSecondary : Colors.grey, fontSize: 15)),
        ],
      ]),
    );
  }

  Widget _buildPointsBadge(bool isDark) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(color: Colors.amber.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(10)),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        const Icon(Icons.stars_rounded, size: 14, color: Colors.amber),
        const SizedBox(width: 4),
        if (_pointsUsed > 0)
          Text('${_selectedCustomer!.points - _pointsUsed} → ${_pointsUsed} pts',
              style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Color(0xFFB45309)))
        else
          Text('${_selectedCustomer!.points} pts',
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Color(0xFFB45309))),
      ]),
    );
  }

  void _showRedeemPoints() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final maxPts = _selectedCustomer?.points ?? 0;
    final maxRp = maxPts; // 1 poin = Rp 1
    final ctrl = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Tukar Poin'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Kamu punya ${_selectedCustomer?.points ?? 0} poin.',
                style: const TextStyle(fontSize: 13)),
            const SizedBox(height: 4),
            Text('1 poin = Rp 1',
                style: TextStyle(fontSize: 12, color: isDark ? NusaConfig.darkTextTertiary : Colors.grey.shade600)),
            const SizedBox(height: 12),
            TextField(
              controller: ctrl,
              keyboardType: TextInputType.number,
              decoration: InputDecoration(
                labelText: 'Jumlah poin',
                hintText: 'Maksimal $maxRp',
                border: const OutlineInputBorder(),
              ),
              onChanged: (v) {
                final val = int.tryParse(v) ?? 0;
                if (val > maxPts) ctrl.text = maxPts.toString();
              },
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Batal'),
          ),
          ElevatedButton(
            onPressed: () {
              final pts = int.tryParse(ctrl.text) ?? 0;
              if (pts <= 0 || pts > maxPts) return;
              setState(() => _pointsUsed = pts);
              Navigator.pop(ctx);
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.amber, foregroundColor: Colors.white),
            child: const Text('Tukar'),
          ),
        ],
      ),
    );
  }
}
