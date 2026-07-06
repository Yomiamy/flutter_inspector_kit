import 'package:flutter/material.dart';
import 'package:flutter_inspector_kit/src/ui/inspector_overlay_manager.dart';
import 'package:flutter_inspector_kit/src/ui/widgets/inspector_fab.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('InspectorOverlayManager', () {
    testWidgets('attach adds InspectorFab to overlay', (tester) async {
      bool tapped = false;
      final manager = InspectorOverlayManager(onFabTap: (ctx) => tapped = true);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) {
                return ElevatedButton(
                  onPressed: () => manager.attach(context: context),
                  child: const Text('Attach'),
                );
              },
            ),
          ),
        ),
      );

      expect(find.byType(InspectorFab), findsNothing);

      await tester.tap(find.text('Attach'));
      await tester.pump();

      expect(find.byType(InspectorFab), findsOneWidget);

      await tester.tap(find.byType(FloatingActionButton));
      expect(tapped, isTrue);
    });

    testWidgets('attach is idempotent', (tester) async {
      final manager = InspectorOverlayManager(onFabTap: (_) {});

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) {
                return ElevatedButton(
                  onPressed: () {
                    manager.attach(context: context);
                    manager.attach(context: context);
                  },
                  child: const Text('Attach Twice'),
                );
              },
            ),
          ),
        ),
      );

      await tester.tap(find.text('Attach Twice'));
      await tester.pump();

      expect(find.byType(InspectorFab), findsOneWidget);
    });

    testWidgets('detach removes InspectorFab', (tester) async {
      final manager = InspectorOverlayManager(onFabTap: (_) {});

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) {
                return Column(
                  children: [
                    ElevatedButton(
                      onPressed: () => manager.attach(context: context),
                      child: const Text('Attach'),
                    ),
                    ElevatedButton(
                      onPressed: () => manager.detach(),
                      child: const Text('Detach'),
                    ),
                  ],
                );
              },
            ),
          ),
        ),
      );

      await tester.tap(find.text('Attach'));
      await tester.pump();
      expect(find.byType(InspectorFab), findsOneWidget);

      await tester.tap(find.text('Detach'));
      await tester.pump();
      expect(find.byType(InspectorFab), findsNothing);
    });
  });
}
