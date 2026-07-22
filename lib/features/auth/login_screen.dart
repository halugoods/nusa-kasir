import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:nusa_kasir/core/auth/employee_session.dart';
import 'package:nusa_kasir/core/config/nusa_config.dart';
import 'package:nusa_kasir/core/providers.dart';
import 'package:nusa_kasir/data/database/app_database.dart';
import 'package:nusa_kasir/data/repositories/attendance_repository.dart';
import 'package:nusa_kasir/features/auth/employee_session_provider.dart';
import 'package:nusa_kasir/shared/widgets/pin_input.dart';
import 'package:nusa_kasir/shared/widgets/nusa_button.dart';
import 'package:nusa_kasir/shared/widgets/screen_scaffold.dart';
import 'package:nusa_kasir/shared/services/nfc_tag_service.dart';

/// POST-SETUP login: user enters their personal PIN or taps an NFC tag.
///
/// Queries the local Employees table instead of using a hardcoded map.
class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});
  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _pinKey = GlobalKey<PinInputState>();
  String? _error;
  bool _loading = false;
  bool _remember = false;
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

  /// Start NFC scanning for tap-to-login.
  Future<void> _startNfcLogin() async {
    if (_loading) return;

    setState(() {
      _nfcScanning = true;
      _error = null;
    });

    final employeeId = await NfcTagService.readEmployeeTag();

    if (!mounted) return;
    setState(() => _nfcScanning = false);

    if (employeeId == null) {
      // Tag not recognized or user cancelled — silently return to PIN
      return;
    }

    // Perform NFC-based login
    await _loginWithEmployeeId(employeeId);
  }

  Future<void> _loginWithEmployeeId(int employeeId) async {
    setState(() => _loading = true);

    try {
      final db = ref.read(databaseProvider);
      final repo = AttendanceRepository(db);
      final emp = await repo.getEmployee(employeeId);

      if (emp == null) {
        if (mounted) {
          setState(() {
            _loading = false;
            _error = 'Karyawan tidak ditemukan';
          });
        }
        return;
      }

      final session = EmployeeSession(
        employeeId: emp.id,
        name: emp.name,
        role: emp.role,
        remember: _remember,
      );
      ref.read(employeeSessionProvider.notifier).login(session, remember: _remember);
      ref.read(authProvider.notifier).state = emp.role;

      final name = await ref.read(settingsRepoProvider).getStoreName();
      if (mounted) context.go(name.isEmpty ? '/onboarding' : '/home');
    } catch (e) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = 'Terjadi kesalahan';
        });
      }
    }
  }

  Future<void> _submit() async {
    final pin = _pinKey.currentState?.text ?? '';
    if (pin.isEmpty) {
      setState(() => _error = 'Masukkan PIN');
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final db = ref.read(databaseProvider);
      final repo = AttendanceRepository(db);
      final emps = await repo.getEmployees();

      final emp = emps.cast<Employee?>().firstWhere(
            (e) => e!.pin == pin,
            orElse: () => null,
          );

      if (emp == null) {
        if (mounted) {
          _pinKey.currentState?.clear();
          setState(() {
            _loading = false;
            _error = 'PIN salah';
          });
        }
        return;
      }

      final session = EmployeeSession(
        employeeId: emp.id,
        name: emp.name,
        role: emp.role,
        remember: _remember,
      );
      ref.read(employeeSessionProvider.notifier).login(session, remember: _remember);
      ref.read(authProvider.notifier).state = emp.role;

      final name = await ref.read(settingsRepoProvider).getStoreName();
      if (mounted) context.go(name.isEmpty ? '/onboarding' : '/home');
    } catch (e) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = 'Terjadi kesalahan';
        });
      }
    }
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

            // ── PIN Input ───────────────────────────────────────
            if (!_nfcAvailable) const SizedBox(height: 24),
            PinInput(
              key: _pinKey,
              autoSubmit: false,
              error: _error,
              onChanged: () { if (_error != null) setState(() => _error = null); },
            ),
            if (_error != null) ...[
              const SizedBox(height: 8),
              Text(_error!,
                  style: const TextStyle(color: NusaConfig.error, fontWeight: FontWeight.w600)),
            ],
            const SizedBox(height: 16),
            GestureDetector(
              onTap: () => setState(() => _remember = !_remember),
              child: Row(
                children: [
                  SizedBox(
                    width: 22, height: 22,
                    child: Checkbox(
                      value: _remember,
                      onChanged: (v) => setState(() => _remember = v ?? false),
                      activeColor: NusaConfig.primaryColor,
                      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text('Ingat PIN selama 8 jam', style: TextStyle(fontSize: 13, color: isDark ? NusaConfig.darkTextSecondary : NusaConfig.textSecondary)),
                ],
              ),
            ),
            const SizedBox(height: 16),
            NusaButton(_loading ? 'Memeriksa...' : 'Masuk',
                onPressed: _loading ? null : _submit),
          ],
        ),
      ),
    );
  }
}
