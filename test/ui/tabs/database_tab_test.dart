import 'package:flutter/material.dart';
import 'package:flutter_inspector_kit/src/core/flutter_inspector_impl.dart';
import 'package:flutter_inspector_kit/src/models/database_browser_source.dart';
import 'package:flutter_inspector_kit/src/models/database_operation.dart';
import 'package:flutter_inspector_kit/src/ui/dashboard/tabs/database/table_rows_view.dart';
import 'package:flutter_inspector_kit/src/ui/dashboard/tabs/database_tab.dart';
import 'package:flutter_test/flutter_test.dart';

class FakeCustomSource extends DatabaseBrowserSource {
  @override
  String get name => 'custom.db';

  @override
  Future<List<DatabaseTableInfo>> listTables() async {
    return [const DatabaseTableInfo(name: 'custom_table', rowCount: 42)];
  }

  @override
  Future<DatabaseTablePage> fetchRows(
    String tableName, {
    int limit = 200,
    int offset = 0,
  }) async {
    return const DatabaseTablePage(columns: [], rows: []);
  }
}

void main() {
  group('DatabaseTab New UI', () {
    testWidgets('displays database tables grouped and supports clearing', (
      tester,
    ) async {
      final inspector = FlutterInspector();
      inspector.database(
        DatabaseOperation.insert,
        'users',
        affectedRows: 1,
        data: {'name': 'Alice'},
      );
      inspector.database(
        DatabaseOperation.update,
        'users',
        affectedRows: 1,
        data: {'name': 'Bob'},
      );
      inspector.database(
        DatabaseOperation.insert,
        'posts',
        affectedRows: 1,
        data: {'title': 'Hello'},
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: DatabaseTab(inspector: inspector)),
        ),
      );

      await tester.pumpAndSettle();

      // Check table list shows grouped tables sorted alphabetically
      expect(find.text('posts'), findsOneWidget);
      expect(find.text('1 rows'), findsOneWidget); // posts table has 1 entry

      expect(find.text('users'), findsOneWidget);
      expect(find.text('2 rows'), findsOneWidget); // users table has 2 entries

      // Clear action
      await tester.tap(find.byIcon(Icons.delete));
      await tester.pumpAndSettle();

      // Check empty state
      expect(find.text('No database activity'), findsOneWidget);
      expect(find.text('users'), findsNothing);
      expect(find.text('posts'), findsNothing);
    });

    testWidgets('shows empty state for empty sources', (tester) async {
      final inspector = FlutterInspector();

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: DatabaseTab(inspector: inspector)),
        ),
      );

      await tester.pumpAndSettle();
      expect(find.text('No database activity'), findsOneWidget);
    });

    testWidgets('dropdown is shown for multiple sources, and switches source', (
      tester,
    ) async {
      final customSource = FakeCustomSource();
      final inspector = FlutterInspector(databaseSources: [customSource]);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: DatabaseTab(inspector: inspector)),
        ),
      );

      await tester.pumpAndSettle();

      // Dropdown should be visible
      expect(
        find.byType(DropdownButton<DatabaseBrowserSource>),
        findsOneWidget,
      );
      // Delete icon is visible because default Operation log is selected
      expect(find.byIcon(Icons.delete), findsOneWidget);

      // Open dropdown and select custom.db
      await tester.tap(find.byType(DropdownButton<DatabaseBrowserSource>));
      await tester.pumpAndSettle();

      // Select 'custom.db'
      await tester.tap(find.text('custom.db').last);
      await tester.pumpAndSettle();

      // Check custom tables are shown
      expect(find.text('custom_table'), findsOneWidget);
      expect(find.text('42 rows'), findsOneWidget);

      // Delete icon is NOT visible since custom.db is selected (not OperationLogSource)
      expect(find.byIcon(Icons.delete), findsNothing);
    });

    testWidgets('dropdown is not shown for single source, only text name', (
      tester,
    ) async {
      final inspector = FlutterInspector(); // Only default Operation log

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: DatabaseTab(inspector: inspector)),
        ),
      );

      await tester.pumpAndSettle();

      expect(find.byType(DropdownButton<DatabaseBrowserSource>), findsNothing);
      expect(find.text('Operation log'), findsOneWidget);
    });

    testWidgets('tapping table pushes TableRowsView', (tester) async {
      final inspector = FlutterInspector();
      inspector.database(DatabaseOperation.insert, 'users');

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: DatabaseTab(inspector: inspector)),
        ),
      );

      await tester.pumpAndSettle();

      await tester.tap(find.text('users'));
      await tester.pumpAndSettle();

      // Verify TableRowsView was pushed
      expect(find.byType(TableRowsView), findsOneWidget);
    });
  });
}
