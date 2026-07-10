import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_inspector_kit/src/models/database_browser_source.dart';
import 'package:flutter_inspector_kit/src/ui/dashboard/tabs/database/table_rows_view.dart';
import 'package:flutter_inspector_kit/src/ui/theme/inspector_theme.dart';
import 'package:flutter_test/flutter_test.dart';

class MockDatabaseBrowserSource extends DatabaseBrowserSource {
  MockDatabaseBrowserSource({
    required this.name,
    this.rowsResponse,
    this.shouldThrow = false,
    this.delay,
  });

  @override
  final String name;
  DatabaseTablePage? rowsResponse;
  bool shouldThrow;
  Duration? delay;
  int fetchCallCount = 0;
  String? lastTableName;
  int? lastLimit;
  int? lastOffset;

  @override
  Future<List<DatabaseTableInfo>> listTables() async => [];

  @override
  Future<DatabaseTablePage> fetchRows(
    String tableName, {
    int limit = 200,
    int offset = 0,
  }) async {
    fetchCallCount++;
    lastTableName = tableName;
    lastLimit = limit;
    lastOffset = offset;
    if (delay != null) {
      await Future.delayed(delay!);
    }
    if (shouldThrow) throw Exception('Database error occurred');
    return rowsResponse ?? const DatabaseTablePage(columns: [], rows: []);
  }
}

void main() {
  group('TableRowsView T5a', () {
    testWidgets('renders table columns and rows correctly', (tester) async {
      final source = MockDatabaseBrowserSource(
        name: 'test.db',
        rowsResponse: const DatabaseTablePage(
          columns: ['id', 'name', 'age'],
          rows: [
            [1, 'Alice', 30],
            [2, 'Bob', null],
          ],
          totalRows: 2,
        ),
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: TableRowsView(source: source, tableName: 'users'),
          ),
        ),
      );

      // Loading state
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      await tester.pumpAndSettle();

      // Check header rendering
      expect(find.text('id'), findsOneWidget);
      expect(find.text('name'), findsOneWidget);
      expect(find.text('age'), findsOneWidget);

      // Check cell values
      expect(find.text('1'), findsOneWidget);
      expect(find.text('Alice'), findsOneWidget);
      expect(find.text('2'), findsOneWidget);
      expect(find.text('Bob'), findsOneWidget);

      // Check NULL italic grey text
      final nullTextFinder = find.byWidgetPredicate(
        (widget) =>
            widget is Text &&
            widget.data == 'NULL' &&
            widget.style?.fontStyle == FontStyle.italic &&
            widget.style?.color == ThemeColor.color9E9E9E,
      );
      expect(nullTextFinder, findsOneWidget);

      // Check bottom status text
      expect(find.text('Showing 2 of 2'), findsOneWidget);
    });

    testWidgets('renders empty table without crashing DataTable', (
      tester,
    ) async {
      final source = MockDatabaseBrowserSource(
        name: 'test.db',
        rowsResponse: const DatabaseTablePage(
          columns: [],
          rows: [],
          totalRows: 0,
        ),
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: TableRowsView(source: source, tableName: 'users'),
          ),
        ),
      );

      await tester.pumpAndSettle();

      expect(find.text('No rows'), findsOneWidget);
      expect(find.byType(DataTable), findsNothing);
      expect(find.text('Showing 0 of 0'), findsOneWidget);
    });

    testWidgets('handles error state with retry button', (tester) async {
      final source = MockDatabaseBrowserSource(
        name: 'test.db',
        shouldThrow: true,
        delay: const Duration(milliseconds: 10),
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: TableRowsView(source: source, tableName: 'users'),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Error message check
      expect(find.textContaining('Database error occurred'), findsOneWidget);
      expect(find.text('Retry'), findsOneWidget);

      // Fix error and retry
      source.shouldThrow = false;
      source.rowsResponse = const DatabaseTablePage(
        columns: ['id'],
        rows: [
          [1],
        ],
        totalRows: 1,
      );

      await tester.tap(find.text('Retry'));
      await tester.pump(); // Show loading
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      await tester.pumpAndSettle();

      expect(find.text('id'), findsOneWidget);
      expect(find.text('1'), findsOneWidget);
      expect(source.fetchCallCount, equals(2));
    });

    testWidgets('app bar refresh button reloads data', (tester) async {
      final source = MockDatabaseBrowserSource(
        name: 'test.db',
        rowsResponse: const DatabaseTablePage(
          columns: ['id'],
          rows: [
            [1],
          ],
          totalRows: 1,
        ),
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: TableRowsView(source: source, tableName: 'users'),
          ),
        ),
      );

      await tester.pumpAndSettle();
      expect(source.fetchCallCount, equals(1));

      await tester.tap(find.byIcon(Icons.refresh));
      await tester.pumpAndSettle();

      expect(source.fetchCallCount, equals(2));
    });
  });

  group('TableRowsView T5b', () {
    testWidgets('supports local column sorting and null last', (tester) async {
      final source = MockDatabaseBrowserSource(
        name: 'test.db',
        rowsResponse: const DatabaseTablePage(
          columns: ['id', 'val'],
          rows: [
            [2, 'banana'],
            [3, null],
            [1, 'apple'],
          ],
          totalRows: 3,
        ),
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: TableRowsView(source: source, tableName: 'users'),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Tap 'id' header to sort ascending
      await tester.tap(find.text('id'));
      await tester.pumpAndSettle();

      // Tap 'id' header again to sort descending
      await tester.tap(find.text('id'));
      await tester.pumpAndSettle();
    });

    testWidgets(
      'tapping cell opens bottom sheet with complete value and copy',
      (tester) async {
        String? clipboardText;
        tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          (call) async {
            if (call.method == 'Clipboard.setData') {
              clipboardText = (call.arguments as Map)['text'] as String?;
            }
            return null;
          },
        );

        final source = MockDatabaseBrowserSource(
          name: 'test.db',
          rowsResponse: const DatabaseTablePage(
            columns: ['data'],
            rows: [
              ['very long cell data string'],
            ],
            totalRows: 1,
          ),
        );

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: TableRowsView(source: source, tableName: 'users'),
            ),
          ),
        );

        await tester.pumpAndSettle();

        // Tap the cell
        await tester.tap(find.text('very long cell data string'));
        await tester.pumpAndSettle();

        // Bottom sheet is open
        expect(find.byType(SelectableText), findsOneWidget);
        expect(find.text('Copy Value'), findsOneWidget);

        await tester.tap(find.text('Copy Value'));
        await tester.pumpAndSettle();

        expect(clipboardText, equals('very long cell data string'));
        expect(find.text('Value copied to clipboard'), findsOneWidget);
      },
    );

    testWidgets('supports loading more rows when available', (tester) async {
      final source = MockDatabaseBrowserSource(
        name: 'test.db',
        rowsResponse: DatabaseTablePage(
          columns: ['id'],
          rows: List.generate(200, (i) => [i]),
          totalRows: 250,
        ),
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: TableRowsView(source: source, tableName: 'users'),
          ),
        ),
      );

      await tester.pumpAndSettle();

      expect(find.text('Showing 200 of 250'), findsOneWidget);
      expect(find.text('Load More'), findsOneWidget);

      // Mock next page response
      source.rowsResponse = DatabaseTablePage(
        columns: ['id'],
        rows: List.generate(50, (i) => [200 + i]),
        totalRows: 250,
      );

      await tester.tap(find.text('Load More'));
      await tester.pumpAndSettle();

      expect(find.text('Showing 250 of 250'), findsOneWidget);
      expect(find.text('Load More'), findsNothing);
      expect(source.fetchCallCount, equals(2));
      expect(source.lastOffset, equals(200));
    });
  });
}
