import 'package:flutter/material.dart';
import 'package:flutter_inspector_kit/src/core/flutter_inspector_impl.dart';
import 'package:flutter_inspector_kit/src/models/log_level.dart';
import 'package:flutter_inspector_kit/src/ui/dashboard/tabs/console_tab.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ConsoleTab', () {
    testWidgets('displays logs and supports clearing', (tester) async {
      final inspector = FlutterInspector();
      inspector.log('Test message 1', level: LogLevel.info);
      inspector.log('Test message 2', level: LogLevel.error);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: ConsoleTab(inspector: inspector)),
        ),
      );

      expect(find.text('Test message 1'), findsOneWidget);
      expect(find.text('Test message 2'), findsOneWidget);

      await tester.tap(find.byIcon(Icons.delete));
      await tester.pump();

      expect(find.text('Test message 1'), findsNothing);
      expect(find.text('Test message 2'), findsNothing);
    });
  });
}
