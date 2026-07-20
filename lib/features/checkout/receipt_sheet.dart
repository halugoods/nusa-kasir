import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:nusa_kasir/core/config/nusa_config.dart';
import 'package:nusa_kasir/core/providers.dart';
import 'package:nusa_kasir/core/utils/format_rupiah.dart';
import 'package:nusa_kasir/core/utils/receipt_printer.dart';
import 'package:nusa_kasir/data/repositories/settings_repository.dart';
import 'package:nusa_kasir/features/pos/cart.dart';
import "package:nusa_kasir/shared/widgets/top_toast.dart";

/// A single receipt line (name, qty, price). Mirrors CartItem but decoupled.
class _ReceiptItem {
  final String name;
  final int qty;
  final int price;
  const _ReceiptItem({required this.name, required this.qty, required this.price});
  int get subtotal => qty * price;
}

/// Thermal-style receipt dialog — matches GAS receipt modal design.
///
/// Centered dialog with 58mm thermal receipt aesthetic:
/// - monospace font, dashed separators
/// - store header, items, totals, footer
/// - Print (Bluetooth) + WhatsApp share buttons
class ReceiptSheet extends ConsumerWidget {
  final List<_ReceiptItem> items;
  final int total;
  final int discount;
  final String paymentMethod;
  final int? cashGiven;
  final int? cashReturn;
  final String? cashierName;
  final String? customerName;
  final String? customerPhone;
  final String? invoice;
  final String? dateStr;
  final int pointsUsed;

  const ReceiptSheet({
    required this.items,
    required this.total,
    required this.discount,
    required this.paymentMethod,
    this.cashGiven,
    this.cashReturn,
    this.cashierName,
    this.customerName,
    this.customerPhone,
    this.invoice,
    this.dateStr,
    this.pointsUsed = 0,
    super.key,
  });

  /// Factory: from CartItem list (new transaction, just printed).
  factory ReceiptSheet.fromCart({
    required List<CartItem> cartItems,
    required int total,
    required int discount,
    required String paymentMethod,
    int? cashGiven,
    int? cashReturn,
    String? cashierName,
    String? customerName,
    String? customerPhone,
    String? invoice,
    String? dateStr,
    int pointsUsed = 0,
  }) {
    final items = cartItems
        .map((c) => _ReceiptItem(name: c.name, qty: c.qty, price: c.price))
        .toList();
    return ReceiptSheet(
      items: items,
      total: total,
      discount: discount,
      paymentMethod: paymentMethod,
      cashGiven: cashGiven,
      cashReturn: cashReturn,
      cashierName: cashierName,
      customerName: customerName,
      customerPhone: customerPhone,
      invoice: invoice,
      dateStr: dateStr,
      pointsUsed: pointsUsed,
    );
  }

  /// Factory: from raw maps (reprint from history).
  factory ReceiptSheet.fromMaps({
    required List<Map<String, dynamic>> rawItems,
    required int total,
    required int discount,
    required String paymentMethod,
    int? cashGiven,
    int? cashReturn,
    String? cashierName,
    String? customerName,
    String? customerPhone,
    String? invoice,
    String? dateStr,
    int pointsUsed = 0,
  }) {
    final items = rawItems.map((m) => _ReceiptItem(
      name: '${m['name'] ?? ''}',
      qty: (m['qty'] as num?)?.toInt() ?? 0,
      price: (m['price'] as num?)?.toInt() ?? 0,
    )).toList();
    return ReceiptSheet(
      items: items,
      total: total,
      discount: discount,
      paymentMethod: paymentMethod,
      cashGiven: cashGiven,
      cashReturn: cashReturn,
      cashierName: cashierName,
      customerName: customerName,
      customerPhone: customerPhone,
      invoice: invoice,
      dateStr: dateStr,
    );
  }

  /// Show as centered dialog (GAS style).
  static Future<void> show(
    BuildContext context, {
    required ReceiptSheet sheet,
    VoidCallback? onDismiss,
  }) {
    return showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => PopScope(
        canPop: false,
        child: sheet,
      ),
    ).then((_) => onDismiss?.call());
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final db = ref.read(databaseProvider);
    return FutureBuilder<String>(
      future: SettingsRepository(db).getStoreName(),
      builder: (context, snap) {
        final storeName = snap.data ?? 'NUSA Kasir';
        return Dialog(
          insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 40),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
          backgroundColor: isDark ? NusaConfig.darkSurface : Colors.white,
          child: Container(
            constraints: const BoxConstraints(maxWidth: 400),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // ── Header bar ──
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                  decoration: BoxDecoration(
                    color: isDark ? NusaConfig.darkSurface2 : Colors.grey.shade50,
                    borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
                    border: Border(bottom: BorderSide(
                        color: isDark ? NusaConfig.darkBorder : Colors.grey.shade200)),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.receipt_long, size: 22, color: Color(0xFFE63946)),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          'Struk Pesanan',
                          style: TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.w700,
                            color: isDark ? NusaConfig.darkTextPrimary : Colors.grey.shade800,
                          ),
                        ),
                      ),
                      GestureDetector(
                        onTap: () => Navigator.pop(context),
                        child: Container(
                          width: 32, height: 32,
                          decoration: BoxDecoration(
                            color: isDark ? NusaConfig.darkDivider : Colors.grey.shade200,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Icon(Icons.close, size: 18,
                              color: isDark ? NusaConfig.darkTextSecondary : Colors.grey.shade600),
                        ),
                      ),
                    ],
                  ),
                ),

                // ── Receipt body (scrollable) ──
                Flexible(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(16),
                    child: Center(
                      child: Container(
                        width: double.infinity,
                        constraints: const BoxConstraints(maxWidth: 260),
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: isDark ? NusaConfig.darkSurface2 : Colors.white,
                          borderRadius: BorderRadius.circular(12),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: isDark ? 0.3 : 0.08),
                              blurRadius: 8,
                              offset: const Offset(0, 2),
                            ),
                          ],
                        ),
                        child: _buildReceipt(context, storeName, isDark),
                      ),
                    ),
                  ),
                ),

                // ── Action buttons ──
                Container(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
                  decoration: BoxDecoration(
                    color: isDark ? NusaConfig.darkSurface : Colors.white,
                    borderRadius: const BorderRadius.vertical(bottom: Radius.circular(24)),
                    border: Border(top: BorderSide(
                        color: isDark ? NusaConfig.darkBorder : Colors.grey.shade200)),
                  ),
                  child: Column(
                    children: [
                      // "Selesai & Tutup" — full width
                      SizedBox(
                        width: double.infinity,
                        height: 48,
                        child: OutlinedButton(
                          onPressed: () => Navigator.pop(context),
                          style: OutlinedButton.styleFrom(
                            backgroundColor: isDark
                                ? NusaConfig.darkSurface2
                                : Colors.grey.shade100,
                            foregroundColor: isDark
                                ? NusaConfig.darkTextPrimary
                                : Colors.grey.shade800,
                            side: BorderSide(
                                color: isDark
                                    ? NusaConfig.darkBorder
                                    : Colors.grey.shade300),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                          ),
                          child: Text('Selesai & Tutup',
                              style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w700,
                                  color: isDark
                                      ? NusaConfig.darkTextPrimary
                                      : Colors.grey.shade800)),
                        ),
                      ),
                      const SizedBox(height: 12),
                      // Cetak Printer — full width
                      SizedBox(
                        width: double.infinity,
                        height: 48,
                        child: ElevatedButton.icon(
                          onPressed: () => _printReceipt(context, ref, storeName),
                          icon: const Icon(Icons.print, size: 18),
                          label: const Text('Cetak Printer',
                              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF3B82F6),
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(14)),
                            elevation: 0,
                          ),
                        ),
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

  /// Builds the thermal-style receipt content.
  Widget _buildReceipt(BuildContext context, String storeName, bool isDark) {
    final textColor = isDark ? NusaConfig.darkTextPrimary : NusaConfig.textPrimary;
    final subtleColor = isDark ? NusaConfig.darkTextSecondary : NusaConfig.textSecondary;
    final mono = TextStyle(
      fontFamily: 'monospace',
      fontSize: 11,
      height: 1.5,
      color: textColor,
    );
    final monoBold = TextStyle(
      fontFamily: 'monospace',
      fontSize: 11,
      height: 1.5,
      fontWeight: FontWeight.bold,
      color: textColor,
    );
    final monoBig = TextStyle(
      fontFamily: 'monospace',
      fontSize: 14,
      height: 1.5,
      fontWeight: FontWeight.bold,
      color: textColor,
    );
    final monoHeader = TextStyle(
      fontFamily: 'monospace',
      fontSize: 15,
      height: 1.4,
      fontWeight: FontWeight.bold,
      color: textColor,
    );
    final monoGrey = TextStyle(
      fontFamily: 'monospace',
      fontSize: 11,
      height: 1.5,
      color: subtleColor,
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // ── Store header ──
        Center(child: Text(storeName, style: monoHeader, textAlign: TextAlign.center)),
        if (invoice != null) ...[
          const SizedBox(height: 2),
          Center(child: Text(invoice!, style: mono, textAlign: TextAlign.center)),
        ],
        const SizedBox(height: 6),
        _dashedLine(isDark: isDark),
        const SizedBox(height: 6),

        // ── Transaction info ──
        if (invoice != null)
          _monoRow('ID  : ', invoice!, mono, mono),
        if (dateStr != null)
          _monoRow('Tgl : ', dateStr!, mono, mono),
        if (cashierName != null && cashierName!.isNotEmpty)
          _monoRow('Kasir:', cashierName!, mono, mono),
        if (customerName != null && customerName!.isNotEmpty)
          _monoRow('Pel  : ', customerName!, mono, mono),
        const SizedBox(height: 6),
        _dashedLine(isDark: isDark),
        const SizedBox(height: 6),

        // ── Items ──
        ...items.map((item) => _buildItemRow(item, mono, monoGrey)),

        const SizedBox(height: 6),
        _dashedLine(isDark: isDark),
        const SizedBox(height: 6),

        // ── Discount & Points ──
        if (discount > 0)
          Padding(
            padding: const EdgeInsets.only(bottom: 2),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('Diskon/Potongan', style: monoGrey),
                Text('-${formatRupiah(discount)}', style: monoGrey),
              ],
            ),
          ),
        if (pointsUsed > 0)
          Padding(
            padding: const EdgeInsets.only(bottom: 2),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('Tukar Poin', style: monoGrey),
                Text('-${formatRupiah(pointsUsed)}', style: monoGrey),
              ],
            ),
          ),

        // ── TOTAL ──
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('TOTAL', style: monoBig),
              Text(formatRupiah(total), style: monoBig),
            ],
          ),
        ),

        // ── Payment ──
        Padding(
          padding: const EdgeInsets.only(bottom: 2),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Bayar ($paymentMethod)', style: monoGrey),
              Text(formatRupiah(cashGiven ?? total), style: monoGrey),
            ],
          ),
        ),
        if (cashReturn != null && cashReturn! > 0)
          Padding(
            padding: const EdgeInsets.only(bottom: 2),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('Kembali', style: monoGrey),
                Text(formatRupiah(cashReturn!), style: monoGrey),
              ],
            ),
          ),

        const SizedBox(height: 6),
        _dashedLine(isDark: isDark),
        const SizedBox(height: 8),

        // ── Footer ──
        Center(
          child: Text('Terima Kasih!', style: monoBold, textAlign: TextAlign.center),
        ),
      ],
    );
  }

  Widget _buildItemRow(_ReceiptItem item, TextStyle mono, TextStyle monoGrey) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(item.name, style: mono),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('${item.qty} x ${formatRupiah(item.price)}', style: monoGrey),
              Text(formatRupiah(item.subtotal), style: mono),
            ],
          ),
        ],
      ),
    );
  }

  Widget _monoRow(String label, String value, TextStyle monoL, TextStyle monoV) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: Row(
        children: [
          Text(label, style: monoL),
          const Spacer(),
          Flexible(child: Text(value, style: monoV, textAlign: TextAlign.right)),
        ],
      ),
    );
  }

  Widget _dashedLine({bool isDark = false}) {
    return CustomPaint(
      size: const Size(double.infinity, 1),
      painter: _DashPainter(
          color: isDark ? NusaConfig.darkDivider : const Color(0xFF999999)),
    );
  }

  // ── Print (Bluetooth thermal) ──
  Future<void> _printReceipt(
      BuildContext context, WidgetRef ref, String storeName) async {
    final printer = ReceiptPrinter();
    try {
      final devices = await printer.discover();
      if (devices.isEmpty) {
        if (context.mounted) {
          TopToast.error(context, 'Sambungkan printer di Pengaturan');
        }
        return;
      }

      final saved = await SettingsRepository(ref.read(databaseProvider))
          .getPrinterAddress();
      PrinterDevice target = devices.first;
      if (saved != null && saved.contains('|')) {
        final savedAddr = saved.split('|').last;
        final found = devices.where((d) => d.address == savedAddr);
        if (found.isNotEmpty) target = found.first;
      }

      await printer.connect(target);
      final ok = await printer.printReceipt(
        storeName: storeName,
        lines: items
            .map((i) => ReceiptLine(name: i.name, qty: i.qty, price: i.price))
            .toList(),
        total: total,
        paymentMethod: paymentMethod,
        cashierName: cashierName,
      );
      if (context.mounted) {
        if (ok) {
          TopToast.success(context, 'Struk berhasil dicetak');
        } else {
          TopToast.error(context, 'Gagal mencetak');
        }
      }
    } catch (_) {
      if (context.mounted) {
        TopToast.error(context, 'Gagal mencetak struk');
      }
    } finally {
      printer.dispose();
    }
  }

}

/// Custom painter for dashed horizontal line (mimics GAS border-top: dashed).
class _DashPainter extends CustomPainter {
  final Color color;
  const _DashPainter({this.color = const Color(0xFF999999)});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1.0
      ..style = PaintingStyle.stroke;
    const dashW = 4.0;
    const gapW = 3.0;
    double x = 0;
    while (x < size.width) {
      canvas.drawLine(Offset(x, 0), Offset((x + dashW).clamp(0, size.width), 0), paint);
      x += dashW + gapW;
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
