import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:qr_flutter/qr_flutter.dart';

import 'package:nusa_kasir/app.dart';
import 'package:nusa_kasir/core/config/nusa_config.dart';
import 'package:nusa_kasir/core/utils/format_rupiah.dart';
import 'package:nusa_kasir/data/repositories/product_repository.dart';
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
  String _paymentMethod = 'Tunai';
  bool _loading = false;
  int? _cashGiven;
  String? _qrisString;

  int get _subtotal => ref.watch(cartProvider).fold(0, (s, e) => s + e.subtotal);
  int get _discount => int.tryParse(_discountCtrl.text) ?? 0;
  int get _total => (_subtotal - _discount).clamp(0, _subtotal);
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
    super.dispose();
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

    setState(() => _loading = true);

    try {
      final db = ref.read(databaseProvider);
      final productRepo = ProductRepository(db);
      final transactionRepo = ref.read(transactionRepoProvider);

      // Deduct stock for each item
      for (final item in cart) {
        await productRepo.adjustStock(item.productId, -item.qty);
      }

      // Save transaction
      final cashierName = ref.read(authProvider);
      final cashGiven = int.tryParse(_cashCtrl.text);
      final cashReturn = cashGiven != null && cashGiven >= _total
          ? cashGiven - _total
          : null;

      await transactionRepo.saveTransaction(
        items: cart,
        total: _total,
        discount: _discount,
        paymentMethod: _paymentMethod,
        cashGiven: cashGiven,
        cashReturn: cashReturn,
        cashierName: cashierName,
        branchId: ref.read(activeBranchProvider)?.id,
      );

      // Clear cart
      ref.read(cartProvider.notifier).clear();

      if (!mounted) return;

      // Show receipt sheet
      showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        builder: (ctx) => ReceiptSheet(
          items: cart,
          total: _total,
          discount: _discount,
          paymentMethod: _paymentMethod,
          cashGiven: cashGiven,
          cashReturn: cashReturn,
          cashierName: cashierName,
        ),
      );
      // Return to POS screen
      if (mounted && widget.sessionId != null) {
        context.go('/kasir?sessionId=${widget.sessionId}');
      } else if (mounted) {
        context.go('/home');
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
    ref.watch(cartProvider); // re-build on cart changes
    final subtotal = _subtotal;

    return ScreenScaffold(
      'Pembayaran',
      ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // --- Summary Card ---
          NusaCard(
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _row('Subtotal', formatRupiah(subtotal)),
                const SizedBox(height: 8),
                NusaInput(
                  'Diskon (Rp)',
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
