import 'dart:convert';

import 'package:daytrace/core/database/app_database.dart';
import 'package:flutter/material.dart';

class SettingsRepository {
  SettingsRepository(this._database);
  final AppDatabase _database;

  Future<TrackingSettings> loadTracking() async {
    await _database.initialize();
    final List<Map<String, Object?>> rows = await _database.select(
      "SELECT value_json FROM app_settings WHERE key = 'tracking_settings'",
    );
    if (rows.isEmpty) return const TrackingSettings();
    final Map<String, dynamic> value = jsonDecode(rows.single['value_json']! as String) as Map<String, dynamic>;
    return TrackingSettings(
      startHour: value['startHour'] as int? ?? 9,
      endHour: value['endHour'] as int? ?? 17,
      promptMinutes: value['promptMinutes'] as int? ?? 60,
    );
  }

  Future<void> saveTracking(TrackingSettings settings) async {
    await _database.initialize();
    await _database.insert(
      "INSERT OR REPLACE INTO app_settings (key, value_json, updated_at) VALUES ('tracking_settings', ?, ?)",
      <Object?>[jsonEncode(settings.toJson()), DateTime.now().toUtc().millisecondsSinceEpoch],
    );
  }

  Future<ThemeMode> loadThemeMode() async {
    await _database.initialize();
    final List<Map<String, Object?>> rows = await _database.select(
      "SELECT value_json FROM app_settings WHERE key = 'theme_mode'",
    );
    if (rows.isEmpty) return ThemeMode.system;
    final String value = jsonDecode(rows.single['value_json']! as String) as String;
    return switch (value) {
      'light' => ThemeMode.light,
      'dark' => ThemeMode.dark,
      _ => ThemeMode.system,
    };
  }

  Future<void> saveThemeMode(ThemeMode mode) async {
    await _database.initialize();
    final String value = switch (mode) {
      ThemeMode.light => 'light',
      ThemeMode.dark => 'dark',
      ThemeMode.system => 'system',
    };
    await _database.insert(
      "INSERT OR REPLACE INTO app_settings (key, value_json, updated_at) VALUES ('theme_mode', ?, ?)",
      <Object?>[jsonEncode(value), DateTime.now().toUtc().millisecondsSinceEpoch],
    );
  }
}

class TrackingSettings {
  const TrackingSettings({this.startHour = 9, this.endHour = 17, this.promptMinutes = 60});
  final int startHour;
  final int endHour;
  final int promptMinutes;
  Map<String, dynamic> toJson() => <String, dynamic>{'startHour': startHour, 'endHour': endHour, 'promptMinutes': promptMinutes};
}
