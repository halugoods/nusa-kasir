import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:nusa_kasir/core/constants/app_constants.dart';

class SecureStore {
  const SecureStore._();
  static const _s = FlutterSecureStorage();
  static Future<void> saveActivation(String key) =>
      _s.write(key: AppConstants.activationKey, value: key);
  static Future<String?> getActivation() => _s.read(key: AppConstants.activationKey);
  static Future<void> clearActivation() => _s.delete(key: AppConstants.activationKey);
  static Future<void> saveSheetsTokens(String json) =>
      _s.write(key: AppConstants.sheetsTokenKey, value: json);
  static Future<String?> getSheetsTokens() => _s.read(key: AppConstants.sheetsTokenKey);
  static Future<void> clearSheetsTokens() => _s.delete(key: AppConstants.sheetsTokenKey);
}
