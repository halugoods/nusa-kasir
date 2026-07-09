import 'package:flutter/material.dart';
import 'package:nusa_kasir/shared/widgets/screen_scaffold.dart';

class PlaceholderScreen extends StatelessWidget {
  final String title;
  const PlaceholderScreen(this.title, {super.key});
  @override
  Widget build(BuildContext c) => ScreenScaffold(
        title,
        const Center(
          child: Text('Segera hadir', style: TextStyle(color: Colors.grey)),
        ),
      );
}
