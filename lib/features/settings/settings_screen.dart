import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:nusa_kasir/app.dart';
import 'package:nusa_kasir/core/config/nusa_config.dart';
import 'package:nusa_kasir/core/utils/secure_storage.dart';
import 'package:nusa_kasir/shared/widgets/nusa_card.dart';
import 'package:nusa_kasir/shared/widgets/nusa_input.dart';
import 'package:nusa_kasir/shared/widgets/nusa_button.dart';
import 'package:nusa_kasir/shared/widgets/screen_scaffold.dart';
import 'package:nusa_kasir/features/settings/backup_sheet.dart';
import 'package:nusa_kasir/features/settings/printer_settings_sheet.dart';
import 'package:nusa_kasir/core/services/update_service.dart';

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});
  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  final _storeCtrl = TextEditingController();
  String? _activationKey;
  String _themeMode = 'system';
  String? _printerName;
  bool _checkingUpdate = false;
  UpdateInfo? _updateInfo;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final repo = ref.read(settingsRepoProvider);
    final name = await repo.getStoreName();
    final key = await SecureStore.getActivation();
    final theme = await repo.getThemeMode();
    final printer = await repo.getPrinterAddress();
    if (mounted) {
      _storeCtrl.text = name;
      _activationKey = key;
      _themeMode = theme ?? 'system';
      _printerName = printer;
      ref.read(themeModeProvider.notifier).state = _themeMode;
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
                        final key = _activationKey ?? '';
                        // Show progress
                        if (mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('Menyiapkan backup...')),
                          );
                        }
                        if (key.isNotEmpty) {
                          await ref.read(activationRepoProvider).uploadBackup(key);
                        }
                        await ref.read(activationRepoProvider).deactivate();
                        if (mounted) context.go('/activation');
                      },
                      child: const Text('Pindah Device'),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              // Theme toggle
              NusaCard(
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Tampilan',
                        style: TextStyle(fontWeight: FontWeight.w600, fontSize: 16)),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        _themeChip('Terang', 'light', Icons.light_mode),
                        const SizedBox(width: 8),
                        _themeChip('Gelap', 'dark', Icons.dark_mode),
                        const SizedBox(width: 8),
                        _themeChip('Sistem', 'system', Icons.phone_android),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              // Printer
              NusaCard(
                InkWell(
                  onTap: () => PrinterSettingsSheet.show(
                    context: context,
                    currentAddress: _printerName,
                    onPrinterSelected: (d) async {
                      await ref
                          .read(settingsRepoProvider)
                          .setPrinterAddress('${d.name}|${d.address}');
                      setState(
                          () => _printerName = '${d.name}|${d.address}');
                    },
                  ),
                  borderRadius: BorderRadius.circular(20),
                  child: const Padding(
                    padding: EdgeInsets.all(14),
                    child: Row(
                      children: [
                        Icon(Icons.print, color: Color(0xFFE63946)),
                        SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('Printer',
                                  style: TextStyle(
                                      fontWeight: FontWeight.w600,
                                      fontSize: 16)),
                            ],
                          ),
                        ),
                        Icon(Icons.chevron_right,
                            color: Color(0xFF6B7280)),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              NusaCard(
                InkWell(
                  onTap: () => showBackupSheet(context, ref),
                  borderRadius: BorderRadius.circular(20),
                  child: const Padding(
                    padding: EdgeInsets.all(14),
                    child: Row(
                      children: [
                        Icon(Icons.backup, color: NusaConfig.primaryColor),
                        SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('Backup & Restore',
                                  style:
                                      TextStyle(fontWeight: FontWeight.w600, fontSize: 16)),
                              SizedBox(height: 4),
                              Text('Simpan atau muat file database',
                                  style: TextStyle(
                                      fontSize: 13, color: NusaConfig.textSecondary)),
                            ],
                          ),
                        ),
                        Icon(Icons.chevron_right, color: NusaConfig.textSecondary),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              // Update check
              NusaCard(
                InkWell(
                  onTap: _updateInfo?.hasUpdate == true
                      ? () => _showUpdateDialog()
                      : _checkUpdate,
                  borderRadius: BorderRadius.circular(20),
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Row(
                      children: [
                        Icon(
                          _updateInfo?.hasUpdate == true
                              ? Icons.system_update
                              : Icons.update,
                          color: _updateInfo?.hasUpdate == true
                              ? Colors.orange
                              : NusaConfig.primaryColor,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                _updateInfo?.hasUpdate == true
                                    ? 'Update Tersedia!'
                                    : 'Cek Update',
                                style: const TextStyle(
                                    fontWeight: FontWeight.w600, fontSize: 16),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                _updateInfo?.hasUpdate == true
                                    ? 'Versi ${_updateInfo!.latestVersion} (build ${_updateInfo!.latestBuildNumber})'
                                    : _checkingUpdate
                                        ? 'Memeriksa...'
                                        : 'v${NusaConfig.appVersion}+${NusaConfig.appBuildNumber}',
                                style: const TextStyle(
                                    fontSize: 13, color: NusaConfig.textSecondary),
                              ),
                            ],
                          ),
                        ),
                        if (_checkingUpdate)
                          const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        else
                          Icon(
                            _updateInfo?.hasUpdate == true
                                ? Icons.download
                                : Icons.refresh,
                            color: NusaConfig.textSecondary,
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      );

  Future<void> _checkUpdate() async {
    setState(() => _checkingUpdate = true);
    final info = await UpdateService.checkForUpdate();
    if (mounted) {
      setState(() {
        _checkingUpdate = false;
        _updateInfo = info;
      });
      if (info.hasUpdate) {
        _showUpdateDialog();
      }
    }
  }

  void _showUpdateDialog() {
    final info = _updateInfo;
    if (info == null || !info.hasUpdate) return;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: Colors.orange.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Icon(Icons.system_update, color: Colors.orange, size: 22),
            ),
            const SizedBox(width: 12),
            const Expanded(
              child: Text('Update Tersedia',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Versi ${info.latestVersion} (build ${info.latestBuildNumber})',
              style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15),
            ),
            const SizedBox(height: 4),
            Text(
              'Saat ini: v${NusaConfig.appVersion}+${NusaConfig.appBuildNumber}',
              style: TextStyle(
                  fontSize: 13,
                  color: isDark
                      ? NusaConfig.darkTextSecondary
                      : NusaConfig.textSecondary),
            ),
            if (info.fileSizeBytes != null && info.fileSizeBytes! > 0) ...[
              const SizedBox(height: 4),
              Text(
                'Ukuran: ${UpdateService.formatSize(info.fileSizeBytes)}',
                style: TextStyle(
                    fontSize: 13,
                    color: isDark
                        ? NusaConfig.darkTextSecondary
                        : NusaConfig.textSecondary),
              ),
            ],
            if (info.changelog != null && info.changelog!.isNotEmpty) ...[
              const SizedBox(height: 12),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: isDark
                      ? NusaConfig.darkSurface2
                      : NusaConfig.backgroundColor,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  info.changelog!,
                  style: TextStyle(
                    fontSize: 13,
                    color: isDark
                        ? NusaConfig.darkTextPrimary
                        : NusaConfig.textPrimary,
                    height: 1.5,
                  ),
                ),
              ),
            ],
            if (info.downloadUrl != null) ...[
              const SizedBox(height: 16),
              Text(
                'Klik "Download" untuk mengunduh APK terbaru dari GitHub. Setelah terunduh, buka file untuk menginstal.',
                style: TextStyle(
                  fontSize: 12,
                  color: isDark
                      ? NusaConfig.darkTextTertiary
                      : NusaConfig.textTertiary,
                  height: 1.4,
                ),
              ),
            ],
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Nanti'),
          ),
          if (info.downloadUrl != null)
            ElevatedButton.icon(
              onPressed: () {
                Navigator.of(ctx).pop();
                _openDownloadUrl(info.downloadUrl!);
              },
              icon: const Icon(Icons.download, size: 18),
              label: const Text('Download'),
              style: ElevatedButton.styleFrom(
                backgroundColor: NusaConfig.primaryColor,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
              ),
            ),
        ],
      ),
    );
  }

  void _openDownloadUrl(String url) {
    // url_launcher is already a dependency
    try {
      launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
    } catch (_) {}
  }

  Widget _themeChip(String label, String mode, IconData icon) {
    final selected = _themeMode == mode;
    return Expanded(
      child: GestureDetector(
        onTap: () async {
          await ref.read(settingsRepoProvider).setThemeMode(mode);
          ref.read(themeModeProvider.notifier).state = mode;
          setState(() => _themeMode = mode);
        },
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(
            color: selected ? NusaConfig.primarySoft : Colors.transparent,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: selected ? NusaConfig.primaryColor : NusaConfig.dividerColor,
            ),
          ),
          child: Column(
            children: [
              Icon(icon,
                  size: 20,
                  color: selected ? NusaConfig.primaryColor : NusaConfig.textSecondary),
              const SizedBox(height: 4),
              Text(label,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: selected ? NusaConfig.primaryColor : NusaConfig.textSecondary,
                  )),
            ],
          ),
        ),
      ),
    );
  }
}
