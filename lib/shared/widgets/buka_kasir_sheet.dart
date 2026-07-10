import 'package:flutter/material.dart';
import 'package:nusa_kasir/core/config/nusa_config.dart';
import 'package:nusa_kasir/core/utils/format_rupiah.dart';

/// Bottom sheet modal for "Buka Kasir" — asks for starting cash balance.
///
/// Matches the reference BukaKasirButton:
///   - Draggable handle bar at top
///   - Calculator icon in red-soft circle + title + subtitle
///   - Store info banner (red-50 bg, wallet icon)
///   - Rp-prefixed numeric input, right-aligned, bold
///   - Quick chips: Rp 50k / 100k / 200k / 500k
///   - "Mulai Sesi Kasir" CTA button (full width, red, arrow icon)
///
/// Call `showBukaKasirSheet(context, storeName, onConfirm)` to display.
class BukaKasirSheet extends StatefulWidget {
  final String storeName;
  final void Function(int saldo) onConfirm;

  const BukaKasirSheet({
    super.key,
    required this.storeName,
    required this.onConfirm,
  });

  /// Convenience method to show the sheet.
  static void show({
    required BuildContext context,
    required String storeName,
    required void Function(int saldo) onConfirm,
  }) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: NusaConfig.surfaceColor,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => BukaKasirSheet(
        storeName: storeName,
        onConfirm: onConfirm,
      ),
    );
  }

  @override
  State<BukaKasirSheet> createState() => _BukaKasirSheetState();
}

class _BukaKasirSheetState extends State<BukaKasirSheet> {
  final _controller = TextEditingController();
  final _focusNode = FocusNode();

  String get _raw => _controller.text.replaceAll(RegExp(r'[^\d]'), '');

  @override
  void initState() {
    super.initState();
    _controller.addListener(() => setState(() {}));
    // Auto-focus after sheet opens
    Future.delayed(const Duration(milliseconds: 300), () {
      if (mounted) _focusNode.requestFocus();
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _setChip(int value) {
    _controller.text = value.toString();
  }

  void _confirm() {
    final nilai = int.tryParse(_raw);
    if (nilai == null || nilai <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Saldo awal wajib diisi'),
          backgroundColor: NusaConfig.primaryColor,
        ),
      );
      return;
    }
    widget.onConfirm(nilai);
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 20,
        bottom: MediaQuery.of(context).viewInsets.bottom + 28,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Handle bar
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(2),
                  color: NusaConfig.dividerColor,
                ),
              ),
            ),
            const SizedBox(height: 16),

            // Header
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Icon
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(12),
                    color: NusaConfig.primarySoft,
                  ),
                  child: const Icon(
                    Icons.calculate_outlined,
                    size: 22,
                    color: NusaConfig.primaryColor,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Text(
                        'Buka Kasir',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: NusaConfig.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Mulai sesi penjualan hari ini',
                        style: const TextStyle(
                          fontSize: 13,
                          color: NusaConfig.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
                // Close button
                GestureDetector(
                  onTap: () => Navigator.of(context).pop(),
                  child: Container(
                    width: 36,
                    height: 36,
                    decoration: const BoxDecoration(shape: BoxShape.circle),
                    child: const Icon(Icons.close,
                        size: 20, color: NusaConfig.textSecondary),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),

            // Store info
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: NusaConfig.primarySoft,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: NusaConfig.primarySoft),
              ),
              child: Row(
                children: [
                  const Icon(Icons.account_balance_wallet_outlined,
                      size: 16, color: NusaConfig.primaryColor),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      widget.storeName,
                      style: const TextStyle(
                        fontSize: 13,
                        color: NusaConfig.textPrimary,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),

            // Label
            const Text(
              'Saldo Awal Kas',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: NusaConfig.textPrimary,
              ),
            ),
            const SizedBox(height: 8),

            // Input with Rp prefix
            Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: NusaConfig.dividerColor),
                color: Colors.white,
              ),
              child: Row(
                children: [
                  const Padding(
                    padding: EdgeInsets.only(left: 16),
                    child: Text(
                      'Rp',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: NusaConfig.textSecondary,
                      ),
                    ),
                  ),
                  Expanded(
                    child: TextField(
                      controller: _controller,
                      focusNode: _focusNode,
                      keyboardType: TextInputType.number,
                      textAlign: TextAlign.right,
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: NusaConfig.textPrimary,
                      ),
                      decoration: const InputDecoration(
                        hintText: '0',
                        hintStyle: TextStyle(color: NusaConfig.textTertiary),
                        border: InputBorder.none,
                        contentPadding:
                            EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'Masukkan jumlah uang tunai yang ada di laci kasir saat ini.',
              style: TextStyle(fontSize: 12, color: NusaConfig.textSecondary),
            ),
            const SizedBox(height: 16),

            // Quick chips
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [50000, 100000, 200000, 500000].map((v) {
                return GestureDetector(
                  onTap: () => _setChip(v),
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: NusaConfig.dividerColor),
                    ),
                    child: Text(
                      'Rp ${formatRupiah(v)}',
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                        color: NusaConfig.textSecondary,
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),
            const SizedBox(height: 24),

            // CTA
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _confirm,
                icon: const Icon(Icons.arrow_forward, size: 18),
                label: const Text('Mulai Sesi Kasir'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: NusaConfig.primaryColor,
                  foregroundColor: Colors.white,
                  elevation: 6,
                  shadowColor: NusaConfig.primaryColor.withValues(alpha: 0.28),
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
