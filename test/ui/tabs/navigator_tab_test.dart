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
      final inspector = FlutterInspector();
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

    testWidgets('shows SegmentedButton with both mode labels', (
      tester,
    ) async {
      final inspector = FlutterInspector();
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

      expect(find.byType(SegmentedButton<StackViewMode>), findsOneWidget);
      expect(find.text('當前堆疊'), findsOneWidget);
      expect(find.text('事件歷史'), findsOneWidget);
    });

    testWidgets('defaults to eventHistory mode showing event list', (
      tester,
    ) async {
      final inspector = FlutterInspector();
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
      // Placeholder not visible
      expect(find.text('當前堆疊視圖（開發中）'), findsNothing);
    });

    testWidgets('switching to activeStack shows placeholder and hides events', (
      tester,
    ) async {
      final inspector = FlutterInspector();
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

      // Tap the 「當前堆疊」 segment
      await tester.tap(find.text('當前堆疊'));
      await tester.pump();

      // Resolved active stack card is visible
      expect(find.text('/switch'), findsNWidgets(2));
      // Event history text gone
      expect(find.text('PUSH /switch'), findsNothing);
    });
  });
}
