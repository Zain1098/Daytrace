import 'dart:convert';
import 'dart:io';

import 'package:daytrace/core/database/app_database.dart';
import 'package:drift/drift.dart';
import 'package:file_picker/file_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

class BackupService {
  BackupService(this._database);
  final AppDatabase _database;

  static const List<String> _tables = <String>[
    'categories',
    'tasks',
    'subtasks',
    'time_entries',
    'reminders',
    'recurrence_rules',
    'daily_notes',
    'generated_summaries',
    'app_settings',
  ];

  Future<File> createBackupFile() async {
    await _database.initialize();
    final Map<String, Object?> data = <String, Object?>{};
    for (final String table in _tables) {
      data[table] = await _database.select('SELECT * FROM $table');
    }
    final Map<String, Object?> backup = <String, Object?>{
      'format': 'daytrace-backup',
      'schemaVersion': _database.schemaVersion,
      'createdAtUtc': DateTime.now().toUtc().toIso8601String(),
      'data': data,
    };
    final Directory directory = await getTemporaryDirectory();
    final String stamp = DateTime.now()
        .toUtc()
        .toIso8601String()
        .replaceAll(':', '-')
        .split('.')
        .first;
    final File file = File(
      '${directory.path}${Platform.pathSeparator}daytrace-backup-$stamp.json',
    );
    return file.writeAsString(
      const JsonEncoder.withIndent('  ').convert(backup),
      flush: true,
    );
  }

  Future<void> shareBackup() async {
    final File file = await createBackupFile();
    await SharePlus.instance.share(
      ShareParams(files: <XFile>[XFile(file.path)], subject: 'DayTrace backup'),
    );
  }

  Future<File> clearAllDataWithSafetyBackup() async {
    final File safetyBackup = await createBackupFile();
    await _database.clearAllUserData();
    return safetyBackup;
  }

  Future<bool> pickAndRestore() async {
    final List<PlatformFile> files = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: <String>['json'],
      allowMultiple: false,
    );
    if (files.isEmpty) return false;
    final PlatformFile picked = files.single;
    final String content = utf8.decode(await picked.readAsBytes());
    await restoreJson(content);
    return true;
  }

  Future<void> restoreJson(String content) async {
    final Map<String, dynamic> backup = _validate(content);
    // A recoverable copy is always made before replace-all restoration.
    await createBackupFile();
    final Map<String, dynamic> data = backup['data']! as Map<String, dynamic>;
    await _database.initialize();
    await _database.transaction<void>((QueryExecutor executor) async {
      for (final String table in <String>[
        'generated_summaries',
        'daily_notes',
        'reminders',
        'time_entries',
        'subtasks',
        'tasks',
        'recurrence_rules',
        'categories',
        'app_settings',
      ]) {
        await executor.runDelete('DELETE FROM $table', const <Object?>[]);
      }
      for (final String table in <String>[
        'categories',
        'recurrence_rules',
        'tasks',
        'subtasks',
        'time_entries',
        'reminders',
        'daily_notes',
        'generated_summaries',
        'app_settings',
      ]) {
        final List<dynamic> rows = data[table]! as List<dynamic>;
        for (final dynamic value in rows) {
          final Map<String, dynamic> row = Map<String, dynamic>.from(
            value as Map,
          );
          final List<String> columns = row.keys.toList(growable: false);
          if (columns.any((String key) => !RegExp(r'^[a-z_]+$').hasMatch(key))) {
            throw const FormatException(
              'Backup contains an invalid column name.',
            );
          }
          final String marks = List<String>.filled(
            columns.length,
            '?',
          ).join(', ');
          await executor.runInsert(
            'INSERT INTO $table (${columns.join(', ')}) VALUES ($marks)',
            columns
                .map<Object?>((String key) => row[key])
                .toList(growable: false),
          );
        }
      }
    });
  }

  Map<String, dynamic> _validate(String content) {
    final dynamic decoded = jsonDecode(content);
    if (decoded is! Map) {
      throw const FormatException('This is not a DayTrace backup.');
    }
    final Map<String, dynamic> backup = Map<String, dynamic>.from(decoded);
    if (backup['format'] != 'daytrace-backup') {
      throw const FormatException('This backup belongs to another app.');
    }
    if (backup['schemaVersion'] is! int ||
        (backup['schemaVersion'] as int) > _database.schemaVersion) {
      throw const FormatException(
        'This backup requires a newer DayTrace version.',
      );
    }
    if (backup['data'] is! Map) {
      throw const FormatException('Backup data is missing.');
    }
    final Map<String, dynamic> data = Map<String, dynamic>.from(
      backup['data'] as Map,
    );
    for (final String table in _tables) {
      if (data[table] is! List) {
        throw FormatException('Backup table $table is missing.');
      }
    }
    return backup;
  }
}
