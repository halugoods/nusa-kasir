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

  /// Prompt the user to scan their fingerprint/face.
  ///
  /// Returns true if authenticated, false if cancelled or failed.
  ///
  /// NO hardware pre-check — we let the OS prompt handle it directly.
  /// Pre-checks (canCheckBiometrics, isDeviceSupported) return false
  /// on many Xiaomi/Redmi MIUI and Samsung OneUI devices even when
  /// biometric hardware works perfectly. We just try it.
  static Future<bool> authenticate({String reason = 'Gunakan sidik jari untuk masuk'}) async {
    try {
      // Log device info for debugging
      try {
        final types = await _auth.getAvailableBiometrics();
        debugPrint('[BiometricService] device types: $types');
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
      return ok;
    } catch (e) {
      debugPrint('[BiometricService] authenticate ERROR: $e');
      return false;
    }
  }
}
