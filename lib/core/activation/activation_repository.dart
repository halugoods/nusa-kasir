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

  /// Get the Google user ID (used as encryption key for backups).
  static Future<String?> _googleUserId() async =>
      SecureStore.read(key: 'nusa_google_user_id');

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
    final uid = await _googleUserId();
    if (uid == null) return null;
    return '$uid/backup.sqlite.enc';
  }

  /// Check if an encrypted backup exists in Supabase Storage for the linked Google account.
  Future<bool> hasBackup() async {
    if (client == null) return false;
    final uid = await _googleUserId();
    if (uid == null) return false;
    try {
      final res = await client!.storage.from('nusa-backups').list(path: uid);
      return res.any((f) => f.name == 'backup.sqlite.enc');
    } catch (_) {
      return false;
    }
  }

  /// Get the cloud backup's last-modified timestamp.
  Future<DateTime?> getBackupTimestamp() async {
    if (client == null) return null;
    final uid = await _googleUserId();
    if (uid == null) return null;
    try {
      final res = await client!.storage.from('nusa-backups').list(path: uid);
      for (final f in res) {
        if (f.name == 'backup.sqlite.enc') {
          return f.updatedAt != null ? DateTime.tryParse(f.updatedAt!) : null;
        }
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  /// Upload current local DB to cloud. Uses Google user ID for encryption.
  Future<bool> uploadBackupNow() async {
    if (client == null) return false;
    final uid = await _googleUserId();
    if (uid == null) return false;
    final path = '$uid/backup.sqlite.enc';
    try {
      final dir = await getApplicationDocumentsDirectory();
      final file = File(p.join(dir.path, 'nusa_kasir.sqlite'));
      if (!await file.exists()) return false;
      final raw = await file.readAsBytes();
      final encrypted = await BackupCrypto.encrypt(raw, uid);
      await client!.storage.from('nusa-backups').uploadBinary(
        path,
        encrypted,
        fileOptions: const FileOptions(upsert: true, contentType: 'application/octet-stream'),
      );
      await SecureStore.saveLastBackupTime(DateTime.now());
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Download backup from cloud and stage it for restore on next launch.
  /// Uses Google user ID for decryption.
  Future<bool> restoreFromCloud() async {
    if (client == null) return false;
    final uid = await _googleUserId();
    if (uid == null) return false;
    final path = '$uid/backup.sqlite.enc';
    try {
      final bytes = await client!.storage.from('nusa-backups').download(path);
      if (bytes.isEmpty) return false;
      final decrypted = await BackupCrypto.decrypt(bytes, uid);
      final dir = await getApplicationDocumentsDirectory();
      final pending = File(p.join(dir.path, 'nusa_kasir.sqlite.pending'));
      await pending.writeAsBytes(decrypted, flush: true);
      await SecureStore.savePendingRestore();
      return true;
    } catch (_) {
      return false;
    }
  }

  // ── Legacy methods (kept for backward compatibility with old activation-key based backups) ──

  /// Upload using old activation-key encryption. Used for migration.
  @Deprecated('Use uploadBackupNow() which encrypts with Google ID')
  Future<bool> uploadBackup(String activationKey) async {
    if (client == null) return false;
    final uid = await _googleUserId();
    if (uid == null) return false;
    final path = '$uid/backup.sqlite.enc';
    try {
      final dir = await getApplicationDocumentsDirectory();
      final file = File(p.join(dir.path, 'nusa_kasir.sqlite'));
      if (!await file.exists()) return false;
      final raw = await file.readAsBytes();
      final encrypted = await BackupCrypto.encrypt(raw, activationKey);
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

  @Deprecated('Use restoreFromCloud() which decrypts with Google ID')
  Future<bool> downloadAndRestore(String activationKey) async {
    if (client == null) return false;
    final path = await _backupPath();
    if (path == null) return false;
    try {
      final bytes = await client!.storage.from('nusa-backups').download(path);
      if (bytes.isEmpty) return false;
      final decrypted = await BackupCrypto.decrypt(bytes, activationKey);
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
