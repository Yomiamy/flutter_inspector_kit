import 'package:flutter/widgets.dart';

import '../inspectors/navigator_inspector.dart';
import '../models/navigator_action.dart';
import '../models/navigator_entry.dart';

/// An observer that records navigation events into the [NavigatorInspector].
class FlutterInspectorNavigatorObserver extends NavigatorObserver {
  /// Creates an observer that feeds events into [_inspector].
  FlutterInspectorNavigatorObserver(this._inspector);

  final NavigatorInspector _inspector;

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    super.didPush(route, previousRoute);
    _inspector.add(NavigatorEntry(
      action: NavigatorAction.push,
      routeName: route.settings.name,
      arguments: route.settings.arguments,
    ));
  }

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    super.didPop(route, previousRoute);
    _inspector.add(NavigatorEntry(
      action: NavigatorAction.pop,
      routeName: route.settings.name,
      arguments: route.settings.arguments,
    ));
  }

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) {
    super.didReplace(newRoute: newRoute, oldRoute: oldRoute);
    if (newRoute != null) {
      _inspector.add(NavigatorEntry(
        action: NavigatorAction.replace,
        routeName: newRoute.settings.name,
        arguments: newRoute.settings.arguments,
      ));
    }
  }

  @override
  void didRemove(Route<dynamic> route, Route<dynamic>? previousRoute) {
    super.didRemove(route, previousRoute);
    _inspector.add(NavigatorEntry(
      action: NavigatorAction.remove,
      routeName: route.settings.name,
      arguments: route.settings.arguments,
    ));
  }
}
