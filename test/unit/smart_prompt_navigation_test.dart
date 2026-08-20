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
}
