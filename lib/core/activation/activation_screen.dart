import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:nusa_kasir/core/config/nusa_config.dart';
import 'package:nusa_kasir/core/services/google_auth_service.dart';
import 'package:nusa_kasir/core/providers.dart';
import 'package:nusa_kasir/core/auth/employee_session.dart';
import 'package:nusa_kasir/core/utils/secure_storage.dart';
import 'package:nusa_kasir/data/database/app_database.dart';
import 'package:nusa_kasir/data/repositories/attendance_repository.dart';
import 'package:nusa_kasir/data/repositories/settings_repository.dart';
import 'package:nusa_kasir/features/auth/employee_session_provider.dart';
import 'package:nusa_kasir/shared/widgets/top_toast.dart';
import 'package:nusa_kasir/core/widgets/nusa_loading_animation.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:nfc_manager/nfc_manager.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

/// Activation & auth screen with 4 branches:
///
///   1. Welcome Screen — user memilih "Masuk dengan Google" secara manual
///   2. Setelah Google ID didapat:
///      a. Belum aktivasi key → minta input key aktivasi
///         → ada tombol "Belum punya key?" → buka landing page
///      b. Sudah aktivasi key → minta PIN untuk sign in
///   3. PIN → cek role → auto check-in attendance → dashboard
///   4. Restore prompt for cloud backup
///
/// Tidak ada auto-trigger Google sign-in — user memilih sendiri.
class ActivationScreen extends ConsumerStatefulWidget {
  const ActivationScreen({super.key});
  @override
  ConsumerState<ActivationScreen> createState() => _ActivationScreenState();
}

class _ActivationScreenState extends ConsumerState<ActivationScreen> {
  // Google Sign-In state
  bool _googleLoading = false;
  String? _googleError;
  String? _googleId;

  // Activation key input (new user)
  final _keyCtrl = TextEditingController();
  bool _keyLoading = false;
  String? _keyError;

  // PIN input (returning user)
  final _pinCtrl = TextEditingController();
  bool _pinLoading = false;
  String? _pinError;
  bool _rememberPin = false;

  // Screen state: 'welcome' | 'google_loading' | 'pin' | 'key'
  String _screen = 'welcome';

  Future<void> _startGoogleSignIn() async {
    if (_googleLoading) return;
    setState(() {
      _googleLoading = true;
      _googleError = null;
      _screen = 'google_loading';
    });
    try {
      final googleAuth = GoogleAuthService();
      final googleId = await googleAuth.signIn();
      if (googleId == null) {
        setState(() {
          _googleLoading = false;
          _googleError = 'Login Google diperlukan untuk menggunakan NUSA Kasir';
          _screen = 'welcome';
        });
        return;
      }
      _googleId = googleId;
      await GoogleAuthService.ensureStored(googleId);

      // Show "checking license" state — keep spinner active during cloud call
      setState(() => _googleLoading = false);
      if (mounted) await _checkLicenseStatus(googleId);
    } catch (e) {
      setState(() {
        _googleLoading = false;
        _googleError = 'Gagal login Google: $e';
        _screen = 'welcome';
      });
    }
  }

  Future<void> _openLandingPage() async {
    final uri = Uri.parse(NusaConfig.landingPageUrl);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  /// Check if employees exist. If not, try cloud restore first, then redirect to /setup.
  Future<void> _goToPinOrSetup() async {
    try {
      final db = ref.read(databaseProvider);
      final repo = AttendanceRepository(db);
      final emps = await repo.getEmployees();
      if (emps.isEmpty) {
        // No employees — try cloud auto-restore first
        final restored = await _autoRestoreIfNeeded();
        if (restored) return; // app will restart
        // No backup or restore failed — setup from scratch
        if (mounted) context.go('/setup');
        return;
      }
    } catch (_) {}
    if (mounted) setState(() => _screen = 'pin');
  }

  /// Auto-restore cloud backup without dialog. Returns true if restore was triggered.
  Future<bool> _autoRestoreIfNeeded() async {
    final key = await SecureStore.getActivation();
    if (key == null) return false;
    final repo = ref.read(activationRepoProvider);
    final hasBak = await repo.hasBackup();
    if (!hasBak) return false;
    // Auto download + stage pending restore
    final ok = await repo.downloadAndRestore(key);
    if (ok) {
      // Brief notification then restart
      if (mounted) {
        await showDialog(
          context: context,
          barrierDismissible: false,
          builder: (ctx) => AlertDialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            title: const Row(
              children: [
                Icon(Icons.cloud_download_outlined, color: NusaConfig.primaryColor, size: 28),
                SizedBox(width: 10),
                Text('Memulihkan Data', style: TextStyle(fontSize: 17)),
              ],
            ),
            content: const Text(
              'Data toko sebelumnya ditemukan di cloud.\nSedang dipulihkan...',
              style: TextStyle(fontSize: 14, height: 1.5),
            ),
            actions: [
              FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: NusaConfig.primaryColor,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                onPressed: () => SystemNavigator.pop(),
                child: const Text('Buka Ulang'),
              ),
            ],
          ),
        );
      }
      return true;
    }
    return false;
  }

  /// Check if this Google account already has an activated license.
  Future<void> _checkLicenseStatus(String googleUserId) async {
    // First check local storage
    final isActivated = await ref.read(activationRepoProvider).isActivated;

    if (isActivated) {
      _goToPinOrSetup();
      return;
    }

    // Try cloud check
    try {
      final res = await Supabase.instance.client.functions.invoke(
        'register_activation',
        body: {'googleUserId': googleUserId},
      );
      final data = res.data as Map<String, dynamic>?;
      if (data?['has_license'] == true) {
        // Check if trial expired
        final isExpired = data!['is_expired'] == true;
        
        if (isExpired) {
          // Trial expired → redirect to landing page
          setState(() {
            _googleLoading = false;
            _googleError = 'Masa trial Anda telah habis.\nBeli lisensi seumur hidup untuk melanjutkan.';
            _screen = 'trial_expired';
          });
          return;
        }

        // Has valid license → go to PIN or setup (handles auto-restore)
        final key = data['key'] as String;
        await SecureStore.saveActivation(key);
        _goToPinOrSetup();
        return;
      }
    } catch (_) {
      // Offline — just proceed to key input
    }

    setState(() => _screen = 'key');
  }


  // ── Key Activation Submit ──────────────────────────────────────────

  Future<void> _submitKey() async {
    final key = _keyCtrl.text.trim().toUpperCase();
    if (key.isEmpty) {
      setState(() => _keyError = 'Masukkan key aktivasi');
      return;
    }

    setState(() {
      _keyLoading = true;
      _keyError = null;
    });

    final googleId = _googleId ?? await GoogleAuthService.getStoredUserId();
    if (googleId == null) {
      setState(() {
        _keyLoading = false;
        _keyError = 'Login Google dulu';
      });
      return;
    }

    final repo = ref.read(activationRepoProvider);
    final r = await repo.activate(key, googleId);
    setState(() => _keyLoading = false);

    if (!r.ok) {
      setState(() => _keyError = r.error);
      return;
    }

    // Activation success → go to setup
    if (mounted) {
      TopToast.success(context, 'Aktivasi berhasil! 🎉');
      context.go('/setup');
    }
  }

  // ── PIN Login Submit (returning user) ─────────────────────────────

  Future<void> _submitPin() async {
    final pin = _pinCtrl.text.trim();
    if (pin.isEmpty) {
      setState(() => _pinError = 'Masukkan PIN');
      return;
    }

    setState(() {
      _pinLoading = true;
      _pinError = null;
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
        setState(() {
          _pinLoading = false;
          _pinError = 'PIN salah';
        });
        return;
      }

      // Create session (only remembered if checkbox is checked)
      final session = EmployeeSession(
        employeeId: emp.id,
        name: emp.name,
        role: emp.role,
        remember: _rememberPin,
      );
      ref.read(employeeSessionProvider.notifier).login(session, remember: _rememberPin);
      ref.read(authProvider.notifier).state = emp.role;

      // Auto check-in attendance
      try {
        await repo.checkIn(emp.id);
      } catch (_) {}

      // Check if setup needed
      final settingsRepo = SettingsRepository(db);
      final name = await settingsRepo.getStoreName();
      if (mounted) context.go(name.isEmpty ? '/setup' : '/home');
    } catch (e) {
      setState(() {
        _pinLoading = false;
        _pinError = 'Terjadi kesalahan: $e';
      });
    }
  }

  // ── Scan / NFC ─────────────────────────────────────────────────────

  Future<void> _scan() async {
    final code = await Navigator.of(context).push<String>(MaterialPageRoute(
      builder: (_) => Scaffold(
        appBar: AppBar(title: const Text('Scan Key Aktivasi')),
        body: MobileScanner(
          onDetect: (c) {
            final raw = c.barcodes.firstOrNull?.rawValue;
            if (raw != null) Navigator.pop(context, raw);
          },
        ),
      ),
    ));
    if (code != null) {
      _keyCtrl.text = code;
      await _submitKey();
    }
  }

  Future<void> _tapNfc() async {
    if (!await NfcManager.instance.isAvailable()) {
      setState(() => _keyError = 'NFC tidak tersedia');
      return;
    }
    await NfcManager.instance.startSession(onDiscovered: (tag) async {
      final ndef = Ndef.from(tag);
      final msg = ndef?.cachedMessage;
      String? key;
      if (msg != null) {
        for (final record in msg.records) {
          if (record.typeNameFormat == NdefTypeNameFormat.nfcWellknown &&
              record.type.isNotEmpty &&
              record.type.first == 0x54) {
            final payload = record.payload;
            if (payload.isNotEmpty) {
              final langLen = payload.first & 0x3F;
              key = String.fromCharCodes(payload.sublist(1 + langLen));
            }
          }
        }
      }
      await NfcManager.instance.stopSession();
      if (key != null) {
        _keyCtrl.text = key;
        await _submitKey();
      }
    });
  }

  @override
  void dispose() {
    _keyCtrl.dispose();
    _pinCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    switch (_screen) {
      case 'welcome':
        return _buildWelcomeScreen(isDark);
      case 'google_loading':
        return _buildGoogleLoadingScreen(isDark);
      case 'trial_expired':
        return _buildTrialExpiredScreen(isDark);
      case 'pin':
        return _buildPinScreen(isDark);
      case 'key':
        return _buildKeyScreen(isDark);
      default:
        return _buildWelcomeScreen(isDark);
    }
  }

  // ── Welcome Screen (first screen — user chooses to sign in) ────────

  Widget _buildWelcomeScreen(bool isDark) {
    return Scaffold(
      backgroundColor: isDark ? NusaConfig.darkBackground : NusaConfig.backgroundColor,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(
              children: [
                const SizedBox(height: 40),
                // Logo
                Container(
                  width: 88, height: 88,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: const LinearGradient(
                      colors: [NusaConfig.primaryColor, NusaConfig.primaryDark],
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: NusaConfig.primaryColor.withValues(alpha: 0.35),
                        blurRadius: 24,
                        offset: const Offset(0, 10),
                      ),
                    ],
                  ),
                  child: const Icon(Icons.store_rounded, color: Colors.white, size: 44),
                ),
                const SizedBox(height: 28),
                // Brand
                Text('NUSA', style: Theme.of(context).textTheme.displaySmall?.copyWith(
                  color: NusaConfig.primaryColor, fontWeight: FontWeight.w800, letterSpacing: -1.5)),
                const SizedBox(height: 6),
                Text(NusaConfig.appSubtitle, textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 14, color: isDark ? NusaConfig.darkTextSecondary : NusaConfig.textSecondary)),
                const SizedBox(height: 48),

                // Google Sign-In button
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: _startGoogleSignIn,
                    icon: Image.asset(
                      'assets/icons/google_logo.png',
                      width: 22,
                      height: 22,
                      errorBuilder: (_, __, ___) => const Icon(Icons.g_mobiledata, size: 28, color: Color(0xFF4285F4)),
                    ),
                    label: const Text(
                      'Masuk dengan Google',
                      style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.white,
                      foregroundColor: const Color(0xFF1F2937),
                      elevation: 1,
                      padding: const EdgeInsets.symmetric(vertical: 15),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                        side: BorderSide(color: isDark ? NusaConfig.darkBorder : const Color(0xFFD1D5DB)),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  'Akun Google Anda digunakan untuk verifikasi lisensi',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 11, color: isDark ? NusaConfig.darkTextTertiary : NusaConfig.textTertiary),
                ),

                // Error message
                if (_googleError != null) ...[
                  const SizedBox(height: 20),
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: NusaConfig.primaryColor.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.error_outline, size: 20, color: NusaConfig.primaryColor.withValues(alpha: 0.7)),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(_googleError!, style: const TextStyle(color: NusaConfig.textSecondary, fontSize: 13)),
                        ),
                      ],
                    ),
                  ),
                ],

                const SizedBox(height: 40),
                // Bottom text
                Text('Belum punya akun?', style: TextStyle(fontSize: 13, color: isDark ? NusaConfig.darkTextSecondary : NusaConfig.textSecondary)),
                const SizedBox(height: 6),
                GestureDetector(
                  onTap: _startGoogleSignIn,
                  child: const Text('Daftar', style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: NusaConfig.primaryColor,
                    decoration: TextDecoration.underline,
                  )),
                ),

                const SizedBox(height: 48),
                // Footer
                Text('v${NusaConfig.appVersion}+${NusaConfig.appBuildNumber}',
                  style: TextStyle(fontSize: 11, color: isDark ? NusaConfig.darkTextTertiary : NusaConfig.textTertiary)),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ── Google Sign-In Loading Screen (shown while signing in) ──────────

  // ── Trial Expired Screen ─────────────────────────────────────────────

  Widget _buildTrialExpiredScreen(bool isDark) {
    return Scaffold(
      backgroundColor: isDark ? NusaConfig.darkBackground : NusaConfig.backgroundColor,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(
              children: [
                const SizedBox(height: 60),
                Container(
                  width: 80, height: 80,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: Colors.amber.shade100,
                  ),
                  child: Icon(Icons.timer_off_rounded, size: 40, color: Colors.amber.shade700),
                ),
                const SizedBox(height: 24),
                Text('Masa Trial Habis', style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w700, color: isDark ? Colors.white : NusaConfig.textPrimary)),
                const SizedBox(height: 12),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Text(
                    _googleError ?? 'Masa trial 30 hari Anda telah berakhir.\nBeli lisensi seumur hidup untuk melanjutkan menggunakan NUSA Kasir.',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 14, height: 1.6, color: isDark ? NusaConfig.darkTextSecondary : NusaConfig.textSecondary),
                  ),
                ),
                const SizedBox(height: 32),
                // Buy CTA → open landing page
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: _openLandingPage,
                    icon: const Icon(Icons.shopping_bag_outlined, size: 20),
                    label: const Text('Beli Lisensi (Rp 199K)'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: NusaConfig.primaryColor,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                // Back to welcome
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton(
                    onPressed: _startGoogleSignIn,
                    style: OutlinedButton.styleFrom(
                      foregroundColor: isDark ? NusaConfig.darkTextSecondary : NusaConfig.textSecondary,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    ),
                    child: const Text('Ganti Akun Google'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildGoogleLoadingScreen(bool isDark) {
    // Determine status text based on current phase
    final statusText = _googleLoading
        ? 'Menghubungkan ke Google...'
        : _googleError != null
            ? null
            : 'Memeriksa lisensi...';

    return Scaffold(
      backgroundColor: isDark ? NusaConfig.darkBackground : NusaConfig.backgroundColor,
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            children: [
              const SizedBox(height: 60),

              if (_googleError != null) ...[
                // Error state — show error with retry
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: NusaConfig.primaryColor.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Column(
                    children: [
                      Icon(Icons.error_outline, size: 40, color: NusaConfig.primaryColor.withValues(alpha: 0.7)),
                      const SizedBox(height: 12),
                      Text(_googleError!, textAlign: TextAlign.center,
                        style: const TextStyle(color: NusaConfig.textSecondary, fontSize: 14)),
                      const SizedBox(height: 16),
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton.icon(
                          onPressed: _startGoogleSignIn,
                          icon: const Icon(Icons.login, size: 20),
                          label: const Text('Login Google'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: NusaConfig.primaryColor,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ] else ...[
                // Loading state — fancy NUSA animation
                NusaLoadingAnimation(statusText: statusText!),
              ],
            ],
          ),
        ),
      ),
    );
  }

  // ── PIN Screen (returning user) ────────────────────────────────────

  Widget _buildPinScreen(bool isDark) {
    return Scaffold(
      backgroundColor: isDark ? NusaConfig.darkBackground : NusaConfig.backgroundColor,
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            children: [
              const SizedBox(height: 40),
              Container(
                width: 72, height: 72,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: const LinearGradient(
                    colors: [NusaConfig.primaryColor, NusaConfig.primaryDark],
                  ),
                  boxShadow: [
                    BoxShadow(color: NusaConfig.primaryColor.withValues(alpha: 0.3), blurRadius: 16, offset: const Offset(0, 6)),
                  ],
                ),
                child: const Icon(Icons.lock_rounded, color: Colors.white, size: 36),
              ),
              const SizedBox(height: 20),
              Text('Masuk ke NUSA', style: Theme.of(context).textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w700,
                color: isDark ? NusaConfig.darkTextPrimary : NusaConfig.textPrimary,
              )),
              const SizedBox(height: 4),
              Text('Masukkan PIN untuk melanjutkan',
                style: TextStyle(fontSize: 13, color: isDark ? NusaConfig.darkTextSecondary : NusaConfig.textSecondary)),
              const SizedBox(height: 32),

              SizedBox(
                width: 220,
                child: TextField(
                  controller: _pinCtrl,
                  obscureText: true,
                  keyboardType: TextInputType.number,
                  maxLength: 6,
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w600, letterSpacing: 12),
                  maxLengthEnforcement: MaxLengthEnforcement.enforced,
                  onSubmitted: (_) => _submitPin(),
                  decoration: InputDecoration(
                    counterText: '',
                    filled: true,
                    fillColor: isDark ? NusaConfig.darkSurface : Colors.white,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(16),
                      borderSide: BorderSide(color: isDark ? NusaConfig.darkBorder : NusaConfig.borderColor),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(16),
                      borderSide: BorderSide(color: isDark ? NusaConfig.darkBorder : NusaConfig.borderColor),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(16),
                      borderSide: const BorderSide(color: NusaConfig.primaryColor, width: 2),
                    ),
                  ),
                ),
              ),

              if (_pinError != null)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(_pinError!, style: const TextStyle(color: NusaConfig.primaryColor, fontSize: 13)),
                ),

              const SizedBox(height: 20),
              // Remember checkbox
              GestureDetector(
                onTap: () => setState(() => _rememberPin = !_rememberPin),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    SizedBox(
                      width: 22, height: 22,
                      child: Checkbox(
                        value: _rememberPin,
                        onChanged: (v) => setState(() => _rememberPin = v ?? false),
                        activeColor: NusaConfig.primaryColor,
                        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text('Ingat PIN selama 8 jam',
                      style: TextStyle(fontSize: 13, color: isDark ? NusaConfig.darkTextSecondary : NusaConfig.textSecondary)),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _pinLoading ? null : _submitPin,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: NusaConfig.primaryColor,
                    foregroundColor: Colors.white,
                    elevation: 2,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  ),
                  child: Text(
                    _pinLoading ? 'Memeriksa...' : 'Masuk',
                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                  ),
                ),
              ),

              const SizedBox(height: 12),
              TextButton(
                onPressed: _startGoogleSignIn,
                child: const Text('Ganti akun Google', style: TextStyle(color: NusaConfig.textSecondary)),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── Key Activation Screen (new user) ───────────────────────────────

  Widget _buildKeyScreen(bool isDark) {
    return Scaffold(
      backgroundColor: isDark ? NusaConfig.darkBackground : NusaConfig.backgroundColor,
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            children: [
              const SizedBox(height: 40),
              Container(
                width: 72, height: 72,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: const LinearGradient(
                    colors: [NusaConfig.primaryColor, NusaConfig.primaryDark],
                  ),
                  boxShadow: [
                    BoxShadow(color: NusaConfig.primaryColor.withValues(alpha: 0.3), blurRadius: 16, offset: const Offset(0, 6)),
                  ],
                ),
                child: const Icon(Icons.vpn_key_rounded, color: Colors.white, size: 36),
              ),
              const SizedBox(height: 20),
              Text('Aktivasi NUSA', style: Theme.of(context).textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w700,
                color: isDark ? NusaConfig.darkTextPrimary : NusaConfig.textPrimary,
              )),
              const SizedBox(height: 4),
              Text('Masukkan key aktivasi dari seller',
                style: TextStyle(fontSize: 13, color: isDark ? NusaConfig.darkTextSecondary : NusaConfig.textSecondary)),
              const SizedBox(height: 32),

              TextField(
                controller: _keyCtrl,
                textAlign: TextAlign.center,
                style: const TextStyle(fontFamily: 'monospace', fontSize: 15, letterSpacing: 1),
                decoration: InputDecoration(
                  hintText: 'NUSA-XXXX-XXXX-...',
                  hintStyle: TextStyle(color: isDark ? NusaConfig.darkTextTertiary : NusaConfig.textTertiary),
                  filled: true,
                  fillColor: isDark ? NusaConfig.darkSurface : Colors.white,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.all(Radius.circular(14)),
                    borderSide: BorderSide(color: isDark ? NusaConfig.darkBorder : NusaConfig.borderColor),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.all(Radius.circular(14)),
                    borderSide: BorderSide(color: isDark ? NusaConfig.darkBorder : NusaConfig.borderColor),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.all(Radius.circular(14)),
                    borderSide: const BorderSide(color: NusaConfig.primaryColor, width: 2),
                  ),
                ),
              ),
              if (_keyError != null)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(_keyError!, style: const TextStyle(color: NusaConfig.primaryColor, fontSize: 13)),
                ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: NusaConfig.primaryColor,
                    foregroundColor: Colors.white,
                    elevation: 2,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  ),
                  onPressed: _keyLoading ? null : _submitKey,
                  child: Text(
                    _keyLoading ? 'Memproses...' : 'Aktivasi',
                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              TextButton.icon(onPressed: _scan, icon: const Icon(Icons.qr_code_scanner), label: const Text('Scan Barcode Kartu')),
              TextButton.icon(onPressed: _tapNfc, icon: const Icon(Icons.nfc), label: const Text('Tap NFC')),
              const SizedBox(height: 8),
              // "Belum punya key?" → open landing page
              TextButton.icon(
                onPressed: _openLandingPage,
                icon: const Icon(Icons.shopping_bag_outlined, size: 18),
                label: const Text('Belum punya key aktivasi?'),
                style: TextButton.styleFrom(foregroundColor: NusaConfig.accentPurple),
              ),
              const SizedBox(height: 4),
              TextButton(
                onPressed: _startGoogleSignIn,
                child: const Text('Ganti akun Google', style: TextStyle(color: NusaConfig.textSecondary)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
