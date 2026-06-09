import 'package:flutter/material.dart';
import 'package:flutter_inspector/src/core/flutter_inspector_impl.dart';
import 'package:flutter_inspector/src/ui/dashboard/dashboard_modal.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('DashboardModal', () {
    testWidgets('renders 4 tabs by default', (tester) async {
      final inspector = FlutterInspector();

      await tester.pumpWidget(MaterialApp(
        home: DashboardModal(inspector: inspector),
      ));

      expect(find.byType(Tab), findsNWidgets(4));
      expect(find.text('Console'), findsOneWidget);
    });

    testWidgets('renders 5 tabs when customTab is provided', (tester) async {
      final inspector = FlutterInspector(
        customTab: const Text('My Custom Tab Content'),
        customTabTitle: 'MyTab',
      );

      await tester.pumpWidget(MaterialApp(
        home: DashboardModal(inspector: inspector),
      ));

      expect(find.byType(Tab), findsNWidgets(5));
      expect(find.text('MyTab'), findsOneWidget);
    });
  });
}
