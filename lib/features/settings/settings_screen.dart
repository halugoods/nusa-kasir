import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:nusa_kasir/app.dart';
import 'package:nusa_kasir/core/config/nusa_config.dart';
import 'package:nusa_kasir/core/utils/secure_storage.dart';
import 'package:nusa_kasir/shared/widgets/nusa_card.dart';
import 'package:nusa_kasir/shared/widgets/nusa_input.dart';
import 'package:nusa_kasir/shared/widgets/nusa_button.dart';
import 'package:nusa_kasir/shared/widgets/screen_scaffold.dart';

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});
  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  final _storeCtrl = TextEditingController();
  String? _activationKey;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final repo = ref.read(settingsRepoProvider);
    final name = await repo.getStoreName();
    final key = await SecureStore.getActivation();
    if (mounted) {
      _storeCtrl.text = name;
      _activationKey = key;
      setState(() {});
    }
  }

  @override
  void dispose() {
    _storeCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ScreenScaffold(
        'Pengaturan',
        SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              NusaCard(
                Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Text('Informasi Toko',
                        style: TextStyle(fontWeight: FontWeight.w600, fontSize: 16)),
                    const SizedBox(height: 12),
                    NusaInput('Nama toko', controller: _storeCtrl),
                    const SizedBox(height: 12),
                    NusaButton('Simpan', onPressed: () async {
                      await ref
                          .read(settingsRepoProvider)
                          .setStoreName(_storeCtrl.text.trim());
                    }),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              NusaCard(
                Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Text('Lisensi',
                        style: TextStyle(fontWeight: FontWeight.w600, fontSize: 16)),
                    const SizedBox(height: 8),
                    Text(_activationKey ?? '-'),
                    const SizedBox(height: 4),
                    const Text('Aktif', style: TextStyle(color: Colors.green)),
                    const SizedBox(height: 12),
                    OutlinedButton(
                      style: OutlinedButton.styleFrom(
                        foregroundColor: NusaConfig.primaryColor,
                        side: BorderSide(color: NusaConfig.primaryColor),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16)),
                        padding: const EdgeInsets.symmetric(vertical: 16),
                      ),
                      onPressed: () async {
                        await ref.read(activationRepoProvider).deactivate();
                        if (mounted) context.go('/activation');
                      },
                      child: const Text('Pindah Device'),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              const NusaCard(
                Text('NUSA Kasir — Aplikasi Kasir untuk Toko Kelontong, v1.0.0'),
              ),
            ],
          ),
        ),
      );
}
