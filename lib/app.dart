import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:nusa_kasir/core/theme/nusa_theme.dart';
import 'package:nusa_kasir/data/database/app_database.dart';
import 'package:nusa_kasir/data/repositories/customer_repository.dart';
import 'package:nusa_kasir/data/repositories/settings_repository.dart';
import 'package:nusa_kasir/data/repositories/transaction_repository.dart';
import 'package:nusa_kasir/core/activation/activation_repository.dart';
// activation_screen already defines activationRepoProvider; hide it so the
// local definition below is the single source of truth.
import 'package:nusa_kasir/core/activation/activation_screen.dart'
    hide activationRepoProvider;
import 'package:nusa_kasir/features/auth/login_screen.dart';
import 'package:nusa_kasir/features/onboarding/onboarding_screen.dart';
import 'package:nusa_kasir/features/dashboard/dashboard_screen.dart';
import 'package:nusa_kasir/features/settings/settings_screen.dart';
import 'package:nusa_kasir/features/products/products_screen.dart';
import 'package:nusa_kasir/features/products/product_form_screen.dart';
import 'package:nusa_kasir/features/stock/stock_screen.dart';
import 'package:nusa_kasir/features/pos/pos_screen.dart';
import 'package:nusa_kasir/features/checkout/checkout_screen.dart';
import 'package:nusa_kasir/features/transactions/transactions_screen.dart';
import 'package:nusa_kasir/features/customers/customers_screen.dart';
import 'package:nusa_kasir/features/promo/promo_screen.dart';
import 'package:nusa_kasir/features/reports/reports_screen.dart';
import 'package:nusa_kasir/features/attendance/attendance_screen.dart';
import 'package:nusa_kasir/features/finance/finance_screen.dart';
import 'package:nusa_kasir/features/suppliers/suppliers_screen.dart';
import 'package:nusa_kasir/features/spreadsheet/spreadsheet_screen.dart';

final databaseProvider = Provider<AppDatabase>((ref) => AppDatabase());
final authProvider = StateProvider<String?>((ref) => null);
final settingsRepoProvider =
    Provider((ref) => SettingsRepository(ref.watch(databaseProvider)));
final transactionRepoProvider =
    Provider((ref) => TransactionRepository(ref.watch(databaseProvider)));
final customerRepoProvider =
    Provider((ref) => CustomerRepository(ref.watch(databaseProvider)));
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
            pageBuilder: (_, __) => _slidePage(const ActivationScreen())),
        GoRoute(
            path: '/login', pageBuilder: (_, __) => _slidePage(const LoginScreen())),
        GoRoute(
            path: '/onboarding',
            pageBuilder: (_, __) => _slidePage(const OnboardingScreen())),
        GoRoute(
            path: '/home',
            pageBuilder: (_, __) => _slidePage(const DashboardScreen())),
        GoRoute(
            path: '/kasir', pageBuilder: (_, __) => _slidePage(const PosScreen())),
        GoRoute(
            path: '/checkout',
            pageBuilder: (_, __) => _slidePage(const CheckoutScreen())),
        GoRoute(
            path: '/produk',
            pageBuilder: (_, __) => _slidePage(const ProductsScreen())),
        GoRoute(
            path: '/produk/tambah',
            pageBuilder: (_, __) => _slidePage(const ProductFormScreen())),
        GoRoute(
            path: '/produk/edit/:id',
            pageBuilder: (_, state) => _slidePage(ProductFormScreen(
                productId: int.parse(state.pathParameters['id']!)))),
        GoRoute(
            path: '/stok', pageBuilder: (_, __) => _slidePage(const StockScreen())),
        GoRoute(
            path: '/transaksi',
            pageBuilder: (_, __) => _slidePage(const TransactionsScreen())),
        GoRoute(
            path: '/pelanggan',
            pageBuilder: (_, __) => _slidePage(const CustomersScreen())),
        GoRoute(
            path: '/promo', pageBuilder: (_, __) => _slidePage(const PromoScreen())),
        GoRoute(
            path: '/laporan',
            pageBuilder: (_, __) => _slidePage(const ReportsScreen())),
        GoRoute(
            path: '/presensi',
            pageBuilder: (_, __) => _slidePage(const AttendanceScreen())),
        GoRoute(
            path: '/keuangan',
            pageBuilder: (_, __) => _slidePage(const FinanceScreen())),
        GoRoute(
            path: '/pengaturan',
            pageBuilder: (_, __) => _slidePage(const SettingsScreen())),
        GoRoute(
            path: '/supplier',
            pageBuilder: (_, __) => _slidePage(const SuppliersScreen())),
        GoRoute(
            path: '/spreadsheet',
            pageBuilder: (_, __) => _slidePage(const SpreadsheetScreen())),
      ],
    );

CustomTransitionPage _slidePage(Widget child) => CustomTransitionPage(
      child: child,
      transitionsBuilder: (context, animation, secondaryAnimation, child) =>
          SlideTransition(
        position: Tween<Offset>(
          begin: const Offset(0.3, 0),
          end: Offset.zero,
        ).animate(CurvedAnimation(
          parent: animation,
          curve: Curves.easeOutCubic,
        )),
        child: child,
      ),
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
