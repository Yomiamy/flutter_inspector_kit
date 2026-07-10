import 'package:flutter/material.dart';
import 'package:flutter_inspector_kit/src/core/flutter_inspector.dart';
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

    testWidgets('Error Summary banner is not rendered when there are no errors', (tester) async {
      final inspector = FlutterInspector();
      inspector.logNetwork(NetworkEntry(method: 'GET', url: '/ok', statusCode: 200));

      await tester.pumpWidget(MaterialApp(home: Scaffold(body: NetworkTab(inspector: inspector))));

      expect(find.textContaining('errors'), findsNothing);
      expect(find.text('Error Summary'), findsNothing);
    });

    testWidgets('Error Summary banner appears when there are errors', (tester) async {
      final inspector = FlutterInspector();
      inspector.logNetwork(NetworkEntry(method: 'GET', url: '/err', statusCode: 502));

      await tester.pumpWidget(MaterialApp(home: Scaffold(body: NetworkTab(inspector: inspector))));

      // "Error Summary" is visible because it's expanded by default
      expect(find.text('Error Summary'), findsOneWidget);
      // find.text does an exact match, so this only hits the group card's
      // label — the row subtitle is a composed string ("502 · - ms · ...")
      // that never equals the bare "502".
      expect(find.text('502'), findsOneWidget); // The label
      expect(find.text('×1'), findsOneWidget); // The count
    });

    testWidgets('Tapping error group card filters the list', (tester) async {
      final inspector = FlutterInspector();
      inspector.logNetwork(NetworkEntry(method: 'GET', url: '/ok', statusCode: 200));
      inspector.logNetwork(NetworkEntry(method: 'GET', url: '/err', statusCode: 502));

      await tester.pumpWidget(MaterialApp(home: Scaffold(body: NetworkTab(inspector: inspector))));

      expect(find.text('/ok'), findsOneWidget);
      expect(find.text('/err'), findsOneWidget);

      await tester.tap(find.text('502'));
      await tester.pump();

      expect(find.text('/ok'), findsNothing);
      expect(find.text('/err'), findsOneWidget);
    });

    testWidgets('Tapping the same group card again clears the filter', (tester) async {
      final inspector = FlutterInspector();
      inspector.logNetwork(NetworkEntry(method: 'GET', url: '/ok', statusCode: 200));
      inspector.logNetwork(NetworkEntry(method: 'GET', url: '/err', statusCode: 502));

      await tester.pumpWidget(MaterialApp(home: Scaffold(body: NetworkTab(inspector: inspector))));

      // First tap to filter
      await tester.tap(find.text('502'));
      await tester.pump();
      expect(find.text('/ok'), findsNothing);

      // Second tap to clear
      await tester.tap(find.text('502'));
      await tester.pump();
      expect(find.text('/ok'), findsOneWidget);
    });

    testWidgets('Clearing buffer hides the error summary banner', (tester) async {
      final inspector = FlutterInspector();
      inspector.logNetwork(NetworkEntry(method: 'GET', url: '/err', statusCode: 502));

      await tester.pumpWidget(MaterialApp(home: Scaffold(body: NetworkTab(inspector: inspector))));
      expect(find.text('Error Summary'), findsOneWidget);

      await tester.tap(find.byIcon(Icons.delete));
      await tester.pump();

      expect(find.text('Error Summary'), findsNothing);
    });

    testWidgets('Collapsing the banner shows summary text', (tester) async {
      final inspector = FlutterInspector();
      inspector.logNetwork(NetworkEntry(method: 'GET', url: '/err1', statusCode: 502));
      inspector.logNetwork(NetworkEntry(method: 'GET', url: '/err2', statusCode: 404));

      await tester.pumpWidget(MaterialApp(home: Scaffold(body: NetworkTab(inspector: inspector))));
      
      expect(find.text('Error Summary'), findsOneWidget); // Expanded header

      await tester.tap(find.byIcon(Icons.expand_less));
      await tester.pump();

      expect(find.text('Error Summary'), findsNothing); // Expanded header gone
      expect(find.text('⚠ 2 errors (2 types)'), findsOneWidget); // Collapsed text

      await tester.tap(find.byIcon(Icons.expand_more));
      await tester.pump();
      expect(find.text('Error Summary'), findsOneWidget); // Expanded header back
    });
  });
}
