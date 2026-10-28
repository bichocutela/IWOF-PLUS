import 'dart:convert';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;

const releasesUrl = 'https://github.com/bichocutela/IWOF-PLUS/releases';
const releaseApiUrl =
    'https://api.github.com/repos/bichocutela/IWOF-PLUS/releases/latest';

class InstalledVersion {
  const InstalledVersion(this.name, this.code);
  final String name;
  final int code;
}

class AvailableRelease {
  const AvailableRelease({
    required this.version,
    required this.apkUrl,
    required this.sha256,
  });
  final String version;
  final String apkUrl;
  final String sha256;
}

class AppUpdates {
  AppUpdates({http.Client? client}) : _client = client ?? http.Client();
  final http.Client _client;

  static const platform = MethodChannel('br.com.iwofplus.iwof_plus/updates');
  static const downloadProgress =
      EventChannel('br.com.iwofplus.iwof_plus/update_progress');

  static int compareVersions(String left, String right) {
    final expression = RegExp(r'^v?(\d+)\.(\d+)\.(\d+)$');
    final first = expression.firstMatch(left);
    final second = expression.firstMatch(right);
    if (first == null || second == null) {
      throw const FormatException('Versão do aplicativo inválida.');
    }
    for (var part = 1; part <= 3; part++) {
      final result = int.parse(first.group(part)!)
          .compareTo(int.parse(second.group(part)!));
      if (result != 0) return result;
    }
    return 0;
  }

  Future<InstalledVersion> installedVersion() async {
    final data = await platform.invokeMapMethod<String, dynamic>(
      'installedVersion',
    );
    if (data == null) throw Exception('Versão instalada indisponível.');
    return InstalledVersion(
      data['name'] as String,
      (data['code'] as num).toInt(),
    );
  }

  Future<AvailableRelease?> latestRelease() async {
    final response = await _client
        .get(
          Uri.parse(releaseApiUrl),
          headers: const {
            'Accept': 'application/vnd.github+json',
            'User-Agent': 'IWOF-PLUS-Android',
          },
        )
        .timeout(const Duration(seconds: 18));
    if (response.statusCode == 404) return null;
    if (response.statusCode != 200) {
      throw Exception('Não foi possível consultar atualizações (${response.statusCode}).');
    }
    final body = jsonDecode(response.body) as Map<String, dynamic>;
    final tag = body['tag_name'] as String? ?? '';
    compareVersions(tag, tag);
    final assets = body['assets'] as List<dynamic>? ?? [];
    Map<String, dynamic>? apk;
    for (final item in assets) {
      final entry = Map<String, dynamic>.from(item as Map);
      if (entry['name'] == 'IWOF-PLUS-arm64.apk') {
        apk = entry;
        break;
      }
    }
    if (apk == null) throw Exception('Esta release não contém o APK ARM64.');
    final url = apk['browser_download_url'] as String? ?? '';
    final digest = apk['digest'] as String? ?? '';
    if (!url.startsWith('$releasesUrl/download/') ||
        !RegExp(r'^sha256:[a-fA-F0-9]{64}$').hasMatch(digest)) {
      throw Exception('Release sem endereço ou SHA-256 verificável.');
    }
    return AvailableRelease(
      version: tag.replaceFirst(RegExp(r'^v'), ''),
      apkUrl: url,
      sha256: digest.substring(7),
    );
  }

  Future<void> install(AvailableRelease release) async {
    await platform.invokeMethod<void>('downloadAndInstall', {
      'url': release.apkUrl,
      'sha256': release.sha256,
    });
  }

  void close() => _client.close();
}
