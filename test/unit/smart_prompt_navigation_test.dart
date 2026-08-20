import 'package:daytrace/core/notifications/notification_service.dart';
import 'package:daytrace/features/today/application/today_controller.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('past-activity request is consumed after navigation handoff', () {
    final ProviderContainer container = ProviderContainer();
    addTearDown(container.dispose);
    final SmartPromptPastActivityNotifier notifier = container.read(
      smartPromptPastActivityRequestProvider.notifier,
    );

    notifier.request();
    expect(container.read(smartPromptPastActivityRequestProvider), 1);

    notifier.consume();
    expect(container.read(smartPromptPastActivityRequestProvider), 0);
  });

  test('active timer actions retain their dedicated notification kind', () {
    const NotificationAction action = NotificationAction.activeTimer(
      actionId: 'pause_active',
    );

    expect(action.kind, NotificationActionKind.activeTimer);
    expect(action.reminderId, isNull);
  });
}
