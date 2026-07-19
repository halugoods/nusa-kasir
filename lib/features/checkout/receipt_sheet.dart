import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart' as launcher;

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
    final db = ref.read(databaseProvider);
    return FutureBuilder<String>(
      future: SettingsRepository(db).getStoreName(),
      builder: (context, snap) {
        final storeName = snap.data ?? 'NUSA Kasir';
        return Dialog(
          insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 40),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
          child: Container(
            constraints: const BoxConstraints(maxWidth: 400),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // ── Header bar ──
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                  decoration: BoxDecoration(
                    color: Colors.grey.shade50,
                    borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
                    border: Border(bottom: BorderSide(color: Colors.grey.shade200)),
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
                            color: Colors.grey.shade800,
                          ),
                        ),
                      ),
                      GestureDetector(
                        onTap: () => Navigator.pop(context),
                        child: Container(
                          width: 32, height: 32,
                          decoration: BoxDecoration(
                            color: Colors.grey.shade200,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Icon(Icons.close, size: 18, color: Colors.grey.shade600),
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
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(12),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.08),
                              blurRadius: 8,
                              offset: const Offset(0, 2),
                            ),
                          ],
                        ),
                        child: _buildReceipt(context, storeName),
                      ),
                    ),
                  ),
                ),

                // ── Action buttons (like GAS) ──
                Container(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: const BorderRadius.vertical(bottom: Radius.circular(24)),
                    border: Border(top: BorderSide(color: Colors.grey.shade200)),
                  ),
                  child: Column(
                    children: [
                      // "Selesai & Tutup" — full width, grey (matching GAS)
                      SizedBox(
                        width: double.infinity,
                        height: 48,
                        child: OutlinedButton(
                          onPressed: () => Navigator.pop(context),
                          style: OutlinedButton.styleFrom(
                            backgroundColor: Colors.grey.shade100,
                            foregroundColor: Colors.grey.shade800,
                            side: BorderSide(color: Colors.grey.shade300),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                          ),
                          child: const Text('Selesai & Tutup',
                              style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
                        ),
                      ),
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

  Widget _actionBtn({
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback onTap,
  }) {
    return SizedBox(
      height: 48,
      child: ElevatedButton.icon(
        onPressed: onTap,
        icon: Icon(icon, size: 18),
        label: Text(label, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
        style: ElevatedButton.styleFrom(
          backgroundColor: color,
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          elevation: 0,
        ),
      ),
    );
  }

  /// Builds the thermal-style receipt content.
  Widget _buildReceipt(BuildContext context, String storeName) {
    const mono = TextStyle(
      fontFamily: 'monospace',
      fontSize: 11,
      height: 1.5,
      color: Colors.black,
    );
    const monoBold = TextStyle(
      fontFamily: 'monospace',
      fontSize: 11,
      height: 1.5,
      fontWeight: FontWeight.bold,
      color: Colors.black,
    );
    const monoBig = TextStyle(
      fontFamily: 'monospace',
      fontSize: 14,
      height: 1.5,
      fontWeight: FontWeight.bold,
      color: Colors.black,
    );
    const monoHeader = TextStyle(
      fontFamily: 'monospace',
      fontSize: 15,
      height: 1.4,
      fontWeight: FontWeight.bold,
      color: Colors.black,
    );
    const monoGrey = TextStyle(
      fontFamily: 'monospace',
      fontSize: 11,
      height: 1.5,
      color: Color(0xFF555555),
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
        _dashedLine(),
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
        _dashedLine(),
        const SizedBox(height: 6),

        // ── Items ──
        ...items.map((item) => _buildItemRow(item, mono, monoGrey)),

        const SizedBox(height: 6),
        _dashedLine(),
        const SizedBox(height: 6),

        // ── Discount ──
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
        _dashedLine(),
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

  Widget _dashedLine() {
    return CustomPaint(
      size: const Size(double.infinity, 1),
      painter: _DashPainter(),
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

  // ── WhatsApp Share ──
  Future<void> _sendWhatsApp(BuildContext context, String storeName) async {
    final buf = StringBuffer();

    // Bold header
    buf.writeln('*STRUK PESANAN $storeName*');
    buf.writeln('--------------------------------');

    if (invoice != null) buf.writeln('ID    : $invoice');
    if (dateStr != null) buf.writeln('Waktu : $dateStr');
    if (cashierName != null && cashierName!.isNotEmpty) {
      buf.writeln('Kasir : $cashierName');
    }
    if (customerName != null && customerName!.isNotEmpty) {
      buf.writeln('Nama  : $customerName');
    }
    buf.writeln('--------------------------------');

    for (final item in items) {
      buf.writeln('▪ ${item.name}');
      buf.writeln('   ${item.qty} x ${formatRupiah(item.price)} = ${formatRupiah(item.subtotal)}');
    }

    buf.writeln('--------------------------------');
    if (discount > 0) {
      buf.writeln('Diskon/Potongan: -${formatRupiah(discount)}');
    }
    buf.writeln('*TOTAL BAYAR: ${formatRupiah(total)}*');
    buf.writeln('Metode: $paymentMethod');
    buf.writeln('--------------------------------');
    buf.writeln('Terima kasih, ditunggu pesanan selanjutnya! 🥟✨');

    // If customer phone exists, send to them; otherwise generic
    String waUrl;
    if (customerPhone != null && customerPhone!.trim().isNotEmpty) {
      String phone = customerPhone!.replaceAll(RegExp(r'[^0-9]'), '');
      if (phone.startsWith('0')) {
        phone = '62${phone.substring(1)}';
      } else if (phone.startsWith('8')) {
        phone = '62$phone';
      }
      waUrl = 'https://wa.me/$phone?text=${Uri.encodeComponent(buf.toString())}';
    } else {
      waUrl = 'https://wa.me/?text=${Uri.encodeComponent(buf.toString())}';
    }

    final uri = Uri.parse(waUrl);
    final canLaunch = await launcher.canLaunchUrl(uri);
    if (canLaunch) {
      await launcher.launchUrl(uri, mode: launcher.LaunchMode.externalApplication);
    } else if (context.mounted) {
      TopToast.error(context, 'Tidak dapat membuka WhatsApp');
    }
  }
}

/// Custom painter for dashed horizontal line (mimics GAS border-top: dashed).
class _DashPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = const Color(0xFF999999)
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
