import 'package:flutter/material.dart';
import 'package:flutter_inspector_kit/src/core/flutter_inspector.dart';
import 'package:flutter_inspector_kit/src/models/navigator_action.dart';
import 'package:flutter_inspector_kit/src/models/navigator_entry.dart';
import 'package:flutter_inspector_kit/src/ui/dashboard/tabs/navigator_tab.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('NavigatorTab', () {
    testWidgets('displays navigator entries and supports clearing', (
      tester,
    ) async {
      final inspector = FlutterInspector(
        navigatorKey: GlobalKey<NavigatorState>(),
      );
      inspector.registry.navigator.add(
        NavigatorEntry(
          action: NavigatorAction.push,
          routeName: '/home',
          arguments: 'test_arg',
        ),
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: NavigatorTab(inspector: inspector)),
        ),
      );

      expect(find.text('PUSH /home'), findsOneWidget);
      expect(find.textContaining('test_arg'), findsOneWidget);

      await tester.tap(find.byIcon(Icons.delete));
      await tester.pump();

      expect(find.text('PUSH /home'), findsNothing);
    });

    testWidgets('shows ChoiceChips with both mode labels', (tester) async {
      final inspector = FlutterInspector(
        navigatorKey: GlobalKey<NavigatorState>(),
      );
      inspector.registry.navigator.add(
        NavigatorEntry(
          action: NavigatorAction.push,
          routeName: '/init',
          arguments: null,
        ),
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: NavigatorTab(inspector: inspector)),
        ),
      );

      expect(find.byType(ChoiceChip), findsNWidgets(2));
      expect(find.text('Active Stack'), findsOneWidget);
      expect(find.text('Event History'), findsOneWidget);
    });

    testWidgets('defaults to eventHistory mode showing event list', (
      tester,
    ) async {
      final inspector = FlutterInspector(
        navigatorKey: GlobalKey<NavigatorState>(),
      );
      inspector.registry.navigator.add(
        NavigatorEntry(
          action: NavigatorAction.push,
          routeName: '/default',
          arguments: null,
        ),
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: NavigatorTab(inspector: inspector)),
        ),
      );

      // Event history visible by default
      expect(find.text('PUSH /default'), findsOneWidget);
      expect(find.byType(ListView), findsOneWidget);
      // Active stack cards not shown until switched
      expect(find.byType(Card), findsNothing);
    });

    testWidgets(
      'switching to activeStack shows resolved stack and hides events',
      (tester) async {
        final inspector = FlutterInspector(
          navigatorKey: GlobalKey<NavigatorState>(),
        );
        inspector.registry.navigator.add(
          NavigatorEntry(
            action: NavigatorAction.push,
            routeName: '/switch',
            arguments: null,
          ),
        );

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(body: NavigatorTab(inspector: inspector)),
          ),
        );

        // Tap the "Active Stack" chip
        await tester.tap(find.text('Active Stack'));
        await tester.pump();

        // Resolved active stack card is visible
        expect(find.text('/switch'), findsNWidgets(2));
        // Event history text gone
        expect(find.text('PUSH /switch'), findsNothing);
      },
    );

    testWidgets('eventHistory title shows widget type and route name', (
      tester,
    ) async {
      final inspector = FlutterInspector(
        navigatorKey: GlobalKey<NavigatorState>(),
      );
      inspector.registry.navigator.add(
        NavigatorEntry(
          action: NavigatorAction.push,
          routeName: '/second',
          widgetType: Scaffold,
        ),
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: NavigatorTab(inspector: inspector)),
        ),
      );

      expect(find.text('PUSH Scaffold (/second)'), findsOneWidget);
    });

    testWidgets('labels query Params and Args apart in eventHistory mode', (
      tester,
    ) async {
      final inspector = FlutterInspector(
        navigatorKey: GlobalKey<NavigatorState>(),
      );
      inspector.registry.navigator.add(
        NavigatorEntry(
          action: NavigatorAction.push,
          routeName: '/details',
          queryParams: {'id': '42'},
          argParams: {'tab': 'overview'},
        ),
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: NavigatorTab(inspector: inspector)),
        ),
      );

      expect(find.text('PUSH /details'), findsOneWidget);
      expect(
        find.textContaining('Params: id=42\nArgs: tab=overview'),
        findsOneWidget,
      );
    });

    testWidgets('labels query Params and Args apart in activeStack mode', (
      tester,
    ) async {
      final inspector = FlutterInspector(
        navigatorKey: GlobalKey<NavigatorState>(),
      );
      inspector.registry.navigator.add(
        NavigatorEntry(
          action: NavigatorAction.push,
          routeName: '/profile',
          queryParams: {'user': 'alice'},
          argParams: {'tab': 'posts'},
        ),
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: NavigatorTab(inspector: inspector)),
        ),
      );

      await tester.tap(find.text('Active Stack'));
      await tester.pump();

      expect(
        find.textContaining('/profile\nParams: user=alice\nArgs: tab=posts'),
        findsOneWidget,
      );
    });
  });
}
