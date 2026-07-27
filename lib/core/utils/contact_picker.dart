import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Opens the native contact picker and returns the selected contact's name & phone.
/// Returns null if the user cancels or an error occurs.
///
/// Architecture: one-way MethodChannel ('com.nusa_kasir/contacts'):
/// 1. Dart → Native: call `pickContact`, native opens OS contact picker
/// 2. Native → Dart: native calls `result.success({name, phone})` directly
///    (not invokeMethod), so the Dart `await invokeMethod` returns the data.
///
/// No completer, no handler registration — just plain async platform call.
class ContactPicker {
  static const _channel = MethodChannel('com.nusa_kasir/contacts');

  /// Opens the native contact picker. Returns the selected contact or null.
  static Future<Map<String, String>?> pickContact() async {
    try {
      // Native will hold this call's result until the user picks or cancels,
      // then reply in onActivityResult via result.success(map/null).
      final data = await _channel.invokeMethod<Map<dynamic, dynamic>>('pickContact');

      debugPrint('[ContactPicker] raw result: $data');

      if (data == null || data.isEmpty) {
        debugPrint('[ContactPicker] null/empty — user cancelled');
        return null;
      }

      final result = {
        'name': (data['name'] as String?) ?? '',
        'phone': (data['phone'] as String?) ?? '',
      };
      debugPrint('[ContactPicker] success: name="${result["name"]}" phone="${result["phone"]}"');
      return result;
    } on MissingPluginException {
      debugPrint('[ContactPicker] MissingPluginException');
      return null;
    } on PlatformException catch (e) {
      debugPrint('[ContactPicker] PlatformException: ${e.code} — ${e.message}');
      return null;
    } catch (e) {
      debugPrint('[ContactPicker] Unexpected error: $e');
      return null;
    }
  }
}

/// Convenience wrapper for backwards compatibility.
Future<Map<String, String>?> pickContact() => ContactPicker.pickContact();
