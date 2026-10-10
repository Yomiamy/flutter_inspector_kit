import 'package:flutter/material.dart';
import 'package:flutter_inspector_kit/src/core/flutter_inspector.dart';
import 'package:flutter_inspector_kit/src/models/navigator_action.dart';
import 'package:flutter_inspector_kit/src/observers/inspector_route_names.dart';
import 'package:flutter_inspector_kit/src/observers/navigator_observer.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('FlutterInspectorNavigatorObserver', () {
    late FlutterInspector inspector;
    late FlutterInspectorNavigatorObserver observer;

    setUp(() {
      inspector = FlutterInspector(navigatorKey: GlobalKey<NavigatorState>());
      observer = inspector.navigatorObserver;
    });

    test('didPush captures push action', () {
      final route = MaterialPageRoute(
        settings: const RouteSettings(name: '/home', arguments: 'arg1'),
        builder: (_) => const SizedBox(),
      );
      observer.didPush(route, null);

      expect(inspector.navigatorInspector.entries.length, 1);
      final entry = inspector.navigatorInspector.entries.first;
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

      expect(inspector.navigatorInspector.entries.length, 1);
      final entry = inspector.navigatorInspector.entries.first;
      expect(entry.action, NavigatorAction.pop);
      expect(entry.routeName, '/home');
    });

    test('didReplace captures replace action', () {
      final newRoute = MaterialPageRoute(
        settings: const RouteSettings(name: '/new'),
        builder: (_) => const SizedBox(),
      );
      observer.didReplace(newRoute: newRoute, oldRoute: null);

      expect(inspector.navigatorInspector.entries.length, 1);
      final entry = inspector.navigatorInspector.entries.first;
      expect(entry.action, NavigatorAction.replace);
      expect(entry.routeName, '/new');
    });

    test('didRemove captures remove action', () {
      final route = MaterialPageRoute(
        settings: const RouteSettings(name: '/removed'),
        builder: (_) => const SizedBox(),
      );
      observer.didRemove(route, null);

      expect(inspector.navigatorInspector.entries.length, 1);
      final entry = inspector.navigatorInspector.entries.first;
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

      final entry = inspector.navigatorInspector.entries.first;
      expect(entry.widgetType, _SamplePage);
    });

    testWidgets('resolves widgetType from builder', (tester) async {
      // A real Navigator is required so the observer has a navigator context
      // from which to run the route builder.
      await tester.pumpWidget(
        MaterialApp(navigatorObservers: [observer], home: const SizedBox()),
      );

      final navigator = tester.state<NavigatorState>(find.byType(Navigator));
      navigator.push(
        MaterialPageRoute<void>(builder: (_) => const _SamplePage()),
      );
      await tester.pumpAndSettle();

      final pushEntry = inspector.navigatorInspector.entries.firstWhere(
        (e) => e.action == NavigatorAction.push,
      );
      expect(pushEntry.widgetType, _SamplePage);
    });

    test(
      'records an unnamed user route (name == null must not be dropped)',
      () {
        final route = MaterialPageRoute<void>(builder: (_) => const SizedBox());
        observer.didPush(route, null);

        expect(inspector.navigatorInspector.entries.length, 1);
        expect(inspector.navigatorInspector.entries.first.routeName, isNull);
      },
    );

    test('records user routes whose names merely resemble the prefix', () {
      for (final name in ['/flutter', '/inspector', '/home', 'flutter_x']) {
        observer.didPush(
          MaterialPageRoute<void>(
            settings: RouteSettings(name: name),
            builder: (_) => const SizedBox(),
          ),
          null,
        );
      }
      expect(inspector.navigatorInspector.entries.length, 4);
    });

    test('ignores inspector dashboard route', () {
      final route = MaterialPageRoute(
        settings: const RouteSettings(name: kInspectorDashboardRoute),
        builder: (_) => const SizedBox(),
      );

      observer.didPush(route, null);
      expect(inspector.navigatorInspector.entries, isEmpty);

      observer.didPop(route, null);
      expect(inspector.navigatorInspector.entries, isEmpty);

      observer.didReplace(newRoute: route, oldRoute: null);
      expect(inspector.navigatorInspector.entries, isEmpty);

      observer.didRemove(route, null);
      expect(inspector.navigatorInspector.entries, isEmpty);
    });

    test('does not mirror any navigation event to the console log', () {
      final route = MaterialPageRoute(
        settings: const RouteSettings(name: '/home'),
        builder: (_) => const SizedBox(),
      );
      observer.didPush(route, null);

      expect(inspector.logEntries, isEmpty);
    });

    test('captures routingParams from routeName query and Map arguments', () {
      final route = MaterialPageRoute(
        settings: const RouteSettings(
          name: '/order?source=push',
          arguments: {'orderId': 12345, 'status': 'shipped'},
        ),
        builder: (_) => const SizedBox(),
      );
      observer.didPush(route, null);

      expect(inspector.navigatorInspector.entries.length, 1);
      final entry = inspector.navigatorInspector.entries.first;
      expect(entry.routingParams, {
        'source': 'push',
        'orderId': '12345',
        'status': 'shipped',
      });
    });

    test(
      'respects inspector redactSensitiveData flag for captured routingParams',
      () {
        final secureInspector = FlutterInspector(
          navigatorKey: GlobalKey<NavigatorState>(),
          redactSensitiveData: true,
        );
        final secureObserver = secureInspector.navigatorObserver;

        final route = MaterialPageRoute(
          settings: const RouteSettings(
            name: '/login?token=abc12345',
            arguments: {'password': 'pass', 'user': 'bob'},
          ),
          builder: (_) => const SizedBox(),
        );
        secureObserver.didPush(route, null);

        final entry = secureInspector.navigatorInspector.entries.first;
        expect(entry.routingParams?['user'], 'bob');
        expect(entry.routingParams?['token'], '••••');
        expect(entry.routingParams?['password'], '••••');
        expect(entry.routeName, '/login');
        expect((entry.arguments as Map)['password'], '••••');
      },
    );

    test('sanitizes nested maps and non-Map arguments in redact mode', () {
      final secureInspector = FlutterInspector(
        navigatorKey: GlobalKey<NavigatorState>(),
        redactSensitiveData: true,
      );
      final secureObserver = secureInspector.navigatorObserver;

      // 1. Nested Map
      secureObserver.didPush(
        MaterialPageRoute(
          settings: const RouteSettings(
            name: '/profile',
            arguments: {
              'meta': {'pinCode': '1234', 'name': 'Alice'},
            },
          ),
          builder: (_) => const SizedBox(),
        ),
        null,
      );
      final nestedEntry = secureInspector.navigatorInspector.entries.first;
      final nestedArgs = nestedEntry.arguments as Map;
      expect((nestedArgs['meta'] as Map)['pinCode'], '••••');
      expect((nestedArgs['meta'] as Map)['name'], 'Alice');

      // 2. Uri argument with sensitive query parameter
      secureObserver.didPush(
        MaterialPageRoute(
          settings: RouteSettings(
            name: '/redirect',
            arguments: Uri.parse(
              'https://example.com/login?token=secret123&user=sam',
            ),
          ),
          builder: (_) => const SizedBox(),
        ),
        null,
      );
      final uriEntry = secureInspector.navigatorInspector.entries.first;
      final uriArgs = uriEntry.arguments as Uri;
      expect(uriArgs.queryParameters['token'], '••••');
      expect(uriArgs.queryParameters['user'], 'sam');

      // 3. String argument with sensitive query parameter
      secureObserver.didPush(
        MaterialPageRoute(
          settings: const RouteSettings(
            name: '/link',
            arguments: '/auth?apiKey=mySecretKey&flag=1',
          ),
          builder: (_) => const SizedBox(),
        ),
        null,
      );
      final strEntry = secureInspector.navigatorInspector.entries.first;
      expect(
        strEntry.arguments as String,
        '/auth?apiKey=%E2%80%A2%E2%80%A2%E2%80%A2%E2%80%A2&flag=1',
      );

      // 4. String argument with malformed query
      secureObserver.didPush(
        MaterialPageRoute(
          settings: const RouteSettings(
            name: '/bad',
            arguments: '/auth?malformed=%E0%A4',
          ),
          builder: (_) => const SizedBox(),
        ),
        null,
      );
      final badEntry = secureInspector.navigatorInspector.entries.first;
      expect(badEntry.arguments as String, '/auth');
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
