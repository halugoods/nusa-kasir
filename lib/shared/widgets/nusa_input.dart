import 'package:flutter/material.dart';
class NusaInput extends StatelessWidget {
  final String label;
  final TextEditingController? controller;
  final TextInputType? type;
  final bool monospace;
  final bool obscure;
  const NusaInput(this.label, {this.controller, this.type, this.monospace = false, this.obscure = false, super.key});
  @override
  Widget build(BuildContext c) => TextField(controller: controller, keyboardType: type, obscureText: obscure,
    style: monospace ? const TextStyle(fontFamily: 'monospace') : null,
    decoration: InputDecoration(labelText: label, border: const OutlineInputBorder(borderRadius: BorderRadius.all(Radius.circular(14)))));
}
