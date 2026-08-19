import 'package:daytrace/app/app.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('Today is the initial DayTrace destination', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const ProviderScope(child: DayTraceApp()));
    await tester.pumpAndSettle();

    expect(find.textContaining('Good '), findsOneWidget);
    expect(find.text('What are you doing next?'), findsOneWidget);
    expect(find.text('Quick add'), findsOneWidget);
  });
}
