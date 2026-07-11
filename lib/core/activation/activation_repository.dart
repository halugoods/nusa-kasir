import 'dart:io';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:nusa_kasir/core/activation/activation_key.dart';
import 'package:nusa_kasir/core/activation/activation_public_key.dart';
import 'package:nusa_kasir/core/utils/device_id.dart';
import 'package:nusa_kasir/core/utils/secure_storage.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:nusa_kasir/core/services/backup_crypto.dart';

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

  /// Check if an encrypted backup exists in Supabase Storage for this key.
  Future<bool> hasBackup(String key) async {
    if (client == null) return false;
    try {
      final sanitizedKey = key.replaceAll(RegExp(r'[^A-Za-z0-9]'), '_');
      final res = await client!.storage
          .from('nusa-backups')
          .list(path: sanitizedKey);
      return res.isNotEmpty;
    } catch (_) {
      return false;
    }
  }

  Future<bool> uploadBackup(String key) async {
    if (client == null) return false;
    try {
      final dir = await getApplicationDocumentsDirectory();
      final file = File(p.join(dir.path, 'nusa_kasir.sqlite'));
      if (!await file.exists()) return false;
      final raw = await file.readAsBytes();
      final encrypted = await BackupCrypto.encrypt(raw, key);
      final sanitizedKey = key.replaceAll(RegExp(r'[^A-Za-z0-9]'), '_');
      await client!.storage.from('nusa-backups').uploadBinary(
        '$sanitizedKey/backup.sqlite.enc',
        encrypted,
        fileOptions: const FileOptions(upsert: true, contentType: 'application/octet-stream'),
      );
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Download encrypted backup and stage it for restore on next launch.
  /// We cannot write the live DB file while the app holds it open, so we
  /// save to a .pending file and set a flag; main.dart swaps it before
  /// the database is opened.
  Future<bool> downloadAndRestore(String key) async {
    if (client == null) return false;
    try {
      final sanitizedKey = key.replaceAll(RegExp(r'[^A-Za-z0-9]'), '_');
      final bytes = await client!.storage
          .from('nusa-backups')
          .download('$sanitizedKey/backup.sqlite.enc');
      if (bytes.isEmpty) return false;
      final decrypted = await BackupCrypto.decrypt(bytes, key);
      final dir = await getApplicationDocumentsDirectory();
      final pending = File(p.join(dir.path, 'nusa_kasir.sqlite.pending'));
      await pending.writeAsBytes(decrypted, flush: true);
      await SecureStore.savePendingRestore();
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<void> deactivate() async => SecureStore.clearActivation();
}
