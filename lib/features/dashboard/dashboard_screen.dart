import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:nusa_kasir/app.dart';
import 'package:nusa_kasir/core/auth/employee_session.dart';
import 'package:nusa_kasir/core/config/nusa_config.dart';
import 'package:nusa_kasir/core/utils/format_rupiah.dart';
import 'package:nusa_kasir/data/repositories/attendance_repository.dart';
import 'package:nusa_kasir/data/repositories/cashier_session_repository.dart';
import 'package:nusa_kasir/data/repositories/report_repository.dart';
import 'package:nusa_kasir/features/auth/employee_session_provider.dart';
import 'package:nusa_kasir/features/auth/rbac.dart';
import 'package:nusa_kasir/shared/widgets/buka_kasir_sheet.dart';
import 'package:nusa_kasir/shared/widgets/dashboard_header.dart';
import 'package:nusa_kasir/shared/widgets/pin_dialog.dart';
import 'package:nusa_kasir/shared/widgets/profile_stats_card.dart';
import 'package:nusa_kasir/data/repositories/branch_repository.dart';
import 'package:nusa_kasir/data/database/app_database.dart';

// ignore_for_file: use_build_context_synchronously

class DashboardScreen extends ConsumerStatefulWidget {
  const DashboardScreen({super.key});
  @override
  ConsumerState<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends ConsumerState<DashboardScreen> {
  String _storeName = 'NUSA';
  String _omzet = 'Rp 0';
  String _trxCount = '0';
  String _avg = 'Rp 0';
  final String _topProduct = '—';
  List<Branche> _branches = [];
  Branche? _activeBranch;

  // Last cashier session (for display)
  String? _lastCashierName;
  String _lastCashierRole = '';
  String _lastCashierTime = '';
  List<Employee> _employees = [];

  final List<Map<String, String>> _items = const [
    {'id': 'produk', 'label': 'Produk', 'icon': 'product'},
    {'id': 'stok', 'label': 'Stok', 'icon': 'inventory'},
    {'id': 'transaksi', 'label': 'Transaksi', 'icon': 'transaction'},
    {'id': 'pelanggan', 'label': 'Pelanggan', 'icon': 'customer'},
    {'id': 'promo', 'label': 'Promo', 'icon': 'promotion'},
    {'id': 'laporan', 'label': 'Laporan', 'icon': 'finance'},
    {'id': 'presensi', 'label': 'Presensi', 'icon': 'notification'},
    {'id': 'karyawan', 'label': 'Karyawan', 'icon': 'employee'},
    {'id': 'keuangan', 'label': 'Keuangan', 'icon': 'finance'},
    {'id': 'spreadsheet', 'label': 'Spreadsheet', 'icon': 'table'},
    {'id': 'supplier', 'label': 'Supplier', 'icon': 'supplier'},
    {'id': 'pengaturan', 'label': 'Pengaturan', 'icon': 'settings'},
  ];

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    // Try to restore remembered session
    await ref.read(employeeSessionProvider.notifier).restore();
    await _load();
  }

  Future<void> _load() async {
    final name = await ref.read(settingsRepoProvider).getStoreName();
    final branches =
        await BranchRepository(ref.read(databaseProvider)).getAll();
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final reportRepo = ReportRepository(ref.read(databaseProvider));
    final sum = await reportRepo.summary(from: today, to: now);

    // Load employees
    final attRepo = AttendanceRepository(ref.read(databaseProvider));
    final emps = await attRepo.getEmployees();

    // Load last cashier session for display
    final cashierRepo =
        CashierSessionRepository(ref.read(databaseProvider));
    final lastSession = await cashierRepo.getLast();

    String? lastCashierName;
    String lastCashierRole = '';
    String lastCashierTime = '';
    if (lastSession != null) {
      final emp = emps.cast<Employee?>().firstWhere(
            (e) => e!.id == lastSession.employeeId,
            orElse: () => null,
          );
      if (emp != null) {
        lastCashierName = emp.name;
        lastCashierRole = emp.role;
        final t = lastSession.openedAt;
        lastCashierTime =
            '${t.hour.toString().padLeft(2, '0')}:'
            '${t.minute.toString().padLeft(2, '0')}';
      }
    }

    if (mounted) {
      setState(() {
        _storeName = name.isNotEmpty ? name : 'NUSA';
        _branches = branches;
        if (branches.isNotEmpty && _activeBranch == null) {
          _activeBranch = branches.first;
          ref.read(activeBranchProvider.notifier).state = branches.first;
        }
        _omzet = formatRupiah(sum['omzet'] as int);
        _trxCount = '${sum['count']}';
        _avg = formatRupiah(sum['avg'] as int);
        _employees = emps;
        _lastCashierName = lastCashierName;
        _lastCashierRole = lastCashierRole;
        _lastCashierTime = lastCashierTime;
      });
    }
  }

  Future<void> _pickAndLogin() async {
    if (_employees.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('Belum ada karyawan. Tambah di menu Karyawan.')),
      );
      return;
    }

    // Show employee picker
    final emp = await _showEmployeePicker();
    if (emp == null || !mounted) return;

    // Show PIN dialog
    final result = await PinDialog.show(
      context: context,
      employeeName: emp.name,
      employeeRole: emp.role,
      correctPin: emp.pin,
    );

    if (result == null || !result.success || !mounted) return;

    // Login (session only — check-in is for attendance, not cashier)
    final session = EmployeeSession(
      employeeId: emp.id,
      name: emp.name,
      role: emp.role,
      remember: result.remember,
    );
    ref.read(employeeSessionProvider.notifier).login(
          session,
          remember: result.remember,
        );
    ref.read(authProvider.notifier).state = emp.role;

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Halo, ${emp.name}! 👋'),
          backgroundColor: NusaConfig.accentGreen,
          duration: const Duration(seconds: 2),
        ),
      );
    }
  }

  Future<void> _handlePresensiTap() async {
    // Presensi is attendance management — no login gate needed
    await context.push('/presensi');
    if (mounted) {
      await _load();
    }
  }

  Future<void> _handleMenuTap(String route) async {
    final session = ref.read(employeeSessionProvider);

    if (session == null) {
      // No session → login first, then navigate
      await _pickAndLogin();
      if (ref.read(employeeSessionProvider) == null) return;
    }

    // Navigate to target route
    if (route == 'presensi') {
      await context.push('/$route');
      if (mounted) await _load();
    } else {
      context.push('/$route');
    }
  }

  Future<Employee?> _showEmployeePicker() async {
    return showDialog<Employee>(
      context: context,
      builder: (ctx) {
        final isDark = Theme.of(ctx).brightness == Brightness.dark;
        return Dialog(
          insetPadding: const EdgeInsets.symmetric(horizontal: 24),
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20)),
          child: Container(
            width: double.infinity,
            constraints: const BoxConstraints(maxWidth: 400),
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Pilih Karyawan',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Siapa yang mau login?',
                  style: TextStyle(
                    fontSize: 13,
                    color: isDark
                        ? NusaConfig.darkTextSecondary
                        : NusaConfig.textSecondary,
                  ),
                ),
                const SizedBox(height: 16),
                Flexible(
                  child: ListView.separated(
                    shrinkWrap: true,
                    itemCount: _employees.length,
                    separatorBuilder: (_, __) =>
                        const SizedBox(height: 4),
                    itemBuilder: (_, i) {
                      final e = _employees[i];
                      return ListTile(
                        leading: CircleAvatar(
                          backgroundColor:
                              NusaConfig.primaryColor.withValues(alpha: 0.12),
                          child: Text(
                            e.name[0].toUpperCase(),
                            style: TextStyle(
                              fontWeight: FontWeight.w700,
                              color: NusaConfig.primaryColor,
                            ),
                          ),
                        ),
                        title: Text(
                          e.name,
                          style: TextStyle(fontWeight: FontWeight.w600),
                        ),
                        subtitle: Text(e.role,
                            style:
                                const TextStyle(fontSize: 12)),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12)),
                        onTap: () => Navigator.of(ctx).pop(e),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final session = ref.watch(employeeSessionProvider);
    final role = session?.role ?? 'Owner';
    final visible = _items.where((i) => hasAccess(role, i['id']!)).toList();

    // Build card props — show last cashier (from CashierSession)
    String initials, userName, roleText, attendanceText;
    if (_lastCashierName != null) {
      initials = _lastCashierName!.isNotEmpty
          ? _lastCashierName![0].toUpperCase()
          : '?';
      userName = _lastCashierName!;
      roleText = _lastCashierRole;
      attendanceText = 'Kasir terakhir • ${_lastCashierTime}';
    } else {
      initials = '?';
      userName = 'Belum ada sesi kasir';
      roleText = '';
      attendanceText = 'Buka Kasir untuk memulai';
    }

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: SafeArea(
        child: Column(
          children: [
            // Header
            DashboardHeader(
              userName: userName,
              role: roleText,
              branch: _storeName,
              hasNotification: false,
              onBellTap: () {},
            ),

            // Branch selector
            if (_branches.length > 1)
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
                child: Row(
                  children: [
                    GestureDetector(
                      onTap: () => context.push('/cabang'),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.store,
                              size: 16, color: NusaConfig.primaryColor),
                          const SizedBox(width: 6),
                          Text(
                            _activeBranch?.name ?? 'Semua Cabang',
                            style: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: NusaConfig.primaryColor,
                            ),
                          ),
                          const SizedBox(width: 4),
                          const Icon(Icons.keyboard_arrow_down,
                              size: 18, color: NusaConfig.primaryColor),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: Row(
                          children: _branches.map((b) {
                            final active = _activeBranch?.id == b.id;
                            return GestureDetector(
                              onTap: () {
                                setState(() => _activeBranch = b);
                                ref
                                    .read(activeBranchProvider.notifier)
                                    .state = b;
                              },
                              child: Container(
                                margin: const EdgeInsets.only(right: 6),
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 10, vertical: 5),
                                decoration: BoxDecoration(
                                  color: active
                                      ? NusaConfig.primarySoft
                                      : Theme.of(context).colorScheme.surface,
                                  borderRadius: BorderRadius.circular(20),
                                  border: Border.all(
                                    color: active
                                        ? NusaConfig.primaryColor
                                        : NusaConfig.dividerColor,
                                  ),
                                ),
                                child: Text(
                                  b.name,
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w600,
                                    color: active
                                        ? NusaConfig.primaryColor
                                        : NusaConfig.textSecondary,
                                  ),
                                ),
                              ),
                            );
                          }).toList(),
                        ),
                      ),
                    ),
                  ],
                ),
              ),

            // Profile card
            ProfileStatsCard(
              initials: initials,
              userName: userName,
              role: roleText,
              branch: _storeName,
              attendanceStatus: attendanceText,
              salesValue: _omzet,
              transactionCount: _trxCount,
              avgValue: _avg,
              topProduct: _topProduct,
            ),

            const SizedBox(height: 20),

            // Menu grid
            Expanded(
              child: GridView.count(
                crossAxisCount: 3,
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
                crossAxisSpacing: 12,
                mainAxisSpacing: 12,
                childAspectRatio: 0.85,
                children: visible.map((item) {
                  return _MenuItem(
                    label: item['label']!,
                    icon: item['icon']!,
                    onTap: () => _handleMenuTap(item['id']!),
                  );
                }).toList(),
              ),
            ),

            // Buka Kasir CTA
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
              child: _BukaKasirCTA(
                onTap: () async {
                  // Need session first — pick employee + PIN
                  final session = ref.read(employeeSessionProvider);
                  if (session == null) {
                    await _pickAndLogin();
                    if (ref.read(employeeSessionProvider) == null) return;
                  }
                  if (!mounted) return;
                  final s = ref.read(employeeSessionProvider)!;
                  BukaKasirSheet.show(
                    context: context,
                    storeName: _storeName,
                    employeeId: s.employeeId,
                    employeeName: s.name,
                    employeeRole: s.role,
                    onConfirm: (sessionId, saldo) {
                      // Navigate to POS with the cashier session
                      if (mounted) {
                        context.push('/kasir?sessionId=$sessionId');
                      }
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Individual menu item — matches reference: 52×52 red icon bg, label below.
class _MenuItem extends StatelessWidget {
  final String label;
  final String icon;
  final VoidCallback? onTap;

  const _MenuItem({
    required this.label,
    required this.icon,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 8),
        decoration: BoxDecoration(
          color: isDark ? NusaConfig.darkSurface : NusaConfig.surfaceColor,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: isDark ? NusaConfig.darkBorder : NusaConfig.borderColor),
          boxShadow: const [
            BoxShadow(
              color: Color(0x0A111827),
              blurRadius: 2,
              offset: Offset(0, 1),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                  color: NusaConfig.primaryColor,
                ),
                alignment: Alignment.center,
                child: MenuIcon(
                  name: icon,
                  color: Colors.white,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                label,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  color: isDark ? NusaConfig.darkTextPrimary : NusaConfig.textPrimary,
                ),
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
    );
  }
}

/// Menu icon mapping.
class MenuIcon extends StatelessWidget {
  final String name;
  final Color? color;
  const MenuIcon({super.key, required this.name, this.color});

  static const Map<String, IconData> _map = {
    'product': Icons.inventory_2_outlined,
    'inventory': Icons.view_module_outlined,
    'transaction': Icons.receipt_long_outlined,
    'customer': Icons.people_outline,
    'promotion': Icons.local_offer_outlined,
    'finance': Icons.bar_chart_outlined,
    'settings': Icons.settings_outlined,
    'notification': Icons.notifications_outlined,
    'table': Icons.table_chart_outlined,
    'supplier': Icons.local_shipping_outlined,
    'employee': Icons.people_alt_outlined,
  };

  @override
  Widget build(BuildContext context) => Icon(
        _map[name] ?? Icons.circle_outlined,
        size: 26,
        color: color,
      );
}

/// "Buka Kasir" CTA button.
class _BukaKasirCTA extends StatelessWidget {
  final VoidCallback? onTap;
  const _BukaKasirCTA({this.onTap});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: ElevatedButton.icon(
        onPressed: onTap,
        icon: const Icon(Icons.calculate_outlined, size: 20),
        label: const Text('Buka Kasir'),
        style: ElevatedButton.styleFrom(
          backgroundColor: NusaConfig.primaryColor,
          foregroundColor: Colors.white,
          elevation: 6,
          shadowColor: NusaConfig.primaryColor.withValues(alpha: 0.28),
          padding: const EdgeInsets.symmetric(vertical: 16),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          textStyle: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }
}
