import 'package:flutter/material.dart';
import 'package:nusa_kasir/core/config/nusa_config.dart';
import 'package:nusa_kasir/shared/widgets/pin_keypad.dart';

/// PIN authentication dialog — shows a branded keypad (EDC/ATM style)
/// with employee name + role header.
///
/// Call [show] and check the returned [PinResult]:
/// ```dart
/// final result = await PinDialog.show(context: ..., ...);
/// if (result?.success == true) { ... }
/// ```
class PinResult {
  final bool success;
  final bool remember;
  const PinResult({required this.success, required this.remember});
}

class PinDialog extends StatelessWidget {
  final String employeeName;
  final String employeeRole;
  final String correctPin;
  final bool showRemember;
  final int pinLength;
  final bool showFingerprint;
  final Future<bool> Function()? onFingerprint;

  const PinDialog({
    super.key,
    required this.employeeName,
    required this.employeeRole,
    required this.correctPin,
    this.showRemember = true,
    this.pinLength = 6,
    this.showFingerprint = false,
    this.onFingerprint,
  });

  /// Show the dialog. Returns [PinResult] or null if cancelled.
  static Future<PinResult?> show({
    required BuildContext context,
    required String employeeName,
    required String employeeRole,
    required String correctPin,
    bool showRemember = true,
    int pinLength = 6,
    bool showFingerprint = false,
    Future<bool> Function()? onFingerprint,
  }) async {
    return showDialog<PinResult>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        final isDark = Theme.of(ctx).brightness == Brightness.dark;
        String? error;
        final keypadKey = GlobalKey<_PinDialogKeypadState>();

        return StatefulBuilder(
          builder: (ctx, setSt) {
            return AlertDialog(
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(24)),
              titlePadding: const EdgeInsets.fromLTRB(24, 28, 24, 0),
              contentPadding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              actionsPadding: EdgeInsets.zero,
              title: Column(children: [
                // Lock icon
                Container(
                  width: 52,
                  height: 52,
                  decoration: BoxDecoration(
                    color: NusaConfig.primaryColor.withValues(alpha: 0.08),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.lock_outline,
                      color: NusaConfig.primaryColor, size: 26),
                ),
                const SizedBox(height: 14),
                Text(
                  employeeName,
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: isDark
                        ? NusaConfig.darkTextPrimary
                        : NusaConfig.textPrimary,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  employeeRole,
                  style: TextStyle(
                    fontSize: 13,
                    color: isDark
                        ? NusaConfig.darkTextSecondary
                        : NusaConfig.textSecondary,
                  ),
                ),
              ]),
              content: _PinDialogKeypad(
                key: keypadKey,
                pinLength: pinLength,
                error: error,
                showFingerprint: showFingerprint,
                onFingerprint: onFingerprint,
                onComplete: (pin) {
                  final ok = pin.isNotEmpty && pin == correctPin;
                  if (ok) {
                    Navigator.of(ctx).pop(
                        PinResult(success: true, remember: showRemember));
                  } else {
                    setSt(() {
                      error = 'PIN salah';
                      keypadKey.currentState?.clear();
                    });
                  }
                },
              ),
              actions: [],
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    // Fallback — normally PinDialog.show() handles rendering
    return const SizedBox.shrink();
  }
}

/// Internal keypad holder that exposes [clear].
class _PinDialogKeypad extends StatefulWidget {
  final int pinLength;
  final String? error;
  final bool showFingerprint;
  final Future<bool> Function()? onFingerprint;
  final ValueChanged<String> onComplete;

  const _PinDialogKeypad({
    super.key,
    required this.pinLength,
    this.error,
    this.showFingerprint = false,
    this.onFingerprint,
    required this.onComplete,
  });

  @override
  State<_PinDialogKeypad> createState() => _PinDialogKeypadState();
}

class _PinDialogKeypadState extends State<_PinDialogKeypad> {
  int _resetCount = 0;

  void clear() {
    // Force fresh PinKeypad so internal digits reset
    setState(() => _resetCount++);
  }

  @override
  Widget build(BuildContext context) {
    return PinKeypad(
      key: ValueKey('dialog_pad_$_resetCount'),
      length: widget.pinLength,
      error: widget.error,
      showFingerprint: widget.showFingerprint,
      showCancel: true,
      onFingerprint: widget.onFingerprint,
      onFingerprintSuccess: () => Navigator.of(context)
          .pop(PinResult(success: true, remember: true)),
      onComplete: widget.onComplete,
      onCancel: () => Navigator.of(context).pop(null),
    );
  }
}
