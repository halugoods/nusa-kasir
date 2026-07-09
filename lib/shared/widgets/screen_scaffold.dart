import 'package:flutter/material.dart';

class ScreenScaffold extends StatelessWidget {
  final String title;
  final Widget body;
  final List<Widget>? actions;
  final Widget? floatingActionButton;
  const ScreenScaffold(this.title, this.body,
      {this.actions, this.floatingActionButton, super.key});
  @override
  Widget build(BuildContext c) => Scaffold(
        appBar: AppBar(
          title: Text(title),
          leading: ModalRoute.of(c)?.canPop == true ? const BackButton() : null,
          actions: actions,
        ),
        body: body,
        floatingActionButton: floatingActionButton,
      );
}
