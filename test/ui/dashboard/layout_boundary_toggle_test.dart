import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_inspector_kit/src/core/flutter_inspector.dart';
import 'package:flutter_inspector_kit/src/ui/dashboard/dashboard_modal.dart';
import 'package:flutter_test/flutter_test.dart';

class _PaintCounter extends CustomPainter {
  int paintCount = 0;

  @override
  void paint(Canvas canvas, Size size) {
    paintCount++;
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

void main() {
  group('Layout Boundary Overlay Toggle', () {
    late FlutterInspector inspector;

    setUp(() {
      debugPaintSizeEnabled = false;
      inspector = FlutterInspector(
        navigatorKey: GlobalKey<NavigatorState>(),
      );
    });

    tearDown(() {
      debugPaintSizeEnabled = false;
    });

    testWidgets(
      'renders toggle button in DashboardModal and toggles debugPaintSizeEnabled on tap',
      (tester) async {
        final paintCounter = _PaintCounter();

        await tester.pumpWidget(
          MaterialApp(
            home: Stack(
              children: [
                DashboardModal(inspector: inspector),
                RepaintBoundary(
                  child: CustomPaint(
                    painter: paintCounter,
                    size: const Size(1, 1),
                  ),
                ),
              ],
            ),
          ),
        );
        final initialPaintCount = paintCounter.paintCount;

        // Initially disabled
        expect(debugPaintSizeEnabled, isFalse);
        final enableButton = find.byTooltip('Enable layout boundaries');
        expect(enableButton, findsOneWidget);
        expect(find.byIcon(Icons.grid_off_outlined), findsOneWidget);

        // Tap to enable
        await tester.tap(enableButton);
        await tester.pumpAndSettle();

        expect(debugPaintSizeEnabled, isTrue);
        expect(paintCounter.paintCount, greaterThan(initialPaintCount));
        final disableButton = find.byTooltip('Disable layout boundaries');
        expect(disableButton, findsOneWidget);
        expect(find.byIcon(Icons.grid_on), findsOneWidget);

        // Tap to disable again
        await tester.tap(disableButton);
        await tester.pumpAndSettle();

        expect(debugPaintSizeEnabled, isFalse);
        expect(find.byTooltip('Enable layout boundaries'), findsOneWidget);
        expect(find.byIcon(Icons.grid_off_outlined), findsOneWidget);
      },
    );

    testWidgets(
      'reflects initial enabled state when debugPaintSizeEnabled is already true',
      (tester) async {
        debugPaintSizeEnabled = true;

        await tester.pumpWidget(
          MaterialApp(
            home: DashboardModal(inspector: inspector),
          ),
        );

        expect(find.byTooltip('Disable layout boundaries'), findsOneWidget);
        expect(find.byIcon(Icons.grid_on), findsOneWidget);

        await tester.tap(find.byTooltip('Disable layout boundaries'));
        await tester.pumpAndSettle();

        expect(debugPaintSizeEnabled, isFalse);
        expect(find.byTooltip('Enable layout boundaries'), findsOneWidget);
      },
    );
  });
}
