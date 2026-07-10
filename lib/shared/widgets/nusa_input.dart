import 'package:flutter/material.dart';

/// Theme-aware text input — adapts to light/dark.
class NusaInput extends StatelessWidget {
  final String label;
  final TextEditingController? controller;
  final TextInputType? type;
  final bool monospace;
  final bool obscure;
  final String? hint;

  const NusaInput(
    this.label, {
    super.key,
    this.controller,
    this.type,
    this.monospace = false,
    this.obscure = false,
    this.hint,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final labelColor = theme.textTheme.titleMedium?.color ?? theme.colorScheme.onSurface;
    final inputFill = isDark ? const Color(0xFF252540) : Colors.white;
    final inputBorder = isDark ? const Color(0xFF3A3A52) : const Color(0xFFE5E7EB);
    final textColor = theme.colorScheme.onSurface;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: labelColor,
          ),
        ),
        const SizedBox(height: 6),
        TextField(
          controller: controller,
          keyboardType: type,
          obscureText: obscure,
          style: monospace
              ? TextStyle(fontFamily: 'monospace', fontSize: 15, color: textColor)
              : TextStyle(fontSize: 15, color: textColor),
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: TextStyle(
              color: isDark ? const Color(0xFF64748B) : const Color(0xFF9CA3AF),
              fontSize: 15,
            ),
            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: inputBorder),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: inputBorder),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: Color(0xFFE63946), width: 1.5),
            ),
            filled: true,
            fillColor: inputFill,
          ),
        ),
      ],
    );
  }
}
