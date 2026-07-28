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

  /// Check if the device has biometric hardware configured.
  /// Uses multiple checks for max compatibility (MIUI, Samsung, stock Android).
  static Future<bool> isHardwareAvailable() async {
    try {
      final canCheck = await _auth.canCheckBiometrics;
      if (canCheck) return true;

      // Fallback: some devices return false on canCheckBiometrics but do have hardware
      final isSupported = await _auth.isDeviceSupported();
      if (isSupported) return true;

      // Last resort: check if any biometric type is enrolled
      final types = await _auth.getAvailableBiometrics();
      debugPrint('[BiometricService] available types: $types');
      return types.isNotEmpty;
    } catch (e) {
      debugPrint('[BiometricService] isHardwareAvailable ERROR: $e');
      return false;
    }
  }

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

  /// Prompt the user to scan their fingerprint/face.
  ///
  /// Returns true if authenticated, false if cancelled or failed.
  ///
  /// Uses biometricOnly: false to allow device PIN/pattern/password as fallback.
  /// This is critical for Xiaomi/Redmi MIUI, Samsung OneUI, and some stock Android
  /// firmwares where the STRONG biometric prompt silently fails.
  static Future<bool> authenticate({String reason = 'Gunakan sidik jari untuk masuk'}) async {
    try {
      if (!await isHardwareAvailable()) {
        debugPrint('[BiometricService] ⚠ no hardware available, skipping prompt');
        return false;
      }

      // Log device capabilities for debugging
      try {
        final types = await _auth.getAvailableBiometrics();
        debugPrint('[BiometricService] device biometric types: $types');
      } catch (_) {}

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
