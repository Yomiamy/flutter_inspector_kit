import 'package:flutter/material.dart';
import 'package:flutter_inspector_kit/src/core/flutter_inspector_impl.dart';
import 'package:flutter_inspector_kit/src/models/database_operation.dart';
import 'package:flutter_inspector_kit/src/ui/dashboard/tabs/database_tab.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('DatabaseTab', () {
    testWidgets('displays database entries and supports clearing', (
      tester,
    ) async {
      final inspector = FlutterInspector();
      inspector.database(
        DatabaseOperation.insert,
        'users',
        affectedRows: 2,
        data: {'query': 'INSERT INTO users'},
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: DatabaseTab(inspector: inspector)),
        ),
      );

      expect(find.text('INSERT on users'), findsOneWidget);
      expect(find.textContaining('Rows affected: 2'), findsOneWidget);
      expect(find.textContaining('INSERT INTO users'), findsOneWidget);

      await tester.tap(find.byIcon(Icons.delete));
      await tester.pump();

      expect(find.text('INSERT on users'), findsNothing);
    });
  });
}
