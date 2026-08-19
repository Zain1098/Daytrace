import 'package:daytrace/features/settings/data/settings_repository.dart';
import 'package:daytrace/features/today/application/today_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final AsyncNotifierProvider<ThemeModeController, ThemeMode> themeModeProvider =
    AsyncNotifierProvider<ThemeModeController, ThemeMode>(
      ThemeModeController.new,
    );

class ThemeModeController extends AsyncNotifier<ThemeMode> {
  @override
  Future<ThemeMode> build() =>
      SettingsRepository(ref.watch(appDatabaseProvider)).loadThemeMode();

  Future<void> select(ThemeMode mode) async {
    final ThemeMode previous = state.value ?? ThemeMode.system;
    state = AsyncData(mode);
    try {
      await SettingsRepository(ref.read(appDatabaseProvider)).saveThemeMode(mode);
    } catch (_) {
      state = AsyncData(previous);
      rethrow;
    }
  }
}
