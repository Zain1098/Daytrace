import 'dart:async';

import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest.dart' as tz;
import 'package:timezone/timezone.dart' as tz;

final NotificationService dayTraceNotificationService = NotificationService();

class NotificationService {
  static const int smartPromptNotificationId = 900002;

  NotificationService({FlutterLocalNotificationsPlugin? plugin})
      : _plugin = plugin ?? FlutterLocalNotificationsPlugin();

  final FlutterLocalNotificationsPlugin _plugin;
  final StreamController<NotificationAction> _actions =
      StreamController<NotificationAction>.broadcast();
  final List<NotificationAction> _pendingActions = <NotificationAction>[];
  bool _initialized = false;

  Stream<NotificationAction> get actions => _actions.stream;

  Future<void> initialize() async {
    if (_initialized) return;
    tz.initializeTimeZones();
    await _plugin.initialize(
      settings: const InitializationSettings(
        android: AndroidInitializationSettings('@mipmap/ic_launcher'),
      ),
      onDidReceiveNotificationResponse: _onNotificationResponse,
    );
    final NotificationAppLaunchDetails? launchDetails =
        await _plugin.getNotificationAppLaunchDetails();
    final NotificationResponse? launchResponse = launchDetails?.notificationResponse;
    if (launchDetails?.didNotificationLaunchApp == true && launchResponse != null) {
      _onNotificationResponse(launchResponse);
    }
    _initialized = true;
  }

  void _onNotificationResponse(NotificationResponse response) {
    final String? payload = response.payload;
    final String? actionId = response.actionId;
    if (actionId == null || actionId.isEmpty) return;
    if (payload == 'smart_prompt') {
      _emitAction(NotificationAction.smartPrompt(actionId: actionId));
      return;
    }
    if (payload == null || !payload.startsWith('reminder:')) return;
    final List<String> parts = payload.split(':');
    if (parts.length != 3) return;
    _emitAction(NotificationAction.reminder(
        actionId: actionId,
        reminderId: parts[1],
        taskId: parts[2],
      ));
  }

  void _emitAction(NotificationAction action) {
    if (_actions.hasListener) {
      _actions.add(action);
    } else {
      _pendingActions.add(action);
    }
  }

  List<NotificationAction> takePendingActions() {
    final List<NotificationAction> actions = List<NotificationAction>.from(_pendingActions);
    _pendingActions.clear();
    return actions;
  }

  Future<bool> requestPermission() async {
    await initialize();
    return await _plugin
            .resolvePlatformSpecificImplementation<
                AndroidFlutterLocalNotificationsPlugin>()
            ?.requestNotificationsPermission() ??
        false;
  }

  Future<void> scheduleTaskReminder({
    required int notificationId,
    required DateTime scheduledAt,
    required String title,
    required String reminderId,
    required String taskId,
  }) async {
    await initialize();
    await _plugin.zonedSchedule(
      id: notificationId,
      title: 'DayTrace reminder',
      body: title,
      scheduledDate: tz.TZDateTime.from(scheduledAt.toUtc(), tz.UTC),
      notificationDetails: const NotificationDetails(
        android: AndroidNotificationDetails(
          'task_reminders',
          'Task reminders',
          channelDescription: 'Scheduled DayTrace task reminders',
          importance: Importance.high,
          priority: Priority.high,
          actions: <AndroidNotificationAction>[
            AndroidNotificationAction('start', 'Start'),
            AndroidNotificationAction('complete', 'Complete'),
            AndroidNotificationAction('snooze_10', 'Snooze 10 min'),
            AndroidNotificationAction('dismiss', 'Dismiss'),
          ],
        ),
      ),
      androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      payload: 'reminder:$reminderId:$taskId',
    );
  }

  Future<void> cancel(int notificationId) async {
    await initialize();
    await _plugin.cancel(id: notificationId);
  }

  Future<void> scheduleSmartPrompt({required DateTime scheduledAt}) async {
    await initialize();
    await _plugin.zonedSchedule(
      id: smartPromptNotificationId,
      title: 'What are you doing?',
      body: 'No activity is running. Add what you are working on to keep today accurate.',
      scheduledDate: tz.TZDateTime.from(scheduledAt.toUtc(), tz.UTC),
      notificationDetails: const NotificationDetails(
        android: AndroidNotificationDetails(
          'smart_prompts',
          'Smart prompts',
          channelDescription: 'Helpful prompts for untracked time',
          importance: Importance.defaultImportance,
          priority: Priority.defaultPriority,
          actions: <AndroidNotificationAction>[
            AndroidNotificationAction(
              'open',
              'Open DayTrace',
              showsUserInterface: true,
            ),
            AndroidNotificationAction(
              'past',
              'Add past activity',
              showsUserInterface: true,
            ),
            AndroidNotificationAction(
              'break',
              'Start break',
              showsUserInterface: true,
            ),
            AndroidNotificationAction(
              'meeting',
              'Start meeting',
              showsUserInterface: true,
            ),
            AndroidNotificationAction(
              'ignore',
              'Ignore',
              showsUserInterface: true,
            ),
          ],
        ),
      ),
      androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      payload: 'smart_prompt',
    );
  }

  Future<void> cancelSmartPrompt() => cancel(smartPromptNotificationId);

  Future<void> showUpdateAvailable({required String version}) async {
    await initialize();
    await _plugin.show(
      id: 900001,
      title: 'DayTrace update available',
      body: 'Version $version is ready to download.',
      notificationDetails: const NotificationDetails(
        android: AndroidNotificationDetails('app_updates', 'App updates', channelDescription: 'DayTrace update availability'),
      ),
      payload: 'update',
    );
  }
}

enum NotificationActionKind { reminder, smartPrompt }

class NotificationAction {
  const NotificationAction.reminder({
    required this.actionId,
    required this.reminderId,
    required this.taskId,
  }) : kind = NotificationActionKind.reminder;

  const NotificationAction.smartPrompt({required this.actionId})
    : kind = NotificationActionKind.smartPrompt,
      reminderId = null,
      taskId = null;

  final NotificationActionKind kind;
  final String actionId;
  final String? reminderId;
  final String? taskId;
}
