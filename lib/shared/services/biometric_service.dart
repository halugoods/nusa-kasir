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
  static Future<bool> isHardwareAvailable() async {
    try {
      return await _auth.canCheckBiometrics;
    } catch (_) {
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
  /// biometricOnly is set to false to allow PIN/password fallback on devices
  /// where the system biometric prompt behaves differently (e.g. Xiaomi/Redmi MIUI).
  static Future<bool> authenticate({String reason = 'Gunakan sidik jari untuk masuk'}) async {
    try {
      if (!await isHardwareAvailable()) return false;

      final ok = await _auth.authenticate(
        localizedReason: reason,
        options: const AuthenticationOptions(
          stickyAuth: true,
          biometricOnly: false,
        ),
      );
      debugPrint('[BiometricService] authenticate → $ok (biometricOnly=false)');
      return ok;
    } catch (e) {
      debugPrint('[BiometricService] authenticate ERROR: $e');
      return false;
    }
  }
}
