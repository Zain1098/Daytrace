import 'package:daytrace/features/settings/data/settings_repository.dart';

/// Schedules one local review prompt at the end of the selected tracking day.
class EndOfDayReviewPolicy {
  const EndOfDayReviewPolicy();

  DateTime? nextReviewAt({
    required DateTime now,
    required TrackingSettings settings,
  }) {
    final DateTime localNow = now.toLocal();
    if (!settings.isWorkingDay(localNow)) return null;
    final DateTime reviewAt = DateTime(
      localNow.year,
      localNow.month,
      localNow.day,
      settings.endHour,
    );
    return reviewAt.isAfter(localNow) ? reviewAt.toUtc() : null;
  }
}
