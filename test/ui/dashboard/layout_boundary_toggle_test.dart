import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_inspector_kit/src/core/flutter_inspector.dart';
import 'package:flutter_inspector_kit/src/ui/dashboard/dashboard_modal.dart';
import 'package:flutter_test/flutter_test.dart';

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
        await tester.pumpWidget(
          MaterialApp(
            home: DashboardModal(inspector: inspector),
          ),
        );

        // Initially disabled
        expect(debugPaintSizeEnabled, isFalse);
        final enableButton = find.byTooltip('Enable layout boundaries');
        expect(enableButton, findsOneWidget);
        expect(find.byIcon(Icons.grid_off_outlined), findsOneWidget);

        // Tap to enable
        await tester.tap(enableButton);
        await tester.pumpAndSettle();

        expect(debugPaintSizeEnabled, isTrue);
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
