import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_inspector/src/models/network_entry.dart';
import 'package:flutter_inspector/src/ui/dashboard/tabs/network/network_detail_view.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final t = DateTime(2026, 6, 10, 12, 0, 0);

  NetworkEntry sample() => NetworkEntry(
        method: 'POST',
        url: 'https://api.test/users?page=2',
        statusCode: 201,
        duration: const Duration(milliseconds: 120),
        requestHeaders: {'Content-Type': 'application/json'},
        requestBody: '{"name":"x"}',
        responseHeaders: {'content-type': 'application/json'},
        responseBody: '{"id":1}',
        isComplete: true,
        timestamp: t,
      );

  group('NetworkDetailView', () {
    testWidgets('renders all sections', (tester) async {
      tester.view.physicalSize = const Size(1200, 4000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
          MaterialApp(home: NetworkDetailView(entry: sample())));

      expect(find.text('General'), findsOneWidget);
      expect(find.text('Query Parameters'), findsOneWidget);
      expect(find.text('Request Headers'), findsOneWidget);
      expect(find.text('Request Body'), findsOneWidget);
      expect(find.text('Response Headers'), findsOneWidget);
      expect(find.text('Response Body'), findsOneWidget);
    });

    testWidgets('copy as cURL writes to clipboard', (tester) async {
      String? clipboardText;
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async {
          if (call.method == 'Clipboard.setData') {
            clipboardText = (call.arguments as Map)['text'] as String?;
          }
          return null;
        },
      );

      await tester.pumpWidget(
          MaterialApp(home: NetworkDetailView(entry: sample())));

      await tester.tap(find.byIcon(Icons.share));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Copy as cURL'));
      await tester.pumpAndSettle();

      expect(clipboardText, isNotNull);
      expect(clipboardText!.startsWith('curl -X POST'), isTrue);
    });
  });

  group('statusColorFor', () {
    test('semantics by range', () {
      expect(statusColorFor(200, false), Colors.green);
      expect(statusColorFor(301, false), Colors.blue);
      expect(statusColorFor(404, false), Colors.orange);
      expect(statusColorFor(500, false), Colors.red);
      expect(statusColorFor(null, true), Colors.red);
    });
  });
}
