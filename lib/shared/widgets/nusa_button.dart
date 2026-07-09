import 'package:flutter/material.dart';
import 'package:nusa_kasir/core/config/nusa_config.dart';

class NusaButton extends StatelessWidget {
  final String label;
  final VoidCallback? onPressed;
  final bool fullWidth;
  const NusaButton(this.label, {this.onPressed, this.fullWidth = true, super.key});
  @override
  Widget build(BuildContext c) => SizedBox(width: fullWidth ? double.infinity : null,
    child: ElevatedButton(onPressed: onPressed, child: Text(label)));
}
