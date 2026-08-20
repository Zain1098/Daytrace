import 'package:daytrace/app/router.dart';
import 'package:daytrace/app/theme/app_theme.dart';
import 'package:daytrace/app/theme/theme_mode_controller.dart';
import 'package:daytrace/features/onboarding/application/onboarding_controller.dart';
import 'package:daytrace/features/onboarding/presentation/onboarding_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class DayTraceApp extends ConsumerWidget {
  const DayTraceApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ThemeMode themeMode = ref.watch(themeModeProvider).value ?? ThemeMode.system;
    final AsyncValue<bool> onboarding = ref.watch(onboardingProvider);
    if (onboarding.isLoading) {
      return _shell(themeMode: themeMode, home: const _StartupLoading());
    }
    if (onboarding.value != true) {
      return _shell(themeMode: themeMode, home: const OnboardingScreen());
    }
    return MaterialApp.router(
      title: 'DayTrace',
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
      themeMode: themeMode,
      routerConfig: appRouter,
    );
  }

  MaterialApp _shell({required ThemeMode themeMode, required Widget home}) =>
      MaterialApp(
        title: 'DayTrace',
        theme: AppTheme.light,
        darkTheme: AppTheme.dark,
        themeMode: themeMode,
        home: home,
      );
}

class _StartupLoading extends StatelessWidget {
  const _StartupLoading();

  @override
  Widget build(BuildContext context) => const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
}
