import 'package:flutter/material.dart';
import 'package:flutter_inspector_kit/src/core/flutter_inspector.dart';
import 'package:flutter_inspector_kit/src/models/database_browser_source.dart';
import 'package:flutter_inspector_kit/src/observers/inspector_route_names.dart';
import 'package:flutter_inspector_kit/src/ui/dashboard/export_report_sheet.dart';
import 'package:flutter_inspector_kit/src/ui/dashboard/tabs/database/table_rows_view.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('inspector route filter (end-to-end)', () {
    testWidgets('no inspector-owned route reaches the entries buffer', (
      tester,
    ) async {
      final inspector = FlutterInspector();
      await tester.pumpWidget(
        MaterialApp(
          navigatorObservers: [inspector.navigatorObserver],
          home: const SizedBox(),
        ),
      );
      final navigator = tester.state<NavigatorState>(find.byType(Navigator));

      const names = [
        kInspectorDashboardRoute,
        kInspectorLogDetailRoute,
        kInspectorNetworkDetailRoute,
        kInspectorTableRowsRoute,
        kInspectorCellDetailsRoute,
        kInspectorExportReportRoute,
      ];

      for (final name in names) {
        navigator.push(
          MaterialPageRoute<void>(
            settings: RouteSettings(name: name),
            builder: (_) => const SizedBox(),
          ),
        );
        await tester.pumpAndSettle();
        navigator.pop();
        await tester.pumpAndSettle();
      }

      // MaterialApp's `home` becomes an initial route named '/' (a host
      // route, not an inspector one) and is recorded — AC-2 says only
      // inspector-owned routes get filtered. So the buffer holds exactly
      // that one entry, none of the inspector routes pushed above.
      expect(inspector.navigatorInspector.entries.length, 1);
      expect(inspector.navigatorInspector.entries.first.routeName, '/');

      // The same observer still records the host app's own navigation.
      navigator.push(
        MaterialPageRoute<void>(
          settings: const RouteSettings(name: '/user-page'),
          builder: (_) => const SizedBox(),
        ),
      );
      await tester.pumpAndSettle();
      expect(inspector.navigatorInspector.entries.length, 2);
      expect(
        inspector.navigatorInspector.entries.first.routeName,
        '/user-page',
      );
    });

    testWidgets('ExportReportSheet.show does not pollute the entries buffer', (
      tester,
    ) async {
      final inspector = FlutterInspector();
      await tester.pumpWidget(
        MaterialApp(
          navigatorObservers: [inspector.navigatorObserver],
          home: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () => ExportReportSheet.show(context, inspector),
              child: const Text('open'),
            ),
          ),
        ),
      );

      // Drop the '/' initial-route entry: only the sheet's own push (or
      // lack thereof) is under test here.
      inspector.clearNavigator();

      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      expect(inspector.navigatorInspector.entries, isEmpty);
    });

    testWidgets(
      'TableRowsView cell details sheet does not pollute the entries buffer',
      (tester) async {
        final inspector = FlutterInspector();
        await tester.pumpWidget(
          MaterialApp(
            navigatorObservers: [inspector.navigatorObserver],
            home: TableRowsView(
              source: _FakeDatabaseBrowserSource(),
              tableName: 'users',
            ),
          ),
        );
        await tester.pumpAndSettle();

        // Drop the '/' initial-route entry: only the cell-details sheet's
        // own push (or lack thereof) is under test here.
        inspector.clearNavigator();

        await tester.tap(find.text('hello'));
        await tester.pumpAndSettle();

        expect(inspector.navigatorInspector.entries, isEmpty);
      },
    );
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
