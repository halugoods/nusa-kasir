import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:cryptography/cryptography.dart';

/// Encrypts/decrypts the local SQLite backup using AES-256-GCM.
///
/// Key is derived from the Google user ID (SHA-256), so any device logged into
/// the same Google account can decrypt the backup. No activation key needed.
///
/// Data is gzip-compressed before encryption to reduce storage (~5x-10x).
class BackupCrypto {
  static final _aes = AesGcm.with256bits();

  /// Derive a 32-byte key from the Google user ID.
  static Future<SecretKey> _deriveKey(String googleUserId) async {
    final alg = Sha256();
    final hash = await alg.hash(utf8.encode(googleUserId));
    return SecretKey(hash.bytes);
  }

  /// Gzip compress data.
  static List<int> _gzip(List<int> data) {
    final compressed = GZipCodec().encode(data);
    return compressed;
  }

  /// Gzip decompress data.
  static List<int> _gunzip(List<int> data) {
    final decompressed = GZipCodec().decode(data);
    return decompressed;
  }

  /// Encrypt [plaintext] → gzip → [nonce(12)] + [ciphertext] + [mac(16)].
  static Future<Uint8List> encrypt(List<int> plaintext, String googleUserId) async {
    final secretKey = await _deriveKey(googleUserId);
    final compressed = _gzip(plaintext);
    final nonce = _aes.newNonce();
    final box = await _aes.encrypt(
      compressed,
      secretKey: secretKey,
      nonce: nonce,
    );
    final out = Uint8List(nonce.length + box.cipherText.length + box.mac.bytes.length);
    var i = 0;
    out.setAll(i, nonce);
    i += nonce.length;
    out.setAll(i, box.cipherText);
    i += box.cipherText.length;
    out.setAll(i, box.mac.bytes);
    return out;
  }

  /// Decrypt [data] (nonce + ciphertext + mac) → gunzip → plaintext bytes.
  static Future<List<int>> decrypt(Uint8List data, String googleUserId) async {
    final secretKey = await _deriveKey(googleUserId);
    const nonceLen = 12;
    const macLen = 16;
    if (data.length < nonceLen + macLen) throw Exception('Data terlalu pendek');
    final nonce = data.sublist(0, nonceLen);
    final cipherText = data.sublist(nonceLen, data.length - macLen);
    final macBytes = data.sublist(data.length - macLen);
    final box = SecretBox(cipherText, nonce: nonce, mac: Mac(macBytes));
    final compressed = await _aes.decrypt(box, secretKey: secretKey);
    return _gunzip(compressed);
  }
}
