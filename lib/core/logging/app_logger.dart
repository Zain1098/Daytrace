import 'dart:developer' as developer;

abstract interface class AppLogger {
  void info(String message);
  void error(String message, Object error, StackTrace stackTrace);
}

final class DeveloperLogger implements AppLogger {
  const DeveloperLogger();

  @override
  void error(String message, Object error, StackTrace stackTrace) => developer
      .log(message, error: error, stackTrace: stackTrace, name: 'DayTrace');

  @override
  void info(String message) => developer.log(message, name: 'DayTrace');
}
