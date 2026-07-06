import 'package:flutter/material.dart';
import 'package:flutter_inspector_kit/src/ui/inspector_overlay_manager.dart';
import 'package:flutter_inspector_kit/src/ui/widgets/inspector_fab.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('InspectorOverlayManager', () {
    testWidgets('attach shows FAB, detach removes it, attach is idempotent, taps work', (tester) async {
      bool tapped = false;
      final manager = InspectorOverlayManager(onFabTap: (_) => tapped = true);

      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) {
              return Scaffold(
                body: Center(
                  child: ElevatedButton(
                    onPressed: () => manager.attach(context: context),
                    child: const Text('Attach'),
                  ),
                ),
              );
            },
          ),
        ),
      );

      // Initially no FAB
      expect(find.byType(InspectorFab), findsNothing);

      // Attach
      await tester.tap(find.text('Attach'));
      await tester.pump();
      expect(find.byType(InspectorFab), findsOneWidget);

      // Repeat attach to verify idempotent behavior (no crash, still one FAB)
      await tester.tap(find.text('Attach'));
      await tester.pump();
      expect(find.byType(InspectorFab), findsOneWidget);

      // Tap FAB
      await tester.tap(find.byType(InspectorFab));
      expect(tapped, isTrue);

      // Detach
      manager.detach();
      await tester.pump();
      expect(find.byType(InspectorFab), findsNothing);
    });
  });
}
