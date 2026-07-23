import 'package:flutter/material.dart';
import 'package:nusa_kasir/shared/widgets/pin_pad.dart';

/// PIN authentication — now uses the custom PinPad (mobile-banking style).
///
/// Shows the employee name and role, a branded numeric keypad (4 or 6 digits),
/// an optional fingerprint button, and NFC auto-detect readiness.
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
    // Use custom PinPad (mobile-banking style) by default
    final padResult = await showDialog<PinPadResult>(
      context: context,
      barrierDismissible: false,
      builder: (_) => PinPad(
        employeeName: employeeName,
        employeeRole: employeeRole,
        correctPin: correctPin,
        pinLength: pinLength,
        showFingerprint: showFingerprint,
        onFingerprint: onFingerprint,
      ),
    );

    if (padResult == null) return null;
    return PinResult(success: padResult.success, remember: showRemember);
  }

  @override
  Widget build(BuildContext context) {
    // Fallback — normally PinDialog.show() uses PinPad directly
    return PinPad(
      employeeName: employeeName,
      employeeRole: employeeRole,
      correctPin: correctPin,
      pinLength: pinLength,
      showFingerprint: showFingerprint,
      onFingerprint: onFingerprint,
    );
  }
}
