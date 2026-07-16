import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:nusa_kasir/core/providers.dart';
import 'package:nusa_kasir/core/config/nusa_config.dart';
import 'package:nusa_kasir/core/utils/secure_storage.dart';
import 'package:nusa_kasir/shared/widgets/nusa_card.dart';
import 'package:nusa_kasir/shared/widgets/nusa_input.dart';
import 'package:nusa_kasir/shared/widgets/nusa_button.dart';
import 'package:nusa_kasir/shared/widgets/screen_scaffold.dart';
import 'package:nusa_kasir/features/settings/backup_sheet.dart';
import 'package:nusa_kasir/features/settings/printer_settings_sheet.dart';
import 'package:nusa_kasir/core/services/update_service.dart';
import 'package:nusa_kasir/data/repositories/role_repository.dart';

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
  bool _backingUp = false;

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

  Future<void> _backupNow() async {
    setState(() => _backingUp = true);
    final ok = await ref.read(activationRepoProvider).uploadBackupNow();
    if (mounted) {
      setState(() => _backingUp = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(ok ? 'Backup berhasil disimpan ke cloud' : 'Gagal backup. Periksa koneksi internet.'),
          backgroundColor: ok ? Colors.green.shade700 : Colors.red.shade700,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ),
      );
    }
  }

  Widget _sectionHeader(String title) => Padding(
        padding: const EdgeInsets.only(top: 8, bottom: 8),
        child: Text(
          title,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w700,
            color: NusaConfig.textSecondary,
            letterSpacing: 1.2,
          ),
        ),
      );

  @override
  Widget build(BuildContext context) => ScreenScaffold(
        'Pengaturan',
        SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _sectionHeader('TOKO'),
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
              const SizedBox(height: 12),
              // Toko Online
              NusaCard(
                InkWell(
                  onTap: () => context.push('/toko_online_setup'),
                  borderRadius: BorderRadius.circular(20),
                  child: const Padding(
                    padding: EdgeInsets.all(14),
                    child: Row(
                      children: [
                        Icon(Icons.shopping_bag_outlined, color: Color(0xFFE63946)),
                        SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('Toko Online',
                                  style: TextStyle(fontWeight: FontWeight.w600, fontSize: 16)),
                              SizedBox(height: 4),
                              Text('Aktifkan & atur toko online (Vercel)',
                                  style: TextStyle(fontSize: 13, color: NusaConfig.textSecondary)),
                            ],
                          ),
                        ),
                        Icon(Icons.chevron_right, color: NusaConfig.textSecondary),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              // Pembayaran (QRIS & Transfer)
              NusaCard(
                InkWell(
                  onTap: () => context.push('/pengaturan_pembayaran'),
                  borderRadius: BorderRadius.circular(20),
                  child: const Padding(
                    padding: EdgeInsets.all(14),
                    child: Row(
                      children: [
                        Icon(Icons.payment, color: Color(0xFF6366F1)),
                        SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('Pembayaran',
                                  style: TextStyle(fontWeight: FontWeight.w600, fontSize: 16)),
                              SizedBox(height: 4),
                              Text('Atur QRIS & rekening bank untuk transfer',
                                  style: TextStyle(fontSize: 13, color: NusaConfig.textSecondary)),
                            ],
                          ),
                        ),
                        Icon(Icons.chevron_right, color: NusaConfig.textSecondary),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 24),
              _sectionHeader('SISTEM'),
              NusaCard(
                Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Text('Lisensi',
                        style: TextStyle(fontWeight: FontWeight.w600, fontSize: 16)),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: Text(_activationKey ?? '-',
                              style: const TextStyle(fontFamily: 'monospace', fontSize: 13)),
                        ),
                        InkWell(
                          borderRadius: BorderRadius.circular(8),
                          onTap: _activationKey != null
                              ? () {
                                  Clipboard.setData(
                                      ClipboardData(text: _activationKey!));
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(
                                      content: Text('Kode aktivasi disalin'),
                                      behavior: SnackBarBehavior.floating,
                                      duration: Duration(seconds: 1),
                                    ),
                                  );
                                }
                              : null,
                          child: const Padding(
                            padding: EdgeInsets.all(4),
                            child: Icon(Icons.copy, size: 16, color: NusaConfig.textSecondary),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    const Text('Aktif', style: TextStyle(color: Colors.green)),
                    const SizedBox(height: 12),
                    OutlinedButton.icon(
                      onPressed: _backingUp ? null : _backupNow,
                      icon: _backingUp
                          ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                          : const Icon(Icons.cloud_upload_outlined, size: 18),
                      label: Text(_backingUp ? 'Menyimpan...' : 'Backup ke Cloud'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: NusaConfig.primaryColor,
                        side: BorderSide(color: NusaConfig.primaryColor),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Data otomatis disinkronkan ke cloud dengan akun Google Anda.',
                      style: TextStyle(fontSize: 11, color: NusaConfig.textTertiary.withValues(alpha: 0.8)),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
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
              const SizedBox(height: 12),
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
              const SizedBox(height: 12),
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
              const SizedBox(height: 24),
              _sectionHeader('DATA'),
              // Kelola Role/Jabatan
              NusaCard(
                InkWell(
                  onTap: () => _showManageRoles(),
                  borderRadius: BorderRadius.circular(20),
                  child: const Padding(
                    padding: EdgeInsets.all(14),
                    child: Row(
                      children: [
                        Icon(Icons.admin_panel_settings, color: NusaConfig.accentPurple),
                        SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('Kelola Role & Jabatan',
                                  style:
                                      TextStyle(fontWeight: FontWeight.w600, fontSize: 16)),
                              SizedBox(height: 4),
                              Text('Tambah, edit, atau hapus role karyawan',
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
              const SizedBox(height: 12),
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
              const SizedBox(height: 32),
              // Tentang Aplikasi
              _sectionHeader('TENTANG APLIKASI'),
              NusaCard(
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(Icons.info_outline,
                              size: 20, color: NusaConfig.textSecondary),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text('Nusa Kasir',
                                    style: TextStyle(
                                        fontWeight: FontWeight.w600,
                                        fontSize: 16)),
                                const SizedBox(height: 2),
                                Text(
                                    'Versi ${NusaConfig.appVersion} (build ${NusaConfig.appBuildNumber})',
                                    style: const TextStyle(
                                        fontSize: 13,
                                        color: NusaConfig.textSecondary)),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      const Divider(),
                      const SizedBox(height: 12),
                      const Row(
                        children: [
                          Icon(Icons.person_outline,
                              size: 18, color: NusaConfig.textSecondary),
                          SizedBox(width: 10),
                          Text('Dibuat oleh Halu Goods',
                              style: TextStyle(
                                  fontSize: 14,
                                  color: NusaConfig.textSecondary)),
                        ],
                      ),
                      const SizedBox(height: 16),
                      Row(
                        children: [
                          _aboutLink(
                            context,
                            'Syarat & Ketentuan',
                            'https://halugoods.com/terms',
                          ),
                          const SizedBox(width: 16),
                          _aboutLink(
                            context,
                            'Kebijakan Privasi',
                            'https://halugoods.com/privacy',
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 24),
            ],
          ),
        ),
      );

  Widget _aboutLink(BuildContext context, String label, String url) {
    return GestureDetector(
      onTap: () {
        try {
          launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
        } catch (_) {}
      },
      child: Text(
        label,
        style: TextStyle(
          fontSize: 13,
          color: NusaConfig.primaryColor,
          decoration: TextDecoration.underline,
        ),
      ),
    );
  }

  Future<void> _checkUpdate() async {
    final mountedCheck = mounted;
    if (!mountedCheck) return;

    setState(() => _checkingUpdate = true);
    final info = await UpdateService.checkForUpdate();
    if (mounted) {
      setState(() {
        _checkingUpdate = false;
        _updateInfo = info;
      });
      if (info.hasUpdate) {
        _showUpdateDialog();
      } else if (info.error != null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(info.error!),
              backgroundColor: Colors.orange.shade700,
              behavior: SnackBarBehavior.floating,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              duration: const Duration(seconds: 4),
            ),
          );
        }
      } else if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Aplikasi sudah versi terbaru ✨'),
            backgroundColor: Colors.green.shade700,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            duration: const Duration(seconds: 2),
          ),
        );
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
    } catch (e) {
      // ignore: avoid_print
      print('[Settings] Gagal buka URL: $e');
    }
  }

  // ── Kelola Role / Jabatan ─────────────────────────────────

  Future<void> _showManageRoles() async {
    final roleRepo = RoleRepository();
    final roles = await roleRepo.getRoles();

    if (!mounted) return;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    showDialog(
      context: context,
      builder: (_) => StatefulBuilder(
        builder: (ctx, setSt) {
          return AlertDialog(
            title: const Text('Kelola Role & Jabatan',
                style: TextStyle(fontWeight: FontWeight.w700)),
            content: SizedBox(
              width: double.maxFinite,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // List existing roles
                  ...roles.map((r) {
                    final name = r['name'] as String;
                    final color = Color(r['color'] as int);
                    final isDefault = RoleRepository.defaultRoleNames.contains(name);
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                        decoration: BoxDecoration(
                          color: isDark ? NusaConfig.darkSurface2 : NusaConfig.backgroundColor,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: isDark ? NusaConfig.darkBorder : NusaConfig.borderColor),
                        ),
                        child: Row(
                          children: [
                            Container(
                              width: 32, height: 32,
                              decoration: BoxDecoration(
                                color: color.withOpacity(0.15),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Icon(Icons.badge, size: 18, color: color),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(name,
                                  style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
                            ),
                            if (!isDefault)
                              GestureDetector(
                                onTap: () async {
                                  Navigator.of(ctx).pop();
                                  await _showRoleForm(roleRepo, existing: r);
                                  if (mounted) _showManageRoles();
                                },
                                child: const Padding(
                                  padding: EdgeInsets.all(8),
                                  child: Icon(Icons.edit, size: 18, color: NusaConfig.textSecondary),
                                ),
                              ),
                            if (!isDefault)
                              GestureDetector(
                                onTap: () async {
                                  final confirm = await showDialog<bool>(
                                    context: ctx,
                                    builder: (_) => AlertDialog(
                                      title: const Text('Hapus Role'),
                                      content: Text('Hapus role "$name"? Karyawan dg role ini akan perlu diubah manual.'),
                                      actions: [
                                        TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Batal')),
                                        TextButton(
                                          onPressed: () => Navigator.of(ctx).pop(true),
                                          child: const Text('Hapus', style: TextStyle(color: NusaConfig.primaryColor)),
                                        ),
                                      ],
                                    ),
                                  );
                                  if (confirm == true) {
                                    await roleRepo.deleteRole(name);
                                    if (mounted) {
                                      Navigator.of(ctx).pop();
                                      _showManageRoles();
                                    }
                                  }
                                },
                                child: const Padding(
                                  padding: EdgeInsets.all(8),
                                  child: Icon(Icons.delete_outline, size: 18, color: NusaConfig.primaryColor),
                                ),
                              ),
                          ],
                        ),
                      ),
                    );
                  }),
                ],
              ),
            ),
            actions: [
              TextButton(
                  onPressed: () => Navigator.of(ctx).pop(),
                  child: const Text('Tutup')),
              ElevatedButton.icon(
                onPressed: () async {
                  Navigator.of(ctx).pop();
                  await _showRoleForm(roleRepo);
                  if (mounted) _showManageRoles();
                },
                icon: const Icon(Icons.add, size: 18),
                label: const Text('Tambah Role'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: NusaConfig.primaryColor,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _showRoleForm(RoleRepository roleRepo, {Map<String, dynamic>? existing}) async {
    final isEdit = existing != null;
    final nameCtrl = TextEditingController(text: existing?['name'] as String?);
    var selectedColor = existing != null ? (existing['color'] as int) : 0xFF3B82F6;
    final accessList = <String>[];
    if (existing != null) {
      accessList.addAll((existing['access'] as List).cast<String>());
    }

    final allScreens = [
      'home', 'kasir', 'produk', 'stok', 'transaksi', 'pelanggan',
      'promo', 'laporan', 'presensi', 'karyawan', 'keuangan',
      'pengaturan', 'supplier', 'spreadsheet', 'pesanan_online', 'ai_chat',
    ];

    if (!mounted) return;

    await showDialog(
      context: context,
      builder: (_) => StatefulBuilder(
        builder: (ctx, setSt) => AlertDialog(
          title: Text(isEdit ? 'Edit Role' : 'Tambah Role Baru',
              style: const TextStyle(fontWeight: FontWeight.w700)),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                NusaInput('Nama Role', controller: nameCtrl),
                const SizedBox(height: 12),
                const Text('Warna', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8, runSpacing: 8,
                  children: [0xFFE63946, 0xFF3B82F6, 0xFF10B981, 0xFF8B5CF6, 0xFFF59E0B, 0xFFEC4899, 0xFF6366F1, 0xFF14B8A6]
                      .map((c) => GestureDetector(
                        onTap: () => setSt(() => selectedColor = c),
                        child: Container(
                          width: 36, height: 36,
                          decoration: BoxDecoration(
                            color: Color(c),
                            borderRadius: BorderRadius.circular(10),
                            border: selectedColor == c
                                ? Border.all(color: Colors.black, width: 3)
                                : null,
                          ),
                        ),
                      ))
                      .toList(),
                ),
                const SizedBox(height: 16),
                const Text('Akses Menu',
                    style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                const SizedBox(height: 8),
                ...allScreens.map((s) => CheckboxListTile(
                  title: Text(s, style: const TextStyle(fontSize: 13)),
                  value: accessList.contains(s),
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  visualDensity: VisualDensity.compact,
                  onChanged: (v) {
                    setSt(() {
                      if (v == true) {
                        accessList.add(s);
                      } else {
                        accessList.remove(s);
                      }
                    });
                  },
                )),
              ],
            ),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.of(ctx).pop(),
                child: const Text('Batal')),
            ElevatedButton(
              onPressed: () async {
                final name = nameCtrl.text.trim();
                if (name.isEmpty) return;
                if (isEdit) {
                  await roleRepo.updateRole(
                      existing['name'] as String, name, selectedColor, accessList);
                } else {
                  await roleRepo.addRole(name, selectedColor, accessList);
                }
                if (mounted) Navigator.of(ctx).pop();
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: NusaConfig.primaryColor,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              child: const Text('Simpan'),
            ),
          ],
        ),
      ),
    );
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
