import 'package:flutter/material.dart';
import 'package:flutter_inspector_kit/src/core/flutter_inspector.dart';
import 'package:flutter_inspector_kit/src/models/log_level.dart';
import 'package:flutter_inspector_kit/src/models/network_entry.dart';
import 'package:flutter_inspector_kit/src/ui/dashboard/dashboard_modal.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('DashboardModal error badges', () {
    testWidgets('Network tab shows 2 when two entries failed', (tester) async {
      final inspector = FlutterInspector();
      inspector.logNetwork(NetworkEntry(method: 'GET', url: '/ok'));
      inspector.logNetwork(
        NetworkEntry(method: 'GET', url: '/fail1', statusCode: 500),
      );
      inspector.logNetwork(
        NetworkEntry(method: 'GET', url: '/fail2', statusCode: 404),
      );

      await tester.pumpWidget(
        MaterialApp(home: DashboardModal(inspector: inspector)),
      );

      expect(find.text('2'), findsOneWidget);
      expect(find.byType(Tab), findsNWidgets(4));
    });

    testWidgets('Network tab shows no badge when all requests succeeded', (
      tester,
    ) async {
      final inspector = FlutterInspector();
      inspector.logNetwork(
        NetworkEntry(method: 'GET', url: '/ok1', statusCode: 200),
      );
      inspector.logNetwork(
        NetworkEntry(method: 'GET', url: '/ok2', statusCode: 200),
      );

      await tester.pumpWidget(
        MaterialApp(home: DashboardModal(inspector: inspector)),
      );

      final badges = tester.widgetList<Badge>(find.byType(Badge));
      expect(badges.every((b) => !b.isLabelVisible), isTrue);
    });

    testWidgets('Console tab shows 2 for one error and one warning', (
      tester,
    ) async {
      final inspector = FlutterInspector();
      inspector.log('error msg', level: LogLevel.error);
      inspector.log('warning msg', level: LogLevel.warning);
      inspector.log('info 1', level: LogLevel.info);
      inspector.log('info 2', level: LogLevel.info);
      inspector.log('info 3', level: LogLevel.info);

      await tester.pumpWidget(
        MaterialApp(home: DashboardModal(inspector: inspector)),
      );

      expect(find.text('2'), findsOneWidget);
    });

    testWidgets('empty inspector renders no badges on either tab', (
      tester,
    ) async {
      final inspector = FlutterInspector();

      await tester.pumpWidget(
        MaterialApp(home: DashboardModal(inspector: inspector)),
      );

      final badges = tester.widgetList<Badge>(find.byType(Badge));
      expect(badges.every((b) => !b.isLabelVisible), isTrue);
      expect(find.byType(Tab), findsNWidgets(4));
      expect(find.text('Console'), findsOneWidget);
    });

    testWidgets(
      'badge appears without any refresh when a failed request arrives',
      (tester) async {
        final inspector = FlutterInspector();

        await tester.pumpWidget(
          MaterialApp(home: DashboardModal(inspector: inspector)),
        );

        expect(find.text('1'), findsNothing);

        inspector.logNetwork(
          NetworkEntry(method: 'GET', url: '/fail', statusCode: 500),
        );
        await tester.pump();

        expect(find.text('1'), findsOneWidget);
      },
    );

    testWidgets('badge disappears after the buffer is cleared', (tester) async {
      final inspector = FlutterInspector();
      inspector.logNetwork(
        NetworkEntry(method: 'GET', url: '/fail', statusCode: 500),
      );

      await tester.pumpWidget(
        MaterialApp(home: DashboardModal(inspector: inspector)),
      );
      expect(find.text('1'), findsOneWidget);

      inspector.clearNetwork();
      await tester.pump();

      final badges = tester.widgetList<Badge>(find.byType(Badge));
      expect(badges.every((b) => !b.isLabelVisible), isTrue);
    });
  });
}
