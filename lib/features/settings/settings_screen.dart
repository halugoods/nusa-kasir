import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:file_picker/file_picker.dart';
import 'package:nusa_kasir/core/providers.dart';
import 'package:nusa_kasir/core/config/nusa_config.dart';
import 'package:nusa_kasir/core/utils/secure_storage.dart';
import 'package:nusa_kasir/shared/widgets/nusa_card.dart';
import 'package:nusa_kasir/shared/widgets/nusa_input.dart';
import 'package:nusa_kasir/shared/widgets/nusa_button.dart';
import 'package:nusa_kasir/shared/widgets/screen_scaffold.dart';
import 'package:nusa_kasir/shared/widgets/top_toast.dart';
import 'package:nusa_kasir/shared/widgets/pin_input.dart';
import 'package:nusa_kasir/features/settings/backup_sheet.dart';
import 'package:nusa_kasir/features/settings/printer_settings_sheet.dart';
import 'package:nusa_kasir/core/services/update_service.dart';
import 'package:nusa_kasir/data/repositories/role_repository.dart';
import 'package:nusa_kasir/data/repositories/attendance_repository.dart';
import 'package:nusa_kasir/data/database/app_database.dart';
import 'package:nusa_kasir/features/auth/employee_session_provider.dart';
import 'package:nusa_kasir/core/auth/employee_session.dart';
import 'package:nusa_kasir/shared/services/biometric_service.dart';

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

  // Fingerprint
  bool _fingerprintEnabled = false;

  // Feature toggles — all true by default
  Map<String, bool> _featureToggles = {};
  static const _featureToggleKey = 'nusa_feature_toggles';

  static const _allFeatures = [
    'produk', 'stok', 'transaksi', 'pelanggan', 'promo',
    'pesanan_online', 'laporan', 'presensi', 'karyawan',
    'keuangan', 'spreadsheet', 'supplier', 'cabang', 'ai_chat', 'pengaturan',
  ];

  static const _featureLabels = {
    'produk': 'Produk', 'stok': 'Stok', 'transaksi': 'Transaksi',
    'pelanggan': 'Pelanggan', 'promo': 'Promo', 'pesanan_online': 'Pesanan Online',
    'laporan': 'Laporan', 'presensi': 'Presensi', 'karyawan': 'Karyawan',
    'keuangan': 'Keuangan', 'spreadsheet': 'Spreadsheet', 'supplier': 'Supplier',
    'cabang': 'Cabang', 'ai_chat': 'AI Chat', 'pengaturan': 'Pengaturan',
  };

  static const _featureIcons = {
    'produk': Icons.inventory_2_outlined, 'stok': Icons.view_module_outlined,
    'transaksi': Icons.receipt_long_outlined, 'pelanggan': Icons.person_outline,
    'promo': Icons.discount_outlined, 'pesanan_online': Icons.shopping_cart_outlined,
    'laporan': Icons.paid_outlined, 'presensi': Icons.fingerprint,
    'karyawan': Icons.people_outline, 'keuangan': Icons.account_balance_wallet_outlined,
    'spreadsheet': Icons.table_chart_outlined, 'supplier': Icons.local_shipping_outlined,
    'cabang': Icons.storefront_outlined, 'ai_chat': Icons.smart_toy_outlined,
    'pengaturan': Icons.settings_outlined,
  };

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

    // Load feature toggles
    final raw = await SecureStore.getFeatureToggles();
    Map<String, bool> toggles = {};
    if (raw != null && raw.isNotEmpty) {
      try {
        final decoded = jsonDecode(raw) as Map<String, dynamic>;
        for (final e in decoded.entries) {
          toggles[e.key] = e.value == true;
        }
      } catch (_) {}
    }
    // Fill in missing features as enabled
    for (final f in _allFeatures) {
      toggles.putIfAbsent(f, () => true);
    }

    if (mounted) {
      _storeCtrl.text = name;
      _activationKey = key;
      _themeMode = theme ?? 'system';
      _printerName = printer;
      _featureToggles = toggles;
      ref.read(themeModeProvider.notifier).state = _themeMode;
      // Sync feature toggles to provider (used by dashboard)
      ref.read(featureTogglesProvider.notifier).state = Map.from(toggles);

      // Load fingerprint state
      _fingerprintEnabled = await BiometricService.isEnabled();

      setState(() {});
    }
  }

  Future<void> _saveFeatureToggles() async {
    final json = jsonEncode(_featureToggles);
    await SecureStore.saveFeatureToggles(json);
    ref.read(featureTogglesProvider.notifier).state = Map.from(_featureToggles);
  }

  @override
  void dispose() {
    _storeCtrl.dispose();
    super.dispose();
  }

  // ── PIN Gate ──────────────────────────────────────────────

  Future<bool> _checkPin() async {
    final session = ref.read(employeeSessionProvider);
    if (session != null) {
      return await _showPinDialog(session.employeeId, session.name);
    }
    // No session — ask for Owner PIN
    final repo = AttendanceRepository(ref.read(databaseProvider));
    final all = await repo.getEmployees();
    final ownerList = all.where((e) => e.role == 'Owner').toList();
    if (ownerList.isEmpty) return true;
    return await _showPinDialog(ownerList.first.id, ownerList.first.name);
  }

  Future<bool> _showPinDialog(int employeeId, String name) async {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final pinKey = GlobalKey<PinInputState>();
    String? error;
    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSt) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
          titlePadding: const EdgeInsets.fromLTRB(24, 24, 24, 0),
          contentPadding: const EdgeInsets.fromLTRB(24, 16, 24, 8),
          actionsPadding: const EdgeInsets.fromLTRB(24, 0, 24, 20),
          title: Column(children: [
            Container(
              width: 56, height: 56,
              decoration: BoxDecoration(
                color: NusaConfig.primaryColor.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(16),
              ),
              child: const Icon(Icons.lock_outline, color: NusaConfig.primaryColor, size: 28),
            ),
            const SizedBox(height: 16),
            const Text('Verifikasi PIN', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
            const SizedBox(height: 6),
            Text('Masukkan PIN $name untuk mengakses pengaturan keamanan',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 13,
                    color: isDark ? NusaConfig.darkTextSecondary : NusaConfig.textSecondary)),
          ]),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            PinInput(
              key: pinKey,
              autoSubmit: false,
              error: error,
              onChanged: () { if (error != null) setSt(() => error = null); },
            ),
            if (error != null) ...[
              const SizedBox(height: 12),
              Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                const Icon(Icons.error_outline, size: 14, color: NusaConfig.primaryColor),
                const SizedBox(width: 6),
                Text(error!, style: const TextStyle(fontSize: 12, color: NusaConfig.primaryColor, fontWeight: FontWeight.w600)),
              ]),
            ],
          ]),
          actions: [
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () async {
                  final pin = pinKey.currentState?.text ?? '';
                  if (pin.length < 4) {
                    setSt(() => error = 'PIN minimal 4 digit');
                    return;
                  }
                  final repo = AttendanceRepository(ref.read(databaseProvider));
                  final all = await repo.getEmployees();
                  final emp = all.where((e) => e.id == employeeId).firstOrNull;
                  if (emp != null && emp.pin == pin) {
                    if (ctx.mounted) Navigator.pop(ctx, true);
                  } else {
                    pinKey.currentState?.clear();
                    setSt(() => error = 'PIN salah — coba lagi');
                  }
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: NusaConfig.primaryColor,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  elevation: 0,
                ),
                child: const Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                  Icon(Icons.lock_open, size: 20),
                  SizedBox(width: 8),
                  Text('Verifikasi', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                ]),
              ),
            ),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton(
                onPressed: () => Navigator.pop(ctx, false),
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  side: BorderSide(color: isDark ? NusaConfig.darkBorder : NusaConfig.dividerColor),
                ),
                child: Text('Batal', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600,
                    color: isDark ? NusaConfig.darkTextSecondary : NusaConfig.textSecondary)),
              ),
            ),
          ],
        ),
      ),
    );
    return result == true;
  }

  Future<void> _pinGate(VoidCallback action) async {
    if (await _checkPin()) {
      action();
    } else {
      TopToast.error(context, 'PIN salah — akses ditolak');
    }
  }

  /// Toggle fingerprint login for Owner. Requires PIN verification first.
  Future<void> _toggleFingerprint(bool isDark, EmployeeSession session) async {
    // Only Owner
    if (session.role != 'Owner') {
      TopToast.info(context, 'Hanya Owner yang bisa mengatur fingerprint');
      return;
    }

    // Verify PIN before toggling
    final ok = await _showPinDialog(session.employeeId, session.name);
    if (!ok) {
      TopToast.error(context, 'Verifikasi PIN gagal');
      return;
    }

    final newVal = !_fingerprintEnabled;

    if (newVal) {
      // Check hardware availability
      final hwOk = await BiometricService.isHardwareAvailable();
      if (!hwOk) {
        if (mounted) {
          TopToast.error(context, 'Device tidak mendukung fingerprint');
        }
        return;
      }

      await BiometricService.enable();
    } else {
      await BiometricService.disable();
    }

    if (mounted) {
      setState(() => _fingerprintEnabled = newVal);
      TopToast.success(context, newVal ? 'Fingerprint diaktifkan' : 'Fingerprint dinonaktifkan');
    }
  }

  // ── Backups ───────────────────────────────────────────────

  Future<void> _backupNow() async {
    setState(() => _backingUp = true);
    final ok = await ref.read(activationRepoProvider).uploadBackupNow();
    if (mounted) {
      setState(() => _backingUp = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(ok ? 'Backup berhasil disimpan ke cloud' : 'Gagal backup. Periksa koneksi internet.'),
        backgroundColor: ok ? Colors.green.shade700 : Colors.red.shade700,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ));
    }
  }

  // ── Section Header ────────────────────────────────────────

  Widget _sectionHeader(String title, bool isDark) => Padding(
    padding: const EdgeInsets.only(top: 8, bottom: 8),
    child: Text(title, style: TextStyle(
      fontSize: 12, fontWeight: FontWeight.w700,
      color: isDark ? NusaConfig.darkTextSecondary : NusaConfig.textSecondary,
      letterSpacing: 1.2,
    )),
  );

  // ── Menu Row (reusable) ───────────────────────────────────

  Widget _menuRow({
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
    Color? iconColor,
    bool isDark = false,
    Widget? trailing,
  }) => NusaCard(
    InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(children: [
          Icon(icon, color: iconColor ?? NusaConfig.primaryColor),
          const SizedBox(width: 12),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 16)),
            const SizedBox(height: 4),
            Text(subtitle, style: TextStyle(fontSize: 13,
                color: isDark ? NusaConfig.darkTextSecondary : NusaConfig.textSecondary)),
          ])),
          if (trailing != null) trailing else
            Icon(Icons.chevron_right, color: isDark ? NusaConfig.darkTextSecondary : NusaConfig.textSecondary),
        ]),
      ),
    ),
  );

  // ── Theme Chip ────────────────────────────────────────────

  Widget _themeChip(String label, String mode, IconData icon, bool isDark) {
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
            border: Border.all(color: selected ? NusaConfig.primaryColor : NusaConfig.dividerColor),
          ),
          child: Column(children: [
            Icon(icon, size: 20,
                color: selected ? NusaConfig.primaryColor
                    : isDark ? NusaConfig.darkTextSecondary : NusaConfig.textSecondary),
            const SizedBox(height: 4),
            Text(label, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600,
                color: selected ? NusaConfig.primaryColor
                    : isDark ? NusaConfig.darkTextSecondary : NusaConfig.textSecondary)),
          ]),
        ),
      ),
    );
  }

  // ── Feature Toggles Bottom Sheet ──────────────────────────

  void _showFeatureToggles() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSt) => Container(
          decoration: BoxDecoration(
            color: isDark ? NusaConfig.darkSurface : NusaConfig.surfaceColor,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          ),
          padding: const EdgeInsets.fromLTRB(20, 10, 20, 20),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            // Drag handle
            Container(
              margin: const EdgeInsets.symmetric(vertical: 8),
              width: 40, height: 4,
              decoration: BoxDecoration(
                color: isDark ? NusaConfig.darkDivider : NusaConfig.dividerColor,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            // Title
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Row(children: [
                Container(
                  width: 38, height: 38,
                  decoration: BoxDecoration(
                    color: NusaConfig.primaryColor.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(Icons.toggle_on_outlined, color: NusaConfig.primaryColor, size: 20),
                ),
                const SizedBox(width: 12),
                const Expanded(child: Text('Kelola Fitur',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700))),
              ]),
            ),
            const SizedBox(height: 4),
            Text('Matikan fitur yang tidak ingin ditampilkan di Home Screen. '
                'Fitur yang dimatikan juga tidak bisa diakses oleh karyawan.',
                style: TextStyle(fontSize: 12,
                    color: isDark ? NusaConfig.darkTextTertiary : NusaConfig.textTertiary)),
            const SizedBox(height: 12),
            Flexible(
              child: ListView(
                shrinkWrap: true,
                children: _allFeatures.map((id) {
                  final enabled = _featureToggles[id] ?? true;
                  return SwitchListTile(
                    dense: true,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 4),
                    secondary: Container(
                      width: 36, height: 36,
                      decoration: BoxDecoration(
                        color: enabled
                            ? NusaConfig.primaryColor.withValues(alpha: 0.12)
                            : (isDark ? NusaConfig.darkSurface2 : NusaConfig.backgroundColor),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Icon(
                        (_featureIcons[id] ?? Icons.circle),
                        size: 18,
                        color: enabled ? NusaConfig.primaryColor
                            : isDark ? NusaConfig.darkTextTertiary : NusaConfig.textTertiary,
                      ),
                    ),
                    title: Text(_featureLabels[id] ?? id,
                        style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600,
                            color: enabled
                                ? (isDark ? NusaConfig.darkTextPrimary : NusaConfig.textPrimary)
                                : (isDark ? NusaConfig.darkTextTertiary : NusaConfig.textTertiary))),
                    value: enabled,
                    activeColor: NusaConfig.primaryColor,
                    onChanged: (v) {
                      setSt(() {
                        _featureToggles[id] = v ?? true;
                        setState(() {}); // sync parent
                      });
                      _saveFeatureToggles();
                    },
                  );
                }).toList(),
              ),
            ),
          ]),
        ),
      ),
    );
  }

  // ── License Detail Bottom Sheet ───────────────────────────

  void _showLicense() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        decoration: BoxDecoration(
          color: isDark ? NusaConfig.darkSurface : NusaConfig.surfaceColor,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        ),
        padding: const EdgeInsets.fromLTRB(20, 10, 20, 20),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Container(
            margin: const EdgeInsets.symmetric(vertical: 8),
            width: 40, height: 4,
            decoration: BoxDecoration(
              color: isDark ? NusaConfig.darkDivider : NusaConfig.dividerColor,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 8),
          Row(children: [
            Container(
              width: 38, height: 38,
              decoration: BoxDecoration(
                color: NusaConfig.accentGreen.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(Icons.key, color: NusaConfig.accentGreen, size: 20),
            ),
            const SizedBox(width: 12),
            const Text('Lisensi', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
          ]),
          const SizedBox(height: 16),

          // Activation key
          const Text('Kode Aktivasi', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
          const SizedBox(height: 6),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: isDark ? NusaConfig.darkSurface2 : NusaConfig.backgroundColor,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: isDark ? NusaConfig.darkBorder : NusaConfig.borderColor),
            ),
            child: Row(children: [
              Expanded(child: Text(_activationKey ?? '-',
                  style: const TextStyle(fontFamily: 'monospace', fontSize: 14))),
              if (_activationKey != null)
                GestureDetector(
                  onTap: () {
                    Clipboard.setData(ClipboardData(text: _activationKey!));
                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                      content: Text('Kode aktivasi disalin'),
                      behavior: SnackBarBehavior.floating,
                      duration: Duration(seconds: 1),
                    ));
                  },
                  child: Icon(Icons.copy, size: 18,
                      color: isDark ? NusaConfig.darkTextSecondary : NusaConfig.textSecondary),
                ),
            ]),
          ),
          const SizedBox(height: 8),
          Row(children: [
            Icon(Icons.check_circle, size: 14, color: NusaConfig.accentGreen),
            const SizedBox(width: 6),
            const Text('Status: Aktif', style: TextStyle(fontSize: 13, color: NusaConfig.accentGreen, fontWeight: FontWeight.w600)),
          ]),
          const SizedBox(height: 16),

          // Backup button
          OutlinedButton.icon(
            onPressed: _backingUp ? null : () { Navigator.pop(ctx); _backupNow(); },
            icon: _backingUp
                ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.cloud_upload_outlined, size: 18),
            label: Text(_backingUp ? 'Menyimpan...' : 'Backup ke Cloud'),
            style: OutlinedButton.styleFrom(
              foregroundColor: NusaConfig.primaryColor,
              side: const BorderSide(color: NusaConfig.primaryColor),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              padding: const EdgeInsets.symmetric(vertical: 14),
            ),
          ),
          const SizedBox(height: 6),
          Text('Data otomatis disinkronkan ke cloud dengan akun Google Anda.',
              style: TextStyle(fontSize: 11,
                  color: (isDark ? NusaConfig.darkTextTertiary : NusaConfig.textTertiary).withValues(alpha: 0.8))),
          const SizedBox(height: 16),
        ]),
      ),
    );
  }

  // ── Update Check ──────────────────────────────────────────

  Future<void> _checkUpdate() async {
    setState(() => _checkingUpdate = true);
    final info = await UpdateService.checkForUpdate();
    if (mounted) {
      setState(() { _checkingUpdate = false; _updateInfo = info; });
      if (info.hasUpdate) {
        _showUpdateDialog();
      } else if (info.error != null) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(info.error!),
          backgroundColor: Colors.orange.shade700,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          duration: const Duration(seconds: 4),
        ));
      } else {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: const Text('Aplikasi sudah versi terbaru ✨'),
          backgroundColor: Colors.green.shade700,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          duration: const Duration(seconds: 2),
        ));
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
        title: Row(children: [
          Container(width: 40, height: 40,
            decoration: BoxDecoration(color: Colors.orange.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(12)),
            child: const Icon(Icons.system_update, color: Colors.orange, size: 22),
          ),
          const SizedBox(width: 12),
          const Expanded(child: Text('Update Tersedia', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700))),
        ]),
        content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Versi ${info.latestVersion} (build ${info.latestBuildNumber})',
              style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15)),
          const SizedBox(height: 4),
          Text('Saat ini: v${NusaConfig.appVersion}+${NusaConfig.appBuildNumber}',
              style: TextStyle(fontSize: 13, color: isDark ? NusaConfig.darkTextSecondary : NusaConfig.textSecondary)),
          if (info.fileSizeBytes != null && info.fileSizeBytes! > 0) ...[
            const SizedBox(height: 4),
            Text('Ukuran: ${UpdateService.formatSize(info.fileSizeBytes)}',
                style: TextStyle(fontSize: 13, color: isDark ? NusaConfig.darkTextSecondary : NusaConfig.textSecondary)),
          ],
          if (info.changelog != null && info.changelog!.isNotEmpty) ...[
            const SizedBox(height: 12),
            Container(width: double.infinity, padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: isDark ? NusaConfig.darkSurface2 : NusaConfig.backgroundColor,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(info.changelog!, style: TextStyle(fontSize: 13,
                  color: isDark ? NusaConfig.darkTextPrimary : NusaConfig.textPrimary, height: 1.5)),
            ),
          ],
          if (info.downloadUrl != null) ...[
            const SizedBox(height: 16),
            Text('Klik Download untuk mengunduh APK terbaru dari GitHub.',
                style: TextStyle(fontSize: 12, color: isDark ? NusaConfig.darkTextTertiary : NusaConfig.textTertiary, height: 1.4)),
          ],
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('Nanti')),
          if (info.downloadUrl != null)
            ElevatedButton.icon(
              onPressed: () { Navigator.of(ctx).pop(); _openDownloadUrl(info.downloadUrl!); },
              icon: const Icon(Icons.download, size: 18),
              label: const Text('Download'),
              style: ElevatedButton.styleFrom(
                backgroundColor: NusaConfig.primaryColor, foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
        ],
      ),
    );
  }

  void _openDownloadUrl(String url) {
    try {
      launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
    } catch (e) {
      debugPrint('[Settings] Gagal buka URL: $e');
    }
  }

  // ── Receipt Settings ──────────────────────────────────────

  Future<void> _showReceiptSettings() async {
    final repo = ref.read(settingsRepoProvider);
    final headerCtrl = TextEditingController(text: await repo.getReceiptHeader() ?? '');
    final footerCtrl = TextEditingController(text: await repo.getReceiptFooter() ?? '');
    final currentLogo = await repo.getStoreLogoPath();
    String paperSize = await repo.getReceiptPaperSize();
    final toggles = await repo.getReceiptToggles();
    final storeName = await repo.getStoreName();
    if (!mounted) return;

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (ctx) {
        final setDark = Theme.of(ctx).brightness == Brightness.dark;
        // State variables declared OUTSIDE StatefulBuilder so they persist across rebuilds
        String? logoPath = currentLogo;
        String headerText = headerCtrl.text;
        String paper = paperSize;
        Map<String, bool> togs = Map.from(toggles);
        return StatefulBuilder(
          builder: (ctx, setSt) {
            return Container(
              decoration: BoxDecoration(
                color: setDark ? NusaConfig.darkSurface : NusaConfig.surfaceColor,
                borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
              ),
              padding: EdgeInsets.only(left: 24, right: 24, top: 16,
                  bottom: MediaQuery.of(ctx).viewInsets.bottom + 40),
              child: SingleChildScrollView(
                child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Container(margin: const EdgeInsets.symmetric(vertical: 8), width: 40, height: 4,
                  decoration: BoxDecoration(color: setDark ? NusaConfig.darkDivider : NusaConfig.dividerColor,
                      borderRadius: BorderRadius.circular(2))),
                const SizedBox(height: 12),

                // Title
                Row(children: [
                  Container(
                    width: 38, height: 38,
                    decoration: BoxDecoration(
                      color: const Color(0xFF10B981).withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(Icons.receipt_long, color: Color(0xFF10B981), size: 20),
                  ),
                  const SizedBox(width: 12),
                  Text('Pengaturan Struk', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700,
                      color: setDark ? NusaConfig.darkTextPrimary : NusaConfig.textPrimary)),
                ]),
                const SizedBox(height: 20),

                // ── Ukuran Kertas ──
                Text('Ukuran Kertas', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14,
                    color: setDark ? NusaConfig.darkTextPrimary : NusaConfig.textPrimary)),
                const SizedBox(height: 8),
                Row(children: [
                  _paperChip('58mm', paper, setDark, onTap: () => setSt(() => paper = '58mm')),
                  const SizedBox(width: 10),
                  _paperChip('80mm', paper, setDark, onTap: () => setSt(() => paper = '80mm')),
                ]),
                const SizedBox(height: 20),

                // ── Logo Toko ──
                Text('Logo Toko', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14,
                    color: setDark ? NusaConfig.darkTextPrimary : NusaConfig.textPrimary)),
                const SizedBox(height: 8),
                if (logoPath != null && logoPath!.isNotEmpty)
                  Padding(padding: const EdgeInsets.only(bottom: 8),
                    child: ClipRRect(borderRadius: BorderRadius.circular(12),
                      child: Image.file(File(logoPath!), height: 80, fit: BoxFit.contain))),
                OutlinedButton.icon(
                  onPressed: () async {
                    final result = await FilePicker.pickFiles(type: FileType.image);
                    if (result != null && result.files.single.path != null) {
                      final path = result.files.single.path!;
                      await repo.setStoreLogoPath(path);
                      setSt(() => logoPath = path);
                    }
                  },
                  icon: const Icon(Icons.image_outlined, size: 18),
                  label: Text(logoPath != null && logoPath!.isNotEmpty ? 'Ganti Logo' : 'Pilih Logo'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: NusaConfig.primaryColor,
                    side: const BorderSide(color: NusaConfig.primaryColor),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                ),
                if (logoPath != null && logoPath!.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  TextButton(
                    onPressed: () async { await repo.setStoreLogoPath(''); setSt(() => logoPath = null); },
                    child: const Text('Hapus Logo', style: TextStyle(color: NusaConfig.primaryColor)),
                  ),
                ],
                const SizedBox(height: 20),

                // ── Header Struk ──
                Text('Header Struk', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14,
                    color: setDark ? NusaConfig.darkTextPrimary : NusaConfig.textPrimary)),
                const SizedBox(height: 8),
                NusaInput('Header', controller: headerCtrl, hint: 'Cth: NUSA MART - Cabang Pusat'),
                const SizedBox(height: 20),

                // ── Footer Struk ──
                Text('Footer Struk', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14,
                    color: setDark ? NusaConfig.darkTextPrimary : NusaConfig.textPrimary)),
                const SizedBox(height: 8),
                Container(
                  decoration: BoxDecoration(
                    color: setDark ? NusaConfig.darkInputFill : NusaConfig.inputFill,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: setDark ? NusaConfig.darkInputBorder : NusaConfig.inputBorder),
                  ),
                  child: TextField(
                    controller: footerCtrl, maxLines: 3,
                    style: TextStyle(color: setDark ? NusaConfig.darkTextPrimary : NusaConfig.textPrimary),
                    decoration: InputDecoration(
                      hintText: 'Terima kasih, ditunggu pesanan selanjutnya!',
                      hintStyle: TextStyle(color: setDark ? NusaConfig.darkTextTertiary : NusaConfig.textTertiary),
                      border: InputBorder.none,
                      contentPadding: const EdgeInsets.all(14),
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                // Footer templates
                Wrap(spacing: 6, runSpacing: 6, children: [
                  _footerChip('🙏 Terima kasih, ditunggu pesanan selanjutnya!', footerCtrl, setSt),
                  _footerChip('🔄 Barang yang sudah dibeli tidak dapat ditukar.', footerCtrl, setSt),
                ]),
                const SizedBox(height: 20),

                // ── Tampilkan di Struk ──
                Text('Tampilkan di Struk', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14,
                    color: setDark ? NusaConfig.darkTextPrimary : NusaConfig.textPrimary)),
                const SizedBox(height: 8),
                _toggleRow('Logo toko', togs['showLogo'] ?? true, setDark, (v) => setSt(() => togs['showLogo'] = v)),
                _toggleRow('Nama kasir', togs['showCashier'] ?? true, setDark, (v) => setSt(() => togs['showCashier'] = v)),
                _toggleRow('Nomor invoice', togs['showInvoice'] ?? true, setDark, (v) => setSt(() => togs['showInvoice'] = v)),
                _toggleRow('Tanggal & jam', togs['showDate'] ?? true, setDark, (v) => setSt(() => togs['showDate'] = v)),
                _toggleRow('Barcode', togs['showBarcode'] ?? false, setDark, (v) => setSt(() => togs['showBarcode'] = v)),
                const SizedBox(height: 20),

                // ── Mini Preview ──
                Text('Preview', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14,
                    color: setDark ? NusaConfig.darkTextPrimary : NusaConfig.textPrimary)),
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: const Color(0xFFE5E7EB)),
                  ),
                  child: Column(children: [
                    if (togs['showLogo'] == true && logoPath != null && logoPath!.isNotEmpty)
                      Padding(padding: const EdgeInsets.only(bottom: 6),
                        child: Image.file(File(logoPath!), height: 40)),
                    Text(headerCtrl.text.isNotEmpty ? headerCtrl.text : (storeName.isNotEmpty ? storeName : 'NUSA MART'),
                        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: Color(0xFF1F2937))),
                    const SizedBox(height: 2),
                    const Text('────────────────────',
                        style: TextStyle(fontSize: 9, color: Color(0xFF9CA3AF))),
                    if (togs['showInvoice'] == true) ...[
                      const SizedBox(height: 2),
                      const Text('INV-001 / Kasir: Budi',
                          style: TextStyle(fontSize: 9, color: Color(0xFF6B7280))),
                    ],
                    if (togs['showDate'] == true) ...[
                      const SizedBox(height: 1),
                      const Text('22 Jul 2026 14:30',
                          style: TextStyle(fontSize: 9, color: Color(0xFF6B7280))),
                    ],
                    const SizedBox(height: 2),
                    const Text('────────────────────',
                        style: TextStyle(fontSize: 9, color: Color(0xFF9CA3AF))),
                    if (togs['showBarcode'] == true) ...[
                      const SizedBox(height: 4),
                      Container(width: double.infinity, height: 24,
                          color: const Color(0xFF1F2937)),
                      const SizedBox(height: 2),
                    ],
                    const SizedBox(height: 4),
                    Text(footerCtrl.text.isNotEmpty ? footerCtrl.text : 'Terima kasih!',
                        textAlign: TextAlign.center,
                        style: const TextStyle(fontSize: 8, color: Color(0xFF6B7280))),
                  ]),
                ),
                const SizedBox(height: 20),

                // Save button
                NusaButton('Simpan', onPressed: () async {
                  await repo.setReceiptHeader(headerCtrl.text.trim());
                  await repo.setReceiptFooter(footerCtrl.text.trim());
                  await repo.setReceiptPaperSize(paper);
                  await repo.setReceiptToggles(togs);
                  if (mounted) Navigator.pop(ctx);
                }),
              ]),
              ),
            );
          },
        );
      },
    );
  }

  // ── Receipt helpers ──────────────────────────────────────

  Widget _paperChip(String label, String current, bool isDark, {required VoidCallback onTap}) {
    final selected = current == label;
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(
            color: selected ? NusaConfig.primarySoft : (isDark ? NusaConfig.darkSurface2 : const Color(0xFFF3F4F6)),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: selected ? NusaConfig.primaryColor : (isDark ? NusaConfig.darkBorder : NusaConfig.dividerColor)),
          ),
          child: Column(children: [
            Icon(selected ? Icons.check_circle : Icons.print, size: 20,
                color: selected ? NusaConfig.primaryColor : (isDark ? NusaConfig.darkTextSecondary : NusaConfig.textSecondary)),
            const SizedBox(height: 4),
            Text(label, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600,
                color: selected ? NusaConfig.primaryColor : (isDark ? NusaConfig.darkTextSecondary : NusaConfig.textSecondary))),
          ]),
        ),
      ),
    );
  }

  Widget _toggleRow(String label, bool value, bool isDark, ValueChanged<bool> onChanged) {
    return SwitchListTile(
      title: Text(label, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500)),
      value: value,
      dense: true,
      contentPadding: EdgeInsets.zero,
      activeColor: NusaConfig.primaryColor,
      onChanged: onChanged,
    );
  }

  Widget _footerChip(String text, TextEditingController ctrl, StateSetter setSt) {
    return GestureDetector(
      onTap: () {
        ctrl.text = text;
        setSt(() {});
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: NusaConfig.primarySoft,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(text, style: const TextStyle(fontSize: 11, color: NusaConfig.primaryColor)),
      ),
    );
  }

  // ── Role Management ───────────────────────────────────────

  Future<void> _showManageRoles() async {
    final roleRepo = RoleRepository();
    final roles = await roleRepo.getRoles();
    if (!mounted) return;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    showDialog(
      context: context,
      builder: (_) => StatefulBuilder(
        builder: (ctx, setSt) => AlertDialog(
          title: const Text('Kelola Role & Jabatan', style: TextStyle(fontWeight: FontWeight.w700)),
          content: SizedBox(width: double.maxFinite,
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
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
                    child: Row(children: [
                      Container(width: 32, height: 32,
                        decoration: BoxDecoration(color: color.withOpacity(0.15), borderRadius: BorderRadius.circular(8)),
                        child: Icon(Icons.badge, size: 18, color: color)),
                      const SizedBox(width: 10),
                      Expanded(child: Text(name, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14))),
                      if (!isDefault)
                        GestureDetector(
                          onTap: () async {
                            Navigator.of(ctx).pop();
                            await _showRoleForm(roleRepo, existing: r);
                          },
                          child: Padding(padding: const EdgeInsets.all(8),
                            child: Icon(Icons.edit, size: 18,
                                color: isDark ? NusaConfig.darkTextSecondary : NusaConfig.textSecondary)),
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
                              if (mounted) Navigator.of(ctx).pop();
                            }
                          },
                          child: const Padding(padding: EdgeInsets.all(8),
                            child: Icon(Icons.delete_outline, size: 18, color: NusaConfig.primaryColor)),
                        ),
                    ]),
                  ),
                );
              }),
            ]),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('Tutup')),
            ElevatedButton.icon(
              onPressed: () async {
                Navigator.of(ctx).pop();
                await _showRoleForm(roleRepo);
              },
              icon: const Icon(Icons.add, size: 18),
              label: const Text('Tambah Role'),
              style: ElevatedButton.styleFrom(
                backgroundColor: NusaConfig.primaryColor, foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _showRoleForm(RoleRepository roleRepo, {Map<String, dynamic>? existing}) async {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final isEdit = existing != null;
    final nameCtrl = TextEditingController(text: existing?['name'] as String?);
    var selectedColor = existing != null ? (existing['color'] as int) : 0xFF3B82F6;
    final accessList = <String>[];
    if (existing != null) accessList.addAll((existing['access'] as List).cast<String>());

    const allScreens = [
      'home', 'kasir', 'produk', 'stok', 'transaksi', 'pelanggan',
      'promo', 'laporan', 'presensi', 'karyawan', 'keuangan',
      'pengaturan', 'supplier', 'spreadsheet', 'pesanan_online', 'ai_chat',
    ];

    if (!mounted) return;

    await showDialog(
      context: context,
      builder: (_) => StatefulBuilder(
        builder: (ctx, setSt) => AlertDialog(
          title: Text(isEdit ? 'Edit Role' : 'Tambah Role Baru', style: const TextStyle(fontWeight: FontWeight.w700)),
          content: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
              NusaInput('Nama Role', controller: nameCtrl),
              const SizedBox(height: 12),
              const Text('Warna', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
              const SizedBox(height: 8),
              Wrap(spacing: 8, runSpacing: 8,
                children: const [0xFFE63946, 0xFF3B82F6, 0xFF10B981, 0xFF8B5CF6, 0xFFF59E0B, 0xFFEC4899, 0xFF6366F1, 0xFF14B8A6]
                    .map((c) => GestureDetector(
                      onTap: () => setSt(() => selectedColor = c),
                      child: Container(width: 36, height: 36,
                        decoration: BoxDecoration(color: Color(c), borderRadius: BorderRadius.circular(10),
                          border: selectedColor == c
                              ? Border.all(color: isDark ? Colors.white : Colors.black, width: 3) : null)),
                    )).toList(),
              ),
              const SizedBox(height: 16),
              const Text('Akses Menu', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
              const SizedBox(height: 8),
              ...allScreens.map((s) => CheckboxListTile(
                title: Text(s, style: const TextStyle(fontSize: 13)),
                value: accessList.contains(s),
                dense: true, contentPadding: EdgeInsets.zero, visualDensity: VisualDensity.compact,
                onChanged: (v) => setSt(() { v == true ? accessList.add(s) : accessList.remove(s); }),
              )),
            ]),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('Batal')),
            ElevatedButton(
              onPressed: () async {
                final name = nameCtrl.text.trim();
                if (name.isEmpty) return;
                if (isEdit) {
                  await roleRepo.updateRole(existing['name'] as String, name, selectedColor, accessList);
                } else {
                  await roleRepo.addRole(name, selectedColor, accessList);
                }
                if (mounted) Navigator.of(ctx).pop();
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: NusaConfig.primaryColor, foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              child: const Text('Simpan'),
            ),
          ],
        ),
      ),
    );
  }

  // ── About Link ────────────────────────────────────────────

  Widget _aboutLink(String label, String url) {
    return GestureDetector(
      onTap: () { try { launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication); } catch (_) {} },
      child: Text(label, style: TextStyle(fontSize: 13, color: NusaConfig.primaryColor,
          decoration: TextDecoration.underline)),
    );
  }

  // ═══════════════════════════════════════════════════════════
  //  BUILD
  // ═══════════════════════════════════════════════════════════

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final session = ref.watch(employeeSessionProvider);

    return ScreenScaffold('Pengaturan',
      SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [

          // ════════════════════════════════════════
          //  TOKO
          // ════════════════════════════════════════
          _sectionHeader('TOKO', isDark),
          // Nama Toko
          NusaCard(Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            const Text('Informasi Toko', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 16)),
            const SizedBox(height: 12),
            NusaInput('Nama toko', controller: _storeCtrl),
            const SizedBox(height: 12),
            NusaButton('Simpan', onPressed: () async {
              await ref.read(settingsRepoProvider).setStoreName(_storeCtrl.text.trim());
            }),
          ])),
          const SizedBox(height: 12),
          // Toko Online
          _menuRow(
            icon: Icons.shopping_bag_outlined, iconColor: const Color(0xFFE63946),
            title: 'Toko Online', subtitle: 'Aktifkan & atur toko online (Vercel)',
            isDark: isDark,
            onTap: () => context.push('/toko_online_setup'),
          ),
          const SizedBox(height: 12),
          // Pembayaran
          _menuRow(
            icon: Icons.payment, iconColor: const Color(0xFF6366F1),
            title: 'Pembayaran', subtitle: 'Atur QRIS & rekening bank untuk transfer',
            isDark: isDark,
            onTap: () => context.push('/pengaturan_pembayaran'),
          ),
          const SizedBox(height: 12),
          // Pengaturan Struk
          _menuRow(
            icon: Icons.receipt_long, iconColor: const Color(0xFF10B981),
            title: 'Pengaturan Struk', subtitle: 'Atur footer struk & upload logo toko',
            isDark: isDark,
            onTap: _showReceiptSettings,
          ),

          const SizedBox(height: 24),

          // ════════════════════════════════════════
          //  TAMPILAN
          // ════════════════════════════════════════
          _sectionHeader('TAMPILAN', isDark),
          NusaCard(Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('Tema', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 16)),
            const SizedBox(height: 12),
            Row(children: [
              _themeChip('Terang', 'light', Icons.light_mode, isDark),
              const SizedBox(width: 8),
              _themeChip('Gelap', 'dark', Icons.dark_mode, isDark),
              const SizedBox(width: 8),
              _themeChip('Sistem', 'system', Icons.phone_android, isDark),
            ]),
          ])),

          const SizedBox(height: 24),

          // ════════════════════════════════════════
          //  KEAMANAN
          // ════════════════════════════════════════
          Row(children: [
            _sectionHeader('KEAMANAN', isDark),
            const SizedBox(width: 6),
            Icon(Icons.lock_outline, size: 13, color: isDark ? NusaConfig.darkTextSecondary : NusaConfig.textSecondary),
          ]),
          // Kelola Fitur
          _menuRow(
            icon: Icons.toggle_on_outlined, iconColor: NusaConfig.accentPurple,
            title: 'Kelola Fitur', subtitle: 'Atur fitur yang tampil di Home Screen',
            isDark: isDark,
            onTap: () => _pinGate(_showFeatureToggles),
            trailing: Icon(Icons.lock_outline, size: 16,
                color: isDark ? NusaConfig.darkTextSecondary : NusaConfig.textSecondary),
          ),
          const SizedBox(height: 12),
          // Kelola Role
          _menuRow(
            icon: Icons.admin_panel_settings, iconColor: NusaConfig.accentPurple,
            title: 'Kelola Role & Jabatan', subtitle: 'Tambah, edit, atau hapus role karyawan',
            isDark: isDark,
            onTap: () => _pinGate(_showManageRoles),
            trailing: Icon(Icons.lock_outline, size: 16,
                color: isDark ? NusaConfig.darkTextSecondary : NusaConfig.textSecondary),
          ),
          const SizedBox(height: 12),
          // Lisensi
          _menuRow(
            icon: Icons.key, iconColor: NusaConfig.accentGreen,
            title: 'Lisensi', subtitle: _activationKey != null ? 'Terverifikasi' : 'Belum diaktivasi',
            isDark: isDark,
            onTap: () => _pinGate(_showLicense),
            trailing: Row(mainAxisSize: MainAxisSize.min, children: [
              if (_activationKey != null)
                Icon(Icons.check_circle, size: 14, color: NusaConfig.accentGreen),
              const SizedBox(width: 6),
              Icon(Icons.lock_outline, size: 16,
                  color: isDark ? NusaConfig.darkTextSecondary : NusaConfig.textSecondary),
            ]),
          ),

          // Fingerprint — Owner only
          if (session?.role == 'Owner') ...[
            const SizedBox(height: 12),
            _menuRow(
              icon: Icons.fingerprint, iconColor: NusaConfig.accentPurple,
              title: 'Login Fingerprint',
              subtitle: _fingerprintEnabled ? 'Aktif — akses cepat pakai sidik jari' : 'Aktifkan akses cepat Owner',
              isDark: isDark,
              onTap: () => _toggleFingerprint(isDark, session!),
              trailing: Switch(
                value: _fingerprintEnabled,
                activeColor: NusaConfig.accentPurple,
                onChanged: (v) => _toggleFingerprint(isDark, session!),
              ),
            ),
          ],

          const SizedBox(height: 24),

          // ════════════════════════════════════════
          //  DATA
          // ════════════════════════════════════════
          _sectionHeader('DATA', isDark),
          _menuRow(
            icon: Icons.backup, iconColor: NusaConfig.primaryColor,
            title: 'Backup & Restore', subtitle: 'Simpan atau muat file database',
            isDark: isDark,
            onTap: () => showBackupSheet(context, ref),
          ),

          const SizedBox(height: 24),

          // ════════════════════════════════════════
          //  PERANGKAT
          // ════════════════════════════════════════
          _sectionHeader('PERANGKAT', isDark),
          // Printer
          _menuRow(
            icon: Icons.print, iconColor: const Color(0xFFE63946),
            title: 'Printer', subtitle: _printerName != null ? _printerName!.split('|').first : 'Atur printer thermal',
            isDark: isDark,
            onTap: () => PrinterSettingsSheet.show(
              context: context, currentAddress: _printerName,
              onPrinterSelected: (d) async {
                await ref.read(settingsRepoProvider).setPrinterAddress('${d.name}|${d.address}');
                setState(() => _printerName = '${d.name}|${d.address}');
              },
            ),
          ),
          const SizedBox(height: 12),
          // Update
          _menuRow(
            icon: _updateInfo?.hasUpdate == true ? Icons.system_update : Icons.update,
            iconColor: _updateInfo?.hasUpdate == true ? Colors.orange : NusaConfig.primaryColor,
            title: _updateInfo?.hasUpdate == true ? 'Update Tersedia!' : 'Cek Update',
            subtitle: _updateInfo?.hasUpdate == true
                ? 'Versi ${_updateInfo!.latestVersion} (build ${_updateInfo!.latestBuildNumber})'
                : _checkingUpdate ? 'Memeriksa...' : 'v${NusaConfig.appVersion}+${NusaConfig.appBuildNumber}',
            isDark: isDark,
            onTap: _updateInfo?.hasUpdate == true ? _showUpdateDialog : _checkUpdate,
            trailing: _checkingUpdate
                ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                : Icon(
                    _updateInfo?.hasUpdate == true ? Icons.download : Icons.refresh,
                    color: isDark ? NusaConfig.darkTextSecondary : NusaConfig.textSecondary),
          ),

          const SizedBox(height: 32),

          // ════════════════════════════════════════
          //  TENTANG APLIKASI
          // ════════════════════════════════════════
          _sectionHeader('TENTANG APLIKASI', isDark),
          NusaCard(Padding(
            padding: const EdgeInsets.all(16),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Icon(Icons.info_outline, size: 20,
                    color: isDark ? NusaConfig.darkTextSecondary : NusaConfig.textSecondary),
                const SizedBox(width: 10),
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  const Text('Nusa Kasir', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 16)),
                  const SizedBox(height: 2),
                  Text('Versi ${NusaConfig.appVersion} (build ${NusaConfig.appBuildNumber})',
                      style: TextStyle(fontSize: 13,
                          color: isDark ? NusaConfig.darkTextSecondary : NusaConfig.textSecondary)),
                ])),
              ]),
              const SizedBox(height: 12), const Divider(), const SizedBox(height: 12),
              Row(children: [
                Icon(Icons.person_outline, size: 18,
                    color: isDark ? NusaConfig.darkTextSecondary : NusaConfig.textSecondary),
                const SizedBox(width: 10),
                Text('Dibuat oleh Halu Goods', style: TextStyle(fontSize: 14,
                    color: isDark ? NusaConfig.darkTextSecondary : NusaConfig.textSecondary)),
              ]),
              const SizedBox(height: 16),
              Row(children: [
                _aboutLink('Syarat & Ketentuan', 'https://halugoods.com/terms'),
                const SizedBox(width: 16),
                _aboutLink('Kebijakan Privasi', 'https://halugoods.com/privacy'),
              ]),
            ]),
          )),
          const SizedBox(height: 24),
        ]),
      ),
    );
  }
}
