import 'package:daytrace/features/reminders/application/end_of_day_review_policy.dart';
import 'package:daytrace/features/settings/data/settings_repository.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const EndOfDayReviewPolicy policy = EndOfDayReviewPolicy();
  const TrackingSettings settings = TrackingSettings(startHour: 9, endHour: 17);

  test('schedules review at the local tracking end on a working day', () {
    expect(
      policy.nextReviewAt(now: DateTime(2026, 8, 19, 10), settings: settings),
      DateTime(2026, 8, 19, 17).toUtc(),
    );
  });

  test('does not schedule a review after the workday or on a non-working day', () {
    expect(
      policy.nextReviewAt(now: DateTime(2026, 8, 19, 17), settings: settings),
      isNull,
    );
    expect(
      policy.nextReviewAt(now: DateTime(2026, 8, 23, 10), settings: settings),
      isNull,
    );
  });
}
