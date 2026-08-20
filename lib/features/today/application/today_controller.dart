import 'dart:async';

import 'package:daytrace/core/database/app_database.dart';
import 'package:daytrace/core/notifications/notification_service.dart';
import 'package:daytrace/core/platform/widget_launch_service.dart';
import 'package:daytrace/core/voice/voice_capture_service.dart';
import 'package:daytrace/features/reminders/application/smart_prompt_policy.dart';
import 'package:daytrace/features/settings/data/settings_repository.dart';
import 'package:daytrace/features/tasks/data/task_repository.dart';
import 'package:daytrace/features/updates/data/app_update_service.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final Provider<AppDatabase> appDatabaseProvider = Provider<AppDatabase>(
  (Ref ref) => AppDatabase(),
);

final Provider<TaskRepository> taskRepositoryProvider = Provider<TaskRepository>(
  (Ref ref) => TaskRepository(ref.watch(appDatabaseProvider)),
);
final Provider<NotificationService> notificationServiceProvider = Provider<NotificationService>(
  (Ref ref) => dayTraceNotificationService,
);
final Provider<VoiceCaptureService> voiceCaptureServiceProvider = Provider<VoiceCaptureService>((Ref ref) => VoiceCaptureService());

final AsyncNotifierProvider<TodayController, TodayData> todayControllerProvider =
    AsyncNotifierProvider<TodayController, TodayData>(TodayController.new);

final NotifierProvider<SmartPromptOpenNotifier, int>
    smartPromptOpenRequestProvider =
    NotifierProvider<SmartPromptOpenNotifier, int>(SmartPromptOpenNotifier.new);

final NotifierProvider<SmartPromptPastActivityNotifier, int>
    smartPromptPastActivityRequestProvider =
    NotifierProvider<SmartPromptPastActivityNotifier, int>(
      SmartPromptPastActivityNotifier.new,
    );

class SmartPromptOpenNotifier extends Notifier<int> {
  @override
  int build() => 0;

  void request() => state++;
}

class SmartPromptPastActivityNotifier extends Notifier<int> {
  @override
  int build() => 0;

  void request() => state++;

  void consume() => state = 0;
}

final StreamProvider<int> widgetQuickAddProvider = StreamProvider<int>(
  (Ref ref) => widgetLaunchService.quickAddRequests,
);

class TodayController extends AsyncNotifier<TodayData> {
  @override
  Future<TodayData> build() async {
    final NotificationService notifications = ref.read(notificationServiceProvider);
    await notifications.initialize();
    await _restoreFutureReminders();
    unawaited(_checkForUpdateInBackground());
    final StreamSubscription<NotificationAction> subscription = notifications.actions.listen(_handleNotificationAction);
    ref.onDispose(subscription.cancel);
    for (final NotificationAction action in notifications.takePendingActions()) {
      unawaited(_handleNotificationAction(action));
    }
    final TodayData today = await ref.read(taskRepositoryProvider).loadToday();
    await _syncSmartPrompt(today);
    return today;
  }

  Future<List<CategoryItem>> loadCategories() =>
      ref.read(taskRepositoryProvider).loadCategories();

  Future<bool> requestNotificationPermission() =>
      ref.read(notificationServiceProvider).requestPermission();

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
    bool scheduleReminder = false,
  }) async {
    final TaskRepository repository = ref.read(taskRepositoryProvider);
    final String taskId = await repository.createTask(
      title: title,
      startNow: startNow,
      categoryId: categoryId,
      description: description,
      priority: priority,
      plannedAt: plannedAt,
      dueAt: dueAt,
      estimatedMinutes: estimatedMinutes,
      subtaskTitles: subtaskTitles,
      recurrence: recurrence,
    );
    if (scheduleReminder && dueAt != null) {
      final ReminderItem reminder = await repository.createReminder(
        taskId: taskId,
        scheduledAt: dueAt,
        timezoneName: 'UTC',
      );
      try {
        await ref.read(notificationServiceProvider).scheduleTaskReminder(
          notificationId: reminder.notificationId,
          scheduledAt: dueAt,
          title: title.trim(),
          reminderId: reminder.id,
          taskId: taskId,
        );
      } catch (_) {
        await repository.cancelReminder(reminder.id);
        rethrow;
      }
    }
    final TodayData today = await repository.loadToday();
    state = AsyncData(today);
    await _syncSmartPrompt(today);
    return taskId;
  }

  Future<void> pauseActiveTask() => _runTimerAction(
    (TaskRepository repository) => repository.pauseActiveTask(),
  );

  Future<void> completeActiveTask() async {
    final TaskRepository repository = ref.read(taskRepositoryProvider);
    final List<int> notificationIds = await repository.completeActiveTask();
    await _cancelPlatformNotifications(notificationIds);
    await _restoreFutureReminders();
    final TodayData today = await repository.loadToday();
    state = AsyncData(today);
    await _syncSmartPrompt(today);
  }

  Future<void> completeTask(String taskId) async {
    final List<int> notificationIds = await ref.read(taskRepositoryProvider).completeTask(taskId);
    await _cancelPlatformNotifications(notificationIds);
    await _restoreFutureReminders();
    final TodayData today = await ref.read(taskRepositoryProvider).loadToday();
    state = AsyncData(today);
    await _syncSmartPrompt(today);
  }

  Future<void> cancelTask(String taskId) async {
    final List<int> notificationIds = await ref.read(taskRepositoryProvider).cancelTask(taskId);
    await _cancelPlatformNotifications(notificationIds);
    final TodayData today = await ref.read(taskRepositoryProvider).loadToday();
    state = AsyncData(today);
    await _syncSmartPrompt(today);
  }

  Future<void> startTask(String taskId) => _runTimerAction(
    (TaskRepository repository) => repository.startTask(taskId),
  );

  Future<void> resumeTask(String taskId) => _runTimerAction(
    (TaskRepository repository) => repository.resumeTask(taskId),
  );

  Future<void> switchToNewTask({
    required String title,
    required ActiveTaskDisposition disposition,
  }) => _runTimerAction(
    (TaskRepository repository) => repository.switchToNewTask(
      title: title,
      disposition: disposition,
    ),
  );

  Future<void> switchToTask({
    required String taskId,
    required ActiveTaskDisposition disposition,
  }) => _runTimerAction(
    (TaskRepository repository) => repository.switchToTask(
      taskId: taskId,
      disposition: disposition,
    ),
  );

  Future<void> _runTimerAction(
    Future<void> Function(TaskRepository repository) action,
  ) async {
    final TaskRepository repository = ref.read(taskRepositoryProvider);
    await action(repository);
    final TodayData today = await repository.loadToday();
    state = AsyncData(today);
    await _syncSmartPrompt(today);
  }

  Future<void> refresh() async {
    final TodayData today = await ref.read(taskRepositoryProvider).loadToday();
    state = AsyncData(today);
    await _syncSmartPrompt(today);
  }

  Future<void> _handleNotificationAction(NotificationAction action) async {
    final TaskRepository repository = ref.read(taskRepositoryProvider);
    try {
      if (action.kind == NotificationActionKind.smartPrompt) {
        switch (action.actionId) {
          case 'open':
            ref.read(smartPromptOpenRequestProvider.notifier).request();
            break;
          case 'past':
            ref.read(smartPromptPastActivityRequestProvider.notifier).request();
            break;
          case 'break':
            await repository.createTask(
              title: 'Break',
              startNow: true,
              categoryId: 'break',
            );
            break;
          case 'meeting':
            await repository.createTask(
              title: 'Meeting',
              startNow: true,
              categoryId: 'meeting',
            );
            break;
          case 'ignore':
            break;
          default:
            return;
        }
        await refresh();
        return;
      }

      final String reminderId = action.reminderId!;
      final String taskId = action.taskId!;
      switch (action.actionId) {
        case 'start':
          final int? notificationId = await repository.dismissReminderAndGetNotificationId(reminderId);
          await repository.startTask(taskId);
          if (notificationId != null) await _cancelPlatformNotifications(<int>[notificationId]);
          break;
        case 'complete':
          final List<int> notificationIds = await repository.completeTask(taskId);
          await _cancelPlatformNotifications(notificationIds);
          break;
        case 'snooze_10':
          final ReminderItem reminder = await repository.snoozeReminder(reminderId, const Duration(minutes: 10));
          final String title = await repository.taskTitle(reminder.taskId);
          await ref.read(notificationServiceProvider).scheduleTaskReminder(
            notificationId: reminder.notificationId,
            scheduledAt: reminder.scheduledAt,
            title: title,
            reminderId: reminder.id,
            taskId: reminder.taskId,
          );
          break;
        case 'dismiss':
          final int? notificationId = await repository.dismissReminderAndGetNotificationId(reminderId);
          if (notificationId != null) await _cancelPlatformNotifications(<int>[notificationId]);
          break;
        default:
          return;
      }
      await refresh();
    } on StateError {
      // Notification responses can be delivered again after process restart.
      // The repository transitions are intentionally idempotent in that case.
    }
  }

  Future<void> _cancelPlatformNotifications(List<int> notificationIds) async {
    final NotificationService notifications = ref.read(notificationServiceProvider);
    for (final int notificationId in notificationIds) {
      await notifications.cancel(notificationId);
    }
  }

  Future<void> _restoreFutureReminders() async {
    final TaskRepository repository = ref.read(taskRepositoryProvider);
    final NotificationService notifications = ref.read(notificationServiceProvider);
    final List<ScheduledReminder> reminders = await repository.loadFutureScheduledReminders();
    for (final ScheduledReminder reminder in reminders) {
      await notifications.scheduleTaskReminder(
        notificationId: reminder.notificationId,
        scheduledAt: reminder.scheduledAt,
        title: reminder.title,
        reminderId: reminder.id,
        taskId: reminder.taskId,
      );
    }
  }

  Future<void> _syncSmartPrompt(TodayData today) async {
    final NotificationService notifications = ref.read(
      notificationServiceProvider,
    );
    final TrackingSettings settings = await SettingsRepository(
      ref.read(appDatabaseProvider),
    ).loadTracking();
    final DateTime? promptAt = const SmartPromptPolicy().nextPromptAt(
      now: DateTime.now(),
      settings: settings,
      activeActivity: today.active,
    );
    try {
      if (promptAt == null) {
        await notifications.cancelSmartPrompt();
      } else {
        await notifications.scheduleSmartPrompt(scheduledAt: promptAt);
      }
    } catch (_) {
      // Smart prompts are optional assistance and must not block offline tasks
      // when notification permission or device scheduling is unavailable.
    }
  }

  Future<void> _checkForUpdateInBackground() async {
    try {
      final AppUpdateInfo update = await AppUpdateService(ref.read(appDatabaseProvider)).checkForUpdate();
      if (update.isAvailable) await ref.read(notificationServiceProvider).showUpdateAvailable(version: update.latestTag);
    } catch (_) {
      // Update checks are optional and must never block the offline core app.
    }
  }
}
