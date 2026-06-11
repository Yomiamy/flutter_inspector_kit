import 'package:flutter/material.dart';
import 'package:flutter_inspector_kit/src/core/flutter_inspector_impl.dart';
import 'package:flutter_inspector_kit/src/ui/dashboard/dashboard_modal.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('DashboardModal', () {
    testWidgets('renders 4 tabs by default', (tester) async {
      final inspector = FlutterInspector();

      await tester.pumpWidget(
        MaterialApp(home: DashboardModal(inspector: inspector)),
      );

      expect(find.byType(Tab), findsNWidgets(4));
      expect(find.text('Console'), findsOneWidget);
    });

    testWidgets('opens on the Network tab when initialIndex is 1', (
      tester,
    ) async {
      final inspector = FlutterInspector();

      await tester.pumpWidget(
        MaterialApp(
          home: DashboardModal(inspector: inspector, initialIndex: 1),
        ),
      );

      final controller = DefaultTabController.of(
        tester.element(find.byType(TabBarView)),
      );
      expect(controller.index, 1);
    });

    testWidgets('clamps an out-of-range initialIndex to the last tab', (
      tester,
    ) async {
      final inspector = FlutterInspector();

      await tester.pumpWidget(
        MaterialApp(
          home: DashboardModal(inspector: inspector, initialIndex: 99),
        ),
      );

      final controller = DefaultTabController.of(
        tester.element(find.byType(TabBarView)),
      );
      expect(controller.index, 3);
    });

    testWidgets('renders 5 tabs when customTab is provided', (tester) async {
      final inspector = FlutterInspector(
        customTab: const Text('My Custom Tab Content'),
        customTabTitle: 'MyTab',
      );

      await tester.pumpWidget(
        MaterialApp(home: DashboardModal(inspector: inspector)),
      );

      expect(find.byType(Tab), findsNWidgets(5));
      expect(find.text('MyTab'), findsOneWidget);
    });
  });
}
