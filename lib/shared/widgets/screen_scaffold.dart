import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
class ScreenScaffold extends StatelessWidget {
  final String title; final Widget body; final List<Widget>? actions;
  const ScreenScaffold(this.title, this.body, {this.actions, super.key});
  @override
  Widget build(BuildContext c) => Scaffold(appBar: AppBar(title: Text(title),
    leading: ModalRoute.of(c)?.canPop == true ? const BackButton() : null, actions: actions), body: body);
}
