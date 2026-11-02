import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_inspector_kit/src/core/flutter_inspector.dart';
import 'package:flutter_inspector_kit/src/models/database_entry.dart';
import 'package:flutter_inspector_kit/src/models/database_operation.dart';
import 'package:flutter_inspector_kit/src/models/log_level.dart';
import 'package:flutter_inspector_kit/src/models/navigator_action.dart';
import 'package:flutter_inspector_kit/src/models/navigator_entry.dart';
import 'package:flutter_inspector_kit/src/models/network_entry.dart';
import 'package:flutter_inspector_kit/src/ui/dashboard/tabs/console_tab.dart';

void main() {
  group('ConsoleTab Dynamic Counter Badges', () {
    testWidgets('empty inspector displays (0) for all chip counters', (
      tester,
    ) async {
      final inspector = FlutterInspector(
        navigatorKey: GlobalKey<NavigatorState>(),
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: ConsoleTab(inspector: inspector)),
        ),
      );

      expect(find.text('All (0)'), findsOneWidget);
      expect(find.text('Log (0)'), findsOneWidget);
      expect(find.text('Network (0)'), findsOneWidget);
      expect(find.text('Nav (0)'), findsOneWidget);
      expect(find.text('DB (0)'), findsOneWidget);
      expect(find.text('📌 Bookmarks (0)'), findsOneWidget);
      expect(find.text('⚡ Errors only (0)'), findsOneWidget);
      expect(find.text('Verbose (0)'), findsOneWidget);
      expect(find.text('Debug (0)'), findsOneWidget);
      expect(find.text('Info (0)'), findsOneWidget);
      expect(find.text('Warning (0)'), findsOneWidget);
    });

    testWidgets('mixed entries produce exact category counts on FilterChips', (
      tester,
    ) async {
      final inspector = FlutterInspector(
        navigatorKey: GlobalKey<NavigatorState>(),
      );

      // 1. Warning log (LogLevel.warning, matches errorsOnly)
      inspector.log('warning message', level: LogLevel.warning);

      // 2. Info log (LogLevel.info)
      inspector.log('info message', level: LogLevel.info);

      // 3. Failed network call (statusCode: 500, matches errorsOnly)
      inspector.logNetwork(
        NetworkEntry(
          method: 'GET',
          url: 'https://api.test/fail',
          statusCode: 500,
          isComplete: true,
        ),
      );

      // 4. Navigation entry
      inspector.registry.navigator.add(
        NavigatorEntry(action: NavigatorAction.push, routeName: '/home'),
      );

      // 5. Database entry
      inspector.registry.database.add(
        DatabaseEntry(
          operation: DatabaseOperation.insert,
          tableName: 'users',
        ),
      );

      // Bookmark 1 entry
      inspector.toggleBookmark(inspector.registry.log.entries.first);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: ConsoleTab(inspector: inspector)),
        ),
      );

      // Total count across all sources = 5
      expect(find.text('All (5)'), findsOneWidget);

      // Per-source counts
      expect(find.text('Log (2)'), findsOneWidget);
      expect(find.text('Network (1)'), findsOneWidget);
      expect(find.text('Nav (1)'), findsOneWidget);
      expect(find.text('DB (1)'), findsOneWidget);

      // Bookmarks count = 1
      expect(find.text('📌 Bookmarks (1)'), findsOneWidget);

      // Errors only count = 2 (1 warning log + 1 failed network)
      expect(find.text('⚡ Errors only (2)'), findsOneWidget);

      // Log levels
      expect(find.text('Info (1)'), findsOneWidget);
      expect(find.text('Warning (1)'), findsOneWidget);
      expect(find.text('Verbose (0)'), findsOneWidget);
      expect(find.text('Debug (0)'), findsOneWidget);

      // Tap clear/delete button to wipe logs
      await tester.tap(find.byIcon(Icons.delete));
      await tester.pumpAndSettle();

      // All counts should reset to (0)
      expect(find.text('All (0)'), findsOneWidget);
      expect(find.text('Log (0)'), findsOneWidget);
      expect(find.text('Network (0)'), findsOneWidget);
      expect(find.text('Nav (0)'), findsOneWidget);
      expect(find.text('DB (0)'), findsOneWidget);
      expect(find.text('📌 Bookmarks (0)'), findsOneWidget);
      expect(find.text('⚡ Errors only (0)'), findsOneWidget);
      expect(find.text('Info (0)'), findsOneWidget);
      expect(find.text('Warning (0)'), findsOneWidget);
    });
  });
}
