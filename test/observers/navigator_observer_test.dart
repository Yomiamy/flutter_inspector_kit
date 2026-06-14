import 'package:flutter/material.dart';
import 'package:flutter_inspector_kit/src/inspectors/navigator_inspector.dart';
import 'package:flutter_inspector_kit/src/models/navigator_action.dart';
import 'package:flutter_inspector_kit/src/observers/navigator_observer.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('FlutterInspectorNavigatorObserver', () {
    late NavigatorInspector inspector;
    late FlutterInspectorNavigatorObserver observer;

    setUp(() {
      inspector = NavigatorInspector();
      observer = FlutterInspectorNavigatorObserver(inspector);
    });

    test('didPush captures push action', () {
      final route = MaterialPageRoute(
        settings: const RouteSettings(name: '/home', arguments: 'arg1'),
        builder: (_) => const SizedBox(),
      );
      observer.didPush(route, null);

      expect(inspector.entries.length, 1);
      final entry = inspector.entries.first;
      expect(entry.action, NavigatorAction.push);
      expect(entry.routeName, '/home');
      expect(entry.arguments, 'arg1');
    });

    test('didPop captures pop action', () {
      final route = MaterialPageRoute(
        settings: const RouteSettings(name: '/home'),
        builder: (_) => const SizedBox(),
      );
      observer.didPop(route, null);

      expect(inspector.entries.length, 1);
      final entry = inspector.entries.first;
      expect(entry.action, NavigatorAction.pop);
      expect(entry.routeName, '/home');
    });

    test('didReplace captures replace action', () {
      final newRoute = MaterialPageRoute(
        settings: const RouteSettings(name: '/new'),
        builder: (_) => const SizedBox(),
      );
      observer.didReplace(newRoute: newRoute, oldRoute: null);

      expect(inspector.entries.length, 1);
      final entry = inspector.entries.first;
      expect(entry.action, NavigatorAction.replace);
      expect(entry.routeName, '/new');
    });

    test('didRemove captures remove action', () {
      final route = MaterialPageRoute(
        settings: const RouteSettings(name: '/removed'),
        builder: (_) => const SizedBox(),
      );
      observer.didRemove(route, null);

      expect(inspector.entries.length, 1);
      final entry = inspector.entries.first;
      expect(entry.action, NavigatorAction.remove);
      expect(entry.routeName, '/removed');
    });

    test('resolves widgetType from a Page child without side effects', () {
      // Navigator 2.0 / GoRouter: the route is backed by a Page whose child is
      // already instantiated, so the widget type is resolved with zero risk.
      final route = const MaterialPage<void>(
        child: _SamplePage(),
      ).createRoute(_FakeContext());

      observer.didPush(route, null);

      final entry = inspector.entries.first;
      expect(entry.widgetType, _SamplePage);
    });

    testWidgets(
      'resolves widgetType from builder',
      (tester) async {
        // A real Navigator is required so the observer has a navigator context
        // from which to run the route builder.
        await tester.pumpWidget(
          MaterialApp(
            navigatorObservers: [observer],
            home: const SizedBox(),
          ),
        );

        final navigator = tester.state<NavigatorState>(find.byType(Navigator));
        navigator.push(
          MaterialPageRoute<void>(builder: (_) => const _SamplePage()),
        );
        await tester.pumpAndSettle();

        final pushEntry = inspector.entries
            .firstWhere((e) => e.action == NavigatorAction.push);
        expect(pushEntry.widgetType, _SamplePage);
      },
    );

    test('ignores inspector dashboard route', () {
      final route = MaterialPageRoute(
        settings: const RouteSettings(name: 'flutter_inspector_dashboard'),
        builder: (_) => const SizedBox(),
      );

      observer.didPush(route, null);
      expect(inspector.entries, isEmpty);

      observer.didPop(route, null);
      expect(inspector.entries, isEmpty);

      observer.didReplace(newRoute: route, oldRoute: null);
      expect(inspector.entries, isEmpty);

      observer.didRemove(route, null);
      expect(inspector.entries, isEmpty);
    });
  });
}

class _SamplePage extends StatelessWidget {
  const _SamplePage();

  @override
  Widget build(BuildContext context) => const SizedBox();
}

/// A minimal [BuildContext] for constructing a route from a [Page] in tests.
/// The Page-child resolution path never touches this context.
class _FakeContext extends Fake implements BuildContext {}
