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
  });
}
