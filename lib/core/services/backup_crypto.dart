import 'dart:convert';
import 'dart:typed_data';
import 'package:cryptography/cryptography.dart';

/// Encrypts/decrypts the local SQLite backup using AES-256-GCM.
///
/// The activation key (serial part) is used to derive a 256-bit key via
/// SHA-256, so Supabase Storage only ever holds ciphertext — it never sees
/// plaintext PINs or customer PII.
class BackupCrypto {
  static final _aes = AesGcm.with256bits();

  /// Derive a 32-byte key from the activation key string.
  static Future<SecretKey> _deriveKey(String key) async {
    final alg = Sha256();
    final hash = await alg.hash(utf8.encode(key));
    return SecretKey(hash.bytes);
  }

  /// Encrypt [plaintext] → [nonce(12)] + [ciphertext] + [mac(16)].
  static Future<Uint8List> encrypt(List<int> plaintext, String key) async {
    final secretKey = await _deriveKey(key);
    final nonce = _aes.newNonce();
    final box = await _aes.encrypt(
      plaintext,
      secretKey: secretKey,
      nonce: nonce,
    );
    // Pack nonce + cipherText + mac into one blob for upload.
    final out = Uint8List(
        nonce.length + box.cipherText.length + box.mac.bytes.length);
    var i = 0;
    out.setAll(i, nonce);
    i += nonce.length;
    out.setAll(i, box.cipherText);
    i += box.cipherText.length;
    out.setAll(i, box.mac.bytes);
    return out;
  }

  /// Decrypt [data] (nonce + ciphertext + mac) → plaintext bytes.
  static Future<List<int>> decrypt(Uint8List data, String key) async {
    final secretKey = await _deriveKey(key);
    const nonceLen = 12;
    const macLen = 16;
    if (data.length < nonceLen + macLen) throw Exception('Data terlalu pendek');
    final nonce = data.sublist(0, nonceLen);
    final cipherText = data.sublist(nonceLen, data.length - macLen);
    final macBytes = data.sublist(data.length - macLen);
    final box = SecretBox(cipherText, nonce: nonce, mac: Mac(macBytes));
    final plain = await _aes.decrypt(box, secretKey: secretKey);
    return plain;
  }
}
