import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:local_auth/local_auth.dart';
import 'package:nusa_kasir/core/auth/employee_session.dart';
import 'package:nusa_kasir/core/config/nusa_config.dart';
import 'package:nusa_kasir/core/providers.dart';
import 'package:nusa_kasir/data/database/app_database.dart';
import 'package:nusa_kasir/data/repositories/attendance_repository.dart';
import 'package:nusa_kasir/features/auth/employee_session_provider.dart';
import 'package:nusa_kasir/shared/widgets/pin_dialog.dart';
import 'package:nusa_kasir/shared/widgets/screen_scaffold.dart';
import 'package:nusa_kasir/shared/services/nfc_tag_service.dart';

/// POST-SETUP login: user taps NFC or enters PIN via popup.
class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});
  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  bool _loading = false;
  bool _nfcScanning = false;
  bool _nfcAvailable = false;

  @override
  void initState() {
    super.initState();
    _checkNfc();
  }

  @override
  void dispose() {
    NfcTagService.stopSession();
    super.dispose();
  }

  Future<void> _checkNfc() async {
    final available = await NfcTagService.isAvailable();
    if (mounted) setState(() => _nfcAvailable = available);
  }

  Future<void> _startNfcLogin() async {
    if (_loading) return;
    setState(() { _nfcScanning = true; });
    final employeeId = await NfcTagService.readEmployeeTag();
    if (!mounted) return;
    setState(() => _nfcScanning = false);
    if (employeeId == null) return;
    await _loginWithEmployeeId(employeeId);
  }

  Future<void> _loginWithEmployeeId(int employeeId) async {
    setState(() => _loading = true);
    try {
      final db = ref.read(databaseProvider);
      final repo = AttendanceRepository(db);
      final emp = await repo.getEmployee(employeeId);
      if (emp == null) {
        if (mounted) setState(() => _loading = false);
        return;
      }
      _doLogin(emp);
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _doLogin(Employee emp) async {
    final session = EmployeeSession(
      employeeId: emp.id,
      name: emp.name,
      role: emp.role,
    );
    ref.read(employeeSessionProvider.notifier).login(session);
    ref.read(authProvider.notifier).state = emp.role;
    final name = await ref.read(settingsRepoProvider).getStoreName();
    if (mounted) context.go(name.isEmpty ? '/onboarding' : '/home');
  }

  Future<bool> _authFingerprint() async {
    try {
      final localAuth = LocalAuthentication();
      final authenticated = await localAuth.authenticate(
        localizedReason: 'Verifikasi sidik jari untuk melanjutkan',
        options: const AuthenticationOptions(
          stickyAuth: true,
          biometricOnly: true,
        ),
      );
      return authenticated;
    } catch (_) {
      return false;
    }
  }

  Future<void> _showPinLogin() async {
    Employee? matchedEmp;

    final result = await PinDialog.show(
      context: context,
      title: 'Masuk',
      subtitle: 'Masukkan PIN karyawan kamu',
      pinLength: 6,
      showRemember: true,
      showFingerprint: true,
      showNfc: _nfcAvailable,
      onFingerprint: () async => await _authFingerprint(),
      onNfc: () async {
        final id = await NfcTagService.readEmployeeTag();
        return id?.toString();
      },
      onVerify: (pin) async {
        final db = ref.read(databaseProvider);
        final repo = AttendanceRepository(db);
        final emps = await repo.getEmployees();
        final emp = emps.cast<Employee?>().firstWhere(
              (e) => e!.pin == pin,
              orElse: () => null,
            );
        if (emp == null) return false;
        matchedEmp = emp;
        return true;
      },
    );

    if (result == null || !result.success) return;

    // NFC login — lookup employee by tag id
    if (result.nfcEmployeeId != null) {
      final db = ref.read(databaseProvider);
      final repo = AttendanceRepository(db);
      final emp = await repo.getEmployee(result.nfcEmployeeId!);
      if (emp != null) matchedEmp = emp;
    }

    if (matchedEmp == null) return;
    if (!mounted) return;

    final session = EmployeeSession(
      employeeId: matchedEmp!.id,
      name: matchedEmp!.name,
      role: matchedEmp!.role,
      remember: result.remember,
    );
    ref.read(employeeSessionProvider.notifier).login(session, remember: result.remember);
    ref.read(authProvider.notifier).state = matchedEmp!.role;
    final name = await ref.read(settingsRepoProvider).getStoreName();
    if (mounted) context.go(name.isEmpty ? '/onboarding' : '/home');
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return ScreenScaffold(
      'Masuk',
      Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SizedBox(height: 32),
            Text(
              'Masuk sebagai',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w700,
                color: isDark ? NusaConfig.darkTextPrimary : NusaConfig.textPrimary,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              _nfcAvailable ? 'Tap kartu NFC atau masukkan PIN' : 'Masukkan PIN karyawan kamu',
              style: TextStyle(fontSize: 13, color: isDark ? NusaConfig.darkTextSecondary : NusaConfig.textSecondary),
            ),

            // ── NFC Tap Area ────────────────────────────────────
            if (_nfcAvailable) ...[
              const SizedBox(height: 20),
              GestureDetector(
                onTap: _nfcScanning ? null : _startNfcLogin,
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 300),
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: _nfcScanning
                          ? NusaConfig.accentPurple
                          : isDark
                              ? NusaConfig.darkBorder
                              : NusaConfig.borderColor,
                      width: _nfcScanning ? 2 : 1,
                    ),
                    color: isDark ? NusaConfig.darkSurface : NusaConfig.surfaceColor,
                  ),
                  child: Column(
                    children: [
                      _nfcScanning
                          ? SizedBox(
                              width: 48,
                              height: 48,
                              child: CircularProgressIndicator(
                                strokeWidth: 3,
                                color: NusaConfig.accentPurple,
                              ),
                            )
                          : Container(
                              width: 48,
                              height: 48,
                              decoration: BoxDecoration(
                                color: NusaConfig.accentPurple.withValues(alpha: 0.12),
                                borderRadius: BorderRadius.circular(14),
                              ),
                              alignment: Alignment.center,
                              child: const Icon(
                                Icons.nfc,
                                size: 28,
                                color: NusaConfig.accentPurple,
                              ),
                            ),
                      const SizedBox(height: 8),
                      Text(
                        _nfcScanning ? 'Mendeteksi...' : 'Tempelkan Kartu NFC',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: _nfcScanning
                              ? NusaConfig.accentPurple
                              : isDark
                                  ? NusaConfig.darkTextPrimary
                                  : NusaConfig.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        _nfcScanning ? 'Dekatkan kartu ke belakang HP' : 'Login cepat tanpa PIN',
                        style: TextStyle(
                          fontSize: 12,
                          color: isDark ? NusaConfig.darkTextSecondary : NusaConfig.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: Container(
                      height: 1,
                      color: isDark ? NusaConfig.darkDivider : NusaConfig.dividerColor,
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    child: Text(
                      'atau',
                      style: TextStyle(
                        fontSize: 12,
                        color: isDark ? NusaConfig.darkTextSecondary : NusaConfig.textSecondary,
                      ),
                    ),
                  ),
                  Expanded(
                    child: Container(
                      height: 1,
                      color: isDark ? NusaConfig.darkDivider : NusaConfig.dividerColor,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
            ],

            // ── PIN Button ──────────────────────────────────────
            const SizedBox(height: 24),
            SizedBox(
              height: 52,
              child: ElevatedButton(
                onPressed: _loading ? null : _showPinLogin,
                style: ElevatedButton.styleFrom(
                  backgroundColor: NusaConfig.primaryColor,
                  foregroundColor: Colors.white,
                  elevation: 2,
                  shadowColor: NusaConfig.primaryColor.withValues(alpha: 0.3),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.lock_outline, size: 20),
                    const SizedBox(width: 10),
                    Text(
                      _loading ? 'Memeriksa...' : 'Masuk dengan PIN',
                      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
