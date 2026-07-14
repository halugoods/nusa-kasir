import 'dart:io';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:nusa_kasir/core/activation/activation_key.dart';
import 'package:nusa_kasir/core/activation/activation_public_key.dart';
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

  Future<bool> get isActivated async =>
      (await SecureStore.getActivation()) != null;

  /// Activate with Google ID (new flow).
  /// - Verifies Ed25519 signature locally
  /// - Sends key + googleUserId to register_activation edge function
  /// - Links license ↔ Google ID in cloud
  Future<ActivationResult> activate(String rawKey, String googleUserId) async {
    final key = rawKey.trim().toUpperCase();
    final valid = await ActivationKey.verify(key, nusaActivationPublicKey);
    if (!valid) return ActivationResult(false, 'Key tidak valid');

    await SecureStore.saveActivation(key);

    if (client != null) {
      try {
        final res = await client!.functions.invoke('register_activation',
            body: {'key': key, 'googleUserId': googleUserId});
        if (res.status >= 400) {
          final data = res.data as Map<String, dynamic>?;
          final err = data?['error'] as String? ?? 'Aktivasi gagal';
          if (res.status == 403) {
            await SecureStore.clearActivation();
            return ActivationResult(false, 'Key dibatalkan atau tidak valid');
          }
          if (res.status == 409) {
            await SecureStore.clearActivation();
            return ActivationResult(false,
                data?['message'] as String? ?? 'Akun Google sudah dipakai untuk license lain');
          }
          await SecureStore.clearActivation();
          return ActivationResult(false, err);
        }
      } catch (_) {
        // offline: keep local activation
      }
    }
    return ActivationResult(true);
  }

  /// Build the backup path using the stored Google user ID.
  static Future<String?> _backupPath() async {
    final uid = await SecureStore.read(key: 'nusa_google_user_id');
    if (uid == null) return null;
    return '$uid/backup.sqlite.enc';
  }

  /// Check if an encrypted backup exists in Supabase Storage for the linked Google account.
  Future<bool> hasBackup() async {
    if (client == null) return false;
    final uid = await SecureStore.read(key: 'nusa_google_user_id');
    if (uid == null) return false;
    try {
      final res = await client!.storage
          .from('nusa-backups')
          .list(path: uid);
      return res.any((f) => f.name == 'backup.sqlite.enc');
    } catch (_) {
      return false;
    }
  }

  Future<bool> uploadBackup(String key) async {
    if (client == null) return false;
    final path = await _backupPath();
    if (path == null) return false;
    try {
      final dir = await getApplicationDocumentsDirectory();
      final file = File(p.join(dir.path, 'nusa_kasir.sqlite'));
      if (!await file.exists()) return false;
      final raw = await file.readAsBytes();
      final encrypted = await BackupCrypto.encrypt(raw, key);
      await client!.storage.from('nusa-backups').uploadBinary(
        path,
        encrypted,
        fileOptions: const FileOptions(upsert: true, contentType: 'application/octet-stream'),
      );
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Download encrypted backup and stage it for restore on next launch.
  Future<bool> downloadAndRestore(String key) async {
    if (client == null) return false;
    final path = await _backupPath();
    if (path == null) return false;
    try {
      final bytes = await client!.storage
          .from('nusa-backups')
          .download(path);
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
