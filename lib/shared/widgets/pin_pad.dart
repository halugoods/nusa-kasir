import 'package:flutter/material.dart';
import 'package:nusa_kasir/core/config/nusa_config.dart';

/// A custom PIN pad widget — ala mobile banking.
///
/// Full-screen numeric keypad with branded design (red #E40000),
/// fingerprint button, and NFC auto-detect readiness.
///
/// Usage inside a dialog or screen:
/// ```dart
/// final ok = await showDialog<bool>(
///   context: context,
///   builder: (_) => PinPad(
///     title: 'Verifikasi PIN',
///     employeeName: 'Budi Setiawan',
///     employeeRole: 'Kasir',
///     correctPin: '123456',
///     pinLength: 6,
///     showFingerprint: true,
///     onFingerprint: () async => false,
///   ),
/// );
/// ```
class PinPadResult {
  final bool success;
  const PinPadResult({required this.success});
}

class PinPad extends StatefulWidget {
  final String title;
  final String employeeName;
  final String employeeRole;
  final String correctPin;
  final int pinLength;
  final bool showFingerprint;
  final Future<bool> Function()? onFingerprint;

  const PinPad({
    super.key,
    this.title = 'Verifikasi PIN',
    required this.employeeName,
    required this.employeeRole,
    required this.correctPin,
    this.pinLength = 6,
    this.showFingerprint = false,
    this.onFingerprint,
  }) : assert(pinLength == 4 || pinLength == 6);

  @override
  State<PinPad> createState() => _PinPadState();
}

class _PinPadState extends State<PinPad>
    with SingleTickerProviderStateMixin {
  String _digits = '';
  String? _error;

  late final AnimationController _shakeCtrl;
  late final Animation<double> _shakeAnim;

  @override
  void initState() {
    super.initState();
    _shakeCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
    );
    _shakeAnim = TweenSequence<double>([
      TweenSequenceItem(tween: Tween(begin: 0, end: 8), weight: 1),
      TweenSequenceItem(tween: Tween(begin: 8, end: -8), weight: 2),
      TweenSequenceItem(tween: Tween(begin: -8, end: 8), weight: 2),
      TweenSequenceItem(tween: Tween(begin: 8, end: 0), weight: 1),
    ]).animate(CurvedAnimation(
      parent: _shakeCtrl,
      curve: Curves.easeInOut,
    ));
  }

  @override
  void dispose() {
    _shakeCtrl.dispose();
    super.dispose();
  }

  void _onDigit(String d) {
    if (_digits.length >= widget.pinLength) return;
    setState(() {
      _error = null;
      _digits += d;
    });
    if (_digits.length == widget.pinLength) {
      _verify();
    }
  }

  void _onDelete() {
    if (_digits.isEmpty) return;
    setState(() {
      _error = null;
      _digits = _digits.substring(0, _digits.length - 1);
    });
  }

  void _verify() {
    if (_digits == widget.correctPin) {
      Navigator.of(context).pop(const PinPadResult(success: true));
    } else {
      setState(() {
        _error = 'PIN salah';
        _digits = '';
      });
      _shakeCtrl.forward(from: 0);
    }
  }

  Future<void> _onFingerprintTap() async {
    if (widget.onFingerprint == null) return;
    final ok = await widget.onFingerprint!();
    if (ok && mounted) {
      Navigator.of(context).pop(const PinPadResult(success: true));
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final count = widget.pinLength;
    final len = _digits.length;
    final bg = isDark ? NusaConfig.darkBackground : NusaConfig.backgroundColor;

    return Dialog(
      insetPadding: EdgeInsets.zero,
      backgroundColor: bg,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
      child: SafeArea(
        child: AnimatedBuilder(
          animation: _shakeAnim,
          builder: (context, child) {
            return Transform.translate(
              offset: Offset(_shakeAnim.value, 0),
              child: child,
            );
          },
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 40),

              // Lock icon
              Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  color: NusaConfig.primaryColor.withValues(alpha: 0.08),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.lock_outline,
                  color: NusaConfig.primaryColor,
                  size: 28,
                ),
              ),
              const SizedBox(height: 16),

              // Title
              Text(
                widget.title,
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                  color: isDark ? NusaConfig.darkTextPrimary : NusaConfig.textPrimary,
                ),
              ),
              const SizedBox(height: 4),

              // Employee info
              Text(
                '${widget.employeeName} — ${widget.employeeRole}',
                style: TextStyle(
                  fontSize: 13,
                  color: isDark ? NusaConfig.darkTextSecondary : NusaConfig.textSecondary,
                ),
              ),
              const SizedBox(height: 36),

              // PIN dots
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(count, (i) {
                  final filled = i < len;
                  return Container(
                    width: 18,
                    height: 18,
                    margin: EdgeInsets.symmetric(horizontal: count == 6 ? 10 : 14),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: _error != null
                            ? NusaConfig.primaryColor
                            : filled
                                ? NusaConfig.primaryColor
                                : isDark
                                    ? NusaConfig.darkBorder
                                    : NusaConfig.dividerColor,
                        width: 2,
                      ),
                      color: filled ? NusaConfig.primaryColor : Colors.transparent,
                    ),
                  );
                }),
              ),

              // Error text
              if (_error != null) ...[
                const SizedBox(height: 16),
                Text(
                  _error!,
                  style: const TextStyle(
                    color: NusaConfig.primaryColor,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],

              const SizedBox(height: 36),

              // Keypad
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 32),
                child: _buildKeypad(isDark),
              ),

              const SizedBox(height: 16),

              // Fingerprint
              if (widget.showFingerprint)
                GestureDetector(
                  onTap: _onFingerprintTap,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 24, vertical: 12),
                    decoration: BoxDecoration(
                      border: Border.all(
                        color: NusaConfig.primaryColor.withValues(alpha: 0.25),
                      ),
                      borderRadius: BorderRadius.circular(28),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.fingerprint,
                            color: NusaConfig.primaryColor, size: 22),
                        const SizedBox(width: 10),
                        Text(
                          'Gunakan Sidik Jari',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: NusaConfig.primaryColor,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

              const SizedBox(height: 8),

              // Cancel
              TextButton(
                onPressed: () => Navigator.of(context).pop(null),
                child: Text(
                  'Batal',
                  style: TextStyle(
                    fontSize: 14,
                    color: isDark ? NusaConfig.darkTextSecondary : NusaConfig.textSecondary,
                  ),
                ),
              ),

              const SizedBox(height: 16),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildKeypad(bool isDark) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _keypadRow(['1', '2', '3'], isDark),
        _keypadRow(['4', '5', '6'], isDark),
        _keypadRow(['7', '8', '9'], isDark),
        Row(
          children: [
            Expanded(
              child: _keyButton(
                child: Icon(Icons.fingerprint,
                    color: NusaConfig.primaryColor, size: 28),
                onTap: _onFingerprintTap,
              ),
            ),
            Expanded(
              child: _keyButton(
                text: '0',
                onTap: () => _onDigit('0'),
                isDark: isDark,
              ),
            ),
            Expanded(
              child: _keyButton(
                child: Icon(Icons.backspace_outlined,
                    color: NusaConfig.primaryColor, size: 24),
                onTap: _onDelete,
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _keypadRow(List<String> digits, bool isDark) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        children: digits.map((d) {
          return Expanded(
            child: _keyButton(
              text: d,
              onTap: () => _onDigit(d),
              isDark: isDark,
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _keyButton({
    String? text,
    Widget? child,
    VoidCallback? onTap,
    bool isDark = false,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 6),
      child: Material(
        color: text != null
            ? (isDark ? NusaConfig.darkSurface : Colors.white)
            : Colors.transparent,
        borderRadius: BorderRadius.circular(18),
        elevation: text != null ? 1 : 0,
        shadowColor: Colors.black12,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(18),
          child: Container(
            height: 60,
            alignment: Alignment.center,
            child: child ??
                Text(
                  text!,
                  style: const TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF1A1A1A),
                  ),
                ),
          ),
        ),
      ),
    );
  }
}

/// Local AnimatedBuilder that works across Flutter versions.
class AnimatedBuilder extends AnimatedWidget {
  final Widget Function(BuildContext, Widget?) builder;
  final Widget? child;

  const AnimatedBuilder({
    super.key,
    required Animation<double> animation,
    required this.builder,
    this.child,
  }) : super(listenable: animation);

  Animation<double> get animation => listenable as Animation<double>;

  @override
  Widget build(BuildContext context) => builder(context, child);
}
