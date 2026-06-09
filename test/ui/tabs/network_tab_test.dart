import 'package:flutter/material.dart';
import 'package:flutter_inspector/src/core/flutter_inspector_impl.dart';
import 'package:flutter_inspector/src/models/network_entry.dart';
import 'package:flutter_inspector/src/ui/dashboard/tabs/network_tab.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('NetworkTab', () {
    testWidgets('displays network entries and supports clearing', (tester) async {
      final inspector = FlutterInspector();
      inspector.logNetwork(NetworkEntry(
        method: 'GET',
        url: '/api/test',
        statusCode: 200,
      ));

      await tester.pumpWidget(MaterialApp(
        home: Scaffold(body: NetworkTab(inspector: inspector)),
      ));

      expect(find.text('[GET] /api/test'), findsOneWidget);

      await tester.tap(find.byIcon(Icons.delete));
      await tester.pump();

      expect(find.text('[GET] /api/test'), findsNothing);
    });
  });
}
