import 'package:flutter/material.dart';
import 'package:flutter_inspector_kit/src/core/flutter_inspector.dart';
import 'package:flutter_inspector_kit/src/models/database_entry.dart';
import 'package:flutter_inspector_kit/src/models/database_operation.dart';
import 'package:flutter_inspector_kit/src/models/log_entry.dart';
import 'package:flutter_inspector_kit/src/models/log_level.dart';
import 'package:flutter_inspector_kit/src/models/navigator_action.dart';
import 'package:flutter_inspector_kit/src/models/navigator_entry.dart';
import 'package:flutter_inspector_kit/src/models/network_entry.dart';
import 'package:flutter_inspector_kit/src/ui/dashboard/tabs/console/log_detail_view.dart';
import 'package:flutter_inspector_kit/src/ui/dashboard/tabs/console_tab.dart';
import 'package:flutter_inspector_kit/src/ui/dashboard/tabs/network/network_detail_view.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ConsoleTab', () {
    // ---- Preserved log-only tests (still valid under default All filter) ----

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

    testWidgets('shows a chevron only on expandable rows', (tester) async {
      final inspector = FlutterInspector();
      // Expandable: has a stackTrace.
      inspector.log('Expandable', level: LogLevel.error, stackTrace: 'x');
      // Non-expandable: plain info with neither stackTrace nor data.
      inspector.log('Flat', level: LogLevel.info);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: ConsoleTab(inspector: inspector)),
        ),
      );

      // Exactly one chevron, and it belongs to the expandable row's tile.
      expect(find.byIcon(Icons.chevron_right), findsOneWidget);
      final expandableTile = find.ancestor(
        of: find.text('Expandable'),
        matching: find.byType(ListTile),
      );
      expect(
        find.descendant(
          of: expandableTile,
          matching: find.byIcon(Icons.chevron_right),
        ),
        findsOneWidget,
      );
    });

    testWidgets(
        'tapping pure info log without stackTrace or data does not navigate',
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

      // Try to tap the log entry.
      final tile = find.byType(ListTile).first;
      await tester.tap(tile);
      await tester.pumpAndSettle();

      // LogDetailView should not appear because onTap is null.
      expect(find.byType(LogDetailView), findsNothing);
    });

    // ---- New merged-timeline tests ----

    testWidgets('filter chip Network shows only network rows', (tester) async {
      final inspector = FlutterInspector();
      inspector.log('a log', level: LogLevel.info);
      inspector.logNetwork(
        NetworkEntry(
          method: 'GET',
          url: 'https://api.test/x',
          statusCode: 200,
          isComplete: true,
        ),
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: ConsoleTab(inspector: inspector)),
        ),
      );

      // Default All filter: both visible.
      expect(find.text('a log'), findsOneWidget);
      expect(find.textContaining('https://api.test/x'), findsOneWidget);

      // Switch to Network filter.
      await tester.tap(find.widgetWithText(FilterChip, 'Network'));
      await tester.pump();

      expect(find.text('a log'), findsNothing);
      expect(find.textContaining('https://api.test/x'), findsOneWidget);
    });

    testWidgets('All filter shows mixed sources sorted newest-first',
        (tester) async {
      final inspector = FlutterInspector();
      final tLog = DateTime(2026, 6, 26, 10, 0, 0); // oldest
      final tNav = DateTime(2026, 6, 26, 10, 0, 1);
      final tNet = DateTime(2026, 6, 26, 10, 0, 2);
      final tDb = DateTime(2026, 6, 26, 10, 0, 3); // newest

      inspector.registry.log.add(LogEntry(message: 'log msg', timestamp: tLog));
      inspector.registry.navigator.add(
        NavigatorEntry(
          action: NavigatorAction.push,
          routeName: '/home',
          timestamp: tNav,
        ),
      );
      inspector.logNetwork(
        NetworkEntry(
          method: 'GET',
          url: 'https://api.test/x',
          statusCode: 200,
          isComplete: true,
          timestamp: tNet,
        ),
      );
      inspector.registry.database.add(
        DatabaseEntry(
          operation: DatabaseOperation.insert,
          tableName: 'users',
          timestamp: tDb,
        ),
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: ConsoleTab(inspector: inspector)),
        ),
      );

      // All four sources present.
      expect(find.text('log msg'), findsOneWidget);
      expect(find.textContaining('/home'), findsOneWidget);
      expect(find.textContaining('https://api.test/x'), findsOneWidget);
      expect(find.textContaining('users'), findsOneWidget);

      // Newest-first: db row above network above nav above log.
      final dbY = tester.getTopLeft(find.textContaining('users')).dy;
      final netY = tester.getTopLeft(find.textContaining('https://api.test/x')).dy;
      final navY = tester.getTopLeft(find.textContaining('/home')).dy;
      final logY = tester.getTopLeft(find.text('log msg')).dy;

      expect(dbY, lessThan(netY));
      expect(netY, lessThan(navY));
      expect(navY, lessThan(logY));
    });

    testWidgets('network row taps into NetworkDetailView', (tester) async {
      final inspector = FlutterInspector();
      inspector.logNetwork(
        NetworkEntry(
          method: 'GET',
          url: 'https://api.test/x',
          statusCode: 200,
          isComplete: true,
        ),
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: ConsoleTab(inspector: inspector)),
        ),
      );

      expect(find.byType(NetworkDetailView), findsNothing);

      await tester.tap(find.textContaining('https://api.test/x'));
      await tester.pumpAndSettle();

      expect(find.byType(NetworkDetailView), findsOneWidget);
    });

    testWidgets('network row tap forwards redactSensitiveData', (tester) async {
      final inspector = FlutterInspector(redactSensitiveData: false);
      inspector.logNetwork(
        NetworkEntry(
          method: 'GET',
          url: 'https://api.test/x',
          statusCode: 200,
          isComplete: true,
        ),
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: ConsoleTab(inspector: inspector)),
        ),
      );

      await tester.tap(find.textContaining('https://api.test/x'));
      await tester.pumpAndSettle();

      final view =
          tester.widget<NetworkDetailView>(find.byType(NetworkDetailView));
      expect(view.redactSensitiveData, isFalse);
    });

    testWidgets('nav and db rows are not tappable (no chevron)',
        (tester) async {
      final inspector = FlutterInspector();
      inspector.registry.navigator.add(
        NavigatorEntry(action: NavigatorAction.push, routeName: '/home'),
      );
      inspector.registry.database.add(
        DatabaseEntry(
          operation: DatabaseOperation.insert,
          tableName: 'users',
        ),
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: ConsoleTab(inspector: inspector)),
        ),
      );

      // Neither nav nor db row shows a chevron.
      expect(find.byIcon(Icons.chevron_right), findsNothing);

      // Tapping the nav row navigates nowhere.
      await tester.tap(find.textContaining('/home'));
      await tester.pumpAndSettle();
      expect(find.byType(NetworkDetailView), findsNothing);
      expect(find.byType(LogDetailView), findsNothing);

      // Tapping the db row navigates nowhere.
      await tester.tap(find.textContaining('users'));
      await tester.pumpAndSettle();
      expect(find.byType(NetworkDetailView), findsNothing);
      expect(find.byType(LogDetailView), findsNothing);
    });

    testWidgets('each row shows displayTime (HH:mm:ss.mmm)', (tester) async {
      final inspector = FlutterInspector();
      inspector.registry.log.add(
        LogEntry(message: 'tm', timestamp: DateTime(2026, 6, 26, 14, 30, 1, 123)),
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: ConsoleTab(inspector: inspector)),
        ),
      );

      expect(find.text('14:30:01.123'), findsOneWidget);
    });
  });
}
