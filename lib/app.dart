import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:nusa_kasir/core/theme/nusa_theme.dart';
import 'package:nusa_kasir/data/database/app_database.dart';
import 'package:nusa_kasir/data/repositories/settings_repository.dart';
import 'package:nusa_kasir/core/activation/activation_repository.dart';
// activation_screen already defines activationRepoProvider; hide it so the
// local definition below is the single source of truth.
import 'package:nusa_kasir/core/activation/activation_screen.dart'
    hide activationRepoProvider;
import 'package:nusa_kasir/features/auth/login_screen.dart';
import 'package:nusa_kasir/features/onboarding/onboarding_screen.dart';
import 'package:nusa_kasir/features/dashboard/dashboard_screen.dart';
import 'package:nusa_kasir/features/settings/settings_screen.dart';
import 'package:nusa_kasir/features/common/placeholder_screen.dart';
import 'package:nusa_kasir/features/products/products_screen.dart';
import 'package:nusa_kasir/features/products/product_form_screen.dart';
import 'package:nusa_kasir/features/stock/stock_screen.dart';

final databaseProvider = Provider<AppDatabase>((ref) => AppDatabase());
final authProvider = StateProvider<String?>((ref) => null);
final settingsRepoProvider =
    Provider((ref) => SettingsRepository(ref.watch(databaseProvider)));
final activationRepoProvider = Provider<ActivationRepository>((ref) {
  try {
    return ActivationRepository(Supabase.instance.client);
  } catch (_) {
    return ActivationRepository(null);
  }
});

GoRouter buildRouter(String initialLocation) => GoRouter(
      initialLocation: initialLocation,
      routes: [
        GoRoute(
            path: '/activation',
            builder: (_, __) => const ActivationScreen()),
        GoRoute(path: '/login', builder: (_, __) => const LoginScreen()),
        GoRoute(
            path: '/onboarding', builder: (_, __) => const OnboardingScreen()),
        GoRoute(path: '/home', builder: (_, __) => const DashboardScreen()),
        GoRoute(path: '/kasir', builder: (_, __) => const PlaceholderScreen('Kasir')),
        GoRoute(path: '/produk', builder: (_, __) => const ProductsScreen()),
        GoRoute(path: '/produk/tambah', builder: (_, __) => const ProductFormScreen()),
        GoRoute(path: '/produk/edit/:id', builder: (_, state) => ProductFormScreen(productId: int.parse(state.pathParameters['id']!))),
        GoRoute(path: '/stok', builder: (_, __) => const StockScreen()),
        GoRoute(
            path: '/transaksi',
            builder: (_, __) => const PlaceholderScreen('Transaksi')),
        GoRoute(
            path: '/pelanggan',
            builder: (_, __) => const PlaceholderScreen('Pelanggan')),
        GoRoute(path: '/promo', builder: (_, __) => const PlaceholderScreen('Promo')),
        GoRoute(
            path: '/laporan',
            builder: (_, __) => const PlaceholderScreen('Laporan')),
        GoRoute(
            path: '/presensi',
            builder: (_, __) => const PlaceholderScreen('Presensi')),
        GoRoute(
            path: '/keuangan',
            builder: (_, __) => const PlaceholderScreen('Keuangan')),
        GoRoute(
            path: '/pengaturan', builder: (_, __) => const SettingsScreen()),
      ],
    );

class NusaApp extends StatelessWidget {
  final String initialLocation;
  const NusaApp({required this.initialLocation, super.key});
  @override
  Widget build(BuildContext context) => MaterialApp.router(
        title: 'NUSA Kasir',
        theme: NusaTheme.light,
        routerConfig: buildRouter(initialLocation),
        debugShowCheckedModeBanner: false,
      );
}
