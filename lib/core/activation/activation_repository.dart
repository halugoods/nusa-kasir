import 'dart:io';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:nusa_kasir/core/activation/activation_key.dart';
import 'package:nusa_kasir/core/activation/activation_public_key.dart';
import 'package:nusa_kasir/core/utils/device_id.dart';
import 'package:nusa_kasir/core/utils/secure_storage.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

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

  Future<bool> uploadBackup(String key) async {
    if (client == null) return false;
    try {
      final dir = await getApplicationDocumentsDirectory();
      final file = File(p.join(dir.path, 'nusa_kasir.sqlite'));
      if (!await file.exists()) return false;
      final sanitizedKey = key.replaceAll(RegExp(r'[^A-Za-z0-9]'), '_');
      await client!.storage.from('nusa-backups').upload(
        '/backup.sqlite',
        file,
        fileOptions: const FileOptions(upsert: true),
      );
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<bool> downloadAndRestore(String key) async {
    if (client == null) return false;
    try {
      final sanitizedKey = key.replaceAll(RegExp(r'[^A-Za-z0-9]'), '_');
      final bytes = await client!.storage
          .from('nusa-backups')
          .download('/backup.sqlite');
      if (bytes.isEmpty) return false;
      final dir = await getApplicationDocumentsDirectory();
      final file = File(p.join(dir.path, 'nusa_kasir.sqlite'));
      await file.writeAsBytes(bytes, flush: true);
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<void> deactivate() async => SecureStore.clearActivation();
}
