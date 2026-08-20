import 'package:daytrace/features/settings/data/settings_repository.dart';
import 'package:daytrace/features/tasks/data/task_repository.dart';

/// Calculates one safe local prompt. Scheduling is repeated only after the
/// user reopens DayTrace or resolves the previous prompt.
class SmartPromptPolicy {
  const SmartPromptPolicy();

  DateTime? nextPromptAt({
    required DateTime now,
    required TrackingSettings settings,
    required ActiveActivity? activeActivity,
  }) {
    if (activeActivity != null || settings.promptMinutes <= 0) return null;

    final DateTime localNow = now.toLocal();
    if (!settings.workingDays.contains(localNow.weekday)) return null;
    if (_isQuietHour(localNow.hour, settings)) return null;
    final DateTime start = DateTime(
      localNow.year,
      localNow.month,
      localNow.day,
      settings.startHour,
    );
    final DateTime end = DateTime(
      localNow.year,
      localNow.month,
      localNow.day,
      settings.endHour,
    );
    if (!localNow.isAfter(start) || !localNow.isBefore(end)) return null;

    final DateTime prompt = localNow.add(
      Duration(minutes: settings.promptMinutes),
    );
    return prompt.isBefore(end) ? prompt.toUtc() : null;
  }

  bool _isQuietHour(int hour, TrackingSettings settings) {
    final int? start = settings.quietStartHour;
    final int? end = settings.quietEndHour;
    if (start == null || end == null || start == end) return false;
    return start < end
        ? hour >= start && hour < end
        : hour >= start || hour < end;
  }
}
