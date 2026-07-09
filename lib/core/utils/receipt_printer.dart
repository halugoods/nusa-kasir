import 'dart:async';

import 'package:esc_pos_bluetooth/esc_pos_bluetooth.dart';
import 'package:esc_pos_utils/esc_pos_utils.dart';

import 'package:nusa_kasir/core/utils/format_rupiah.dart';

/// A single line item on a receipt.
class ReceiptLine {
  const ReceiptLine({
    required this.name,
    required this.qty,
    required this.price,
  });

  final String name;
  final int qty;
  final int price;

  int get subtotal => qty * price;
}

/// A discovered Bluetooth thermal printer.
class PrinterDevice {
  const PrinterDevice({
    required this.name,
    required this.address,
  });

  final String name;
  final String address;
}

/// Utility for discovering, connecting to and printing receipts on a
/// Bluetooth thermal (ESC/POS) printer.
///
/// Backed by `esc_pos_bluetooth` + `esc_pos_utils`.
class ReceiptPrinter {
  final PrinterBluetoothManager _manager = PrinterBluetoothManager();

  final Map<String, PrinterBluetooth> _discovered = {};
  PrinterBluetooth? _selected;
  StreamSubscription<List<PrinterBluetooth>>? _scanSubscription;

  /// Scan for paired/classic Bluetooth thermal printers and return them.
  ///
  /// Returns an empty list if no printers are found or scanning fails.
  Future<List<PrinterDevice>> discover({
    Duration timeout = const Duration(seconds: 5),
  }) async {
    _discovered.clear();
    final devices = <PrinterDevice>[];

    _scanSubscription = _manager.scanResults.listen((printers) {
      for (final printer in printers) {
        final address = printer.address;
        if (address == null || address.isEmpty) continue;
        if (_discovered.containsKey(address)) continue;
        _discovered[address] = printer;
        devices.add(
          PrinterDevice(
            name: printer.name?.isNotEmpty == true ? printer.name! : 'Printer',
            address: address,
          ),
        );
      }
    });

    _manager.startScan(timeout);
    // Give the scan time to complete, then stop it.
    await Future<void>.delayed(timeout + const Duration(seconds: 1));
    await _stopScan();

    return List<PrinterDevice>.unmodifiable(devices);
  }

  /// Connect to a printer previously returned by [discover], by address.
  Future<void> connect(PrinterDevice device) async {
    final printer = _discovered[device.address];
    if (printer == null) {
      throw StateError(
        'Printer ${device.address} was not discovered. '
        'Call discover() before connect().',
      );
    }
    _manager.selectPrinter(printer);
    _selected = printer;
  }

  /// Build the ESC/POS bytes for a receipt and send them to the connected
  /// printer. Returns `true` if the print job completed successfully.
  Future<bool> printReceipt({
    required String storeName,
    required List<ReceiptLine> lines,
    required int total,
    String? paymentMethod,
    String? cashierName,
  }) async {
    if (_selected == null) {
      return false;
    }

    final profile = await CapabilityProfile.load();
    final generator = Generator(PaperSize.mm58, profile);

    final List<int> bytes = [];

    // Header.
    bytes.addAll(generator.text(
      storeName,
      styles: const PosStyles(
        align: PosAlign.center,
        bold: true,
        height: PosTextSize.size2,
      ),
      linesAfter: 1,
    ));
    bytes.addAll(generator.hr());

    // Line items: name | qty x | price | subtotal.
    for (final line in lines) {
      bytes.addAll(generator.row([
        PosColumn(
          text: line.name,
          width: 6,
        ),
        PosColumn(
          text: '${line.qty} x',
          width: 2,
          styles: const PosStyles(align: PosAlign.right),
        ),
        PosColumn(
          text: formatRupiah(line.price),
          width: 2,
          styles: const PosStyles(align: PosAlign.right),
        ),
        PosColumn(
          text: formatRupiah(line.subtotal),
          width: 2,
          styles: const PosStyles(align: PosAlign.right),
        ),
      ]));
    }

    bytes.addAll(generator.hr());

    // Total.
    bytes.addAll(generator.row([
      PosColumn(
        text: 'TOTAL',
        width: 6,
        styles: const PosStyles(bold: true),
      ),
      PosColumn(
        text: formatRupiah(total),
        width: 6,
        styles: const PosStyles(bold: true, align: PosAlign.right),
      ),
    ]));

    if (paymentMethod != null && paymentMethod.isNotEmpty) {
      bytes.addAll(generator.text('Pembayaran: $paymentMethod'));
    }
    if (cashierName != null && cashierName.isNotEmpty) {
      bytes.addAll(generator.text('Kasir: $cashierName'));
    }

    bytes.addAll(generator.hr());

    // Footer.
    bytes.addAll(generator.text(
      'Terima kasih!',
      styles: const PosStyles(align: PosAlign.center, bold: true),
    ));
    bytes.addAll(generator.feed(2));
    bytes.addAll(generator.cut());

    final result = await _manager.printTicket(bytes);
    return result == PosPrintResult.success;
  }

  /// Disconnect and release any active scan subscription.
  Future<void> dispose() async {
    await _stopScan();
    _selected = null;
    _discovered.clear();
  }

  Future<void> _stopScan() async {
    await _scanSubscription?.cancel();
    _scanSubscription = null;
    _manager.stopScan();
  }
}
