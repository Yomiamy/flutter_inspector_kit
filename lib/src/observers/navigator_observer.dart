import 'package:flutter/widgets.dart';

import '../core/flutter_inspector.dart';
import '../models/navigator_action.dart';
import '../models/navigator_entry.dart';

/// An observer that records navigation events into the inspector.
///
/// Each navigation event is buffered into the navigator inspector so that
/// route changes are visible in the Navigator tab.
class FlutterInspectorNavigatorObserver extends NavigatorObserver {
  /// Creates an observer that feeds events into [_inspector].
  FlutterInspectorNavigatorObserver(this._inspector);

  final FlutterInspector _inspector;

  bool _isInspectorRoute(Route<dynamic> route) =>
      route.settings.name == 'flutter_inspector_dashboard';

  Type? _resolveWidgetType(Route<dynamic> route) {
    final settings = route.settings;
    if (settings is Page) {
      try {
        final dynamic page = settings;
        final child = page.child;
        if (child is Widget) {
          return child.runtimeType;
        }
      } catch (_) {}
    }

    final context = navigator?.context;
    if (context != null) {
      try {
        final dynamic dynamicRoute = route;
        final builder = dynamicRoute.builder;
        if (builder != null) {
          final widget = builder(context);
          if (widget is Widget) {
            return widget.runtimeType;
          }
        }
      } catch (_) {}
    }

    return null;
  }

  /// Buffers [route] as a navigation event into the navigator inspector.
  void _record(NavigatorAction action, Route<dynamic> route) {
    final routeName = route.settings.name;
    final widgetType = _resolveWidgetType(route);
    _inspector.navigatorInspector.add(
      NavigatorEntry(
        action: action,
        routeName: routeName,
        widgetType: widgetType,
        arguments: route.settings.arguments,
      ),
    );
  }

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    super.didPush(route, previousRoute);
    if (_isInspectorRoute(route)) return;
    _record(NavigatorAction.push, route);
  }

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    super.didPop(route, previousRoute);
    if (_isInspectorRoute(route)) return;
    _record(NavigatorAction.pop, route);
  }

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) {
    super.didReplace(newRoute: newRoute, oldRoute: oldRoute);
    if (newRoute != null && !_isInspectorRoute(newRoute)) {
      _record(NavigatorAction.replace, newRoute);
    }
  }

  @override
  void didRemove(Route<dynamic> route, Route<dynamic>? previousRoute) {
    super.didRemove(route, previousRoute);
    if (_isInspectorRoute(route)) return;
    _record(NavigatorAction.remove, route);
  }
}
