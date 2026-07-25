import 'package:flutter/services.dart';

/// Opens the native contact picker and returns the selected contact's name & phone.
/// Returns null if the user cancels or an error occurs.
Future<Map<String, String>?> pickContact() async {
  try {
    final result = await const MethodChannel('com.nusa_kasir/contacts')
        .invokeMethod<Map<dynamic, dynamic>>('pickContact');
    if (result == null) return null;
    return {
      'name': (result['name'] as String?) ?? '',
      'phone': (result['phone'] as String?) ?? '',
    };
  } on MissingPluginException {
    // Platform channel not implemented (e.g. iOS without native handler,
    // or running on desktop/web). Silently return null — caller should handle.
    return null;
  } on PlatformException catch (e) {
    // Native error — log and return null. Caller may show toast.
    debugPrint('[ContactPicker] PlatformException: ${e.code} — ${e.message}');
    return null;
  } catch (e) {
    debugPrint('[ContactPicker] Unexpected error: $e');
    return null;
  }
}
