import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart' as launcher;

import 'package:nusa_kasir/app.dart';
import 'package:nusa_kasir/core/utils/format_rupiah.dart';
import 'package:nusa_kasir/core/utils/receipt_printer.dart';
import 'package:nusa_kasir/data/repositories/settings_repository.dart';
import 'package:nusa_kasir/features/pos/cart.dart';
import 'package:nusa_kasir/shared/widgets/nusa_button.dart';
import "package:nusa_kasir/shared/widgets/top_toast.dart";

class ReceiptSheet extends ConsumerWidget {
  final List<CartItem> items;
  final int total;
  final int discount;
  final String paymentMethod;
  final int? cashGiven;
  final int? cashReturn;
  final String? cashierName;

  const ReceiptSheet({
    required this.items,
    required this.total,
    required this.discount,
    required this.paymentMethod,
    this.cashGiven,
    this.cashReturn,
    this.cashierName,
    super.key,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final db = ref.read(databaseProvider);
    return FutureBuilder<String>(
      future: SettingsRepository(db).getStoreName(),
      builder: (context, snap) {
        final storeName = snap.data ?? 'NUSA Kasir';
        return Padding(
          padding: EdgeInsets.only(
            left: 24,
            right: 24,
            top: 24,
            bottom: MediaQuery.of(context).viewInsets.bottom + 24,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Handle
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 16),

              // Store name
              Text(storeName,
                  style: const TextStyle(
                      fontSize: 18, fontWeight: FontWeight.bold)),
              const SizedBox(height: 4),
              Text('Struk Pembayaran',
                  style: TextStyle(color: Colors.grey.shade600)),
              const Divider(height: 24),

              // Items
              ...items.map((item) => Padding(
                    padding: const EdgeInsets.symmetric(vertical: 2),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(item.name,
                              style: const TextStyle(fontSize: 14)),
                        ),
                        Text('${item.qty} x ',
                            style: TextStyle(color: Colors.grey.shade600)),
                        Text(formatRupiah(item.price),
                            style: TextStyle(color: Colors.grey.shade600)),
                        const SizedBox(width: 8),
                        Text(formatRupiah(item.subtotal),
                            style: const TextStyle(
                                fontWeight: FontWeight.w600, fontSize: 14)),
                      ],
                    ),
                  )),

              const Divider(height: 16),

              // Totals
              if (discount > 0)
                _receiptRow('Diskon', formatRupiah(discount)),
              _receiptRow('Total', formatRupiah(total), bold: true),
              const SizedBox(height: 4),
              Text('Pembayaran: $paymentMethod',
                  style: TextStyle(color: Colors.grey.shade600, fontSize: 13)),
              if (cashGiven != null)
                _receiptRow('Tunai', formatRupiah(cashGiven!)),
              if (cashReturn != null && cashReturn! > 0)
                _receiptRow('Kembalian', formatRupiah(cashReturn!)),
              if (cashierName != null && cashierName!.isNotEmpty)
                Text('Kasir: $cashierName',
                    style:
                        TextStyle(color: Colors.grey.shade600, fontSize: 13)),
              const SizedBox(height: 4),
              Text('Terima kasih!',
                  style: TextStyle(
                      color: Colors.grey.shade600,
                      fontSize: 13,
                      fontStyle: FontStyle.italic)),
              const SizedBox(height: 16),

              // Actions
              Row(
                children: [
                  Expanded(
                    child: NusaButton(
                      'Cetak Struk',
                      onPressed: () =>
                          _printReceipt(context, ref, storeName),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: NusaButton(
                      'Kirim WA',
                      onPressed: () =>
                          _sendWhatsApp(context, storeName),
                    ),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _receiptRow(String label, String value, {bool bold = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 1),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label,
              style: TextStyle(
                  fontWeight: bold ? FontWeight.w700 : FontWeight.w400,
                  fontSize: 14)),
          Text(value,
              style: TextStyle(
                  fontWeight: bold ? FontWeight.w700 : FontWeight.w400,
                  fontSize: 14)),
        ],
      ),
    );
  }

  Future<void> _printReceipt(
      BuildContext context, WidgetRef ref, String storeName) async {
    final printer = ReceiptPrinter();
    try {
      final devices = await printer.discover();
      if (devices.isEmpty) {
        if (context.mounted) {
          TopToast.error(
              context, 'Sambungkan printer di Pengaturan');
        }
        return;
      }

      // Try to use the saved printer by address first
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
            .map((i) => ReceiptLine(
                name: i.name, qty: i.qty, price: i.price))
            .toList(),
        total: total,
        paymentMethod: paymentMethod,
        cashierName: cashierName,
      );
      if (context.mounted) {
        TopToast.error(
            context, ok ? 'Struk berhasil dicetak' : 'Gagal mencetak');
      }
    } catch (_) {
      if (context.mounted) {
        TopToast.error(context, 'Gagal mencetak struk');
      }
    } finally {
      printer.dispose();
    }
  }

  Future<void> _sendWhatsApp(BuildContext context, String storeName) async {
    final lines = StringBuffer();
    lines.writeln(storeName);
    lines.writeln('---');
    for (final item in items) {
      lines.writeln('${item.name} x${item.qty} = ${formatRupiah(item.subtotal)}');
    }
    if (discount > 0) {
      lines.writeln('Diskon: ${formatRupiah(discount)}');
    }
    lines.writeln('TOTAL: ${formatRupiah(total)}');
    lines.writeln('Pembayaran: $paymentMethod');
    lines.writeln('---');
    lines.writeln('Terima kasih');

    final uri = Uri.parse(
        'https://wa.me/?text=${Uri.encodeComponent(lines.toString())}');
    final canLaunch = await launcher.canLaunchUrl(uri);
    if (canLaunch) {
      await launcher.launchUrl(uri, mode: launcher.LaunchMode.externalApplication);
    } else if (context.mounted) {
      TopToast.error(context, 'Tidak dapat membuka WhatsApp');
    }
  }
}
