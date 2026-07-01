import 'package:flutter/material.dart';
import 'package:flutter_inspector_kit/src/core/flutter_inspector.dart';
import 'package:flutter_inspector_kit/src/models/navigator_action.dart';
import 'package:flutter_inspector_kit/src/models/navigator_entry.dart';
import 'package:flutter_inspector_kit/src/ui/dashboard/tabs/navigator_tab.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('NavigatorActiveStackView', () {
    testWidgets('displays active stack top-first with two cards', (tester) async {
      final inspector = FlutterInspector();
      // Push A
      inspector.registry.navigator.add(
        NavigatorEntry(
          action: NavigatorAction.push,
          routeName: '/routeA',
          widgetType: SizedBox,
          arguments: null,
        ),
      );
      // Push B
      inspector.registry.navigator.add(
        NavigatorEntry(
          action: NavigatorAction.push,
          routeName: '/routeB',
          widgetType: Container,
          arguments: null,
        ),
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: NavigatorTab(inspector: inspector)),
        ),
      );

      // Tap 「當前堆疊」 segment
      await tester.tap(find.text('當前堆疊'));
      await tester.pump();

      // We expect two cards
      final cardFinder = find.byType(Card);
      expect(cardFinder, findsNWidgets(2));

      // Verifying top-first sequence using unique widgetType display names
      final aFinder = find.text('SizedBox');
      final bFinder = find.text('Container');
      expect(aFinder, findsOneWidget);
      expect(bFinder, findsOneWidget);

      final aTopLeft = tester.getTopLeft(aFinder);
      final bTopLeft = tester.getTopLeft(bFinder);
      // Top-first means the top of stack (B) is at the top of the list, which means it has a smaller Y coordinate.
      expect(bTopLeft.dy, lessThan(aTopLeft.dy));
    });

    testWidgets('cards display displayName and routeName, but do not show arguments', (tester) async {
      final inspector = FlutterInspector();
      inspector.registry.navigator.add(
        NavigatorEntry(
          action: NavigatorAction.push,
          routeName: '/routeWithArgs',
          widgetType: Scaffold,
          arguments: 'secret_argument_value',
        ),
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: NavigatorTab(inspector: inspector)),
        ),
      );

      await tester.tap(find.text('當前堆疊'));
      await tester.pump();

      expect(find.text('Scaffold'), findsOneWidget);
      expect(find.text('/routeWithArgs'), findsOneWidget);
      expect(find.textContaining('secret_argument_value'), findsNothing);
    });

    testWidgets('empty navigatorEntries displays empty placeholder without crashing', (tester) async {
      final inspector = FlutterInspector();

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: NavigatorTab(inspector: inspector)),
        ),
      );

      await tester.tap(find.text('當前堆疊'));
      await tester.pump();

      // We expect some empty placeholder text, e.g. "當前堆疊為空"
      expect(find.text('當前堆疊為空'), findsOneWidget);
      expect(find.byType(Card), findsNothing);
    });

    testWidgets('clearing navigator syncs the active stack view to empty placeholder', (tester) async {
      final inspector = FlutterInspector();
      inspector.registry.navigator.add(
        NavigatorEntry(
          action: NavigatorAction.push,
          routeName: '/routeToClear',
        ),
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: NavigatorTab(inspector: inspector)),
        ),
      );

      await tester.tap(find.text('當前堆疊'));
      await tester.pump();

      expect(find.text('/routeToClear'), findsNWidgets(2));

      // Click delete button
      await tester.tap(find.byIcon(Icons.delete));
      await tester.pump();

      expect(find.text('/routeToClear'), findsNothing);
      expect(find.text('當前堆疊為空'), findsOneWidget);
    });
  });
}
