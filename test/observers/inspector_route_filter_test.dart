import 'package:flutter/material.dart';
import 'package:flutter_inspector_kit/src/core/flutter_inspector.dart';
import 'package:flutter_inspector_kit/src/models/database_browser_source.dart';
import 'package:flutter_inspector_kit/src/models/database_operation.dart';
import 'package:flutter_inspector_kit/src/models/log_level.dart';
import 'package:flutter_inspector_kit/src/models/network_entry.dart';
import 'package:flutter_inspector_kit/src/ui/dashboard/export_report_sheet.dart';
import 'package:flutter_inspector_kit/src/ui/dashboard/tabs/console_tab.dart';
import 'package:flutter_inspector_kit/src/ui/dashboard/tabs/database/table_rows_view.dart';
import 'package:flutter_inspector_kit/src/ui/dashboard/tabs/database_tab.dart';
import 'package:flutter_inspector_kit/src/ui/dashboard/tabs/network_tab.dart';
import 'package:flutter_test/flutter_test.dart';

/// Drives the real dashboard entry points rather than hand-built routes.
///
/// Asserting on route names we construct ourselves would only prove the
/// observer filters those strings — it would still pass if a call site dropped
/// `pushInspectorRoute` or its `routeSettings`, which is exactly the regression
/// this file exists to catch.
void main() {
  group('inspector route filter (real dashboard entry points)', () {
    /// Pumps [child] under an app whose Navigator is observed by [inspector],
    /// then drops the entry recorded for the initial route so each test starts
    /// from an empty buffer.
    Future<void> pumpObserved(
      WidgetTester tester,
      FlutterInspector inspector,
      Widget child,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          navigatorObservers: [inspector.navigatorObserver],
          home: Scaffold(body: child),
        ),
      );
      await tester.pumpAndSettle();
      inspector.clearNavigator();
    }

    testWidgets('ConsoleTab log row does not record navigation', (
      tester,
    ) async {
      final inspector = FlutterInspector();
      inspector.log('boom', level: LogLevel.error, stackTrace: '#0 main');
      await pumpObserved(tester, inspector, ConsoleTab(inspector: inspector));

      await tester.tap(find.text('boom'));
      await tester.pumpAndSettle();
      expect(inspector.navigatorInspector.entries, isEmpty);

      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(inspector.navigatorInspector.entries, isEmpty);
    });

    testWidgets('ConsoleTab network row does not record navigation', (
      tester,
    ) async {
      final inspector = FlutterInspector();
      inspector.logNetwork(
        NetworkEntry(method: 'GET', url: 'https://x.test/a', statusCode: 200),
      );
      await pumpObserved(tester, inspector, ConsoleTab(inspector: inspector));

      await tester.tap(find.textContaining('https://x.test/a'));
      await tester.pumpAndSettle();
      expect(inspector.navigatorInspector.entries, isEmpty);

      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(inspector.navigatorInspector.entries, isEmpty);
    });

    testWidgets('NetworkTab row does not record navigation', (tester) async {
      final inspector = FlutterInspector();
      inspector.logNetwork(
        NetworkEntry(method: 'GET', url: 'https://x.test/b', statusCode: 200),
      );
      await pumpObserved(tester, inspector, NetworkTab(inspector: inspector));

      await tester.tap(find.textContaining('https://x.test/b'));
      await tester.pumpAndSettle();
      expect(inspector.navigatorInspector.entries, isEmpty);

      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(inspector.navigatorInspector.entries, isEmpty);
    });

    testWidgets('DatabaseTab table row does not record navigation', (
      tester,
    ) async {
      final inspector = FlutterInspector();
      inspector.database(DatabaseOperation.insert, 'users');
      await pumpObserved(tester, inspector, DatabaseTab(inspector: inspector));
      await tester.pumpAndSettle();

      await tester.tap(find.text('users'));
      await tester.pumpAndSettle();
      expect(inspector.navigatorInspector.entries, isEmpty);

      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(inspector.navigatorInspector.entries, isEmpty);
    });

    testWidgets('TableRowsView cell details sheet does not record navigation', (
      tester,
    ) async {
      final inspector = FlutterInspector();
      await pumpObserved(
        tester,
        inspector,
        TableRowsView(source: _FakeDatabaseBrowserSource(), tableName: 'users'),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('hello'));
      await tester.pumpAndSettle();
      expect(inspector.navigatorInspector.entries, isEmpty);
    });

    testWidgets('ExportReportSheet does not record navigation', (tester) async {
      final inspector = FlutterInspector();
      await pumpObserved(
        tester,
        inspector,
        Builder(
          builder: (context) => ElevatedButton(
            onPressed: () => ExportReportSheet.show(context, inspector),
            child: const Text('open'),
          ),
        ),
      );

      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      expect(inspector.navigatorInspector.entries, isEmpty);
    });

    testWidgets('host app navigation is still recorded', (tester) async {
      final inspector = FlutterInspector();
      await pumpObserved(tester, inspector, const SizedBox());
      final navigator = tester.state<NavigatorState>(find.byType(Navigator));

      navigator.push(
        MaterialPageRoute<void>(
          settings: const RouteSettings(name: '/user-page'),
          builder: (_) => const SizedBox(),
        ),
      );
      await tester.pumpAndSettle();

      // Unnamed host route — must never be dropped (name == null).
      navigator.push(MaterialPageRoute<void>(builder: (_) => const SizedBox()));
      await tester.pumpAndSettle();

      final names = inspector.navigatorInspector.entries
          .map((e) => e.routeName)
          .toList();
      expect(names, containsAll(<String?>['/user-page', null]));
    });
  });
}

class _FakeDatabaseBrowserSource implements DatabaseBrowserSource {
  @override
  String get name => 'fake';

  @override
  Future<List<DatabaseTableInfo>> listTables() async => [
    const DatabaseTableInfo(name: 'users', rowCount: 1),
  ];

  @override
  Future<DatabaseTablePage> fetchRows(
    String tableName, {
    int limit = 200,
    int offset = 0,
  }) async {
    return const DatabaseTablePage(
      columns: ['name'],
      rows: [
        ['hello'],
      ],
      totalRows: 1,
    );
  }
}
