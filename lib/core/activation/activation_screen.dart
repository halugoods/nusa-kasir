import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:nusa_kasir/core/activation/activation_repository.dart';
import 'package:nusa_kasir/core/config/nusa_config.dart';
import 'package:nusa_kasir/core/services/google_auth_service.dart';
import 'package:nusa_kasir/shared/widgets/top_toast.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:nfc_manager/nfc_manager.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

final activationRepoProvider = Provider<ActivationRepository>((ref) {
  try {
    return ActivationRepository(Supabase.instance.client);
  } catch (_) {
    return ActivationRepository(null);
  }
});

class ActivationScreen extends ConsumerStatefulWidget {
  const ActivationScreen({super.key});
  @override
  ConsumerState<ActivationScreen> createState() => _ActivationScreenState();
}

class _ActivationScreenState extends ConsumerState<ActivationScreen> {
  final _ctrl = TextEditingController();
  bool _loading = false;
  String? _error;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Scaffold(
      backgroundColor: isDark ? NusaConfig.darkBackground : NusaConfig.backgroundColor,
      body: Center(child: SingleChildScrollView(padding: const EdgeInsets.all(24),
        child: Column(children: [
          const SizedBox(height: 40),
          Container(
            width: 72, height: 72,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: const LinearGradient(
                colors: [NusaConfig.primaryColor, NusaConfig.primaryDark],
              ),
              boxShadow: [BoxShadow(color: NusaConfig.primaryColor.withValues(alpha: 0.3), blurRadius: 16, offset: const Offset(0, 6))],
            ),
            child: const Icon(Icons.store_rounded, color: Colors.white, size: 36),
          ),
          const SizedBox(height: 20),
          Text('NUSA', style: Theme.of(context).textTheme.displaySmall?.copyWith(
            color: NusaConfig.primaryColor, fontWeight: FontWeight.w800, letterSpacing: -1)),
          const SizedBox(height: 4),
          Text(NusaConfig.appSubtitle, textAlign: TextAlign.center,
            style: TextStyle(fontSize: 13, color: isDark ? NusaConfig.darkTextSecondary : NusaConfig.textSecondary)),
          const SizedBox(height: 32),
          TextField(controller: _ctrl, textAlign: TextAlign.center,
            style: const TextStyle(fontFamily: 'monospace', fontSize: 17, letterSpacing: 1),
            decoration: InputDecoration(
              hintText: 'Masukkan Key Aktivasi',
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
            )),
          if (_error != null) Padding(padding: const EdgeInsets.only(top: 8),
            child: Text(_error!, style: const TextStyle(color: NusaConfig.primaryColor, fontSize: 13))),
          const SizedBox(height: 16),
          SizedBox(width: double.infinity, child: ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: NusaConfig.primaryColor,
              foregroundColor: Colors.white,
              elevation: 2,
              padding: const EdgeInsets.symmetric(vertical: 16),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            ),
            onPressed: _loading ? null : _submit, child: Text(_loading ? 'Memproses...' : 'Aktivasi',
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)))),
          const SizedBox(height: 12),
          TextButton.icon(onPressed: _scan, icon: const Icon(Icons.qr_code_scanner), label: const Text('Scan Barcode Kartu')),
          TextButton.icon(onPressed: _tapNfc, icon: const Icon(Icons.nfc), label: const Text('Tap NFC')),
        ]))),
    );
  }

  Future<void> _submit() async {
    setState(() => _loading = true);
    final key = _ctrl.text.trim().toUpperCase();
    final repo = ref.read(activationRepoProvider);
    final r = await repo.activate(key);
    setState(() => _loading = false);

    if (!r.ok) {
      setState(() => _error = r.error);
      return;
    }

    // Activation success — now link Google account for backup identity
    if (mounted) await _linkGoogleAndRestore(key);
  }

  /// Link Google account → check for cloud backup → offer restore.
  Future<void> _linkGoogleAndRestore(String activationKey) async {
    final googleAuth = GoogleAuthService();

    // Check if already linked (e.g., re-activation on same device)
    final alreadyLinked = await GoogleAuthService.isLinked();

    if (!alreadyLinked) {
      final link = await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: const Row(
            children: [
              Icon(Icons.cloud_sync, color: NusaConfig.primaryColor, size: 28),
              SizedBox(width: 10),
              Text('Simpan ke Cloud', style: TextStyle(fontSize: 17)),
            ],
          ),
          content: const Text(
            'Login dengan Google agar data toko bisa dipindahkan antar device '
            'tanpa kehilangan data.',
            style: TextStyle(fontSize: 14, height: 1.5),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Nanti', style: TextStyle(color: NusaConfig.textSecondary)),
            ),
            FilledButton.icon(
              onPressed: () => Navigator.pop(ctx, true),
              icon: const Icon(Icons.login, size: 18),
              label: const Text('Login Google'),
              style: FilledButton.styleFrom(
                backgroundColor: NusaConfig.primaryColor,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
          ],
        ),
      );

      if (link != true) {
        if (mounted) context.go('/setup');
        return;
      }

      // Perform Google Sign-In
      setState(() => _loading = true);
      final googleId = await googleAuth.signIn();
      setState(() => _loading = false);

      if (googleId == null) {
        TopToast.error(context, 'Gagal login Google. Coba lagi nanti.');
        if (mounted) context.go('/setup');
        return;
      }

      TopToast.success(context, 'Google terhubung!');
    }

    // Check for existing backup in cloud
    final repo = ref.read(activationRepoProvider);
    final hasBackup = await repo.hasBackup();

    if (hasBackup && mounted) {
      await _promptRestore(activationKey);
    } else if (mounted) {
      context.go('/setup');
    }
  }

  Future<void> _promptRestore(String key) async {
    final restore = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Row(
          children: [
            Icon(Icons.cloud_download_outlined, color: NusaConfig.primaryColor, size: 28),
            SizedBox(width: 10),
            Text('Data Ditemukan', style: TextStyle(fontSize: 17)),
          ],
        ),
        content: const Text(
          'Data toko sebelumnya ditemukan di cloud. '
          'Mau dipulihkan sekarang?',
          style: TextStyle(fontSize: 14, height: 1.5),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Nanti', style: TextStyle(color: NusaConfig.textSecondary)),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: NusaConfig.primaryColor,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Pulihkan'),
          ),
        ],
      ),
    );

    if (restore != true) {
      if (mounted) context.go('/setup');
      return;
    }

    setState(() => _loading = true);
    final repo = ref.read(activationRepoProvider);
    final ok = await repo.downloadAndRestore(key);
    setState(() => _loading = false);

    if (ok && mounted) {
      await showDialog(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: const Row(
            children: [
              Icon(Icons.check_circle, color: NusaConfig.accentGreen, size: 28),
              SizedBox(width: 10),
              Text('Data Siap!', style: TextStyle(fontSize: 17)),
            ],
          ),
          content: const Text(
            'App akan keluar. Buka lagi NUSA Kasir untuk melanjutkan.',
            style: TextStyle(fontSize: 14, height: 1.5),
          ),
          actions: [
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: NusaConfig.primaryColor,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              onPressed: () => SystemNavigator.pop(),
              child: const Text('Oke'),
            ),
          ],
        ),
      );
    } else if (mounted) {
      TopToast.error(context, 'Gagal memulihkan data. Periksa koneksi internet.');
      context.go('/setup');
    }
  }

  Future<void> _scan() async {
    final code = await Navigator.of(context).push<String>(MaterialPageRoute(
      builder: (_) => Scaffold(
        body: MobileScanner(onDetect: (c) => Navigator.pop(context, c.barcodes.first.rawValue)),
      ),
    ));
    if (code != null) { _ctrl.text = code; await _submit(); }
  }

  Future<void> _tapNfc() async {
    if (!await NfcManager.instance.isAvailable()) {
      setState(() => _error = 'NFC tidak tersedia'); return;
    }
    await NfcManager.instance.startSession(onDiscovered: (tag) async {
      final key = _readNdef(tag);
      await NfcManager.instance.stopSession();
      if (key != null) { _ctrl.text = key; await _submit(); }
    });
  }

  String? _readNdef(NfcTag tag) {
    final ndef = Ndef.from(tag);
    final msg = ndef?.cachedMessage;
    if (msg == null) return null;
    for (final record in msg.records) {
      if (record.typeNameFormat == NdefTypeNameFormat.nfcWellknown &&
          record.type.isNotEmpty && record.type.first == 0x54) {
        final payload = record.payload;
        if (payload.isEmpty) return null;
        final languageCodeLength = payload.first & 0x3F;
        return String.fromCharCodes(payload.sublist(1 + languageCodeLength));
      }
    }
    return null;
  }
}
