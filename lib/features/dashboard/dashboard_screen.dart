import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:nusa_kasir/core/auth/employee_session.dart';
import 'package:nusa_kasir/core/config/nusa_config.dart';
import 'package:nusa_kasir/core/providers.dart';
import 'package:nusa_kasir/core/utils/format_rupiah.dart';
import 'package:nusa_kasir/data/repositories/attendance_repository.dart';
import 'package:nusa_kasir/data/repositories/cashier_session_repository.dart';
import 'package:nusa_kasir/data/repositories/report_repository.dart';
import 'package:nusa_kasir/data/repositories/branch_repository.dart';
import 'package:nusa_kasir/data/database/app_database.dart';
import 'package:nusa_kasir/features/auth/employee_session_provider.dart';
import 'package:nusa_kasir/features/auth/rbac.dart';
import 'package:nusa_kasir/shared/widgets/dashboard_header.dart';
import 'package:nusa_kasir/shared/widgets/pin_dialog.dart';
import 'package:nusa_kasir/shared/widgets/top_toast.dart';
import 'package:nusa_kasir/shared/widgets/profile_stats_card.dart';

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

  // Current session info
  String _currentName = '';
  String _currentRole = '';
  int? _currentEmployeeId;

  // Attendance tracking
  bool _hasCheckedIn = false;
  String _checkInTime = '';

  // Last cashier session
  String? _lastCashierName;
  String _lastCashierRole = '';
  String _lastCashierTime = '';
  List<Employee> _employees = [];

  final List<Map<String, dynamic>> _items = const [
    {'id': 'produk', 'label': 'Produk', 'icon': 'product'},
    {'id': 'stok', 'label': 'Stok', 'icon': 'inventory'},
    {'id': 'transaksi', 'label': 'Transaksi', 'icon': 'transaction'},
    {'id': 'pelanggan', 'label': 'Pelanggan', 'icon': 'customer'},
    {'id': 'promo', 'label': 'Promo', 'icon': 'promotion'},
    {'id': 'pesanan_online', 'label': 'Online', 'icon': 'online'},
    {'id': 'laporan', 'label': 'Laporan', 'icon': 'finance'},
    {'id': 'presensi', 'label': 'Presensi', 'icon': 'notification'},
    {'id': 'karyawan', 'label': 'Karyawan', 'icon': 'employee'},
    {'id': 'keuangan', 'label': 'Keuangan', 'icon': 'finance'},
    {'id': 'spreadsheet', 'label': 'Spreadsheet', 'icon': 'table'},
    {'id': 'supplier', 'label': 'Supplier', 'icon': 'supplier'},
    {'id': 'ai_chat', 'label': 'AI Chat', 'icon': 'ai'},
    {'id': 'pengaturan', 'label': 'Pengaturan', 'icon': 'settings'},
  ];

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    // Restore session
    await ref.read(employeeSessionProvider.notifier).restore();
    final session = ref.read(employeeSessionProvider);
    if (session != null) {
      ref.read(authProvider.notifier).state = session.role;
      _currentName = session.name;
      _currentRole = session.role;
      _currentEmployeeId = session.employeeId;
      // Check attendance for today
      await _checkAttendance(session.employeeId);
    }
    await _load();
  }

  Future<void> _checkAttendance(int employeeId) async {
    try {
      final attRepo = AttendanceRepository(ref.read(databaseProvider));
      final today = await attRepo.getToday(employeeId);
      if (mounted) {
        setState(() {
          _hasCheckedIn = today != null && today.checkIn != null;
          _checkInTime = today?.checkIn ?? '';
        });
      }
    } catch (_) {}
  }

  Future<void> _load() async {
    final name = await ref.read(settingsRepoProvider).getStoreName();
    final branches =
        await BranchRepository(ref.read(databaseProvider)).getAll();
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final reportRepo = ReportRepository(ref.read(databaseProvider));
    final sum = await reportRepo.summary(from: today, to: now);

    final attRepo = AttendanceRepository(ref.read(databaseProvider));
    final emps = await attRepo.getEmployees();

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

    // Check attendance for each employee — who hasn't checked in today?
    // (we'll use this to show badge on employee picker)
    // For now just reload the list

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

  // ── Menu navigation with RBAC guard ────────────────────────────────

  Future<void> _handleMenuTap(String route) async {
    final session = ref.read(employeeSessionProvider);
    final role = session?.role ?? 'Kasir';

    // 1. Login required
    if (session == null) {
      await _pickAndLogin();
      if (ref.read(employeeSessionProvider) == null) return;
    }

    final currentRole = ref.read(employeeSessionProvider)?.role ?? 'Kasir';

    // 2. Owner-only guard
    if (isOwnerOnly(route) && currentRole != 'Owner' && currentRole != 'Manager') {
      _showOwnerOnlyDialog(route);
      return;
    }

    // 3. PIN guard for sensitive menus (kasir)
    if (needsPinGuard(route)) {
      final pinOk = await _requirePinReentry();
      if (!pinOk) return;
    }

    // 4. Attendance check: if not checked in, check in now
    if (!_hasCheckedIn && session != null) {
      final attRepo = AttendanceRepository(ref.read(databaseProvider));
      await attRepo.checkIn(session.employeeId);
      if (mounted) setState(() => _hasCheckedIn = true);
    }

    // Navigate
    if (route == 'presensi') {
      await context.push('/$route');
      if (mounted) await _load();
    } else {
      context.push('/$route');
    }
  }

  /// Show "Hanya owner" dialog with lock icon.
  void _showOwnerOnlyDialog(String route) {
    final label = _items.firstWhere(
      (i) => i['id'] == route,
      orElse: () => {'label': route},
    )['label'] as String;

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Row(
          children: [
            Icon(Icons.lock_rounded, color: NusaConfig.primaryColor, size: 28),
            SizedBox(width: 10),
            Text('Akses Terbatas', style: TextStyle(fontSize: 17)),
          ],
        ),
        content: Text(
          'Menu "$label" hanya bisa diakses oleh Owner/Manager. '
          'Silakan minta Owner untuk login jika perlu mengakses menu ini.',
          style: const TextStyle(fontSize: 14, height: 1.5),
        ),
        actions: [
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: NusaConfig.primaryColor,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Mengerti'),
          ),
        ],
      ),
    );
  }

  /// Force PIN re-entry for sensitive operations.
  Future<bool> _requirePinReentry() async {
    final session = ref.read(employeeSessionProvider);
    if (session == null) return false;

    final emp = _employees.cast<Employee?>().firstWhere(
          (e) => e!.id == session.employeeId,
          orElse: () => null,
        );
    if (emp == null) return false;

    final result = await PinDialog.show(
      context: context,
      employeeName: emp.name,
      employeeRole: emp.role,
      correctPin: emp.pin,
      showRemember: false,
    );

    if (result == null || !result.success) {
      return false;
    }

    // Touch session on successful PIN
    ref.read(employeeSessionProvider.notifier).touch();
    return true;
  }

  // ── Employee Picker + Login ────────────────────────────────────────

  Future<void> _pickAndLogin() async {
    if (_employees.isEmpty) {
      TopToast.info(context, 'Belum ada karyawan. Tambah di menu Karyawan.');
      return;
    }

    // Show employee picker with attendance badges
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

    // Login
    final session = EmployeeSession(
      employeeId: emp.id,
      name: emp.name,
      role: emp.role,
      remember: result.remember,
    );
    ref.read(employeeSessionProvider.notifier).login(session, remember: result.remember);
    ref.read(authProvider.notifier).state = emp.role;

    // Touch session
    ref.read(employeeSessionProvider.notifier).touch();

    // Auto check-in if not yet checked in today
    try {
      final attRepo = AttendanceRepository(ref.read(databaseProvider));
      await attRepo.checkIn(emp.id);
      await _checkAttendance(emp.id);
    } catch (_) {}

    if (mounted) {
      _currentName = emp.name;
      _currentRole = emp.role;
      _currentEmployeeId = emp.id;
      TopToast.success(context, 'Halo, ${emp.name}! 👋');
    }
  }

  // ── Buka Kasir ─────────────────────────────────────────────────────

  Future<void> _bukaKasir() async {
    // Need a logged-in employee session first
    final session = ref.read(employeeSessionProvider);
    if (session == null) {
      await _pickAndLogin();
      if (ref.read(employeeSessionProvider) == null) return;
    }
    if (!mounted) return;

    // PIN re-entry for security
    final pinOk = await _requirePinReentry();
    if (!pinOk) return;
    if (!mounted) return;

    final s = ref.read(employeeSessionProvider)!;

    // Check if there's already an active cashier session
    final cashierRepo = CashierSessionRepository(ref.read(databaseProvider));
    final active = await cashierRepo.getActive();
    if (active != null) {
      if (mounted) {
        TopToast.info(context, 'Kasir masih terbuka. Melanjutkan sesi sebelumnya.');
        context.push('/kasir?sessionId=${active.id}');
      }
      return;
    }

    // Auto check-in if not yet
    if (!_hasCheckedIn) {
      try {
        final attRepo = AttendanceRepository(ref.read(databaseProvider));
        await attRepo.checkIn(s.employeeId);
        setState(() => _hasCheckedIn = true);
      } catch (_) {}
    }

    // Create cashier session with saldo = 0
    try {
      final sessionId = await cashierRepo.open(
        employeeId: s.employeeId,
        startingCash: 0,
      );
      if (mounted) {
        TopToast.success(context, 'Kasir dibuka — Halo, ${s.name}! 👋');
        context.push('/kasir?sessionId=$sessionId');
      }
    } catch (e) {
      if (mounted) {
        TopToast.error(context, 'Gagal membuka kasir: $e');
      }
    }
  }

  Future<void> _handlePresensiTap() async {
    await context.push('/presensi');
    if (mounted) {
      await _load();
    }
  }

  // ── Employee Picker with Attendance Badge ─────────────────────────

  Future<Employee?> _showEmployeePicker() async {
    // Build attendance status map for today
    final attRepo = AttendanceRepository(ref.read(databaseProvider));
    final Map<int, bool> checkedInMap = {};
    for (final e in _employees) {
      final att = await attRepo.getToday(e.id);
      checkedInMap[e.id] = att != null && att.checkIn != null;
    }

    if (!mounted) return null;

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
                      final checkedIn = checkedInMap[e.id] ?? false;
                      return ListTile(
                        leading: CircleAvatar(
                          backgroundColor:
                              NusaConfig.primaryColor.withValues(alpha: 0.12),
                          child: Stack(
                            children: [
                              Center(
                                child: Text(
                                  e.name[0].toUpperCase(),
                                  style: TextStyle(
                                    fontWeight: FontWeight.w700,
                                    color: NusaConfig.primaryColor,
                                  ),
                                ),
                              ),
                              // Attendance reminder badge
                              if (!checkedIn)
                                Positioned(
                                  right: 0,
                                  bottom: 0,
                                  child: Container(
                                    width: 14,
                                    height: 14,
                                    decoration: BoxDecoration(
                                      color: NusaConfig.accentGold,
                                      shape: BoxShape.circle,
                                      border: Border.all(color: Colors.white, width: 1.5),
                                    ),
                                    child: const Icon(
                                      Icons.warning_amber_rounded,
                                      size: 8,
                                      color: Colors.white,
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ),
                        title: Row(
                          children: [
                            Flexible(
                              child: Text(
                                e.name,
                                style: TextStyle(fontWeight: FontWeight.w600),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            if (!checkedIn) ...[
                              const SizedBox(width: 6),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(
                                  color: NusaConfig.accentGold.withValues(alpha: 0.15),
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: const Text(
                                  'Belum absen',
                                  style: TextStyle(
                                    fontSize: 10,
                                    fontWeight: FontWeight.w600,
                                    color: NusaConfig.accentGold,
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ),
                        subtitle: Text(e.role,
                            style: const TextStyle(fontSize: 12)),
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

  // ── Build ──────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final session = ref.watch(employeeSessionProvider);
    final role = session?.role ?? 'Owner';

    // Build menu items with access indicators
    final menuItems = _items.map((item) {
      final id = item['id'] as String;
      final label = item['label'] as String;
      final icon = item['icon'] as String;

      String accessType;
      if (isOwnerOnly(id) && role != 'Owner' && role != 'Manager') {
        accessType = '🔒';
      } else if (needsPinGuard(id)) {
        accessType = '🔐';
      } else if (hasAccess(role, id)) {
        accessType = '✅';
      } else {
        accessType = '🔒';
      }

      return {
        'id': id,
        'label': label,
        'icon': icon,
        'access': accessType,
      };
    }).toList();

    // Build card props
    String initials, userName, roleText, attendanceText;
    if (_currentName.isNotEmpty) {
      initials = _currentName[0].toUpperCase();
      userName = _currentName;
      roleText = _currentRole;
      attendanceText = _hasCheckedIn
          ? 'Hadir • $_checkInTime'
          : '⚠️  Belum absen hari ini — buka kasir untuk absen otomatis';
    } else if (_lastCashierName != null) {
      initials = _lastCashierName!.isNotEmpty
          ? _lastCashierName![0].toUpperCase()
          : '?';
      userName = _lastCashierName!;
      roleText = _lastCashierRole;
      attendanceText = 'Kasir terakhir • $_lastCashierTime';
    } else {
      initials = '?';
      userName = 'Belum ada sesi kasir';
      roleText = '';
      attendanceText = 'Buka Kasir untuk memulai';
    }

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: () async { await _load(); },
          child: SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            child: Column(
              children: [
                // Header
                DashboardHeader(
                  userName: userName,
                  role: roleText,
                  branch: _storeName,
                  hasNotification: !_hasCheckedIn && _currentName.isNotEmpty,
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

                const SizedBox(height: 16),

                // Menu grid with lock indicators
                GridView.count(
                  crossAxisCount: 3,
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
                  crossAxisSpacing: 12,
                  mainAxisSpacing: 12,
                  childAspectRatio: 0.85,
                  children: menuItems.map((item) {
                    return _MenuItem(
                      label: item['label'] as String,
                      icon: item['icon'] as String,
                      access: item['access'] as String,
                      onTap: () => _handleMenuTap(item['id'] as String),
                    );
                  }).toList(),
                ),

                // Buka Kasir CTA
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
                  child: _BukaKasirCTA(
                    onTap: () => _bukaKasir(),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Individual menu item with access indicator.
class _MenuItem extends StatelessWidget {
  final String label;
  final String icon;
  final String access;
  final VoidCallback? onTap;

  const _MenuItem({
    required this.label,
    required this.icon,
    required this.access,
    this.onTap,
  });

  static const _iconColors = {
    'product': NusaConfig.accentGreen,
    'inventory': Color(0xFF6366F1),
    'transaction': Color(0xFF3B82F6),
    'customer': Color(0xFFEC4899),
    'promotion': NusaConfig.accentGold,
    'finance': Color(0xFF14B8A6),
    'settings': Color(0xFF6B7280),
    'notification': NusaConfig.primaryColor,
    'table': NusaConfig.accentGreen,
    'supplier': Color(0xFFF97316),
    'employee': NusaConfig.accentPurple,
    'online': Color(0xFF0EA5E9),
    'ai': Color(0xFFD946EF),
  };

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final isLocked = access == '🔒';
    final iconColor = _iconColors[icon] ?? NusaConfig.primaryColor;

    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 6),
        decoration: BoxDecoration(
          color: isDark ? NusaConfig.darkSurface : NusaConfig.surfaceColor,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isDark ? NusaConfig.darkBorder : NusaConfig.borderColor,
          ),
          boxShadow: [
            BoxShadow(
              color: isDark ? Colors.transparent : Colors.black.withValues(alpha: 0.04),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Icon
            Stack(
              children: [
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(14),
                    color: isLocked
                        ? (isDark ? NusaConfig.darkSurface2 : const Color(0xFFF3F4F6))
                        : iconColor.withValues(alpha: 0.12),
                  ),
                  alignment: Alignment.center,
                  child: MenuIcon(
                    name: icon,
                    color: isLocked
                        ? (isDark ? NusaConfig.darkTextTertiary : NusaConfig.textTertiary)
                        : iconColor,
                  ),
                ),
                // Lock badge
                if (isLocked)
                  Positioned(
                    right: -2,
                    bottom: -2,
                    child: Container(
                      width: 18,
                      height: 18,
                      decoration: BoxDecoration(
                        color: NusaConfig.primaryColor,
                        shape: BoxShape.circle,
                        border: Border.all(color: isDark ? NusaConfig.darkSurface : Colors.white, width: 1.5),
                      ),
                      alignment: Alignment.center,
                      child: const Text('🔒', style: TextStyle(fontSize: 7)),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: isLocked
                    ? (isDark ? NusaConfig.darkTextTertiary : NusaConfig.textTertiary)
                    : (isDark ? NusaConfig.darkTextPrimary : NusaConfig.textPrimary),
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
    'online': Icons.shopping_cart_outlined,
    'ai': Icons.auto_awesome_outlined,
  };

  @override
  Widget build(BuildContext context) => Icon(
        _map[name] ?? Icons.circle_outlined,
        size: 26,
        color: color,
      );
}

/// "Buka Kasir" CTA card — subtle gradient card, not just a flat button.
class _BukaKasirCTA extends StatelessWidget {
  final VoidCallback? onTap;
  const _BukaKasirCTA({this.onTap});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 20),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              NusaConfig.primaryColor,
              NusaConfig.primaryDark,
            ],
          ),
          boxShadow: [
            BoxShadow(
              color: NusaConfig.primaryColor.withValues(alpha: 0.25),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Icon(Icons.calculate_outlined, size: 22, color: Colors.white),
            ),
            const SizedBox(width: 14),
            const Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Buka Kasir',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                  ),
                ),
                Text(
                  'Mulai sesi transaksi',
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.white70,
                  ),
                ),
              ],
            ),
            const Spacer(),
            const Icon(Icons.arrow_forward_ios, size: 16, color: Colors.white70),
          ],
        ),
      ),
    );
  }
}
