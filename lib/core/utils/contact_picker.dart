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
  } catch (e) {
    return null;
  }
}
