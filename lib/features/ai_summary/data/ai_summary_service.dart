import 'dart:convert';

import 'package:daytrace/core/database/app_database.dart';
import 'package:daytrace/features/reports/data/report_repository.dart';
import 'package:http/http.dart' as http;
import 'package:uuid/uuid.dart';

class AiSummaryConfig {
  const AiSummaryConfig({this.enabled = false, this.endpoint = ''});

  final bool enabled;
  final String endpoint;

  bool get isReady => enabled && Uri.tryParse(endpoint)?.hasScheme == true;
}

/// Calls only a user-configured proxy after an explicit button press. No
/// provider secret or API key is persisted in the application.
class AiSummaryService {
  AiSummaryService(this._database, {http.Client? client}) : _client = client ?? http.Client();

  final AppDatabase _database;
  final http.Client _client;
  final Uuid _uuid = Uuid();

  Future<AiSummaryConfig> loadConfig() async {
    await _database.initialize();
    final List<Map<String, Object?>> rows = await _database.select(
      "SELECT value_json FROM app_settings WHERE key = 'ai_summary_config'",
    );
    if (rows.isEmpty) return const AiSummaryConfig();
    final Map<String, dynamic> value = jsonDecode(rows.single['value_json']! as String) as Map<String, dynamic>;
    return AiSummaryConfig(enabled: value['enabled'] == true, endpoint: value['endpoint'] as String? ?? '');
  }

  Future<void> saveConfig(AiSummaryConfig config) async {
    await _database.initialize();
    await _database.insert(
      "INSERT OR REPLACE INTO app_settings (key, value_json, updated_at) VALUES ('ai_summary_config', ?, ?)",
      <Object?>[jsonEncode(<String, Object>{'enabled': config.enabled, 'endpoint': config.endpoint.trim()}), DateTime.now().toUtc().millisecondsSinceEpoch],
    );
  }

  Future<String> generateDailySummary(DailyReport report) async {
    final AiSummaryConfig config = await loadConfig();
    if (!config.isReady) throw StateError('Enable AI summary and add a secure proxy URL in Settings first.');
    final Uri uri = Uri.parse(config.endpoint);
    if (uri.scheme != 'https') throw StateError('AI proxy URL must use HTTPS.');
    final Map<String, Object?> payload = <String, Object?>{
      'type': 'daytrace_daily_report',
      'date': report.day.toIso8601String(),
      'local_summary': report.localSummary,
      'tracked_minutes': report.trackedMinutes,
      'category_minutes': report.categoryMinutes,
    };
    final http.Response response = await _client.post(
      uri,
      headers: const <String, String>{'content-type': 'application/json'},
      body: jsonEncode(payload),
    ).timeout(const Duration(seconds: 20));
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw StateError('AI proxy returned HTTP ${response.statusCode}. Your local summary is unchanged.');
    }
    final Map<String, dynamic> result = jsonDecode(response.body) as Map<String, dynamic>;
    final String summary = result['summary'] as String? ?? '';
    if (summary.trim().isEmpty) throw StateError('AI proxy returned no summary. Your local summary is unchanged.');
    final DateTime start = DateTime(report.day.year, report.day.month, report.day.day).toUtc();
    await _database.insert(
      '''INSERT INTO generated_summaries
         (id, range_start, range_end, summary_type, content, provider, model, input_hash, created_at)
         VALUES (?, ?, ?, 'ai', ?, 'user-configured-proxy', ?, NULL, ?)''',
      <Object?>[_uuid.v4(), start.millisecondsSinceEpoch, start.add(const Duration(days: 1)).millisecondsSinceEpoch, summary.trim(), result['model'] as String?, DateTime.now().toUtc().millisecondsSinceEpoch],
    );
    return summary.trim();
  }
}
