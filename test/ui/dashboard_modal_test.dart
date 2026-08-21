import 'package:flutter/material.dart';
import 'package:flutter_inspector_kit/src/core/flutter_inspector.dart';
import 'package:flutter_inspector_kit/src/models/key_value_browser_source.dart';
import 'package:flutter_inspector_kit/src/ui/dashboard/dashboard_modal.dart';
import 'package:flutter_inspector_kit/src/ui/dashboard/tabs/storage_tab.dart';
import 'package:flutter_test/flutter_test.dart';

class FakeKvSource implements KeyValueBrowserSource {
  @override
  String get name => 'Prefs';

  @override
  Future<List<KeyValueEntry>> listAll() async => const [
    KeyValueEntry(key: 'token', value: 'abc', type: KeyValueType.string),
  ];

  @override
  Future<void> setValue(String key, Object? value) async {}

  @override
  Future<void> remove(String key) async {}

  @override
  Future<void> clear() async {}
}

void main() {
  group('DashboardModal', () {
    testWidgets('renders 4 tabs by default', (tester) async {
      final inspector = FlutterInspector(
        navigatorKey: GlobalKey<NavigatorState>(),
      );

      await tester.pumpWidget(
        MaterialApp(home: DashboardModal(inspector: inspector)),
      );

      expect(find.byType(Tab), findsNWidgets(4));
      expect(find.text('Console'), findsOneWidget);
    });

    testWidgets('opens on the Network tab when initialIndex is 1', (
      tester,
    ) async {
      final inspector = FlutterInspector(
        navigatorKey: GlobalKey<NavigatorState>(),
      );

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
      final inspector = FlutterInspector(
        navigatorKey: GlobalKey<NavigatorState>(),
      );

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
        navigatorKey: GlobalKey<NavigatorState>(),
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

  group('DashboardModal Storage tab', () {
    testWidgets('is absent when no key-value source is registered', (
      tester,
    ) async {
      final inspector = FlutterInspector(
        navigatorKey: GlobalKey<NavigatorState>(),
      );

      await tester.pumpWidget(
        MaterialApp(home: DashboardModal(inspector: inspector)),
      );

      expect(find.byType(Tab), findsNWidgets(4));
      expect(find.text('Storage'), findsNothing);
    });

    testWidgets('appears when a key-value source is registered', (
      tester,
    ) async {
      final inspector = FlutterInspector(
        navigatorKey: GlobalKey<NavigatorState>(),
        keyValueSources: [FakeKvSource()],
      );

      await tester.pumpWidget(
        MaterialApp(home: DashboardModal(inspector: inspector)),
      );

      expect(find.byType(Tab), findsNWidgets(5));
      expect(find.text('Storage'), findsOneWidget);
    });

    testWidgets('is appended after Database and before a custom tab', (
      tester,
    ) async {
      final inspector = FlutterInspector(
        navigatorKey: GlobalKey<NavigatorState>(),
        keyValueSources: [FakeKvSource()],
        customTab: const Text('custom body'),
        customTabTitle: 'MyTab',
      );

      await tester.pumpWidget(
        MaterialApp(home: DashboardModal(inspector: inspector)),
      );

      expect(find.byType(Tab), findsNWidgets(6));

      // Compare on-screen x positions: Storage must sit between Database and
      // the custom tab, so existing tab indices keep their meaning.
      double xOf(String label) => tester.getTopLeft(find.text(label)).dx;
      expect(xOf('Database'), lessThan(xOf('Storage')));
      expect(xOf('Storage'), lessThan(xOf('MyTab')));
    });

    testWidgets('selecting Storage shows StorageTab, not another tab body', (
      tester,
    ) async {
      final inspector = FlutterInspector(
        navigatorKey: GlobalKey<NavigatorState>(),
        keyValueSources: [FakeKvSource()],
        customTab: const Text('custom body'),
        customTabTitle: 'MyTab',
      );

      await tester.pumpWidget(
        MaterialApp(home: DashboardModal(inspector: inspector)),
      );
      await tester.tap(find.text('Storage'));
      await tester.pumpAndSettle();

      // Guards against tabs/children drifting out of sync: the title can be
      // right while the body belongs to a different tab, with no compile error.
      expect(find.byType(StorageTab), findsOneWidget);
      expect(find.text('custom body'), findsNothing);
    });

    testWidgets('existing tab indices are unchanged by the new tab', (
      tester,
    ) async {
      final inspector = FlutterInspector(
        navigatorKey: GlobalKey<NavigatorState>(),
        keyValueSources: [FakeKvSource()],
      );

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
      final inspector = FlutterInspector(
        navigatorKey: GlobalKey<NavigatorState>(),
        keyValueSources: [FakeKvSource()],
      );

      await tester.pumpWidget(
        MaterialApp(
          home: DashboardModal(inspector: inspector, initialIndex: 99),
        ),
      );

      // Catches "tabs updated but tabCount forgotten".
      final controller = DefaultTabController.of(
        tester.element(find.byType(TabBarView)),
      );
      expect(controller.index, 4);
    });
  });
}
