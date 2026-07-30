import 'package:flutter/foundation.dart';
import 'package:local_auth/local_auth.dart';
import 'package:nusa_kasir/core/utils/secure_storage.dart';

/// Biometric (fingerprint/face) service for Owner quick unlock.
///
/// Fingerprint does NOT select which user logs in — it only unlocks
/// an existing valid Owner session. If no Owner session exists or the
/// session is expired, biometric is never prompted.
class BiometricService {
  const BiometricService._();

  static final _auth = LocalAuthentication();
  static const _keyEnabled = 'nusa_fingerprint_enabled';

  // ── Settings ────────────────────────────────────────────────────

  /// Check if biometric is enabled in NUSA settings (Owner toggle).
  static Future<bool> isEnabled() async {
    try {
      final v = await SecureStore.read(key: _keyEnabled);
      return v == 'true';
    } catch (_) {
      return false;
    }
  }

  /// Enable biometric login for Owner.
  static Future<void> enable() async {
    await SecureStore.write(key: _keyEnabled, value: 'true');
  }

  /// Disable biometric login for Owner.
  static Future<void> disable() async {
    await SecureStore.write(key: _keyEnabled, value: 'false');
  }

  // ── Authentication ──────────────────────────────────────────────

  /// Result of an authentication attempt.
  /// [ok] — true if biometric/pin accepted.
  /// [message] — user-facing message (only set when [ok] is false).
  static ({bool ok, String? message}) lastResult = (ok: false, message: null);

  /// Prompt the user to scan their fingerprint/face.
  ///
  /// Returns true if authenticated, false if cancelled or failed.
  ///
  /// NO hardware pre-check — we let the OS prompt handle it directly.
  /// Pre-checks (canCheckBiometrics, isDeviceSupported) return false
  /// on many Xiaomi/Redmi MIUI and Samsung OneUI devices even when
  /// biometric hardware works perfectly. We just try it.
  ///
  /// Check if the device can authenticate at all.
  /// Returns (ok, message). Does NOT show any dialog.
  static Future<({bool ok, String message})> checkCapabilities() async {
    try {
      final supported = await _auth.isDeviceSupported();
      debugPrint('[BiometricService] isDeviceSupported: $supported');
      if (!supported) {
        return (ok: false, message: 'Perangkat tidak mendukung biometric');
      }

      final canCheck = await _auth.canCheckBiometrics;
      debugPrint('[BiometricService] canCheckBiometrics: $canCheck');

      final types = await _auth.getAvailableBiometrics();
      debugPrint('[BiometricService] available biometrics: $types');

      if (types.isEmpty && !canCheck) {
        return (ok: false, message: 'Tidak ada sidik jari terdaftar di perangkat');
      }

      // Check if device has any secure lock screen
      try {
        // On some devices (Xiaomi), even with fingerprint enrolled,
        // canCheckBiometrics returns false. We still try — the OS dialog
        // will show the correct error if no biometrics are enrolled.
      } catch (_) {}

      return (ok: true, message: 'OK — ${types.map((t) => t.name).join(', ')}');
    } catch (e) {
      debugPrint('[BiometricService] checkCapabilities error: $e');
      // On error, let the authenticate() call decide — don't block
      return (ok: true, message: 'Unknown (will try anyway)');
    }
  }

  /// After calling this, read [lastResult] for a user-facing error message.
  static Future<bool> authenticate({String reason = 'Gunakan sidik jari untuk masuk'}) async {
    try {
      // Diagnostic: log device capabilities (does NOT block auth)
      try {
        final types = await _auth.getAvailableBiometrics();
        debugPrint('[BiometricService] device biometric types: $types');
        if (types.isEmpty) {
          debugPrint('[BiometricService] ⚠ getAvailableBiometrics() returned EMPTY list — device may not report types even though hardware works');
          debugPrint('[BiometricService] Proceeding anyway — OS dialog will handle it');
        }
      } catch (e) {
        debugPrint('[BiometricService] could not get biometric types: $e');
      }

      // Try biometric + PIN/pattern/password fallback
      final ok = await _auth.authenticate(
        localizedReason: reason,
        biometricOnly: false,
        persistAcrossBackgrounding: false,
      );
      debugPrint('[BiometricService] authenticate → $ok');

      if (!ok) {
        lastResult = (ok: false, message: 'Pemindaian dibatalkan atau gagal — coba lagi');
      } else {
        lastResult = (ok: true, message: null);
      }
      return ok;
    } on Exception catch (e) {
      // Extract actual error message — LocalAuthException has .message
      String msg;
      try {
        msg = (e as dynamic).message as String? ?? '$e';
      } catch (_) {
        msg = '$e';
      }
      debugPrint('[BiometricService] authenticate ERROR (${e.runtimeType}): $msg');
      lastResult = (ok: false, message: 'Gagal: $msg');
      return false;
    } catch (e) {
      debugPrint('[BiometricService] authenticate UNKNOWN ERROR: $e');
      lastResult = (ok: false, message: 'Gagal — $e');
      return false;
    }
  }
}
