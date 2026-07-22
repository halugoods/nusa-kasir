import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:nusa_kasir/core/constants/app_constants.dart';

class SecureStore {
  const SecureStore._();
  static const _s = FlutterSecureStorage();

  // -- Generic key-value --
  static Future<void> write({required String key, required String value}) =>
      _s.write(key: key, value: value);
  static Future<String?> read({required String key}) =>
      _s.read(key: key);
  static Future<void> delete({required String key}) =>
      _s.delete(key: key);

  // -- Activation --
  static Future<void> saveActivation(String key) =>
      _s.write(key: AppConstants.activationKey, value: key);
  static Future<String?> getActivation() => _s.read(key: AppConstants.activationKey);
  static Future<void> clearActivation() => _s.delete(key: AppConstants.activationKey);

  // -- Pending DB restore (device migration) --
  static Future<void> savePendingRestore() =>
      _s.write(key: 'nusa_pending_restore', value: '1');
  static Future<bool> hasPendingRestore() async =>
      (await _s.read(key: 'nusa_pending_restore')) == '1';
  static Future<void> clearPendingRestore() =>
      _s.delete(key: 'nusa_pending_restore');

  // -- Cloud backup timestamp (for conflict resolution) --
  static Future<void> saveLastBackupTime(DateTime t) =>
      _s.write(key: 'nusa_last_backup_at', value: t.toIso8601String());
  static Future<DateTime?> getLastBackupTime() async {
    final v = await _s.read(key: 'nusa_last_backup_at');
    return v != null ? DateTime.tryParse(v) : null;
  }
  static Future<void> clearLastBackupTime() =>
      _s.delete(key: 'nusa_last_backup_at');

  // -- Sheets tokens --
  static Future<void> saveSheetsTokens(String json) =>
      _s.write(key: AppConstants.sheetsTokenKey, value: json);
  static Future<String?> getSheetsTokens() => _s.read(key: AppConstants.sheetsTokenKey);
  static Future<void> clearSheetsTokens() => _s.delete(key: AppConstants.sheetsTokenKey);

  // -- Sheets email + spreadsheet ID per user --
  static Future<void> saveSheetsEmail(String email) =>
      _s.write(key: 'nusa_sheets_email', value: email);
  static Future<String?> getSheetsEmail() => _s.read(key: 'nusa_sheets_email');
  static Future<void> clearSheetsEmail() => _s.delete(key: 'nusa_sheets_email');

  static Future<void> saveSheetsId(String id) =>
      _s.write(key: 'nusa_sheets_id', value: id);
  static Future<String?> getSheetsId() => _s.read(key: 'nusa_sheets_id');
  static Future<void> clearSheetsId() => _s.delete(key: 'nusa_sheets_id');

  // -- Feature toggles (JSON) --
  static Future<void> saveFeatureToggles(String json) =>
      _s.write(key: 'nusa_feature_toggles', value: json);
  static Future<String?> getFeatureToggles() =>
      _s.read(key: 'nusa_feature_toggles');
  static Future<void> clearFeatureToggles() =>
      _s.delete(key: 'nusa_feature_toggles');
}
