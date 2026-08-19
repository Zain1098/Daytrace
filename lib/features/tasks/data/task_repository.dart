import 'package:daytrace/core/database/app_database.dart';
import 'package:daytrace/core/time/clock.dart';
import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

enum ActiveTaskDisposition { pause, complete }

class TaskRepository {
  TaskRepository(this._database, {Uuid? uuid, Clock? clock})
    : _uuid = uuid ?? Uuid(),
      _clock = clock ?? const SystemClock();

  final AppDatabase _database;
  final Uuid _uuid;
  final Clock _clock;

  Future<TodayData> loadToday() async {
    await _database.initialize();
    final int now = _now();
    final DateTime localNow = _clock.now().toLocal();
    final int localDayStart = DateTime(
      localNow.year,
      localNow.month,
      localNow.day,
    ).toUtc().millisecondsSinceEpoch;
    final List<Map<String, Object?>> rows = await _database.select('''
      SELECT
        t.id,
        t.title,
        t.status,
        t.created_at,
        c.name AS category_name,
        c.color_value AS category_color_value
      FROM tasks t
      LEFT JOIN categories c ON c.id = t.category_id AND c.deleted_at IS NULL
      WHERE t.deleted_at IS NULL AND t.status IN ('planned', 'in_progress', 'paused')
      ORDER BY CASE t.status WHEN 'in_progress' THEN 0 WHEN 'paused' THEN 1 ELSE 2 END, t.created_at DESC
    ''');
    final List<Map<String, Object?>> metrics = await _database.select('''
      SELECT
        SUM(CASE WHEN status = 'completed' THEN 1 ELSE 0 END) AS completed_count,
        SUM(CASE WHEN status IN ('planned','in_progress','paused') THEN 1 ELSE 0 END) AS pending_count
      FROM tasks WHERE deleted_at IS NULL
    ''');
    final List<Map<String, Object?>> activeRows = await _database.select('''
      SELECT t.id, t.title, e.start_at
      FROM time_entries e
      INNER JOIN tasks t ON t.id = e.task_id
      WHERE e.end_at IS NULL AND e.deleted_at IS NULL
      LIMIT 1
    ''');
    final List<Map<String, Object?>> todayEntries = await _database.select(
      '''SELECT start_at, end_at
         FROM time_entries
         WHERE deleted_at IS NULL
           AND start_at < ?
           AND COALESCE(end_at, ?) > ?''',
      <Object?>[now, now, localDayStart],
    );

    final Map<String, Object?> metric = metrics.single;
    return TodayData(
      tasks: rows.map(TaskItem.fromRow).toList(growable: false),
      active: activeRows.isEmpty ? null : ActiveActivity.fromRow(activeRows.single),
      completedCount: (metric['completed_count'] as int?) ?? 0,
      pendingCount: (metric['pending_count'] as int?) ?? 0,
      trackedMinutes: _trackedMinutesForToday(
        entries: todayEntries,
        dayStart: localDayStart,
        now: now,
      ),
    );
  }

  int _trackedMinutesForToday({
    required List<Map<String, Object?>> entries,
    required int dayStart,
    required int now,
  }) {
    final int totalMilliseconds = entries.fold<int>(0, (
      int total,
      Map<String, Object?> entry,
    ) {
      final int start = (entry['start_at']! as int).clamp(dayStart, now).toInt();
      final int rawEnd = (entry['end_at'] as int?) ?? now;
      final int end = rawEnd.clamp(dayStart, now).toInt();
      return total + (end > start ? end - start : 0);
    });
    return totalMilliseconds ~/ Duration.millisecondsPerMinute;
  }

  Future<List<CategoryItem>> loadCategories() async {
    await _database.initialize();
    final List<Map<String, Object?>> rows = await _database.select('''
      SELECT id, name, color_value
      FROM categories
      WHERE deleted_at IS NULL AND is_archived = 0
      ORDER BY sort_order, name
    ''');
    return rows.map(CategoryItem.fromRow).toList(growable: false);
  }

  Future<List<TaskItem>> loadAllTasks() async {
    await _database.initialize();
    final List<Map<String, Object?>> rows = await _database.select('''
      SELECT
        t.id,
        t.title,
        t.status,
        c.name AS category_name,
        c.color_value AS category_color_value
      FROM tasks t
      LEFT JOIN categories c ON c.id = t.category_id AND c.deleted_at IS NULL
      WHERE t.deleted_at IS NULL
      ORDER BY
        CASE t.status
          WHEN 'in_progress' THEN 0
          WHEN 'paused' THEN 1
          WHEN 'planned' THEN 2
          WHEN 'completed' THEN 3
          WHEN 'cancelled' THEN 4
          ELSE 5
        END,
        t.updated_at DESC
    ''');
    return rows.map(TaskItem.fromRow).toList(growable: false);
  }

  Future<List<TimelineItem>> loadTimeline(DateTime localDay) async {
    await _database.initialize();
    final DateTime start = DateTime(localDay.year, localDay.month, localDay.day);
    final int startAt = start.toUtc().millisecondsSinceEpoch;
    final int endAt = start.add(const Duration(days: 1)).toUtc().millisecondsSinceEpoch;
    final List<Map<String, Object?>> rows = await _database.select(
      '''SELECT e.id, e.task_id, e.category_id, e.entry_type, e.start_at, e.end_at, e.note,
                t.title AS task_title, c.name AS category_name
         FROM time_entries e
         LEFT JOIN tasks t ON t.id = e.task_id
         LEFT JOIN categories c ON c.id = e.category_id
         WHERE e.deleted_at IS NULL AND e.start_at < ?
           AND COALESCE(e.end_at, ?) > ?
         ORDER BY e.start_at''',
      <Object?>[endAt, endAt, startAt],
    );
    return rows.map(TimelineItem.fromRow).toList(growable: false);
  }

  Future<List<TimelineItem>> searchTimeline({
    String query = '',
    DateTime? from,
    DateTime? to,
    String? entryType,
  }) async {
    await _database.initialize();
    final List<String> where = <String>['e.deleted_at IS NULL'];
    final List<Object?> arguments = <Object?>[];
    if (from != null) {
      where.add('COALESCE(e.end_at, e.start_at) >= ?');
      arguments.add(DateTime(from.year, from.month, from.day).toUtc().millisecondsSinceEpoch);
    }
    if (to != null) {
      where.add('e.start_at < ?');
      arguments.add(DateTime(to.year, to.month, to.day).add(const Duration(days: 1)).toUtc().millisecondsSinceEpoch);
    }
    if (entryType != null && entryType != 'all') {
      where.add('e.entry_type = ?');
      arguments.add(entryType);
    }
    final String needle = query.trim();
    if (needle.isNotEmpty) {
      where.add('(LOWER(COALESCE(e.note, \'\')) LIKE ? OR LOWER(COALESCE(t.title, \'\')) LIKE ? OR LOWER(COALESCE(c.name, \'\')) LIKE ?)');
      final String pattern = '%${needle.toLowerCase()}%';
      arguments.addAll(<Object?>[pattern, pattern, pattern]);
    }
    final List<Map<String, Object?>> rows = await _database.select(
      '''SELECT e.id, e.task_id, e.category_id, e.entry_type, e.start_at, e.end_at, e.note,
                t.title AS task_title, c.name AS category_name
         FROM time_entries e
         LEFT JOIN tasks t ON t.id = e.task_id
         LEFT JOIN categories c ON c.id = e.category_id
         WHERE ${where.join(' AND ')}
         ORDER BY e.start_at DESC''',
      arguments,
    );
    return rows.map(TimelineItem.fromRow).toList(growable: false);
  }

  Future<void> createManualEntry({
    required DateTime startAt,
    required DateTime endAt,
    required String note,
    String? categoryId,
    String entryType = 'manual',
  }) async {
    final int start = startAt.toUtc().millisecondsSinceEpoch;
    final int end = endAt.toUtc().millisecondsSinceEpoch;
    if (end <= start) {
      throw ArgumentError.value(endAt, 'endAt', 'End time must be after start time.');
    }
    if (note.trim().isEmpty) {
      throw ArgumentError.value(note, 'note', 'An activity description is required.');
    }
    if (!const <String>['manual', 'break', 'meeting', 'untracked'].contains(entryType)) {
      throw ArgumentError.value(entryType, 'entryType', 'Unsupported entry type.');
    }
    await _database.initialize();
    await _database.transaction<void>((QueryExecutor executor) async {
      final List<Map<String, Object?>> overlaps = await executor.runSelect(
        '''SELECT id FROM time_entries
           WHERE deleted_at IS NULL AND start_at < ?
             AND COALESCE(end_at, ?) > ? LIMIT 1''',
        <Object?>[end, end, start],
      );
      if (overlaps.isNotEmpty) {
        throw StateError('This time overlaps an existing activity.');
      }
      final int now = _now();
      await executor.runInsert(
        '''INSERT INTO time_entries
           (id, category_id, entry_type, start_at, end_at, note, source, created_at, updated_at)
           VALUES (?, ?, ?, ?, ?, ?, 'manual', ?, ?)''',
        <Object?>[_uuid.v4(), categoryId, entryType, start, end, note.trim(), now, now],
      );
    });
  }

  Future<void> deleteTimeEntry(String entryId) async {
    await _database.initialize();
    final int changed = await _database.update(
      '''UPDATE time_entries SET deleted_at = ?, updated_at = ?
         WHERE id = ? AND end_at IS NOT NULL AND deleted_at IS NULL''',
      <Object?>[_now(), _now(), entryId],
    );
    if (changed == 0) throw StateError('Only a finished timeline entry can be removed.');
  }

  Future<void> updateTimeEntry({
    required String entryId,
    required DateTime startAt,
    required DateTime endAt,
    required String note,
    required String entryType,
    String? taskId,
  }) async {
    final int start = startAt.toUtc().millisecondsSinceEpoch;
    final int end = endAt.toUtc().millisecondsSinceEpoch;
    if (end <= start) {
      throw ArgumentError.value(endAt, 'endAt', 'End time must be after start time.');
    }
    if (!const <String>['manual', 'break', 'meeting', 'untracked', 'task'].contains(entryType)) {
      throw ArgumentError.value(entryType, 'entryType', 'Unsupported entry type.');
    }
    await _database.initialize();
    await _database.transaction<void>((QueryExecutor executor) async {
      final List<Map<String, Object?>> existing = await executor.runSelect(
        '''SELECT id FROM time_entries
           WHERE id = ? AND end_at IS NOT NULL AND deleted_at IS NULL''',
        <Object?>[entryId],
      );
      if (existing.isEmpty) {
        throw StateError('Only a finished activity can be edited.');
      }
      await _validateEntryTarget(executor, taskId);
      await _rejectOverlap(executor, start: start, end: end, excludingEntryId: entryId);
      final int now = _now();
      await executor.runUpdate(
        '''UPDATE time_entries
           SET task_id = ?, entry_type = ?, start_at = ?, end_at = ?, note = ?,
               updated_at = ?
           WHERE id = ?''',
        <Object?>[
          taskId,
          taskId == null ? entryType : 'task',
          start,
          end,
          note.trim().isEmpty ? null : note.trim(),
          now,
          entryId,
        ],
      );
    });
  }

  Future<void> splitTimeEntry({
    required String entryId,
    required DateTime splitAt,
    String? secondNote,
  }) async {
    final int split = splitAt.toUtc().millisecondsSinceEpoch;
    await _database.initialize();
    await _database.transaction<void>((QueryExecutor executor) async {
      final List<Map<String, Object?>> rows = await executor.runSelect(
        '''SELECT task_id, category_id, entry_type, start_at, end_at, note, source
           FROM time_entries
           WHERE id = ? AND end_at IS NOT NULL AND deleted_at IS NULL''',
        <Object?>[entryId],
      );
      if (rows.isEmpty) throw StateError('Only a finished activity can be split.');
      final Map<String, Object?> row = rows.single;
      final int start = row['start_at']! as int;
      final int end = row['end_at']! as int;
      if (split <= start || split >= end) {
        throw ArgumentError.value(splitAt, 'splitAt', 'Split time must fall inside the activity.');
      }
      final int now = _now();
      await executor.runUpdate(
        'UPDATE time_entries SET end_at = ?, updated_at = ? WHERE id = ?',
        <Object?>[split, now, entryId],
      );
      await executor.runInsert(
        '''INSERT INTO time_entries
           (id, task_id, category_id, entry_type, start_at, end_at, note, source, created_at, updated_at)
           VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)''',
        <Object?>[
          _uuid.v4(),
          row['task_id'],
          row['category_id'],
          row['entry_type'],
          split,
          end,
          (secondNote?.trim().isEmpty ?? true) ? row['note'] : secondNote!.trim(),
          row['source'],
          now,
          now,
        ],
      );
    });
  }

  Future<List<TaskItem>> loadAssignableTasks() => loadAllTasks();

  Future<String?> loadDailyNote(DateTime localDay) async {
    await _database.initialize();
    final String date = _localDateKey(localDay);
    final List<Map<String, Object?>> rows = await _database.select(
      'SELECT note FROM daily_notes WHERE local_date = ?',
      <Object?>[date],
    );
    return rows.isEmpty ? null : rows.single['note']! as String;
  }

  Future<void> saveDailyNote(DateTime localDay, String note) async {
    await _database.initialize();
    final String trimmed = note.trim();
    final String date = _localDateKey(localDay);
    final int now = _now();
    if (trimmed.isEmpty) {
      await _database.update('DELETE FROM daily_notes WHERE local_date = ?', <Object?>[date]);
      return;
    }
    await _database.insert(
      '''INSERT INTO daily_notes (id, local_date, note, created_at, updated_at)
         VALUES (?, ?, ?, ?, ?)
         ON CONFLICT(local_date) DO UPDATE SET note = excluded.note, updated_at = excluded.updated_at''',
      <Object?>[_uuid.v4(), date, trimmed, now, now],
    );
  }

  Future<TaskStatusCounts> loadTaskStatusCounts(DateTime start, DateTime end) async {
    await _database.initialize();
    final int startAt = DateTime(start.year, start.month, start.day).toUtc().millisecondsSinceEpoch;
    final int endAt = DateTime(end.year, end.month, end.day).toUtc().millisecondsSinceEpoch;
    final List<Map<String, Object?>> rows = await _database.select(
      '''SELECT
           SUM(CASE WHEN status = 'completed' AND completed_at >= ? AND completed_at < ? THEN 1 ELSE 0 END) AS completed,
           SUM(CASE WHEN status IN ('planned', 'paused', 'in_progress') AND due_at IS NOT NULL AND due_at < ? THEN 1 ELSE 0 END) AS overdue,
           SUM(CASE WHEN status IN ('planned', 'paused', 'in_progress') THEN 1 ELSE 0 END) AS pending,
           SUM(CASE WHEN status = 'cancelled' AND cancelled_at >= ? AND cancelled_at < ? THEN 1 ELSE 0 END) AS cancelled
         FROM tasks WHERE deleted_at IS NULL''',
      <Object?>[startAt, endAt, endAt, startAt, endAt],
    );
    return TaskStatusCounts.fromRow(rows.single);
  }

  Future<void> _validateEntryTarget(QueryExecutor executor, String? taskId) async {
    if (taskId == null) return;
    final List<Map<String, Object?>> tasks = await executor.runSelect(
      'SELECT id FROM tasks WHERE id = ? AND deleted_at IS NULL',
      <Object?>[taskId],
    );
    if (tasks.isEmpty) throw StateError('The selected task no longer exists.');
  }

  Future<void> _rejectOverlap(
    QueryExecutor executor, {
    required int start,
    required int end,
    String? excludingEntryId,
  }) async {
    final List<Object?> parameters = <Object?>[end, end, start];
    String exclusion = '';
    if (excludingEntryId != null) {
      exclusion = ' AND id != ?';
      parameters.add(excludingEntryId);
    }
    final List<Map<String, Object?>> overlaps = await executor.runSelect(
      '''SELECT id FROM time_entries
         WHERE deleted_at IS NULL AND start_at < ?
           AND COALESCE(end_at, ?) > ?$exclusion LIMIT 1''',
      parameters,
    );
    if (overlaps.isNotEmpty) {
      throw StateError('This time overlaps an existing activity.');
    }
  }

  String _localDateKey(DateTime day) {
    final DateTime local = day.toLocal();
    return '${local.year.toString().padLeft(4, '0')}-${local.month.toString().padLeft(2, '0')}-${local.day.toString().padLeft(2, '0')}';
  }

  /// Marks every pending reminder for a task cancelled and returns their stable
  /// notification identifiers so the caller can cancel the platform alarms.
  Future<List<int>> cancelPendingRemindersForTask(String taskId) async {
    await _database.initialize();
    return _database.transaction<List<int>>((QueryExecutor executor) async {
      final List<Map<String, Object?>> rows = await executor.runSelect(
        "SELECT notification_id FROM reminders WHERE task_id = ? AND status IN ('scheduled', 'snoozed')",
        <Object?>[taskId],
      );
      if (rows.isNotEmpty) {
        await executor.runUpdate(
          "UPDATE reminders SET status = 'cancelled', updated_at = ? WHERE task_id = ? AND status IN ('scheduled', 'snoozed')",
          <Object?>[_now(), taskId],
        );
      }
      return rows.map((Map<String, Object?> row) => row['notification_id']! as int).toList(growable: false);
    });
  }

  Future<ReminderItem> createReminder({
    required String taskId,
    required DateTime scheduledAt,
    required String timezoneName,
  }) async {
    await _database.initialize();
    final int now = _now();
    final String reminderId = _uuid.v4();
    final int notificationId = await _database.transaction<int>((QueryExecutor executor) async {
      final List<Map<String, Object?>> tasks = await executor.runSelect(
        "SELECT id FROM tasks WHERE id = ? AND status IN ('planned', 'paused') AND deleted_at IS NULL",
        <Object?>[taskId],
      );
      if (tasks.isEmpty) throw StateError('Only an active planned task can have a reminder.');
      final List<Map<String, Object?>> rows = await executor.runSelect(
        'SELECT COALESCE(MAX(notification_id), 0) + 1 AS next_id FROM reminders',
        const <Object?>[],
      );
      final int nextId = rows.single['next_id']! as int;
      await executor.runInsert(
        '''INSERT INTO reminders
           (id, task_id, scheduled_at, timezone_name, notification_id, status, created_at, updated_at)
           VALUES (?, ?, ?, ?, ?, 'scheduled', ?, ?)''',
        <Object?>[reminderId, taskId, scheduledAt.toUtc().millisecondsSinceEpoch, timezoneName, nextId, now, now],
      );
      return nextId;
    });
    return ReminderItem(id: reminderId, taskId: taskId, scheduledAt: scheduledAt.toUtc(), notificationId: notificationId);
  }

  Future<List<ScheduledReminder>> loadFutureScheduledReminders() async {
    await _database.initialize();
    final List<Map<String, Object?>> rows = await _database.select(
      '''SELECT r.id, r.task_id, r.notification_id, r.scheduled_at, t.title
         FROM reminders r
         INNER JOIN tasks t ON t.id = r.task_id
         WHERE r.status = 'scheduled' AND r.scheduled_at > ?
           AND t.deleted_at IS NULL AND t.status IN ('planned', 'paused')
         ORDER BY r.scheduled_at''',
      <Object?>[_now()],
    );
    return rows.map(ScheduledReminder.fromRow).toList(growable: false);
  }

  Future<void> dismissReminder(String reminderId) => _setReminderStatus(reminderId, 'dismissed');

  Future<void> cancelReminder(String reminderId) async {
    await _database.initialize();
    await _database.update(
      "UPDATE reminders SET status = 'cancelled', updated_at = ? WHERE id = ? AND status IN ('scheduled', 'snoozed')",
      <Object?>[_now(), reminderId],
    );
  }

  Future<int?> dismissReminderAndGetNotificationId(String reminderId) =>
      _setReminderStatusAndGetNotificationId(reminderId, 'dismissed');

  Future<ReminderItem> snoozeReminder(String reminderId, Duration duration) async {
    await _database.initialize();
    final List<Map<String, Object?>> rows = await _database.select(
      "SELECT task_id, timezone_name FROM reminders WHERE id = ? AND status IN ('scheduled', 'fired')",
      <Object?>[reminderId],
    );
    if (rows.isEmpty) throw StateError('This reminder can no longer be snoozed.');
    final Map<String, Object?> row = rows.single;
    await _setReminderStatus(reminderId, 'snoozed');
    return createReminder(
      taskId: row['task_id']! as String,
      scheduledAt: _clock.now().add(duration),
      timezoneName: row['timezone_name']! as String,
    );
  }

  Future<String> taskTitle(String taskId) async {
    await _database.initialize();
    final List<Map<String, Object?>> rows = await _database.select(
      'SELECT title FROM tasks WHERE id = ? AND deleted_at IS NULL',
      <Object?>[taskId],
    );
    if (rows.isEmpty) throw StateError('The reminder task no longer exists.');
    return rows.single['title']! as String;
  }

  Future<void> _setReminderStatus(String reminderId, String status) async {
    await _setReminderStatusAndGetNotificationId(reminderId, status);
  }

  Future<int?> _setReminderStatusAndGetNotificationId(String reminderId, String status) async {
    await _database.initialize();
    return _database.transaction<int?>((QueryExecutor executor) async {
      final List<Map<String, Object?>> rows = await executor.runSelect(
        "SELECT notification_id FROM reminders WHERE id = ? AND status IN ('scheduled', 'fired')",
        <Object?>[reminderId],
      );
      if (rows.isEmpty) return null;
      await executor.runUpdate(
        'UPDATE reminders SET status = ?, updated_at = ? WHERE id = ?',
        <Object?>[status, _now(), reminderId],
      );
      return rows.single['notification_id']! as int;
    });
  }

  Future<String> createTask({
    required String title,
    required bool startNow,
    String? categoryId,
    String? description,
    String priority = 'medium',
    DateTime? plannedAt,
    DateTime? dueAt,
    int? estimatedMinutes,
    List<String> subtaskTitles = const <String>[],
    RecurrenceDraft? recurrence,
  }) async {
    final String trimmedTitle = title.trim();
    if (trimmedTitle.isEmpty) {
      throw ArgumentError.value(title, 'title', 'A task title is required.');
    }
    if (!const <String>['low', 'medium', 'high', 'urgent'].contains(priority)) {
      throw ArgumentError.value(priority, 'priority', 'Unsupported priority.');
    }
    if (estimatedMinutes != null && estimatedMinutes < 0) {
      throw ArgumentError.value(
        estimatedMinutes,
        'estimatedMinutes',
        'Estimated duration cannot be negative.',
      );
    }
    final List<String> cleanedSubtasks = subtaskTitles
        .map((String title) => title.trim())
        .where((String title) => title.isNotEmpty)
        .toList(growable: false);
    recurrence?.validate();
    await _database.initialize();
    final int now = _clock.now().toUtc().millisecondsSinceEpoch;
    final String taskId = _uuid.v4();
    await _database.transaction<void>((QueryExecutor executor) async {
      if (startNow) {
        final List<Map<String, Object?>> openEntries = await executor.runSelect(
          'SELECT id FROM time_entries WHERE end_at IS NULL AND deleted_at IS NULL LIMIT 1',
          const <Object?>[],
        );
        if (openEntries.isNotEmpty) {
          throw StateError('Finish or pause the current activity before starting another one.');
        }
      }
      String? recurrenceRuleId;
      if (recurrence != null) {
        recurrenceRuleId = _uuid.v4();
        await executor.runInsert(
          '''INSERT INTO recurrence_rules
             (id, frequency, interval_value, weekdays_mask, day_of_month,
              starts_at, ends_at, occurrence_count, timezone_name, created_at, updated_at)
             VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)''',
          <Object?>[
            recurrenceRuleId,
            recurrence.frequency,
            recurrence.interval,
            recurrence.weekdaysMask,
            recurrence.dayOfMonth,
            (plannedAt ?? dueAt ?? _clock.now()).toUtc().millisecondsSinceEpoch,
            recurrence.endsAt?.toUtc().millisecondsSinceEpoch,
            recurrence.occurrenceCount,
            recurrence.timezoneName,
            now,
            now,
          ],
        );
      }
      await executor.runInsert(
        '''INSERT INTO tasks
           (id, title, description, category_id, status, priority, planned_at,
            due_at, estimated_minutes, recurrence_rule_id, created_at, updated_at)
           VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)''',
        <Object?>[
          taskId,
          trimmedTitle,
          (description?.trim().isEmpty ?? true) ? null : description!.trim(),
          categoryId,
          startNow ? 'in_progress' : 'planned',
          priority,
          plannedAt?.toUtc().millisecondsSinceEpoch,
          dueAt?.toUtc().millisecondsSinceEpoch,
          estimatedMinutes,
          recurrenceRuleId,
          now,
          now,
        ],
      );
      for (int index = 0; index < cleanedSubtasks.length; index++) {
        await executor.runInsert(
          '''INSERT INTO subtasks
             (id, task_id, title, is_completed, sort_order, created_at, updated_at)
             VALUES (?, ?, ?, 0, ?, ?, ?)''',
          <Object?>[_uuid.v4(), taskId, cleanedSubtasks[index], index, now, now],
        );
      }
      if (startNow) {
        await executor.runInsert(
          '''INSERT INTO time_entries
             (id, task_id, entry_type, start_at, source, created_at, updated_at)
             VALUES (?, ?, 'task', ?, 'app', ?, ?)''',
          <Object?>[_uuid.v4(), taskId, now, now, now],
        );
      }
    });
    return taskId;
  }

  Future<void> pauseActiveTask() async {
    await _closeActiveTask(completed: false);
  }

  Future<List<int>> completeActiveTask() => _closeActiveTask(completed: true);

  Future<List<int>> completeTask(String taskId) async {
    await _database.initialize();
    return _database.transaction<List<int>>((QueryExecutor executor) async {
      final List<Map<String, Object?>> tasks = await executor.runSelect(
        "SELECT id FROM tasks WHERE id = ? AND status IN ('planned', 'paused') AND deleted_at IS NULL",
        <Object?>[taskId],
      );
      if (tasks.isEmpty) {
        throw StateError('Only a planned or paused task can be completed here.');
      }
      final int now = _now();
      await executor.runUpdate(
        '''UPDATE tasks
           SET status = 'completed', completed_at = ?, updated_at = ?
           WHERE id = ?''',
        <Object?>[now, now, taskId],
      );
      final List<Map<String, Object?>> reminders = await executor.runSelect(
        "SELECT notification_id FROM reminders WHERE task_id = ? AND status IN ('scheduled', 'snoozed')",
        <Object?>[taskId],
      );
      await executor.runUpdate(
        "UPDATE reminders SET status = 'cancelled', updated_at = ? WHERE task_id = ? AND status IN ('scheduled', 'snoozed')",
        <Object?>[now, taskId],
      );
      await _createNextRecurringTask(executor, taskId, now);
      return reminders.map((Map<String, Object?> row) => row['notification_id']! as int).toList(growable: false);
    });
  }

  Future<TaskDetails> loadTaskDetails(String taskId) async {
    await _database.initialize();
    final List<Map<String, Object?>> tasks = await _database.select(
      '''SELECT t.id, t.title, t.description, t.status, t.priority, t.planned_at,
                t.due_at, t.estimated_minutes, c.name AS category_name,
                r.frequency, r.interval_value, r.weekdays_mask
         FROM tasks t
         LEFT JOIN categories c ON c.id = t.category_id AND c.deleted_at IS NULL
         LEFT JOIN recurrence_rules r ON r.id = t.recurrence_rule_id
         WHERE t.id = ? AND t.deleted_at IS NULL''',
      <Object?>[taskId],
    );
    if (tasks.isEmpty) throw StateError('This task no longer exists.');
    final List<Map<String, Object?>> subtasks = await _database.select(
      '''SELECT id, title, is_completed, sort_order
         FROM subtasks WHERE task_id = ? ORDER BY sort_order, created_at''',
      <Object?>[taskId],
    );
    return TaskDetails.fromRows(tasks.single, subtasks);
  }

  Future<void> setSubtaskCompleted({
    required String subtaskId,
    required bool completed,
  }) async {
    await _database.initialize();
    final int now = _now();
    final int changed = await _database.update(
      '''UPDATE subtasks SET is_completed = ?, updated_at = ?
         WHERE id = ? AND EXISTS (
           SELECT 1 FROM tasks t
           WHERE t.id = subtasks.task_id AND t.deleted_at IS NULL
             AND t.status IN ('planned', 'paused', 'in_progress')
         )''',
      <Object?>[completed ? 1 : 0, now, subtaskId],
    );
    if (changed == 0) throw StateError('This subtask can no longer be changed.');
  }

  Future<List<int>> cancelTask(String taskId) async {
    await _database.initialize();
    return _database.transaction<List<int>>((QueryExecutor executor) async {
      final List<Map<String, Object?>> tasks = await executor.runSelect(
        "SELECT id FROM tasks WHERE id = ? AND status IN ('planned', 'paused') AND deleted_at IS NULL",
        <Object?>[taskId],
      );
      if (tasks.isEmpty) {
        throw StateError('Only a planned or paused task can be cancelled.');
      }
      final int now = _now();
      await executor.runUpdate(
        "UPDATE tasks SET status = 'cancelled', cancelled_at = ?, updated_at = ? WHERE id = ?",
        <Object?>[now, now, taskId],
      );
      final List<Map<String, Object?>> reminders = await executor.runSelect(
        "SELECT notification_id FROM reminders WHERE task_id = ? AND status IN ('scheduled', 'snoozed')",
        <Object?>[taskId],
      );
      await executor.runUpdate(
        "UPDATE reminders SET status = 'cancelled', updated_at = ? WHERE task_id = ? AND status IN ('scheduled', 'snoozed')",
        <Object?>[now, taskId],
      );
      return reminders.map((Map<String, Object?> row) => row['notification_id']! as int).toList(growable: false);
    });
  }

  Future<void> startTask(String taskId) async {
    await _database.initialize();
    await _database.transaction<void>((QueryExecutor executor) async {
      final List<Map<String, Object?>> openEntries = await executor.runSelect(
        'SELECT id FROM time_entries WHERE end_at IS NULL AND deleted_at IS NULL LIMIT 1',
        const <Object?>[],
      );
      if (openEntries.isNotEmpty) {
        throw StateError('Finish or pause the current activity before starting another one.');
      }
      await _startPlannedTask(executor, taskId);
    });
  }

  Future<void> resumeTask(String taskId) async {
    await _database.initialize();
    await _database.transaction<void>((QueryExecutor executor) async {
      final List<Map<String, Object?>> openEntries = await executor.runSelect(
        'SELECT id FROM time_entries WHERE end_at IS NULL AND deleted_at IS NULL LIMIT 1',
        const <Object?>[],
      );
      if (openEntries.isNotEmpty) {
        throw StateError('Finish or pause the current activity before resuming another one.');
      }
      final List<Map<String, Object?>> tasks = await executor.runSelect(
        "SELECT id FROM tasks WHERE id = ? AND status = 'paused' AND deleted_at IS NULL",
        <Object?>[taskId],
      );
      if (tasks.isEmpty) {
        throw StateError('Only a paused task can be resumed.');
      }
      final int now = _now();
      await executor.runUpdate(
        "UPDATE tasks SET status = 'in_progress', updated_at = ? WHERE id = ?",
        <Object?>[now, taskId],
      );
      await executor.runInsert(
        '''INSERT INTO time_entries
           (id, task_id, entry_type, start_at, source, created_at, updated_at)
           VALUES (?, ?, 'task', ?, 'app', ?, ?)''',
        <Object?>[_uuid.v4(), taskId, now, now, now],
      );
    });
  }

  Future<void> switchToNewTask({
    required String title,
    required ActiveTaskDisposition disposition,
  }) async {
    final String trimmedTitle = title.trim();
    if (trimmedTitle.isEmpty) {
      throw ArgumentError.value(title, 'title', 'A task title is required.');
    }
    await _database.initialize();
    await _database.transaction<void>((QueryExecutor executor) async {
      await _endOpenEntry(
        executor,
        completed: disposition == ActiveTaskDisposition.complete,
      );
      final int now = _now();
      final String taskId = _uuid.v4();
      await executor.runInsert(
        '''INSERT INTO tasks (id, title, status, created_at, updated_at)
           VALUES (?, ?, 'in_progress', ?, ?)''',
        <Object?>[taskId, trimmedTitle, now, now],
      );
      await executor.runInsert(
        '''INSERT INTO time_entries
           (id, task_id, entry_type, start_at, source, created_at, updated_at)
           VALUES (?, ?, 'task', ?, 'app', ?, ?)''',
        <Object?>[_uuid.v4(), taskId, now, now, now],
      );
    });
  }

  Future<void> switchToTask({
    required String taskId,
    required ActiveTaskDisposition disposition,
  }) async {
    await _database.initialize();
    await _database.transaction<void>((QueryExecutor executor) async {
      await _endOpenEntry(
        executor,
        completed: disposition == ActiveTaskDisposition.complete,
      );
      await _startPlannedTask(executor, taskId);
    });
  }

  Future<List<int>> _closeActiveTask({required bool completed}) async {
    await _database.initialize();
    return _database.transaction<List<int>>((QueryExecutor executor) async {
      return _endOpenEntry(executor, completed: completed);
    });
  }

  Future<List<int>> _endOpenEntry(
    QueryExecutor executor, {
    required bool completed,
  }) async {
    final List<Map<String, Object?>> rows = await executor.runSelect(
        '''SELECT e.id AS entry_id, e.start_at, t.id AS task_id
           FROM time_entries e
           INNER JOIN tasks t ON t.id = e.task_id
           WHERE e.end_at IS NULL AND e.deleted_at IS NULL
           LIMIT 1''',
        const <Object?>[],
      );
    if (rows.isEmpty) {
      throw StateError('There is no active activity to ${completed ? 'complete' : 'pause'}.');
    }
    final Map<String, Object?> row = rows.single;
    final int startAt = row['start_at']! as int;
    final int requestedEnd = _now();
    final int endAt = requestedEnd <= startAt ? startAt + 1 : requestedEnd;
    await executor.runUpdate(
      'UPDATE time_entries SET end_at = ?, updated_at = ? WHERE id = ?',
      <Object?>[endAt, endAt, row['entry_id']],
    );
    final List<int> reminderIds = <int>[];
    if (completed) {
      final List<Map<String, Object?>> reminders = await executor.runSelect(
        "SELECT notification_id FROM reminders WHERE task_id = ? AND status IN ('scheduled', 'snoozed')",
        <Object?>[row['task_id']],
      );
      reminderIds.addAll(reminders.map((Map<String, Object?> item) => item['notification_id']! as int));
      await executor.runUpdate(
        "UPDATE reminders SET status = 'cancelled', updated_at = ? WHERE task_id = ? AND status IN ('scheduled', 'snoozed')",
        <Object?>[endAt, row['task_id']],
      );
    }
    await executor.runUpdate(
      completed
          ? '''UPDATE tasks
               SET status = 'completed', completed_at = ?, updated_at = ? WHERE id = ?'''
          : "UPDATE tasks SET status = 'paused', updated_at = ? WHERE id = ?",
      completed
          ? <Object?>[endAt, endAt, row['task_id']]
          : <Object?>[endAt, row['task_id']],
    );
    if (completed) {
      await _createNextRecurringTask(executor, row['task_id']! as String, endAt);
    }
    return reminderIds;
  }

  Future<void> _createNextRecurringTask(
    QueryExecutor executor,
    String completedTaskId,
    int completedAt,
  ) async {
    final List<Map<String, Object?>> sourceRows = await executor.runSelect(
      '''SELECT t.title, t.description, t.category_id, t.priority, t.planned_at,
                t.due_at, t.estimated_minutes, t.recurrence_rule_id,
                r.frequency, r.interval_value, r.weekdays_mask, r.day_of_month,
                r.ends_at, r.occurrence_count
         FROM tasks t
         INNER JOIN recurrence_rules r ON r.id = t.recurrence_rule_id
         WHERE t.id = ?''',
      <Object?>[completedTaskId],
    );
    if (sourceRows.isEmpty) return;
    final Map<String, Object?> source = sourceRows.single;
    final int? remaining = source['occurrence_count'] as int?;
    if (remaining != null && remaining <= 1) return;
    final DateTime completed = DateTime.fromMillisecondsSinceEpoch(completedAt, isUtc: true);
    final int? sourceAnchor = (source['planned_at'] as int?) ?? source['due_at'] as int?;
    final DateTime anchor = sourceAnchor == null
        ? completed
        : DateTime.fromMillisecondsSinceEpoch(sourceAnchor, isUtc: true);
    final DateTime nextAnchor = RecurrenceDraft.nextOccurrence(
      after: completed,
      anchor: anchor,
      frequency: source['frequency']! as String,
      interval: source['interval_value']! as int,
      weekdaysMask: source['weekdays_mask'] as int?,
      dayOfMonth: source['day_of_month'] as int?,
    );
    final int? endsAt = source['ends_at'] as int?;
    if (endsAt != null && nextAnchor.millisecondsSinceEpoch > endsAt) return;
    final Duration shift = nextAnchor.difference(anchor);
    final int now = _now();
    final String nextTaskId = _uuid.v4();
    await executor.runInsert(
      '''INSERT INTO tasks
         (id, title, description, category_id, status, priority, planned_at,
          due_at, estimated_minutes, recurrence_rule_id, created_at, updated_at)
         VALUES (?, ?, ?, ?, 'planned', ?, ?, ?, ?, ?, ?, ?)''',
      <Object?>[
        nextTaskId,
        source['title'],
        source['description'],
        source['category_id'],
        source['priority'],
        source['planned_at'] == null
            ? null
            : (source['planned_at']! as int) + shift.inMilliseconds,
        source['due_at'] == null
            ? null
            : (source['due_at']! as int) + shift.inMilliseconds,
        source['estimated_minutes'],
        source['recurrence_rule_id'],
        now,
        now,
      ],
    );
    final List<Map<String, Object?>> subtasks = await executor.runSelect(
      'SELECT title, sort_order FROM subtasks WHERE task_id = ? ORDER BY sort_order, created_at',
      <Object?>[completedTaskId],
    );
    for (final Map<String, Object?> subtask in subtasks) {
      await executor.runInsert(
        '''INSERT INTO subtasks
           (id, task_id, title, is_completed, sort_order, created_at, updated_at)
           VALUES (?, ?, ?, 0, ?, ?, ?)''',
        <Object?>[_uuid.v4(), nextTaskId, subtask['title'], subtask['sort_order'], now, now],
      );
    }
    if (remaining != null) {
      await executor.runUpdate(
        'UPDATE recurrence_rules SET occurrence_count = ?, updated_at = ? WHERE id = ?',
        <Object?>[remaining - 1, now, source['recurrence_rule_id']],
      );
    }
  }

  Future<void> _startPlannedTask(QueryExecutor executor, String taskId) async {
    final List<Map<String, Object?>> tasks = await executor.runSelect(
      "SELECT id FROM tasks WHERE id = ? AND status = 'planned' AND deleted_at IS NULL",
      <Object?>[taskId],
    );
    if (tasks.isEmpty) {
      throw StateError('Only a planned task can be started.');
    }
    final int now = _now();
    await executor.runUpdate(
      "UPDATE tasks SET status = 'in_progress', updated_at = ? WHERE id = ?",
      <Object?>[now, taskId],
    );
    await executor.runInsert(
      '''INSERT INTO time_entries
         (id, task_id, entry_type, start_at, source, created_at, updated_at)
         VALUES (?, ?, 'task', ?, 'app', ?, ?)''',
      <Object?>[_uuid.v4(), taskId, now, now, now],
    );
  }

  int _now() => _clock.now().toUtc().millisecondsSinceEpoch;
}

class TodayData {
  const TodayData({
    required this.tasks,
    required this.active,
    required this.completedCount,
    required this.pendingCount,
    required this.trackedMinutes,
  });

  final List<TaskItem> tasks;
  final ActiveActivity? active;
  final int completedCount;
  final int pendingCount;
  final int trackedMinutes;
}

class TaskItem {
  const TaskItem({
    required this.id,
    required this.title,
    required this.status,
    required this.categoryName,
    required this.categoryColorValue,
  });

  factory TaskItem.fromRow(Map<String, Object?> row) => TaskItem(
    id: row['id']! as String,
    title: row['title']! as String,
    status: row['status']! as String,
    categoryName: row['category_name'] as String?,
    categoryColorValue: row['category_color_value'] as int?,
  );

  final String id;
  final String title;
  final String status;
  final String? categoryName;
  final int? categoryColorValue;
}

class CategoryItem {
  const CategoryItem({
    required this.id,
    required this.name,
    required this.colorValue,
  });

  factory CategoryItem.fromRow(Map<String, Object?> row) => CategoryItem(
    id: row['id']! as String,
    name: row['name']! as String,
    colorValue: row['color_value']! as int,
  );

  final String id;
  final String name;
  final int colorValue;
}

class TimelineItem {
  const TimelineItem({
    required this.id,
    required this.taskId,
    required this.categoryId,
    required this.entryType,
    required this.startAt,
    required this.endAt,
    required this.note,
    required this.taskTitle,
    required this.categoryName,
  });

  factory TimelineItem.fromRow(Map<String, Object?> row) => TimelineItem(
    id: row['id']! as String,
    taskId: row['task_id'] as String?,
    categoryId: row['category_id'] as String?,
    entryType: row['entry_type']! as String,
    startAt: DateTime.fromMillisecondsSinceEpoch(row['start_at']! as int, isUtc: true),
    endAt: row['end_at'] == null ? null : DateTime.fromMillisecondsSinceEpoch(row['end_at']! as int, isUtc: true),
    note: row['note'] as String?,
    taskTitle: row['task_title'] as String?,
    categoryName: row['category_name'] as String?,
  );

  final String id;
  final String? taskId;
  final String? categoryId;
  final String entryType;
  final DateTime startAt;
  final DateTime? endAt;
  final String? note;
  final String? taskTitle;
  final String? categoryName;
}

class TaskStatusCounts {
  const TaskStatusCounts({
    required this.completed,
    required this.pending,
    required this.overdue,
    required this.cancelled,
  });

  factory TaskStatusCounts.fromRow(Map<String, Object?> row) => TaskStatusCounts(
    completed: (row['completed'] as int?) ?? 0,
    pending: (row['pending'] as int?) ?? 0,
    overdue: (row['overdue'] as int?) ?? 0,
    cancelled: (row['cancelled'] as int?) ?? 0,
  );

  final int completed;
  final int pending;
  final int overdue;
  final int cancelled;
}

class ReminderItem {
  const ReminderItem({required this.id, required this.taskId, required this.scheduledAt, required this.notificationId});
  final String id;
  final String taskId;
  final DateTime scheduledAt;
  final int notificationId;
}

class ScheduledReminder {
  const ScheduledReminder({required this.id, required this.taskId, required this.notificationId, required this.scheduledAt, required this.title});
  factory ScheduledReminder.fromRow(Map<String, Object?> row) => ScheduledReminder(
    id: row['id']! as String,
    taskId: row['task_id']! as String,
    notificationId: row['notification_id']! as int,
    scheduledAt: DateTime.fromMillisecondsSinceEpoch(row['scheduled_at']! as int, isUtc: true),
    title: row['title']! as String,
  );
  final String id;
  final String taskId;
  final int notificationId;
  final DateTime scheduledAt;
  final String title;
}

class ActiveActivity {
  const ActiveActivity({required this.id, required this.title, required this.startedAt});

  factory ActiveActivity.fromRow(Map<String, Object?> row) => ActiveActivity(
    id: row['id']! as String,
    title: row['title']! as String,
    startedAt: DateTime.fromMillisecondsSinceEpoch(row['start_at']! as int, isUtc: true),
  );

  final String id;
  final String title;
  final DateTime startedAt;
}

class SubtaskItem {
  const SubtaskItem({required this.id, required this.title, required this.isCompleted});

  factory SubtaskItem.fromRow(Map<String, Object?> row) => SubtaskItem(
    id: row['id']! as String,
    title: row['title']! as String,
    isCompleted: (row['is_completed']! as int) == 1,
  );

  final String id;
  final String title;
  final bool isCompleted;
}

class TaskDetails {
  const TaskDetails({
    required this.id,
    required this.title,
    required this.description,
    required this.status,
    required this.priority,
    required this.categoryName,
    required this.dueAt,
    required this.estimatedMinutes,
    required this.recurrenceLabel,
    required this.subtasks,
  });

  factory TaskDetails.fromRows(
    Map<String, Object?> task,
    List<Map<String, Object?>> subtasks,
  ) => TaskDetails(
    id: task['id']! as String,
    title: task['title']! as String,
    description: task['description'] as String?,
    status: task['status']! as String,
    priority: task['priority']! as String,
    categoryName: task['category_name'] as String?,
    dueAt: task['due_at'] == null
        ? null
        : DateTime.fromMillisecondsSinceEpoch(task['due_at']! as int, isUtc: true),
    estimatedMinutes: task['estimated_minutes'] as int?,
    recurrenceLabel: RecurrenceDraft.label(
      frequency: task['frequency'] as String?,
      interval: task['interval_value'] as int?,
      weekdaysMask: task['weekdays_mask'] as int?,
    ),
    subtasks: subtasks.map(SubtaskItem.fromRow).toList(growable: false),
  );

  final String id;
  final String title;
  final String? description;
  final String status;
  final String priority;
  final String? categoryName;
  final DateTime? dueAt;
  final int? estimatedMinutes;
  final String? recurrenceLabel;
  final List<SubtaskItem> subtasks;
}

class RecurrenceDraft {
  const RecurrenceDraft({
    required this.frequency,
    this.interval = 1,
    this.weekdaysMask,
    this.dayOfMonth,
    this.endsAt,
    this.occurrenceCount,
    this.timezoneName = 'UTC',
  });

  final String frequency;
  final int interval;
  final int? weekdaysMask;
  final int? dayOfMonth;
  final DateTime? endsAt;
  final int? occurrenceCount;
  final String timezoneName;

  void validate() {
    if (!const <String>['daily', 'weekly', 'monthly'].contains(frequency)) {
      throw ArgumentError.value(frequency, 'frequency', 'Unsupported recurrence.');
    }
    if (interval < 1) throw ArgumentError.value(interval, 'interval', 'Interval must be at least one.');
    if (frequency == 'weekly' && weekdaysMask != null && weekdaysMask == 0) {
      throw ArgumentError.value(weekdaysMask, 'weekdaysMask', 'Select at least one weekday.');
    }
  }

  static DateTime nextOccurrence({
    required DateTime after,
    required DateTime anchor,
    required String frequency,
    required int interval,
    int? weekdaysMask,
    int? dayOfMonth,
  }) {
    final DateTime cursor = after.toUtc();
    final DateTime base = anchor.toUtc();
    if (frequency == 'daily') {
      DateTime candidate = DateTime.utc(base.year, base.month, base.day, base.hour, base.minute, base.second, base.millisecond, base.microsecond);
      while (!candidate.isAfter(cursor)) {
        candidate = candidate.add(Duration(days: interval));
      }
      return candidate;
    }
    if (frequency == 'weekly' && weekdaysMask != null) {
      for (int offset = 1; offset <= 370; offset++) {
        final DateTime date = DateTime.utc(cursor.year, cursor.month, cursor.day)
            .add(Duration(days: offset));
        final bool selected = (weekdaysMask & (1 << (date.weekday - 1))) != 0;
        final DateTime candidate = DateTime.utc(date.year, date.month, date.day, base.hour, base.minute, base.second, base.millisecond, base.microsecond);
        if (selected && candidate.isAfter(cursor)) return candidate;
      }
    }
    if (frequency == 'weekly') {
      DateTime candidate = base;
      while (!candidate.isAfter(cursor)) {
        candidate = candidate.add(Duration(days: 7 * interval));
      }
      return candidate;
    }
    final int desiredDay = dayOfMonth ?? base.day;
    int year = base.year;
    int month = base.month;
    DateTime candidate = base;
    while (!candidate.isAfter(cursor)) {
      month += interval;
      year += (month - 1) ~/ 12;
      month = ((month - 1) % 12) + 1;
      final int lastDay = DateTime.utc(year, month + 1, 0).day;
      candidate = DateTime.utc(year, month, desiredDay.clamp(1, lastDay).toInt(), base.hour, base.minute, base.second, base.millisecond, base.microsecond);
    }
    return candidate;
  }

  static String? label({String? frequency, int? interval, int? weekdaysMask}) {
    if (frequency == null) return null;
    final String prefix = interval == null || interval == 1 ? '' : 'Every $interval ';
    if (frequency == 'weekly' && weekdaysMask != null) {
      const List<String> names = <String>['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
      final List<String> selected = <String>[
        for (int index = 0; index < names.length; index++)
          if ((weekdaysMask & (1 << index)) != 0) names[index],
      ];
      return selected.isEmpty ? '${prefix}week' : 'Every ${selected.join(', ')}';
    }
    return '$prefix${frequency == 'daily' ? 'day' : frequency == 'weekly' ? 'week' : 'month'}';
  }
}
