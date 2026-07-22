import 'package:flutter/material.dart';
import 'package:nusa_kasir/core/config/nusa_config.dart';
import 'package:nusa_kasir/core/utils/receipt_printer.dart';
import 'package:nusa_kasir/core/utils/secure_storage.dart';
import 'package:nusa_kasir/shared/widgets/top_toast.dart';

/// Bottom sheet for managing Bluetooth thermal printer settings:
/// - Scan & connect to BT printers
/// - Test print
/// - Auto-print toggle (print automatically after transaction)
/// - Paper size selector (58mm / 80mm)
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
  bool _autoPrint = false;
  String _paperSize = '58';
  bool _testPrinting = false;
  String? _connectedAddr;
  String? _storedAddr;

  @override
  void initState() {
    super.initState();
    _storedAddr = widget.currentAddress;
    if (_storedAddr != null && _storedAddr!.contains('|')) {
      _connectedAddr = _storedAddr!.split('|').last;
    }
    _loadSettings();
    _scan();
  }

  Future<void> _loadSettings() async {
    final auto = await SecureStore.getAutoPrint();
    final paper = await SecureStore.getPaperSize();
    if (mounted) {
      setState(() {
        _autoPrint = auto;
        _paperSize = paper;
      });
    }
  }

  Future<void> _setAutoPrint(bool v) async {
    await SecureStore.setAutoPrint(v);
    if (mounted) setState(() => _autoPrint = v);
  }

  Future<void> _setPaperSize(String v) async {
    await SecureStore.setPaperSize(v);
    if (mounted) setState(() => _paperSize = v);
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
      if (mounted) {
        setState(() {
          _connectedAddr = device.address;
          _storedAddr = '${device.name}|${device.address}';
        });
        TopToast.success(context, 'Terhubung ke ${device.name}');
      }
    } catch (_) {
      if (mounted) {
        TopToast.error(context, 'Gagal menyambung ke printer');
      }
    } finally {
      await printer.dispose();
      if (mounted) setState(() => _connecting = null);
    }
  }

  Future<void> _testPrint() async {
    if (_storedAddr == null || !_storedAddr!.contains('|')) {
      TopToast.error(context, 'Hubungkan printer terlebih dahulu');
      return;
    }

    setState(() => _testPrinting = true);
    final printer = ReceiptPrinter();
    try {
      final devices = await printer.discover();
      if (devices.isEmpty) {
        if (mounted) TopToast.error(context, 'Tidak ada printer ditemukan');
        return;
      }

      final savedAddr = _storedAddr!.split('|').last;
      final found = devices.where((d) => d.address == savedAddr);
      if (found.isEmpty) {
        if (mounted) {
          TopToast.error(context, 'Printer tidak ditemukan. Silakan pindai ulang.');
        }
        return;
      }

      await printer.connect(found.first);
      final ok = await printer.printTest('NUSA Kasir', paperWidth: _paperSize);
      if (mounted) {
        if (ok) {
          TopToast.success(context, 'Test print berhasil dikirim');
        } else {
          TopToast.error(context, 'Gagal mengirim test print');
        }
      }
    } catch (_) {
      if (mounted) {
        TopToast.error(context, 'Gagal mencetak: pastikan printer menyala dan terhubung');
      }
    } finally {
      await printer.dispose();
      if (mounted) setState(() => _testPrinting = false);
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
    final accentRed = const Color(0xFFE63946);
    final accentGreen = const Color(0xFF10B981);

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
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Printer Bluetooth',
                        style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: textColor)),
                    const SizedBox(height: 4),
                    Text(
                      'Atur printer thermal untuk mencetak struk',
                      style: TextStyle(fontSize: 13, color: subColor),
                    ),
                  ],
                ),
              ),
              if (_connectedAddr != null)
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: accentGreen.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 8,
                        height: 8,
                        decoration: const BoxDecoration(
                          color: NusaConfig.accentGreen,
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 6),
                      const Text('Terhubung',
                          style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: NusaConfig.accentGreen)),
                    ],
                  ),
                ),
            ],
          ),
          const SizedBox(height: 16),

          // ── Settings toggles ──
          // Auto-print toggle
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: borderColor),
            ),
            child: Row(
              children: [
                Icon(Icons.auto_awesome, size: 20, color: subColor),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Cetak Otomatis',
                          style: TextStyle(
                              fontWeight: FontWeight.w600,
                              fontSize: 14,
                              color: textColor)),
                      Text('Langsung cetak struk setelah transaksi',
                          style: TextStyle(fontSize: 11, color: subColor)),
                    ],
                  ),
                ),
                Switch(
                  value: _autoPrint,
                  activeColor: accentRed,
                  onChanged: _setAutoPrint,
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),

          // Paper size selector
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: borderColor),
            ),
            child: Row(
              children: [
                Icon(Icons.view_agenda_outlined, size: 20, color: subColor),
                const SizedBox(width: 10),
                Text('Ukuran Kertas',
                    style: TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 14,
                        color: textColor)),
                const Spacer(),
                _paperChip('58mm',
                    selected: _paperSize == '58', isDark: isDark),
                const SizedBox(width: 6),
                _paperChip('80mm',
                    selected: _paperSize == '80', isDark: isDark),
              ],
            ),
          ),
          const SizedBox(height: 14),

          // ── Buttons row ──
          Row(
            children: [
              // Scan button
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _scanning ? null : _scan,
                  icon: _scanning
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.bluetooth_searching, size: 18),
                  label: Text(_scanning ? 'Memindai...' : 'Pindai'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: textColor,
                    side: BorderSide(color: borderColor),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              // Test print button
              Expanded(
                child: OutlinedButton.icon(
                  onPressed:
                      (_testPrinting || _connectedAddr == null) ? null : _testPrint,
                  icon: _testPrinting
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.print, size: 18),
                  label: Text(_testPrinting ? 'Mencetak...' : 'Test Print'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: _connectedAddr != null ? accentRed : subColor,
                    side: BorderSide(
                        color: _connectedAddr != null ? accentRed : borderColor),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                ),
              ),
            ],
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
                  const SizedBox(height: 4),
                  Text(
                    'Pastikan Bluetooth aktif dan printer dalam mode pairing',
                    style: TextStyle(fontSize: 11, color: subColor),
                    textAlign: TextAlign.center,
                  ),
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
                final isCurrent = _connectedAddr == d.address;
                return GestureDetector(
                  onTap: isConnecting ? null : () => _connect(d),
                  child: Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color:
                            isCurrent ? accentRed : borderColor,
                      ),
                      color: isCurrent
                          ? accentRed.withValues(alpha: 0.06)
                          : null,
                    ),
                    child: Row(
                      children: [
                        Icon(
                          Icons.print,
                          size: 22,
                          color: isCurrent ? accentRed : subColor,
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
                        if (!isCurrent && !isConnecting)
                          Text('Hubungkan',
                              style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  color: accentRed)),
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

  Widget _paperChip(String label,
      {required bool selected, required bool isDark}) {
    return GestureDetector(
      onTap: () => _setPaperSize(label == '58mm' ? '58' : '80'),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        decoration: BoxDecoration(
          color: selected
              ? const Color(0xFFE63946).withValues(alpha: 0.12)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: selected
                ? const Color(0xFFE63946)
                : (isDark ? const Color(0xFF3A3A52) : const Color(0xFFE5E7EB)),
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: selected
                ? const Color(0xFFE63946)
                : (isDark ? const Color(0xFF94A3B8) : const Color(0xFF6B7280)),
          ),
        ),
      ),
    );
  }
}
