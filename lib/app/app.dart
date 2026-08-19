import 'package:daytrace/app/router.dart';
import 'package:daytrace/app/theme/app_theme.dart';
import 'package:daytrace/app/theme/theme_mode_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class DayTraceApp extends ConsumerWidget {
  const DayTraceApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ThemeMode themeMode = ref.watch(themeModeProvider).value ?? ThemeMode.system;
    return MaterialApp.router(
      title: 'DayTrace',
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
      themeMode: themeMode,
      routerConfig: appRouter,
    );
  }
}
