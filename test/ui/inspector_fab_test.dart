import 'package:flutter/material.dart';
import 'package:flutter_inspector_kit/src/ui/widgets/inspector_fab.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('InspectorFab', () {
    testWidgets('renders when visible is true', (tester) async {
      bool tapped = false;
      await tester.pumpWidget(
        MaterialApp(
          home: Stack(children: [InspectorFab(onTap: () => tapped = true)]),
        ),
      );

      expect(find.byType(FloatingActionButton), findsOneWidget);
      await tester.tap(find.byType(FloatingActionButton));
      expect(tapped, isTrue);
    });

    testWidgets('does not render when visible is false', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Stack(children: [InspectorFab(onTap: () {}, visible: false)]),
        ),
      );

      expect(find.byType(FloatingActionButton), findsNothing);
    });

    testWidgets('drags update position', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Stack(children: [InspectorFab(onTap: () {})]),
        ),
      );

      final fabFinder = find.byType(FloatingActionButton);
      final initialOffset = tester.getTopLeft(fabFinder);

      await tester.drag(fabFinder, const Offset(50, 50));
      await tester.pump();

      final newOffset = tester.getTopLeft(fabFinder);
      expect(newOffset.dx, greaterThan(initialOffset.dx));
      expect(newOffset.dy, greaterThan(initialOffset.dy));
    });
  });
}
