import 'package:daytrace/features/settings/data/settings_repository.dart';
import 'package:daytrace/features/today/application/today_controller.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final AsyncNotifierProvider<OnboardingController, bool> onboardingProvider =
    AsyncNotifierProvider<OnboardingController, bool>(OnboardingController.new);

class OnboardingController extends AsyncNotifier<bool> {
  SettingsRepository get _settings =>
      SettingsRepository(ref.read(appDatabaseProvider));

  @override
  Future<bool> build() => _settings.isOnboardingComplete();

  Future<void> complete({
    required bool requestNotifications,
    TrackingSettings? trackingSettings,
  }) async {
    if (trackingSettings != null) {
      await _settings.saveTracking(trackingSettings);
    }
    if (requestNotifications) {
      await ref.read(notificationServiceProvider).requestPermission();
    }
    await _settings.setOnboardingComplete(true);
    state = const AsyncData<bool>(true);
  }
}
