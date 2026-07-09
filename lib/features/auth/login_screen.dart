import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:nusa_kasir/app.dart';
import 'package:nusa_kasir/core/config/nusa_config.dart';
import 'package:nusa_kasir/features/auth/rbac.dart';
import 'package:nusa_kasir/shared/widgets/nusa_input.dart';
import 'package:nusa_kasir/shared/widgets/nusa_button.dart';
import 'package:nusa_kasir/shared/widgets/screen_scaffold.dart';

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});
  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _ctrl = TextEditingController();
  String? _error;

  Future<void> _submit() async {
    final pin = _ctrl.text.trim();
    final role = pinToRole[pin];
    if (role == null) {
      setState(() => _error = 'PIN salah');
      return;
    }
    ref.read(authProvider.notifier).state = role;
    final name = await ref.read(settingsRepoProvider).getStoreName();
    if (mounted) context.go(name.isEmpty ? '/onboarding' : '/home');
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ScreenScaffold(
        'Masuk sebagai',
        Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
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
              NusaButton('Masuk', onPressed: _submit),
            ],
          ),
        ),
      );
}
