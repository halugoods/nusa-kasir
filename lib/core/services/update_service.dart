import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:nusa_kasir/core/config/nusa_config.dart';

/// Result of an update check.
@immutable
class UpdateInfo {
  final bool hasUpdate;
  final String? latestVersion;
  final int? latestBuildNumber;
  final String? downloadUrl;
  final String? changelog;
  final int? fileSizeBytes;

  const UpdateInfo({
    required this.hasUpdate,
    this.latestVersion,
    this.latestBuildNumber,
    this.downloadUrl,
    this.changelog,
    this.fileSizeBytes,
  });

  factory UpdateInfo.noUpdate() => const UpdateInfo(hasUpdate: false);
}

/// Checks GitHub Releases for newer versions.
///
/// Release tags must follow the format `v1.0.0+2` where the suffix
/// after `+` is the build number (must be an integer > current build).
class UpdateService {
  static const _apiBase = 'https://api.github.com';
  static const _userAgent = 'nusa-kasir-updater';
  static const Duration _timeout = Duration(seconds: 15);

  /// Fetches the latest release from GitHub and compares against the
  /// current build number defined in [NusaConfig].
  static Future<UpdateInfo> checkForUpdate() async {
    try {
      final client = HttpClient();
      client.connectionTimeout = _timeout;
      final req = await client.getUrl(
        Uri.parse('$_apiBase/repos/${NusaConfig.githubRepo}/releases/latest'),
      );
      req.headers.set(HttpHeaders.acceptHeader, 'application/vnd.github+json');
      req.headers.set(HttpHeaders.userAgentHeader, _userAgent);
      final res = await req.close().timeout(_timeout);

      if (res.statusCode != 200) return UpdateInfo.noUpdate();

      final body = await res.transform(utf8.decoder).join();
      final json = jsonDecode(body) as Map<String, dynamic>;

      final tag = (json['tag_name'] as String?) ?? '';
      final parsed = _parseTag(tag);
      if (parsed == null) return UpdateInfo.noUpdate();

      final (version, buildNumber) = parsed;

      if (buildNumber <= NusaConfig.appBuildNumber) {
        return UpdateInfo.noUpdate();
      }

      // Find the APK asset
      String? downloadUrl;
      int? fileSizeBytes;
      final assets = (json['assets'] as List<dynamic>?) ?? [];
      for (final asset in assets) {
        final name = (asset['name'] as String?) ?? '';
        if (name.endsWith('.apk')) {
          downloadUrl = (asset['browser_download_url'] as String?) ?? '';
          fileSizeBytes = (asset['size'] as int?) ?? 0;
          break;
        }
      }

      return UpdateInfo(
        hasUpdate: true,
        latestVersion: version,
        latestBuildNumber: buildNumber,
        downloadUrl: downloadUrl,
        changelog: (json['body'] as String?) ?? '',
        fileSizeBytes: fileSizeBytes,
      );
    } on TimeoutException {
      return UpdateInfo.noUpdate();
    } catch (_) {
      return UpdateInfo.noUpdate();
    }
  }

  /// Parses a tag like "v1.2.3+5" → (version, buildNumber).
  /// Returns null if the tag doesn't match the expected format.
  static (String, int)? _parseTag(String tag) {
    final m = RegExp(r'^v?(\d+\.\d+\.\d+)\+(\d+)$').firstMatch(tag.trim());
    if (m == null) return null;
    return (m.group(1)!, int.parse(m.group(2)!));
  }

  /// Formats file size for display.
  static String formatSize(int? bytes) {
    if (bytes == null || bytes <= 0) return '';
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
}
