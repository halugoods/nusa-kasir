import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:nusa_kasir/core/config/nusa_config.dart';

/// PIN login dialog — used when an employee needs to authenticate.
///
/// Shows the employee name and role, a PIN input (4-6 digits, obscured),
/// a "Remember PIN for 8 hours" checkbox, and Masuk/Batal buttons.
///
/// Call [show] and check the returned [PinResult]:
/// ```dart
/// final result = await PinDialog.show(context: ..., ...);
/// if (result?.success == true) {
///   // authenticated; result!.remember indicates whether to save session
/// }
/// ```
class PinResult {
  final bool success;
  final bool remember;
  const PinResult({required this.success, required this.remember});
}

class PinDialog extends StatefulWidget {
  final String employeeName;
  final String employeeRole;
  final String correctPin;
  final bool showRemember;

  const PinDialog({
    super.key,
    required this.employeeName,
    required this.employeeRole,
    required this.correctPin,
    this.showRemember = true,
  });

  /// Show the dialog. Returns [PinResult] or null if cancelled.
  static Future<PinResult?> show({
    required BuildContext context,
    required String employeeName,
    required String employeeRole,
    required String correctPin,
    bool showRemember = true,
  }) {
    return showDialog<PinResult>(
      context: context,
      barrierDismissible: false,
      builder: (_) => PinDialog(
        employeeName: employeeName,
        employeeRole: employeeRole,
        correctPin: correctPin,
        showRemember: showRemember,
      ),
    );
  }

  @override
  State<PinDialog> createState() => _PinDialogState();
}

class _PinDialogState extends State<PinDialog>
    with SingleTickerProviderStateMixin {
  final _ctrl = TextEditingController();
  bool _remember = false;
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
      TweenSequenceItem(tween: Tween(begin: 0, end: 10), weight: 1),
      TweenSequenceItem(tween: Tween(begin: 10, end: -10), weight: 2),
      TweenSequenceItem(tween: Tween(begin: -10, end: 10), weight: 2),
      TweenSequenceItem(tween: Tween(begin: 10, end: 0), weight: 1),
    ]).animate(CurvedAnimation(
      parent: _shakeCtrl,
      curve: Curves.easeInOut,
    ));
  }

  @override
  void dispose() {
    _ctrl.dispose();
    _shakeCtrl.dispose();
    super.dispose();
  }

  void _submit() {
    if (_ctrl.text.trim() == widget.correctPin) {
      Navigator.of(context).pop(
        PinResult(success: true, remember: widget.showRemember ? _remember : false),
      );
    } else {
      setState(() {
        _error = 'PIN salah';
        _ctrl.clear();
      });
      _shakeCtrl.forward(from: 0);
    }
  }

  Color? get _roleColor {
    switch (widget.employeeRole) {
      case 'Owner':
        return NusaConfig.primaryColor;
      case 'Manager':
        return NusaConfig.accentPurple;
      case 'Kasir':
        return NusaConfig.accentGreen;
      case 'Gudang':
        return const Color(0xFFF59E0B);
      case 'Finance':
        return const Color(0xFF3B82F6);
      default:
        return NusaConfig.textSecondary;
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 24),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      child: AnimatedBuilder(
        animation: _shakeAnim,
        builder: (context, child) {
          return Transform.translate(
            offset: Offset(_shakeAnim.value, 0),
            child: child,
          );
        },
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Header — avatar + name + role
              Container(
                width: 64,
                height: 64,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(18),
                  color: (_roleColor ?? NusaConfig.primaryColor)
                      .withValues(alpha: 0.12),
                ),
                child: Icon(
                  Icons.person_rounded,
                  size: 36,
                  color: _roleColor ?? NusaConfig.primaryColor,
                ),
              ),
              const SizedBox(height: 16),
              Text(
                widget.employeeName,
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color:
                      isDark ? NusaConfig.darkTextPrimary : NusaConfig.textPrimary,
                ),
              ),
              const SizedBox(height: 4),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                decoration: BoxDecoration(
                  color: (_roleColor ?? NusaConfig.primaryColor)
                      .withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  widget.employeeRole,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: _roleColor ?? NusaConfig.primaryColor,
                  ),
                ),
              ),
              const SizedBox(height: 24),

              // PIN input
              SizedBox(
                width: 220,
                child: TextField(
                  controller: _ctrl,
                  obscureText: true,
                  keyboardType: TextInputType.number,
                  maxLength: 6,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 28,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 12,
                  ),
                  maxLengthEnforcement: MaxLengthEnforcement.enforced,
                  decoration: InputDecoration(
                    counterText: '',
                    filled: true,
                    fillColor: isDark
                        ? NusaConfig.darkSurface2
                        : NusaConfig.backgroundColor,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(16),
                      borderSide: BorderSide(
                        color: _error != null
                            ? NusaConfig.primaryColor
                            : isDark
                                ? NusaConfig.darkBorder
                                : NusaConfig.borderColor,
                      ),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(16),
                      borderSide: BorderSide(
                        color: _error != null
                            ? NusaConfig.primaryColor
                            : isDark
                                ? NusaConfig.darkBorder
                                : NusaConfig.borderColor,
                      ),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(16),
                      borderSide: const BorderSide(
                        color: NusaConfig.primaryColor,
                        width: 1.8,
                      ),
                    ),
                    contentPadding: const EdgeInsets.symmetric(
                        vertical: 14, horizontal: 16),
                  ),
                  onSubmitted: (_) => _submit(),
                ),
              ),

              if (_error != null) ...[
                const SizedBox(height: 8),
                Text(
                  _error!,
                  style: const TextStyle(
                    color: NusaConfig.primaryColor,
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],

              const SizedBox(height: 16),

              // Remember checkbox (only for login, not for buka kasir PIN re-entry)
              if (widget.showRemember) ...[
                const SizedBox(height: 16),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    SizedBox(
                      height: 24,
                      width: 24,
                      child: Checkbox(
                        value: _remember,
                        onChanged: (v) =>
                            setState(() => _remember = v ?? false),
                        activeColor: NusaConfig.primaryColor,
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(5)),
                      ),
                    ),
                    const SizedBox(width: 8),
                    GestureDetector(
                      onTap: () =>
                          setState(() => _remember = !_remember),
                      child: Text(
                        'Ingat PIN selama 8 jam',
                        style: TextStyle(
                          fontSize: 13,
                          color: isDark
                              ? NusaConfig.darkTextSecondary
                              : NusaConfig.textSecondary,
                        ),
                      ),
                    ),
                  ],
                ),
              ],

              const SizedBox(height: 24),

              // Buttons
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed:
                          () => Navigator.of(context).pop(null),
                      style: OutlinedButton.styleFrom(
                        padding:
                            const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        side: BorderSide(
                          color: isDark
                              ? NusaConfig.darkBorder
                              : NusaConfig.dividerColor,
                        ),
                      ),
                      child: const Text('Batal'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: _submit,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: NusaConfig.primaryColor,
                        foregroundColor: Colors.white,
                        padding:
                            const EdgeInsets.symmetric(vertical: 14),
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: const Text(
                        'Masuk',
                        style: TextStyle(fontWeight: FontWeight.w700),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Simple AnimatedBuilder that works with Flutter 3.44.
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
