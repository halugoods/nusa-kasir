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
/// The handler is registered ONCE (statically). Each call creates its own
/// [Completer] so concurrent or back-to-back calls don't interfere.
class ContactPicker {
  static const _channel = MethodChannel('com.nusa_kasir/contacts');
  static Completer<Map<String, String>?>? _completer;
  static bool _initialized = false;

  static void _init() {
    if (_initialized) return;
    _initialized = true;

    _channel.setMethodCallHandler((call) async {
      if (call.method == 'onContactResult') {
        final c = _completer;
        if (c == null || c.isCompleted) {
          debugPrint('[ContactPicker] onContactResult received but no active completer');
          return;
        }
        if (call.arguments == null) {
          debugPrint('[ContactPicker] onContactResult: null (user cancelled)');
          c.complete(null);
        } else {
          final data = Map<String, dynamic>.from(call.arguments as Map);
          final result = {
            'name': (data['name'] as String?) ?? '',
            'phone': (data['phone'] as String?) ?? '',
          };
          debugPrint('[ContactPicker] onContactResult: name="${result["name"]}" phone="${result["phone"]}"');
          c.complete(result);
        }
      }
    });
  }

  /// Opens the native contact picker. Returns the selected contact or null.
  static Future<Map<String, String>?> pickContact() async {
    _init(); // handler registered once

    // Create a fresh completer for this call
    _completer = Completer<Map<String, String>?>();

    try {
      final launched = await _channel
          .invokeMethod<bool>('pickContact')
          .timeout(const Duration(seconds: 10));

      debugPrint('[ContactPicker] pickContact launched=$launched');

      if (launched != true) {
        _completer = null;
        return null;
      }

      final result = await _completer!.future.timeout(
        const Duration(seconds: 60),
        onTimeout: () {
          debugPrint('[ContactPicker] Timed out waiting for onContactResult');
          return null;
        },
      );
      debugPrint('[ContactPicker] returning: $result');
      return result;
    } on MissingPluginException {
      debugPrint('[ContactPicker] MissingPluginException');
      _completer = null;
      return null;
    } on PlatformException catch (e) {
      debugPrint('[ContactPicker] PlatformException: ${e.code} — ${e.message}');
      _completer = null;
      return null;
    } catch (e) {
      debugPrint('[ContactPicker] Unexpected error: $e');
      _completer = null;
      return null;
    }
  }
}

/// Convenience wrapper for backwards compatibility.
Future<Map<String, String>?> pickContact() => ContactPicker.pickContact();
