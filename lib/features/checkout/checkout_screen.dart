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
import 'package:nusa_kasir/features/auth/employee_session_provider.dart';
import 'package:nusa_kasir/features/pos/cart.dart';
import 'package:nusa_kasir/shared/widgets/nusa_button.dart';
import 'package:nusa_kasir/shared/widgets/nusa_card.dart';
import 'package:nusa_kasir/shared/widgets/nusa_input.dart';
import "package:nusa_kasir/shared/widgets/top_toast.dart";
import 'package:nusa_kasir/shared/widgets/screen_scaffold.dart';
import 'package:nusa_kasir/features/checkout/receipt_sheet.dart';

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
    _loadQris();
  }

  Future<void> _loadQris() async {
    final qris = await ref.read(settingsRepoProvider).getQris();
    if (mounted) setState(() => _qrisString = qris);
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
          await CustomerRepository(db).addSpent(_selectedCustomer!.id, _total);
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

    return ScreenScaffold(
      'Pembayaran',
      ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // --- Customer Selector ---
          NusaCard(
            InkWell(
              onTap: _pickCustomer,
              borderRadius: BorderRadius.circular(16),
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Row(
                  children: [
                    const Icon(Icons.person_outline, color: NusaConfig.primaryColor),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        _selectedCustomer != null
                            ? _selectedCustomer!.name
                            : 'Pilih Pelanggan (opsional)',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                          color: _selectedCustomer != null
                              ? NusaConfig.textPrimary
                              : NusaConfig.textSecondary,
                        ),
                      ),
                    ),
                    if (_selectedCustomer != null)
                      GestureDetector(
                        onTap: () => setState(() => _selectedCustomer = null),
                        child: const Icon(Icons.close, size: 18, color: NusaConfig.textSecondary),
                      ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 12),

          // --- Summary Card ---
          NusaCard(
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _row('Subtotal', formatRupiah(subtotal)),
                const SizedBox(height: 8),

                // Tier discount (auto, if customer selected)
                if (_selectedCustomer != null) ...[
                  _row(
                    'Diskon ${_selectedCustomer!.level} (${CustomerRepository.tierDiscountPercent(_selectedCustomer!.level).toInt()}%)',
                    '-${formatRupiah(_tierDiscount)}',
                  ),
                  const SizedBox(height: 4),
                ],

                // Promo code row
                Row(
                  children: [
                    Expanded(
                      child: NusaInput(
                        'Kode Promo',
                        controller: _promoCtrl,
                      ),
                    ),
                    const SizedBox(width: 8),
                    if (_appliedPromo != null)
                      IconButton(
                        onPressed: _clearPromo,
                        icon: const Icon(Icons.close, color: NusaConfig.primaryColor),
                        tooltip: 'Hapus promo',
                      )
                    else
                      SizedBox(
                        height: 48,
                        child: ElevatedButton(
                          onPressed: _applyPromo,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: NusaConfig.primaryColor,
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          ),
                          child: const Text('Pakai'),
                        ),
                      ),
                  ],
                ),
                if (_appliedPromo != null) ...[
                  const SizedBox(height: 4),
                  Text(
                    '✓ ${_appliedPromo!.name} (-${formatRupiah(_promoDiscount)})',
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: NusaConfig.accentGreen,
                    ),
                  ),
                ],

                // Points redeem (if customer has points)
                if (_selectedCustomer != null && _selectedCustomer!.points > 0) ...[
                  const SizedBox(height: 8),
                  _buildPointsRow(),
                ],

                if (_pointsUsed > 0) ...[
                  const SizedBox(height: 4),
                  Text(
                    '✓ Poin ditukar: -${formatRupiah(_pointsUsed)}',
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: NusaConfig.accentGreen,
                    ),
                  ),
                ],

                const SizedBox(height: 8),
                NusaInput(
                  'Diskon Manual (Rp)',
                  controller: _discountCtrl,
                  type: TextInputType.number,
                ),
                const SizedBox(height: 8),
                Divider(color: Colors.grey.shade300),
                const SizedBox(height: 4),
                _row('Total', formatRupiah(_total),
                    bold: true, large: true),
              ],
            ),
          ),
          const SizedBox(height: 20),

          // --- Payment Method ---
          const Text('Metode Pembayaran',
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            children: ['Tunai', 'QRIS', 'Transfer'].map((m) {
              final sel = _paymentMethod == m;
              return ChoiceChip(
                label: Text(m),
                selected: sel,
                onSelected: (_) => setState(() => _paymentMethod = m),
                selectedColor: NusaConfig.primarySoft,
                backgroundColor: Colors.grey.shade100,
              );
            }).toList(),
          ),
          const SizedBox(height: 16),

          // --- Payment Detail ---
          if (_paymentMethod == 'Tunai') _buildTunai(),
          if (_paymentMethod == 'QRIS') _buildQris(),
          if (_paymentMethod == 'Transfer') _buildTransfer(),

          const SizedBox(height: 24),

          // --- Confirm Button ---
          NusaButton(
            _loading ? 'Memproses...' : 'Konfirmasi Pembayaran',
            onPressed: _loading ? null : _confirmPayment,
          ),
          const SizedBox(height: 8),
          NusaButton(
            'Batal',
            onPressed: _loading ? null : () => context.pop(),
            fullWidth: false,
          ),
        ],
      ),
    );
  }

  Widget _buildTunai() {
    return NusaCard(
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            controller: _cashCtrl,
            keyboardType: TextInputType.number,
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: NusaConfig.textPrimary,
            ),
            decoration: InputDecoration(
              hintText: 'Jumlah Dibayarkan',
              hintStyle: const TextStyle(
                color: NusaConfig.textTertiary,
                fontSize: 15,
              ),
              filled: true,
              fillColor: Colors.white,
              contentPadding: const EdgeInsets.symmetric(
                  horizontal: 16, vertical: 14),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide:
                    const BorderSide(color: NusaConfig.dividerColor),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide:
                    const BorderSide(color: NusaConfig.dividerColor),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(
                    color: NusaConfig.primaryColor, width: 1.5),
              ),
            ),
            onChanged: (v) {
              setState(() {
                _cashGiven = int.tryParse(v);
              });
            },
          ),
          if (_kembalian != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                'Kembalian: ${formatRupiah(_kembalian!)}',
                style: const TextStyle(
                    fontSize: 16, fontWeight: FontWeight.w600),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildQris() {
    final qris = _qrisString;
    return NusaCard(
      Column(
        children: [
          if (qris != null && qris.isNotEmpty) ...[
            QrImageView(
              data: qris,
              version: QrVersions.auto,
              size: 200,
            ),
            const SizedBox(height: 8),
            const Text('Scan QRIS untuk membayar',
                style: TextStyle(color: Colors.grey)),
          ] else ...[
            const Icon(Icons.qr_code, size: 64, color: Colors.grey),
            const SizedBox(height: 8),
            const Text(
              'Set QRIS di Pengaturan',
              style: TextStyle(color: Colors.grey, fontSize: 15),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildPointsRow() {
    final maxRedeemable = (_selectedCustomer!.points).clamp(0, _subtotal - _manualDiscount - _promoDiscount - _tierDiscount);
    final remaining = _selectedCustomer!.points - _pointsUsed;
    return NusaCard(
      padding: const EdgeInsets.all(12),
      Row(
        children: [
          const Icon(Icons.redeem, size: 18, color: Colors.amber),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Poin: ${remaining} (Rp ${formatRupiah(remaining)})',
                    style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                Text('1 poin = Rp 1',
                    style: const TextStyle(fontSize: 11, color: NusaConfig.textTertiary)),
              ],
            ),
          ),
          if (_pointsUsed > 0)
            TextButton(
              onPressed: () => setState(() => _pointsUsed = 0),
              child: const Text('Batal'),
            )
          else
            SizedBox(
              height: 36,
              child: ElevatedButton(
                onPressed: maxRedeemable <= 0 ? null : () => _pickPoints(maxRedeemable),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.amber.shade600,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10)),
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                ),
                child: const Text('Tukar', style: TextStyle(fontSize: 12)),
              ),
            ),
        ],
      ),
    );
  }

  void _pickPoints(int maxRedeemable) {
    showDialog(
      context: context,
      builder: (_) {
        final ctrl = TextEditingController(text: maxRedeemable.toString());
        return AlertDialog(
          title: const Text('Tukar Poin'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('Maksimal: ${formatRupiah(maxRedeemable)} (${maxRedeemable} poin)',
                  style: const TextStyle(fontSize: 13, color: NusaConfig.textSecondary)),
              const SizedBox(height: 12),
              NusaInput('Jumlah poin', controller: ctrl,
                  type: TextInputType.number),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Batal'),
            ),
            NusaButton('Tukar', fullWidth: false, onPressed: () {
              final val = int.tryParse(ctrl.text.trim()) ?? 0;
              if (val <= 0) {
                TopToast.error(context, 'Masukkan jumlah poin');
                return;
              }
              if (val > maxRedeemable) {
                TopToast.error(context, 'Poin tidak cukup');
                return;
              }
              setState(() => _pointsUsed = val);
              Navigator.pop(context);
            }),
          ],
        );
      },
    );
  }

  Widget _buildTransfer() {
    return NusaCard(
      const Column(
        children: [
          Icon(Icons.account_balance, size: 64, color: Colors.blueGrey),
          SizedBox(height: 8),
          Text(
            'Transfer ke rekening NUSA\nBCA 1234567890 a.n. NUSA Kasir',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 15),
          ),
        ],
      ),
    );
  }

  Widget _row(String label, String value,
      {bool bold = false, bool large = false}) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label,
            style: TextStyle(
              fontSize: large ? 16 : 14,
              fontWeight: bold ? FontWeight.w700 : FontWeight.w400,
            )),
        Text(value,
            style: TextStyle(
              fontSize: large ? 20 : 14,
              fontWeight: bold ? FontWeight.w700 : FontWeight.w400,
            )),
      ],
    );
  }
}
