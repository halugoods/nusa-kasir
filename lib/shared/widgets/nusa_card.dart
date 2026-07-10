import 'package:flutter/material.dart';

class NusaCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry? padding;
  const NusaCard(this.child, {this.padding, super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Container(
      padding: padding ?? const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isDark ? const Color(0xFF3A3A52) : const Color(0xFFF3F4F6),
        ),
        boxShadow: [
          BoxShadow(
            color: isDark
                ? const Color(0x1A000000)
                : const Color(0x0A111827),
            blurRadius: 3,
            offset: const Offset(0, 1),
          ),
        ],
      ),
      child: child,
    );
  }
}
