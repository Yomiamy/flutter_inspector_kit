import 'package:flutter/material.dart';
import 'package:flutter_inspector_kit/src/core/flutter_inspector.dart';
import 'package:flutter_inspector_kit/src/models/log_entry.dart';
import 'package:flutter_inspector_kit/src/models/log_level.dart';
import 'package:flutter_inspector_kit/src/ui/dashboard/tabs/console/log_detail_view.dart';
import 'package:flutter_inspector_kit/src/ui/dashboard/tabs/console_tab.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('RenderFlex Badge in ConsoleTab', () {
    testWidgets('displays overflow badge for RenderFlex errors', (tester) async {
      final inspector = FlutterInspector(
        navigatorKey: GlobalKey<NavigatorState>(),
      );

      inspector.log(
        'A RenderFlex overflowed by 24.0 pixels on the bottom.',
        level: LogLevel.error,
        data: {
          'isRenderFlexOverflow': true,
          'overflowPixels': 24.0,
          'overflowDirection': 'bottom',
        },
      );
      inspector.log(
        'A standard log message without overflow',
        level: LogLevel.info,
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: ConsoleTab(inspector: inspector)),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Overflow: 24px bottom'), findsOneWidget);
    });

    testWidgets('formats small decimal overflow without displaying zero', (tester) async {
      final inspector = FlutterInspector(
        navigatorKey: GlobalKey<NavigatorState>(),
      );

      inspector.log(
        'A RenderFlex overflowed by 0.4 pixels on the bottom.',
        level: LogLevel.error,
        data: {
          'isRenderFlexOverflow': true,
          'overflowPixels': 0.4,
          'overflowDirection': 'bottom',
        },
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: ConsoleTab(inspector: inspector)),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Overflow: 0.4px bottom'), findsOneWidget);
    });

    testWidgets('renders safely in narrow layout without overflow', (tester) async {
      final inspector = FlutterInspector(
        navigatorKey: GlobalKey<NavigatorState>(),
      );

      inspector.log(
        'A RenderFlex overflowed by 123.4 pixels on the right.',
        level: LogLevel.error,
        data: {
          'isRenderFlexOverflow': true,
          'overflowPixels': 123.4,
          'overflowDirection': 'right',
        },
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: SizedBox(
                width: 150,
                child: ConsoleTab(inspector: inspector),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
    });

    testWidgets('does not display overflow badge for ordinary error log', (tester) async {
      final inspector = FlutterInspector(
        navigatorKey: GlobalKey<NavigatorState>(),
      );

      inspector.log(
        'Some standard error message',
        level: LogLevel.error,
        data: {'source': 'custom'},
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: ConsoleTab(inspector: inspector)),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.textContaining('Overflow:'), findsNothing);
    });
  });

  group('RenderFlex Overflow in LogDetailView', () {
    testWidgets('shows Overflow Context row in General section', (tester) async {
      final entry = LogEntry(
        message: 'A RenderFlex overflowed by 16.0 pixels on the right.',
        level: LogLevel.error,
        data: {
          'isRenderFlexOverflow': true,
          'overflowPixels': 16.0,
          'overflowDirection': 'right',
        },
      );

      await tester.pumpWidget(
        MaterialApp(
          home: LogDetailView(entry: entry),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.textContaining('Overflow Context'), findsOneWidget);
      expect(find.text('16.0 px on the right'), findsOneWidget);
    });

    testWidgets('does not show Overflow Context row for regular entry', (tester) async {
      final entry = LogEntry(
        message: 'Normal message',
        level: LogLevel.info,
      );

      await tester.pumpWidget(
        MaterialApp(
          home: LogDetailView(entry: entry),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Overflow Context'), findsNothing);
    });
  });
}
