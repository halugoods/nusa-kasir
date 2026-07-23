import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:nusa_kasir/core/config/nusa_config.dart';

/// PIN input with configurable [length] (4 or 6 digits).
///
/// Visually shows N rounded boxes behind a hidden TextField for seamless
/// typing/pasting. Boxes auto-size via LayoutBuilder so they fit inside
/// dialogs and bottom sheets without overflowing.
///
/// When [autoSubmit] is true (default), [onComplete] fires automatically
/// when all [length] digits are entered. When false, read [PinInputState.text].
class PinInput extends StatefulWidget {
  final void Function(String pin)? onComplete;
  final String? error;
  final bool autofocus;
  final VoidCallback? onChanged;
  final bool autoSubmit;
  final int length;

  const PinInput({
    super.key,
    this.onComplete,
    this.error,
    this.autofocus = true,
    this.onChanged,
    this.autoSubmit = true,
    this.length = 6,
  }) : assert(length == 4 || length == 6);

  @override
  PinInputState createState() => PinInputState();
}

class PinInputState extends State<PinInput> {
  late final TextEditingController _ctrl;
  final _focusNode = FocusNode();
  String _text = '';

  /// The current digit text (e.g. "1234").
  String get text => _text;

  @override
  void initState() {
    super.initState();
    _ctrl = TextEditingController();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void clear() {
    _ctrl.clear();
    setState(() => _text = '');
    _focusNode.requestFocus();
  }

  void _onChanged(String value) {
    final digits = value.replaceAll(RegExp(r'[^0-9]'), '');
    if (digits.length > widget.length) {
      _ctrl.text = _text = digits.substring(0, widget.length);
      _ctrl.selection = TextSelection.collapsed(offset: widget.length);
    } else {
      _text = digits;
    }
    widget.onChanged?.call();
    if (widget.autoSubmit &&
        _text.length == widget.length &&
        widget.onComplete != null) {
      widget.onComplete!(_text);
    }
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final hasError = widget.error != null;
    final focused = _focusNode.hasFocus;
    final len = _text.length;
    final count = widget.length;

    return LayoutBuilder(
      builder: (context, constraints) {
        // Responsive box sizing — fits tight dialogs, capped at 48×56 on wide screens
        const gap = 8.0;
        final totalGaps = (count - 1) * gap;
        final boxW =
            ((constraints.maxWidth - totalGaps) / count).clamp(36.0, 48.0);
        final boxH = boxW * 56 / 48;
        final dotSize = boxW * 26 / 48;
        final radius = boxW * 14 / 48;

        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 1,
              height: 1,
              child: TextField(
                controller: _ctrl,
                focusNode: _focusNode,
                autofocus: widget.autofocus,
                keyboardType: TextInputType.number,
                maxLength: count,
                maxLengthEnforcement: MaxLengthEnforcement.enforced,
                onChanged: _onChanged,
                style: const TextStyle(fontSize: 1, color: Colors.transparent),
                cursorColor: Colors.transparent,
                decoration: const InputDecoration(
                  counterText: '',
                  border: InputBorder.none,
                  focusedBorder: InputBorder.none,
                  enabledBorder: InputBorder.none,
                ),
              ),
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(count, (i) {
                final filled = i < len;
                final isCurrent = i == len;
                return Padding(
                  padding: EdgeInsets.only(left: i == 0 ? 0 : gap),
                  child: Container(
                    width: boxW,
                    height: boxH,
                    decoration: BoxDecoration(
                      color: isDark
                          ? NusaConfig.darkSurface2
                          : NusaConfig.backgroundColor,
                      borderRadius: BorderRadius.circular(radius),
                      border: Border.all(
                        color: hasError
                            ? NusaConfig.primaryColor
                            : (focused || isCurrent)
                                ? NusaConfig.primaryColor
                                : isDark
                                    ? NusaConfig.darkBorder
                                    : NusaConfig.borderColor,
                        width: (focused || isCurrent || hasError) ? 2 : 1,
                      ),
                    ),
                    alignment: Alignment.center,
                    child: filled
                        ? FittedBox(
                            fit: BoxFit.scaleDown,
                            child: Text(
                              '\u2022',
                              style: TextStyle(
                                fontSize: dotSize,
                                fontWeight: FontWeight.w700,
                                color: isDark
                                    ? NusaConfig.darkTextPrimary
                                    : NusaConfig.textPrimary,
                              ),
                            ),
                          )
                        : null,
                  ),
                );
              }),
            ),
          ],
        );
      },
    );
  }
}
