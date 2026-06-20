import 'package:flutter/material.dart';
import 'package:flutter_inspector_kit/src/core/flutter_inspector.dart';
import 'package:flutter_inspector_kit/src/models/log_level.dart';
import 'package:flutter_inspector_kit/src/ui/dashboard/tabs/console_tab.dart';
import 'package:flutter_inspector_kit/src/ui/dashboard/tabs/console/log_detail_view.dart';
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

    testWidgets('tapping error log with stackTrace opens LogDetailView',
        (tester) async {
      final inspector = FlutterInspector();
      inspector.log(
        'Error occurred',
        level: LogLevel.error,
        stackTrace: 'line 1\nline 2\nline 3',
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: ConsoleTab(inspector: inspector)),
        ),
      );

      expect(find.text('Error occurred'), findsOneWidget);
      expect(find.byType(LogDetailView), findsNothing);

      await tester.tap(find.text('Error occurred'));
      await tester.pumpAndSettle();

      expect(find.byType(LogDetailView), findsOneWidget);
    });

    testWidgets('tapping error log with data opens LogDetailView',
        (tester) async {
      final inspector = FlutterInspector();
      inspector.log(
        'Error with data',
        level: LogLevel.error,
        data: {'key': 'value'},
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: ConsoleTab(inspector: inspector)),
        ),
      );

      expect(find.text('Error with data'), findsOneWidget);
      expect(find.byType(LogDetailView), findsNothing);

      await tester.tap(find.text('Error with data'));
      await tester.pumpAndSettle();

      expect(find.byType(LogDetailView), findsOneWidget);
    });

    testWidgets('tapping pure info log without stackTrace or data does not navigate',
        (tester) async {
      final inspector = FlutterInspector();
      inspector.log('Pure info', level: LogLevel.info);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: ConsoleTab(inspector: inspector)),
        ),
      );

      expect(find.text('Pure info'), findsOneWidget);
      expect(find.byType(LogDetailView), findsNothing);

      // Try to tap the log entry
      final tile = find.byType(ListTile).first;
      await tester.tap(tile);
      await tester.pumpAndSettle();

      // LogDetailView should not appear because onTap is null
      expect(find.byType(LogDetailView), findsNothing);
    });
  });
}
