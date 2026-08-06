import 'package:flutter/material.dart';
import 'package:flutter_inspector_kit/src/core/flutter_inspector.dart';
import 'package:flutter_inspector_kit/src/models/log_level.dart';
import 'package:flutter_inspector_kit/src/models/network_entry.dart';
import 'package:flutter_inspector_kit/src/ui/dashboard/dashboard_modal.dart';
import 'package:flutter_test/flutter_test.dart';

/// Locates the [Tab] labelled [tabLabel] and asserts whether [countText]
/// (the badge number) is nested under it specifically — not just anywhere
/// in the tree. Without this, a Console/Network badge swap would still
/// pass a bare `find.text(countText)` assertion.
Finder _badgeCountUnderTab(String tabLabel, String countText) {
  final tab = find.ancestor(
    of: find.text(tabLabel),
    matching: find.byType(Tab),
  );
  return find.descendant(of: tab, matching: find.text(countText));
}

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

      expect(_badgeCountUnderTab('Network', '2'), findsOneWidget);
      expect(_badgeCountUnderTab('Console', '2'), findsNothing);
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

      expect(_badgeCountUnderTab('Console', '2'), findsOneWidget);
      expect(_badgeCountUnderTab('Network', '2'), findsNothing);
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

        expect(_badgeCountUnderTab('Network', '1'), findsNothing);

        inspector.logNetwork(
          NetworkEntry(method: 'GET', url: '/fail', statusCode: 500),
        );
        await tester.pump();

        expect(_badgeCountUnderTab('Network', '1'), findsOneWidget);
        expect(_badgeCountUnderTab('Console', '1'), findsNothing);
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

    testWidgets(
      'rebuilding with a new inspector re-subscribes to its revision',
      (tester) async {
        final oldInspector = FlutterInspector();
        oldInspector.logNetwork(
          NetworkEntry(method: 'GET', url: '/old-fail', statusCode: 500),
        );

        await tester.pumpWidget(
          MaterialApp(home: DashboardModal(inspector: oldInspector)),
        );
        expect(find.text('1'), findsOneWidget);

        final newInspector = FlutterInspector();
        // Same widget position/type with no key: State is preserved and
        // didUpdateWidget fires instead of a fresh initState.
        await tester.pumpWidget(
          MaterialApp(home: DashboardModal(inspector: newInspector)),
        );
        // The new inspector starts empty, so its badge must be gone.
        expect(find.text('1'), findsNothing);

        // Mutating the *new* inspector must update the badge...
        newInspector.logNetwork(
          NetworkEntry(method: 'GET', url: '/new-fail', statusCode: 500),
        );
        await tester.pump();
        expect(find.text('1'), findsOneWidget);

        // ...while the *old* inspector must no longer be listened to.
        oldInspector.logNetwork(
          NetworkEntry(method: 'GET', url: '/old-fail-2', statusCode: 500),
        );
        await tester.pump();
        expect(find.text('1'), findsOneWidget);
        expect(find.text('2'), findsNothing);
      },
    );
  });
}
