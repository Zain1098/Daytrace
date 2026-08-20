import 'package:daytrace/core/database/app_database.dart';
import 'package:daytrace/core/time/clock.dart';
import 'package:daytrace/features/reports/data/report_repository.dart';
import 'package:daytrace/features/reminders/application/smart_prompt_policy.dart';
import 'package:daytrace/features/settings/data/settings_repository.dart';
import 'package:daytrace/features/tasks/data/task_repository.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeClock implements Clock {
  _FakeClock(this.value);

  DateTime value;

  @override
  DateTime now() => value;
}

void main() {
  late AppDatabase database;
  late TaskRepository repository;
  late _FakeClock clock;

  setUp(() async {
    database = AppDatabase(executor: NativeDatabase.memory());
    clock = _FakeClock(DateTime.utc(2026, 8, 11, 9));
    repository = TaskRepository(database, clock: clock);
    await database.initialize();
  });

  tearDown(() => database.close());

  test('Start Now persists an in-progress task and one open time entry', () async {
    await repository.createTask(title: 'Inspect machine', startNow: true);

    final TodayData today = await repository.loadToday();
    final List<Map<String, Object?>> openEntries = await database.select(
      'SELECT id FROM time_entries WHERE end_at IS NULL',
    );

    expect(today.active?.title, 'Inspect machine');
    expect(today.tasks.single.status, 'in_progress');
    expect(openEntries, hasLength(1));
  });

  test('version 3 migration provides planning, reminder, and settings tables', () async {
    final List<Map<String, Object?>> taskColumns = await database.select(
      'PRAGMA table_info(tasks)',
    );
    final List<Map<String, Object?>> tables = await database.select(
      "SELECT name FROM sqlite_master WHERE type = 'table'",
    );

    expect(taskColumns.map((Map<String, Object?> row) => row['name']), containsAll(<String>[
      'description',
      'priority',
      'planned_at',
      'due_at',
      'estimated_minutes',
      'cancelled_at',
    ]));
    expect(tables.map((Map<String, Object?> row) => row['name']), containsAll(<String>[
      'subtasks',
      'recurrence_rules',
      'reminders',
      'app_settings',
      'schema_migrations',
    ]));
  });

  test('theme preference persists locally', () async {
    final SettingsRepository settings = SettingsRepository(database);

    await settings.saveThemeMode(ThemeMode.dark);

    expect(await settings.loadThemeMode(), ThemeMode.dark);
  });

  test('smart prompts stay inside tracking hours', () {
    const SmartPromptPolicy policy = SmartPromptPolicy();
    const TrackingSettings settings = TrackingSettings(
      startHour: 9,
      endHour: 17,
      promptMinutes: 60,
    );

    expect(
      policy.nextPromptAt(
        now: DateTime(2026, 8, 19, 10),
        settings: settings,
        activeActivity: null,
      ),
      DateTime(2026, 8, 19, 11).toUtc(),
    );
    expect(
      policy.nextPromptAt(
        now: DateTime(2026, 8, 19, 16, 30),
        settings: settings,
        activeActivity: null,
      ),
      isNull,
    );
  });

  test('task persists the selected category', () async {
    await repository.createTask(
      title: 'Read chapter',
      startNow: false,
      categoryId: 'study',
    );

    final List<Map<String, Object?>> tasks = await database.select(
      'SELECT category_id FROM tasks WHERE title = ?',
      <Object?>['Read chapter'],
    );

    expect(tasks.single['category_id'], 'study');
  });

  test('task persists planning details using UTC timestamps', () async {
    final DateTime plannedAt = DateTime.utc(2026, 8, 12, 9);
    final DateTime dueAt = DateTime.utc(2026, 8, 12, 17);
    await repository.createTask(
      title: 'Prepare presentation',
      startNow: false,
      description: 'Review the production update.',
      priority: 'high',
      plannedAt: plannedAt,
      dueAt: dueAt,
      estimatedMinutes: 90,
    );

    final List<Map<String, Object?>> tasks = await database.select(
      '''SELECT description, priority, planned_at, due_at, estimated_minutes
         FROM tasks WHERE title = ?''',
      <Object?>['Prepare presentation'],
    );

    expect(tasks.single['description'], 'Review the production update.');
    expect(tasks.single['priority'], 'high');
    expect(tasks.single['planned_at'], plannedAt.millisecondsSinceEpoch);
    expect(tasks.single['due_at'], dueAt.millisecondsSinceEpoch);
    expect(tasks.single['estimated_minutes'], 90);
  });

  test('Today task includes its category display details', () async {
    await repository.createTask(
      title: 'Read chapter',
      startNow: false,
      categoryId: 'study',
    );

    final TodayData today = await repository.loadToday();

    expect(today.tasks.single.categoryName, 'Study');
    expect(today.tasks.single.categoryColorValue, 0xFF40A475);
  });

  test('Today tracked duration clips an entry that started before midnight', () async {
    clock.value = DateTime.utc(2026, 8, 11, 0, 30);
    await database.insert(
      '''INSERT INTO time_entries
         (id, entry_type, start_at, end_at, source, created_at, updated_at)
         VALUES (?, 'manual', ?, ?, 'manual', ?, ?)''',
      <Object?>[
        'cross-midnight-entry',
        DateTime.utc(2026, 8, 10, 23).millisecondsSinceEpoch,
        DateTime.utc(2026, 8, 11, 1).millisecondsSinceEpoch,
        DateTime.utc(2026, 8, 10, 23).millisecondsSinceEpoch,
        DateTime.utc(2026, 8, 11, 1).millisecondsSinceEpoch,
      ],
    );

    final TodayData today = await repository.loadToday();

    expect(today.trackedMinutes, 30);
  });

  test('Today tracked duration includes the active interval up to now', () async {
    await repository.createTask(title: 'Inspect machine', startNow: true);
    clock.value = DateTime.utc(2026, 8, 11, 9, 47);

    final TodayData today = await repository.loadToday();

    expect(today.trackedMinutes, 47);
  });

  test('cannot start a second activity while one is open', () async {
    await repository.createTask(title: 'First task', startNow: true);

    await expectLater(
      repository.createTask(title: 'Second task', startNow: true),
      throwsA(isA<StateError>()),
    );
  });

  test('a planned task can be started without creating a duplicate task', () async {
    await repository.createTask(title: 'Inspect machine', startNow: false);
    final String taskId = (await repository.loadToday()).tasks.single.id;

    await repository.startTask(taskId);

    final TodayData today = await repository.loadToday();
    expect(today.active?.id, taskId);
    expect(today.tasks, hasLength(1));
    expect(today.tasks.single.status, 'in_progress');
  });

  test('a planned task can be completed without creating a time entry', () async {
    await repository.createTask(title: 'Send report', startNow: false);
    final String taskId = (await repository.loadToday()).tasks.single.id;
    clock.value = DateTime.utc(2026, 8, 11, 9, 45);

    await repository.completeTask(taskId);

    final TodayData today = await repository.loadToday();
    final List<Map<String, Object?>> tasks = await database.select(
      'SELECT status, completed_at FROM tasks WHERE id = ?',
      <Object?>[taskId],
    );
    final List<Map<String, Object?>> entries = await database.select(
      'SELECT id FROM time_entries WHERE task_id = ?',
      <Object?>[taskId],
    );
    expect(today.tasks, isEmpty);
    expect(today.completedCount, 1);
    expect(tasks.single['status'], 'completed');
    expect(tasks.single['completed_at'], clock.value.millisecondsSinceEpoch);
    expect(entries, isEmpty);
  });

  test('a paused task can be cancelled while retaining its recorded interval', () async {
    await repository.createTask(title: 'Study notes', startNow: true);
    clock.value = DateTime.utc(2026, 8, 11, 9, 20);
    await repository.pauseActiveTask();
    final String taskId = (await repository.loadToday()).tasks.single.id;

    await repository.cancelTask(taskId);

    final TodayData today = await repository.loadToday();
    final List<Map<String, Object?>> taskRows = await database.select(
      'SELECT status FROM tasks WHERE id = ?',
      <Object?>[taskId],
    );
    final List<Map<String, Object?>> entries = await database.select(
      'SELECT end_at FROM time_entries WHERE task_id = ?',
      <Object?>[taskId],
    );
    expect(today.tasks, isEmpty);
    expect(taskRows.single['status'], 'cancelled');
    expect(entries.single['end_at'], isNotNull);
  });

  test('all-task query includes completed and cancelled tasks', () async {
    await repository.createTask(title: 'Completed task', startNow: false);
    await repository.createTask(title: 'Cancelled task', startNow: false);
    final List<TaskItem> initial = await repository.loadAllTasks();
    final String completedId = initial
        .singleWhere((TaskItem task) => task.title == 'Completed task')
        .id;
    final String cancelledId = initial
        .singleWhere((TaskItem task) => task.title == 'Cancelled task')
        .id;

    await repository.completeTask(completedId);
    await repository.cancelTask(cancelledId);

    final List<TaskItem> allTasks = await repository.loadAllTasks();
    expect(allTasks.map((TaskItem task) => task.status), contains('completed'));
    expect(allTasks.map((TaskItem task) => task.status), contains('cancelled'));
  });

  test('switching to a planned task leaves exactly one open time entry', () async {
    await repository.createTask(title: 'First task', startNow: true);
    await repository.createTask(title: 'Second task', startNow: false);
    final String secondTaskId = (await repository.loadToday()).tasks
        .singleWhere((TaskItem task) => task.title == 'Second task')
        .id;
    clock.value = DateTime.utc(2026, 8, 11, 9, 15);

    await repository.switchToTask(
      taskId: secondTaskId,
      disposition: ActiveTaskDisposition.pause,
    );

    final TodayData today = await repository.loadToday();
    final List<Map<String, Object?>> openEntries = await database.select(
      'SELECT id FROM time_entries WHERE end_at IS NULL',
    );
    expect(today.active?.id, secondTaskId);
    expect(openEntries, hasLength(1));
  });

  test('pause closes the entry and preserves the task as paused', () async {
    await repository.createTask(title: 'Study notes', startNow: true);
    clock.value = DateTime.utc(2026, 8, 11, 9, 25);

    await repository.pauseActiveTask();

    final TodayData today = await repository.loadToday();
    final List<Map<String, Object?>> entries = await database.select(
      'SELECT start_at, end_at FROM time_entries',
    );
    expect(today.active, isNull);
    expect(today.tasks.single.status, 'paused');
    expect(entries.single['end_at'], greaterThan(entries.single['start_at']!));
  });

  test('complete closes the entry and removes the task from active plans', () async {
    await repository.createTask(title: 'Send report', startNow: true);
    clock.value = DateTime.utc(2026, 8, 11, 10);

    await repository.completeActiveTask();

    final TodayData today = await repository.loadToday();
    final List<Map<String, Object?>> taskRows = await database.select(
      'SELECT status, completed_at FROM tasks',
    );
    expect(today.active, isNull);
    expect(today.tasks, isEmpty);
    expect(today.completedCount, 1);
    expect(taskRows.single['status'], 'completed');
    expect(taskRows.single['completed_at'], isNotNull);
  });

  test('resume opens a new interval for a paused task', () async {
    await repository.createTask(title: 'Study notes', startNow: true);
    clock.value = DateTime.utc(2026, 8, 11, 9, 20);
    await repository.pauseActiveTask();
    final String taskId = (await repository.loadToday()).tasks.single.id;
    clock.value = DateTime.utc(2026, 8, 11, 10);

    await repository.resumeTask(taskId);

    final TodayData today = await repository.loadToday();
    final List<Map<String, Object?>> entries = await database.select(
      'SELECT end_at FROM time_entries ORDER BY start_at',
    );
    expect(today.active?.id, taskId);
    expect(entries, hasLength(2));
    expect(entries.first['end_at'], isNotNull);
    expect(entries.last['end_at'], isNull);
  });

  test('switch pauses current task and starts the requested task atomically', () async {
    await repository.createTask(title: 'First task', startNow: true);
    clock.value = DateTime.utc(2026, 8, 11, 9, 15);

    await repository.switchToNewTask(
      title: 'Second task',
      disposition: ActiveTaskDisposition.pause,
    );

    final TodayData today = await repository.loadToday();
    expect(today.active?.title, 'Second task');
    expect(today.tasks.map((TaskItem task) => task.status), containsAll(<String>['in_progress', 'paused']));
    final List<Map<String, Object?>> entries = await database.select(
      'SELECT id FROM time_entries WHERE end_at IS NULL',
    );
    expect(entries, hasLength(1));
  });

  test('task persists subtasks and their completion state', () async {
    await repository.createTask(
      title: 'Prepare shift handover',
      startNow: false,
      subtaskTitles: <String>['Collect readings', 'Send summary', ''],
    );
    final String taskId = (await repository.loadToday()).tasks.single.id;

    TaskDetails details = await repository.loadTaskDetails(taskId);
    expect(details.subtasks.map((SubtaskItem item) => item.title), <String>[
      'Collect readings',
      'Send summary',
    ]);

    await repository.setSubtaskCompleted(
      subtaskId: details.subtasks.first.id,
      completed: true,
    );
    details = await repository.loadTaskDetails(taskId);
    expect(details.subtasks.first.isCompleted, isTrue);
  });

  test('completing a daily recurring task creates one planned next occurrence', () async {
    final DateTime dueAt = DateTime.utc(2026, 8, 11, 17);
    await repository.createTask(
      title: 'Write daily log',
      startNow: false,
      dueAt: dueAt,
      subtaskTitles: <String>['Review timeline'],
      recurrence: const RecurrenceDraft(frequency: 'daily'),
    );
    final String taskId = (await repository.loadToday()).tasks.single.id;
    clock.value = DateTime.utc(2026, 8, 11, 18);

    await repository.completeTask(taskId);

    final List<Map<String, Object?>> tasks = await database.select(
      '''SELECT status, due_at FROM tasks WHERE title = ? ORDER BY created_at''',
      <Object?>['Write daily log'],
    );
    final List<Map<String, Object?>> nextSubtasks = await database.select(
      '''SELECT s.title FROM subtasks s
         INNER JOIN tasks t ON t.id = s.task_id
         WHERE t.title = ? AND t.status = 'planned' ''',
      <Object?>['Write daily log'],
    );
    expect(tasks.map((Map<String, Object?> row) => row['status']), containsAll(<String>[
      'completed',
      'planned',
    ]));
    expect(
      tasks.singleWhere((Map<String, Object?> row) => row['status'] == 'planned')['due_at'],
      DateTime.utc(2026, 8, 12, 17).millisecondsSinceEpoch,
    );
    expect(nextSubtasks.single['title'], 'Review timeline');
  });

  test('weekday recurrence selects the next configured weekday', () {
    final DateTime next = RecurrenceDraft.nextOccurrence(
      after: DateTime.utc(2026, 8, 11, 18), // Tuesday
      anchor: DateTime.utc(2026, 8, 11, 9),
      frequency: 'weekly',
      interval: 1,
      weekdaysMask: (1 << 0) | (1 << 2), // Monday and Wednesday
    );
    expect(next, DateTime.utc(2026, 8, 12, 9));
  });

  test('editing a timeline entry rejects an overlap', () async {
    await repository.createManualEntry(
      startAt: DateTime.utc(2026, 8, 11, 9),
      endAt: DateTime.utc(2026, 8, 11, 10),
      note: 'First activity',
    );
    await repository.createManualEntry(
      startAt: DateTime.utc(2026, 8, 11, 11),
      endAt: DateTime.utc(2026, 8, 11, 12),
      note: 'Second activity',
    );
    final String firstId = (await repository.loadTimeline(DateTime.utc(2026, 8, 11))).first.id;

    await expectLater(
      repository.updateTimeEntry(
        entryId: firstId,
        startAt: DateTime.utc(2026, 8, 11, 9),
        endAt: DateTime.utc(2026, 8, 11, 11, 30),
        note: 'Edited',
        entryType: 'manual',
      ),
      throwsA(isA<StateError>()),
    );
  });

  test('splitting an activity creates adjacent entries and reassigns safely', () async {
    await repository.createTask(title: 'Machine inspection', startNow: false);
    final String taskId = (await repository.loadToday()).tasks.single.id;
    await repository.createManualEntry(
      startAt: DateTime.utc(2026, 8, 11, 9),
      endAt: DateTime.utc(2026, 8, 11, 11),
      note: 'Inspection preparation',
    );
    final String entryId = (await repository.loadTimeline(DateTime.utc(2026, 8, 11))).single.id;

    await repository.splitTimeEntry(
      entryId: entryId,
      splitAt: DateTime.utc(2026, 8, 11, 10),
      secondNote: 'Inspection execution',
    );
    final List<TimelineItem> entries = await repository.loadTimeline(DateTime.utc(2026, 8, 11));
    expect(entries, hasLength(2));
    expect(entries.first.endAt, DateTime.utc(2026, 8, 11, 10));
    expect(entries.last.startAt, DateTime.utc(2026, 8, 11, 10));

    await repository.updateTimeEntry(
      entryId: entries.last.id,
      startAt: entries.last.startAt,
      endAt: entries.last.endAt!,
      note: entries.last.note ?? '',
      entryType: 'task',
      taskId: taskId,
    );
    final TimelineItem updated = (await repository.loadTimeline(DateTime.utc(2026, 8, 11))).last;
    expect(updated.taskId, taskId);
    expect(updated.entryType, 'task');
  });

  test('daily notes and weekly report are built from local records', () async {
    await repository.createManualEntry(
      startAt: DateTime.utc(2026, 8, 11, 9),
      endAt: DateTime.utc(2026, 8, 11, 10, 30),
      note: 'Weekly planning',
    );
    await repository.createManualEntry(
      startAt: DateTime.utc(2026, 8, 12, 9),
      endAt: DateTime.utc(2026, 8, 12, 11),
      note: 'Inspection',
    );
    await repository.saveDailyNote(DateTime.utc(2026, 8, 11), 'Machine was offline for one hour.');
    final ReportRepository reports = ReportRepository(repository);

    final DailyReport daily = await reports.loadDaily(DateTime.utc(2026, 8, 11));
    final WeeklyReport weekly = await reports.loadWeekly(DateTime.utc(2026, 8, 11));

    expect(daily.note, 'Machine was offline for one hour.');
    expect(daily.trackedMinutes, 90);
    expect(weekly.trackedMinutes, 210);
    expect(weekly.localSummary, contains('Tracked time: 3h 30m'));
  });

  test('onboarding completion is persisted locally', () async {
    final SettingsRepository settings = SettingsRepository(database);

    expect(await settings.isOnboardingComplete(), isFalse);
    await settings.setOnboardingComplete(true);
    expect(await settings.isOnboardingComplete(), isTrue);
  });
}
