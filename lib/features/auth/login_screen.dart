import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:nusa_kasir/core/auth/employee_session.dart';
import 'package:nusa_kasir/core/config/nusa_config.dart';
import 'package:nusa_kasir/core/providers.dart';
import 'package:nusa_kasir/data/database/app_database.dart';
import 'package:nusa_kasir/data/repositories/attendance_repository.dart';
import 'package:nusa_kasir/features/auth/employee_session_provider.dart';
import 'package:nusa_kasir/shared/widgets/nusa_input.dart';
import 'package:nusa_kasir/shared/widgets/nusa_button.dart';
import 'package:nusa_kasir/shared/widgets/screen_scaffold.dart';

/// POST-SETUP login: user enters their personal PIN to authenticate.
///
/// Queries the local Employees table instead of using a hardcoded map.
class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});
  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _ctrl = TextEditingController();
  String? _error;
  bool _loading = false;
  bool _remember = false;

  Future<void> _submit() async {
    final pin = _ctrl.text.trim();
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

      // Find employee with matching PIN
      final emp = emps.cast<Employee?>().firstWhere(
            (e) => e!.pin == pin,
            orElse: () => null,
          );

      if (emp == null) {
        if (mounted) {
          setState(() {
            _loading = false;
            _error = 'PIN salah';
          });
        }
        return;
      }

      // Create session (only remembered if checkbox is checked)
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
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ScreenScaffold(
        'NUSA',
        Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 32),
              const Text(
                'Masuk sebagai',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                  color: NusaConfig.textPrimary,
                ),
              ),
              const SizedBox(height: 4),
              const Text(
                'Masukkan PIN karyawan kamu',
                style: TextStyle(fontSize: 13, color: NusaConfig.textSecondary),
              ),
              const SizedBox(height: 24),
              NusaInput('PIN',
                  controller: _ctrl,
                  type: TextInputType.number,
                  obscure: true),
              if (_error != null) ...[
                const SizedBox(height: 8),
                Text(_error!,
                    style: const TextStyle(color: NusaConfig.primaryColor)),
              ],
              const SizedBox(height: 16),
              // Remember checkbox
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
                    const Text('Ingat PIN selama 8 jam', style: TextStyle(fontSize: 13, color: NusaConfig.textSecondary)),
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
