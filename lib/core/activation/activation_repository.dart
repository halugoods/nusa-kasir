import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:nusa_kasir/core/activation/activation_key.dart';
import 'package:nusa_kasir/core/activation/activation_public_key.dart';
import 'package:nusa_kasir/core/utils/device_id.dart';
import 'package:nusa_kasir/core/utils/secure_storage.dart';

class ActivationResult {
  final bool ok;
  final String? error;
  ActivationResult(this.ok, [this.error]);
}

class ActivationRepository {
  final SupabaseClient? client;
  ActivationRepository(this.client);

  Future<bool> get isActivated async => (await SecureStore.getActivation()) != null;

  Future<ActivationResult> activate(String rawKey) async {
    final key = rawKey.trim().toUpperCase();
    final valid = await ActivationKey.verify(key, nusaActivationPublicKey);
    if (!valid) return ActivationResult(false, 'Key tidak valid');
    await SecureStore.saveActivation(key);
    if (client != null) {
      try {
        final deviceId = await getDeviceId();
        final res = await client!.functions.invoke('register_activation',
            body: {'key': key, 'deviceId': deviceId});
        if (res.status >= 400) {
          if (res.status == 409) {
            return ActivationResult(false, 'Key sudah dipakai di 2 device (hubungi seller)');
          }
          if (res.status == 403) {
            await SecureStore.clearActivation();
            return ActivationResult(false, 'Key dibatalkan');
          }
        }
      } catch (_) {
        // offline: keep local activation
      }
    }
    return ActivationResult(true);
  }

  Future<void> deactivate() async => SecureStore.clearActivation();
}
