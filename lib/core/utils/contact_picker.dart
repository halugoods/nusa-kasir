import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Opens the native contact picker and returns the selected contact's name & phone.
/// Returns null if the user cancels or an error occurs.
///
/// Architecture: two-way MethodChannel ('com.nusa_kasir/contacts'):
/// 1. Dart → Native: `pickContact` → native opens contact picker, replies `true`
/// 2. Native → Dart: `onContactResult` → native sends back {name, phone} (or null)
///
/// This decouples from `MethodChannel.Result` lifecycle — the contact data is
/// stored in a Kotlin `companion object` (static) which survives Android activity
/// recreation. The native side calls `invokeMethod` to push the result to Dart.
Future<Map<String, String>?> pickContact() async {
  final completer = Completer<Map<String, String>?>();
  final channel = const MethodChannel('com.nusa_kasir/contacts');

  // Listen for the result pushed back from native
  channel.setMethodCallHandler((call) async {
    if (call.method == 'onContactResult') {
      if (completer.isCompleted) return;
      if (call.arguments == null) {
        completer.complete(null);
      } else {
        final data = Map<String, dynamic>.from(call.arguments as Map);
        completer.complete({
          'name': (data['name'] as String?) ?? '',
          'phone': (data['phone'] as String?) ?? '',
        });
      }
    }
  });

  try {
    // Launch the picker — native replies true immediately
    final launched = await channel
        .invokeMethod<bool>('pickContact')
        .timeout(const Duration(seconds: 10));

    if (launched != true) {
      return null;
    }

    // Wait for onContactResult from native (with timeout)
    final result = await completer.future.timeout(
      const Duration(seconds: 45),
      onTimeout: () {
        debugPrint('[ContactPicker] Timed out waiting for onContactResult');
        return null;
      },
    );
    return result;
  } on MissingPluginException {
    return null;
  } on PlatformException catch (e) {
    debugPrint('[ContactPicker] PlatformException: ${e.code} — ${e.message}');
    return null;
  } catch (e) {
    debugPrint('[ContactPicker] Unexpected error: $e');
    return null;
  }
}
