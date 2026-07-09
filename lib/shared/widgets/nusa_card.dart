import 'package:flutter/material.dart';
class NusaCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry? padding;
  const NusaCard(this.child, {this.padding, super.key});
  @override
  Widget build(BuildContext c) => Card(
    child: Padding(padding: padding ?? const EdgeInsets.all(20), child: child));
}
