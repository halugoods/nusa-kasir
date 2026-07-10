import 'package:flutter/material.dart';
import 'package:nusa_kasir/core/utils/receipt_printer.dart';

/// Bottom sheet for discovering and selecting a Bluetooth thermal printer.
class PrinterSettingsSheet extends StatefulWidget {
  final String? currentAddress;
  final void Function(PrinterDevice device) onPrinterSelected;

  const PrinterSettingsSheet({
    super.key,
    this.currentAddress,
    required this.onPrinterSelected,
  });

  static void show({
    required BuildContext context,
    String? currentAddress,
    required void Function(PrinterDevice device) onPrinterSelected,
  }) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => PrinterSettingsSheet(
        currentAddress: currentAddress,
        onPrinterSelected: onPrinterSelected,
      ),
    );
  }

  @override
  State<PrinterSettingsSheet> createState() => _PrinterSettingsSheetState();
}

class _PrinterSettingsSheetState extends State<PrinterSettingsSheet> {
  List<PrinterDevice> _devices = [];
  bool _scanning = false;
  String? _connecting;

  @override
  void initState() {
    super.initState();
    _scan();
  }

  Future<void> _scan() async {
    setState(() => _scanning = true);
    final printer = ReceiptPrinter();
    try {
      final devices = await printer.discover();
      if (mounted) setState(() => _devices = devices);
    } finally {
      await printer.dispose();
      if (mounted) setState(() => _scanning = false);
    }
  }

  Future<void> _connect(PrinterDevice device) async {
    setState(() => _connecting = device.address);
    final printer = ReceiptPrinter();
    try {
      await printer.connect(device);
      widget.onPrinterSelected(device);
      if (mounted) Navigator.of(context).pop();
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Gagal menyambung ke printer'),
            backgroundColor: Color(0xFFE63946),
          ),
        );
      }
    } finally {
      await printer.dispose();
      if (mounted) setState(() => _connecting = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final textColor = theme.colorScheme.onSurface;
    final subColor =
        isDark ? const Color(0xFF94A3B8) : const Color(0xFF6B7280);
    final borderColor =
        isDark ? const Color(0xFF3A3A52) : const Color(0xFFF3F4F6);

    return Padding(
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 20,
        bottom: MediaQuery.of(context).viewInsets.bottom + 28,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Handle
          Center(
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(2),
                color: isDark
                    ? const Color(0xFF3A3A52)
                    : const Color(0xFFE5E7EB),
              ),
            ),
          ),
          const SizedBox(height: 16),
          // Header
          Text('Printer Bluetooth',
              style: TextStyle(
                  fontSize: 18, fontWeight: FontWeight.bold, color: textColor)),
          const SizedBox(height: 4),
          Text(
            'Pilih printer thermal untuk mencetak struk',
            style: TextStyle(fontSize: 13, color: subColor),
          ),
          const SizedBox(height: 16),

          // Scan button
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: _scanning ? null : _scan,
              icon: _scanning
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.bluetooth_searching, size: 18),
              label: Text(_scanning ? 'Memindai...' : 'Pindai Ulang'),
              style: OutlinedButton.styleFrom(
                foregroundColor: textColor,
                side: BorderSide(color: borderColor),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
            ),
          ),
          const SizedBox(height: 16),

          // Device list
          if (_devices.isEmpty && !_scanning)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 24),
              child: Column(
                children: [
                  Icon(Icons.print_disabled, size: 48, color: subColor),
                  const SizedBox(height: 8),
                  Text('Tidak ada printer ditemukan',
                      style: TextStyle(fontSize: 14, color: subColor)),
                ],
              ),
            ),

          // Scrollable list
          Flexible(
            child: ListView.separated(
              shrinkWrap: true,
              itemCount: _devices.length,
              separatorBuilder: (_, __) => const SizedBox(height: 8),
              itemBuilder: (_, i) {
                final d = _devices[i];
                final isConnecting = _connecting == d.address;
                final isCurrent = widget.currentAddress == d.address;
                return GestureDetector(
                  onTap: isConnecting ? null : () => _connect(d),
                  child: Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: isCurrent
                            ? const Color(0xFFE63946)
                            : borderColor,
                      ),
                      color: isCurrent
                          ? const Color(0xFFFDE8EA).withValues(alpha: 0.5)
                          : null,
                    ),
                    child: Row(
                      children: [
                        Icon(
                          Icons.print,
                          size: 22,
                          color: isCurrent
                              ? const Color(0xFFE63946)
                              : subColor,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(d.name,
                                  style: TextStyle(
                                      fontWeight: FontWeight.w600,
                                      color: textColor)),
                              Text(d.address,
                                  style: TextStyle(
                                      fontSize: 11, color: subColor)),
                            ],
                          ),
                        ),
                        if (isCurrent)
                          const Icon(Icons.check_circle,
                              size: 20, color: Color(0xFFE63946)),
                        if (isConnecting)
                          const SizedBox(
                            width: 20,
                            height: 20,
                            child:
                                CircularProgressIndicator(strokeWidth: 2),
                          ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
