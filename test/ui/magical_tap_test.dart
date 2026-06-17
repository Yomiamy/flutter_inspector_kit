import 'package:flutter/material.dart';
import 'package:flutter_inspector_kit/src/ui/widgets/magical_tap.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('FlutterInspectorMagicalTap', () {
    testWidgets('triggers callback after specified tap count', (tester) async {
      bool tapped = false;
      await tester.pumpWidget(
        MaterialApp(
          home: FlutterInspectorMagicalTap(
            onTap: () => tapped = true,
            tapCount: 3,
            timeout: const Duration(milliseconds: 500),
            child: const SizedBox(width: 100, height: 100),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final finder = find.byType(SizedBox);
      await tester.tap(finder, warnIfMissed: false);
      await tester.runAsync(() => Future.delayed(const Duration(milliseconds: 10)));
      await tester.tap(finder, warnIfMissed: false);
      await tester.runAsync(() => Future.delayed(const Duration(milliseconds: 10)));
      await tester.tap(finder, warnIfMissed: false);

      expect(tapped, isTrue);
    });

    testWidgets('resets tap count if timeout exceeded', (tester) async {
      bool tapped = false;
      await tester.pumpWidget(
        MaterialApp(
          home: FlutterInspectorMagicalTap(
            onTap: () => tapped = true,
            tapCount: 3,
            timeout: const Duration(milliseconds: 100),
            child: const SizedBox(width: 100, height: 100),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final finder = find.byType(SizedBox);
      await tester.tap(finder, warnIfMissed: false);
      await tester.runAsync(() => Future.delayed(const Duration(milliseconds: 10)));
      await tester.tap(finder, warnIfMissed: false);

      // exceed timeout
      await tester.runAsync(() => Future.delayed(const Duration(milliseconds: 150)));

      await tester.tap(finder, warnIfMissed: false); // tap 3

      expect(tapped, isFalse);
    });
  });
}
