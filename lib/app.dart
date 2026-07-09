import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:nusa_kasir/core/theme/nusa_theme.dart';
import 'package:nusa_kasir/core/activation/activation_screen.dart';

final router = GoRouter(
  initialLocation: '/activation',
  routes: [
    GoRoute(path: '/activation', builder: (_, __) => const ActivationScreen()),
  ],
);

class NusaApp extends StatelessWidget {
  const NusaApp({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp.router(
        title: 'NUSA Kasir',
        theme: NusaTheme.light,
        routerConfig: router,
        debugShowCheckedModeBanner: false,
      );
}
