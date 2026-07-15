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

  /// Pack multiple (filename, bytes) pairs into a single binary archive.
  ///
  /// Format:
  ///   "NUS1" (magic 4 bytes)
  ///   fileCount (uint32 LE)
  ///   For each file:
  ///     nameLen (uint16 LE)
  ///     name (UTF-8 bytes)
  ///     dataLen (uint32 LE)
  ///     data (raw bytes)
  static Uint8List packFiles(Map<String, Uint8List> files) {
    final entries = files.entries.toList();
    // Calculate total size
    var total = 4 + 4; // magic + count
    for (final e in entries) {
      total += 2 + e.key.length + 4 + e.value.length;
    }
    final buf = ByteData(total);
    var offset = 0;

    // Magic
    buf.setUint8(offset++, 0x4E); // N
    buf.setUint8(offset++, 0x55); // U
    buf.setUint8(offset++, 0x53); // S
    buf.setUint8(offset++, 0x31); // 1

    // File count
    buf.setUint32(offset, entries.length, Endian.little);
    offset += 4;

    // Files
    for (final e in entries) {
      final nameBytes = utf8.encode(e.key);
      buf.setUint16(offset, nameBytes.length, Endian.little);
      offset += 2;
      for (var i = 0; i < nameBytes.length; i++) {
        buf.setUint8(offset++, nameBytes[i]);
      }
      buf.setUint32(offset, e.value.length, Endian.little);
      offset += 4;
      for (var i = 0; i < e.value.length; i++) {
        buf.setUint8(offset++, e.value[i]);
      }
    }
    return buf.buffer.asUint8List();
  }

  /// Unpack a binary archive back to a map of filename → bytes.
  static Map<String, Uint8List> unpackFiles(Uint8List data) {
    final result = <String, Uint8List>{};
    final buf = ByteData.sublistView(data);
    var offset = 0;

    // Magic
    if (buf.getUint8(offset++) != 0x4E ||
        buf.getUint8(offset++) != 0x55 ||
        buf.getUint8(offset++) != 0x53 ||
        buf.getUint8(offset++) != 0x31) {
      // Not our archive format — treat as raw SQLite (legacy)
      result['nusa_kasir.sqlite'] = data;
      return result;
    }

    final count = buf.getUint32(offset, Endian.little);
    offset += 4;

    for (var f = 0; f < count; f++) {
      final nameLen = buf.getUint16(offset, Endian.little);
      offset += 2;
      final name = utf8.decode(data.sublist(offset, offset + nameLen));
      offset += nameLen;
      final dataLen = buf.getUint32(offset, Endian.little);
      offset += 4;
      result[name] = data.sublist(offset, offset + dataLen);
      offset += dataLen;
    }
    return result;
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
