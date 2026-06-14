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
  });
}
