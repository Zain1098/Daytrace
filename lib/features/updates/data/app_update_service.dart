import 'dart:convert';

import 'package:daytrace/core/database/app_database.dart';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';

class AppUpdateService {
  AppUpdateService(this._database, {http.Client? client}) : _client = client ?? http.Client();
  final AppDatabase _database;
  final http.Client _client;

  static const String defaultRepository = 'Zain1098/Daytrace';

  Future<UpdateConfig> loadConfig() async {
    await _database.initialize();
    final List<Map<String, Object?>> rows = await _database.select("SELECT key, value_json FROM app_settings WHERE key IN ('update_github_repository', 'update_apk_url')");
    final Map<String, String> values = <String, String>{for (final Map<String, Object?> row in rows) row['key']! as String: jsonDecode(row['value_json']! as String) as String};
    return UpdateConfig(repository: values['update_github_repository'] ?? defaultRepository, directApkUrl: values['update_apk_url'] ?? '');
  }

  Future<void> saveConfig(UpdateConfig config) async {
    await _database.initialize();
    final int now = DateTime.now().toUtc().millisecondsSinceEpoch;
    for (final MapEntry<String, String> entry in <String, String>{'update_github_repository': config.repository.trim(), 'update_apk_url': config.directApkUrl.trim()}.entries) {
      await _database.insert('INSERT OR REPLACE INTO app_settings (key, value_json, updated_at) VALUES (?, ?, ?)', <Object?>[entry.key, jsonEncode(entry.value), now]);
    }
  }

  Future<AppUpdateInfo> checkForUpdate() async {
    final UpdateConfig config = await loadConfig();
    final PackageInfo package = await PackageInfo.fromPlatform();
    final Uri api = Uri.https('api.github.com', '/repos/${config.repository}/releases/latest');
    final http.Response response = await _client.get(api, headers: const <String, String>{'Accept': 'application/vnd.github+json', 'User-Agent': 'DayTrace-update-check'});
    if (response.statusCode != 200) throw StateError('Could not check GitHub release (${response.statusCode}).');
    final Map<String, dynamic> release = jsonDecode(response.body) as Map<String, dynamic>;
    final String tag = release['tag_name'] as String? ?? '';
    final List<dynamic> assets = release['assets'] as List<dynamic>? ?? const <dynamic>[];
    final String assetUrl = assets.cast<Map<dynamic, dynamic>>().map((Map<dynamic, dynamic> item) => item['browser_download_url'] as String?).whereType<String>().firstWhere((String url) => url.toLowerCase().endsWith('.apk'), orElse: () => '');
    final String url = config.directApkUrl.isNotEmpty ? config.directApkUrl : (assetUrl ?? '');
    if (url.isEmpty) throw StateError('Latest release has no APK asset or download URL.');
    final int? latestBuild = _buildNumber(tag);
    final int currentBuild = int.tryParse(package.buildNumber) ?? 0;
    return AppUpdateInfo(currentVersion: '${package.version}+${package.buildNumber}', latestTag: tag, downloadUrl: url, isAvailable: latestBuild != null && latestBuild > currentBuild);
  }

  Future<void> openDownload(String url) async {
    final bool opened = await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
    if (!opened) throw StateError('Could not open the APK download.');
  }

  int? _buildNumber(String tag) {
    final RegExpMatch? match = RegExp(r'\+(\d+)$').firstMatch(tag.trim());
    return match == null ? null : int.tryParse(match.group(1)!);
  }
}

class UpdateConfig {
  const UpdateConfig({required this.repository, required this.directApkUrl});
  final String repository;
  final String directApkUrl;
}

class AppUpdateInfo {
  const AppUpdateInfo({required this.currentVersion, required this.latestTag, required this.downloadUrl, required this.isAvailable});
  final String currentVersion;
  final String latestTag;
  final String downloadUrl;
  final bool isAvailable;
}
