import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';

/// Local SQLite entry point for the first task-and-timer vertical slice.
///
/// The wrapper intentionally exposes only safe raw operations while Phase 1 is
/// transitioning from the generator-free Phase 0 shell to typed Drift tables.
class AppDatabase implements QueryExecutorUser {
  AppDatabase({QueryExecutor? executor})
    : _executor = executor ?? driftDatabase(name: 'daytrace');

  final QueryExecutor _executor;

  @override
  int get schemaVersion => 4;

  Future<void> initialize() => _executor.ensureOpen(this);

  Future<List<Map<String, Object?>>> select(
    String statement, [
    List<Object?> arguments = const <Object?>[],
  ]) => _executor.runSelect(statement, arguments);

  Future<int> insert(
    String statement, [
    List<Object?> arguments = const <Object?>[],
  ]) => _executor.runInsert(statement, arguments);

  Future<int> update(
    String statement, [
    List<Object?> arguments = const <Object?>[],
  ]) => _executor.runUpdate(statement, arguments);

  Future<T> transaction<T>(Future<T> Function(QueryExecutor executor) action) async {
    final TransactionExecutor executor = _executor.beginTransaction();
    await executor.ensureOpen(this);
    try {
      final T result = await action(executor);
      await executor.send();
      return result;
    } catch (_) {
      await executor.rollback();
      rethrow;
    }
  }

  Future<void> close() => _executor.close();

  /// Removes user records only after a caller has created a recoverable backup.
  /// Schema migration history stays intact and the required default categories
  /// are immediately re-seeded in the same transaction.
  Future<void> clearAllUserData() async {
    await initialize();
    await transaction<void>((QueryExecutor executor) async {
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
      await _seedDefaultCategories(executor);
    });
  }

  @override
  Future<void> beforeOpen(QueryExecutor executor, OpeningDetails details) async {
    await executor.runCustom('PRAGMA foreign_keys = ON');
    await executor.runCustom('''
      CREATE TABLE IF NOT EXISTS categories (
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        icon_key TEXT,
        color_value INTEGER,
        sort_order INTEGER NOT NULL DEFAULT 0,
        is_system INTEGER NOT NULL DEFAULT 0 CHECK (is_system IN (0,1)),
        is_archived INTEGER NOT NULL DEFAULT 0 CHECK (is_archived IN (0,1)),
        created_at INTEGER NOT NULL,
        updated_at INTEGER NOT NULL,
        deleted_at INTEGER
      )
    ''');
    await executor.runCustom('''
      CREATE TABLE IF NOT EXISTS tasks (
        id TEXT PRIMARY KEY,
        title TEXT NOT NULL CHECK (length(trim(title)) > 0),
        description TEXT,
        category_id TEXT REFERENCES categories(id) ON DELETE SET NULL,
        status TEXT NOT NULL DEFAULT 'planned'
          CHECK (status IN ('planned','in_progress','paused','completed','cancelled','archived')),
        priority TEXT NOT NULL DEFAULT 'medium'
          CHECK (priority IN ('low','medium','high','urgent')),
        planned_at INTEGER,
        due_at INTEGER,
        estimated_minutes INTEGER CHECK (estimated_minutes IS NULL OR estimated_minutes >= 0),
        created_at INTEGER NOT NULL,
        updated_at INTEGER NOT NULL,
        completed_at INTEGER,
        cancelled_at INTEGER,
        recurrence_rule_id TEXT,
        notes TEXT,
        deleted_at INTEGER
      )
    ''');
    await executor.runCustom('''
      CREATE TABLE IF NOT EXISTS time_entries (
        id TEXT PRIMARY KEY,
        task_id TEXT REFERENCES tasks(id) ON DELETE SET NULL,
        category_id TEXT REFERENCES categories(id) ON DELETE SET NULL,
        entry_type TEXT NOT NULL DEFAULT 'task'
          CHECK (entry_type IN ('task','break','meeting','untracked','manual')),
        start_at INTEGER NOT NULL,
        end_at INTEGER,
        note TEXT,
        source TEXT NOT NULL DEFAULT 'app'
          CHECK (source IN ('app','notification','manual','voice','import')),
        created_at INTEGER NOT NULL,
        updated_at INTEGER NOT NULL,
        deleted_at INTEGER,
        CHECK (end_at IS NULL OR end_at > start_at)
      )
    ''');
    await executor.runCustom('''
      CREATE UNIQUE INDEX IF NOT EXISTS idx_one_open_time_entry
      ON time_entries((1)) WHERE end_at IS NULL AND deleted_at IS NULL
    ''');
    await executor.runCustom('''
      CREATE INDEX IF NOT EXISTS idx_tasks_status_due ON tasks(status)
    ''');
    await _applyVersion3Migration(executor);
    await _applyVersion4Migration(executor);
    await _seedDefaultCategories(executor);
  }

  Future<void> _applyVersion3Migration(QueryExecutor executor) async {
    await executor.runCustom('''
      CREATE TABLE IF NOT EXISTS schema_migrations (
        version INTEGER PRIMARY KEY,
        applied_at INTEGER NOT NULL,
        description TEXT NOT NULL
      )
    ''');
    final List<Map<String, Object?>> applied = await executor.runSelect(
      'SELECT version FROM schema_migrations WHERE version = 3',
      const <Object?>[],
    );
    if (applied.isNotEmpty) return;

    await _addColumnIfMissing(executor, 'tasks', 'description', 'TEXT');
    await _addColumnIfMissing(
      executor,
      'tasks',
      'priority',
      "TEXT NOT NULL DEFAULT 'medium'",
    );
    await _addColumnIfMissing(executor, 'tasks', 'planned_at', 'INTEGER');
    await _addColumnIfMissing(executor, 'tasks', 'due_at', 'INTEGER');
    await _addColumnIfMissing(executor, 'tasks', 'estimated_minutes', 'INTEGER');
    await _addColumnIfMissing(executor, 'tasks', 'cancelled_at', 'INTEGER');
    await _addColumnIfMissing(executor, 'tasks', 'recurrence_rule_id', 'TEXT');
    await _addColumnIfMissing(executor, 'tasks', 'notes', 'TEXT');
    await _addColumnIfMissing(executor, 'time_entries', 'note', 'TEXT');
    await executor.runCustom('''
      CREATE TABLE IF NOT EXISTS subtasks (
        id TEXT PRIMARY KEY,
        task_id TEXT NOT NULL REFERENCES tasks(id) ON DELETE CASCADE,
        title TEXT NOT NULL,
        is_completed INTEGER NOT NULL DEFAULT 0 CHECK (is_completed IN (0,1)),
        sort_order INTEGER NOT NULL DEFAULT 0,
        created_at INTEGER NOT NULL,
        updated_at INTEGER NOT NULL
      )
    ''');
    await executor.runCustom('''
      CREATE TABLE IF NOT EXISTS recurrence_rules (
        id TEXT PRIMARY KEY,
        frequency TEXT NOT NULL CHECK (frequency IN ('daily','weekly','monthly')),
        interval_value INTEGER NOT NULL DEFAULT 1 CHECK (interval_value > 0),
        weekdays_mask INTEGER,
        day_of_month INTEGER,
        starts_at INTEGER NOT NULL,
        ends_at INTEGER,
        occurrence_count INTEGER,
        timezone_name TEXT NOT NULL,
        created_at INTEGER NOT NULL,
        updated_at INTEGER NOT NULL
      )
    ''');
    await executor.runCustom('''
      CREATE TABLE IF NOT EXISTS reminders (
        id TEXT PRIMARY KEY,
        task_id TEXT NOT NULL REFERENCES tasks(id) ON DELETE CASCADE,
        scheduled_at INTEGER NOT NULL,
        timezone_name TEXT NOT NULL,
        notification_id INTEGER NOT NULL UNIQUE,
        status TEXT NOT NULL DEFAULT 'scheduled'
          CHECK (status IN ('scheduled','fired','snoozed','completed','dismissed','cancelled')),
        snoozed_from_id TEXT REFERENCES reminders(id) ON DELETE SET NULL,
        created_at INTEGER NOT NULL,
        updated_at INTEGER NOT NULL
      )
    ''');
    await executor.runCustom('''
      CREATE TABLE IF NOT EXISTS app_settings (
        key TEXT PRIMARY KEY,
        value_json TEXT NOT NULL,
        updated_at INTEGER NOT NULL
      )
    ''');
    await executor.runCustom('CREATE INDEX IF NOT EXISTS idx_tasks_planned_at ON tasks(planned_at)');
    await executor.runCustom('CREATE INDEX IF NOT EXISTS idx_reminders_scheduled ON reminders(status, scheduled_at)');
    await executor.runInsert(
      'INSERT INTO schema_migrations (version, applied_at, description) VALUES (3, ?, ?)',
      <Object?>[
        DateTime.now().toUtc().millisecondsSinceEpoch,
        'Phase 2 and 3 planning, reminders, settings, and timeline migration',
      ],
    );
  }

  Future<void> _applyVersion4Migration(QueryExecutor executor) async {
    final List<Map<String, Object?>> applied = await executor.runSelect(
      'SELECT version FROM schema_migrations WHERE version = 4',
      const <Object?>[],
    );
    if (applied.isNotEmpty) return;
    await executor.runCustom('''
      CREATE TABLE IF NOT EXISTS daily_notes (
        id TEXT PRIMARY KEY,
        local_date TEXT NOT NULL UNIQUE,
        note TEXT NOT NULL,
        created_at INTEGER NOT NULL,
        updated_at INTEGER NOT NULL
      )
    ''');
    await executor.runCustom('''
      CREATE TABLE IF NOT EXISTS generated_summaries (
        id TEXT PRIMARY KEY,
        range_start INTEGER NOT NULL,
        range_end INTEGER NOT NULL,
        summary_type TEXT NOT NULL CHECK (summary_type IN ('local','ai')),
        content TEXT NOT NULL,
        provider TEXT,
        model TEXT,
        input_hash TEXT,
        created_at INTEGER NOT NULL
      )
    ''');
    await executor.runCustom('CREATE INDEX IF NOT EXISTS idx_summaries_range ON generated_summaries(range_start, range_end)');
    await executor.runInsert(
      'INSERT INTO schema_migrations (version, applied_at, description) VALUES (4, ?, ?)',
      <Object?>[DateTime.now().toUtc().millisecondsSinceEpoch, 'Phase 4 daily notes and generated summaries'],
    );
  }

  Future<void> _addColumnIfMissing(
    QueryExecutor executor,
    String table,
    String column,
    String definition,
  ) async {
    final List<Map<String, Object?>> columns = await executor.runSelect(
      'PRAGMA table_info($table)',
      const <Object?>[],
    );
    final bool exists = columns.any(
      (Map<String, Object?> row) => row['name'] == column,
    );
    if (!exists) {
      await executor.runCustom('ALTER TABLE $table ADD COLUMN $column $definition');
    }
  }

  Future<void> _seedDefaultCategories(QueryExecutor executor) async {
    final int now = DateTime.now().toUtc().millisecondsSinceEpoch;
    const List<(String, String, int)> defaults = <(String, String, int)>[
      ('company', 'Company', 0xFF5B5CE2),
      ('study', 'Study', 0xFF40A475),
      ('personal', 'Personal', 0xFFE58A55),
      ('home', 'Home', 0xFFD96499),
      ('meeting', 'Meeting', 0xFF4385D8),
      ('break', 'Break', 0xFF8D78C7),
    ];
    for (int index = 0; index < defaults.length; index++) {
      final (String id, String name, int color) = defaults[index];
      await executor.runInsert(
        '''INSERT OR IGNORE INTO categories
           (id, name, color_value, sort_order, is_system, created_at, updated_at)
           VALUES (?, ?, ?, ?, 1, ?, ?)''',
        <Object?>[id, name, color, index, now, now],
      );
    }
  }
}
