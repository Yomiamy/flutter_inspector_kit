import 'package:flutter/material.dart';
import 'package:flutter_inspector_kit/src/core/flutter_inspector_impl.dart';
import 'package:flutter_inspector_kit/src/models/network_entry.dart';
import 'package:flutter_inspector_kit/src/ui/dashboard/tabs/network/network_detail_view.dart';
import 'package:flutter_inspector_kit/src/ui/dashboard/tabs/network_tab.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('NetworkTab', () {
    testWidgets('displays network entries and supports clearing', (
      tester,
    ) async {
      final inspector = FlutterInspector();
      inspector.logNetwork(
        NetworkEntry(method: 'GET', url: '/api/test', statusCode: 200),
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: NetworkTab(inspector: inspector)),
        ),
      );

      expect(find.text('/api/test'), findsOneWidget);

      await tester.tap(find.byIcon(Icons.delete));
      await tester.pump();

      expect(find.text('/api/test'), findsNothing);
    });

    testWidgets('keyword search filters the list', (tester) async {
      final inspector = FlutterInspector();
      inspector.logNetwork(
        NetworkEntry(method: 'GET', url: '/api/users', statusCode: 200),
      );
      inspector.logNetwork(
        NetworkEntry(method: 'POST', url: '/api/login', statusCode: 401),
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: NetworkTab(inspector: inspector)),
        ),
      );

      expect(find.text('/api/users'), findsOneWidget);
      expect(find.text('/api/login'), findsOneWidget);

      await tester.enterText(find.byType(TextField), 'login');
      await tester.pump();

      expect(find.text('/api/users'), findsNothing);
      expect(find.text('/api/login'), findsOneWidget);
    });

    testWidgets('method filter chip narrows results', (tester) async {
      final inspector = FlutterInspector();
      inspector.logNetwork(
        NetworkEntry(method: 'GET', url: '/api/users', statusCode: 200),
      );
      inspector.logNetwork(
        NetworkEntry(method: 'POST', url: '/api/login', statusCode: 401),
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: NetworkTab(inspector: inspector)),
        ),
      );

      await tester.tap(find.widgetWithText(FilterChip, 'POST'));
      await tester.pump();

      expect(find.text('/api/users'), findsNothing);
      expect(find.text('/api/login'), findsOneWidget);
    });

    testWidgets('tapping an entry opens the detail view', (tester) async {
      final inspector = FlutterInspector();
      inspector.logNetwork(
        NetworkEntry(
          method: 'GET',
          url: '/api/detail',
          statusCode: 200,
          isComplete: true,
        ),
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: NetworkTab(inspector: inspector)),
        ),
      );

      await tester.tap(find.text('/api/detail'));
      await tester.pumpAndSettle();

      expect(find.byType(NetworkDetailView), findsOneWidget);
      expect(find.text('General'), findsOneWidget);
    });
  });
}
