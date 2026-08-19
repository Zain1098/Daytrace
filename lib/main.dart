import 'package:daytrace/app/app.dart';
import 'package:daytrace/core/notifications/notification_service.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await dayTraceNotificationService.initialize();
  runApp(const ProviderScope(child: DayTraceApp()));
}
