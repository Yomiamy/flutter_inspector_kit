import 'package:flutter/widgets.dart';

import '../inspectors/navigator_inspector.dart';
import '../models/navigator_action.dart';
import '../models/navigator_entry.dart';

/// An observer that records navigation events into the [NavigatorInspector].
class FlutterInspectorNavigatorObserver extends NavigatorObserver {
  /// Creates an observer that feeds events into [_inspector].
  FlutterInspectorNavigatorObserver(this._inspector);

  final NavigatorInspector _inspector;

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

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    super.didPush(route, previousRoute);
    if (_isInspectorRoute(route)) return;
    _inspector.add(
      NavigatorEntry(
        action: NavigatorAction.push,
        routeName: route.settings.name,
        widgetType: _resolveWidgetType(route),
        arguments: route.settings.arguments,
      ),
    );
  }

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    super.didPop(route, previousRoute);
    if (_isInspectorRoute(route)) return;
    _inspector.add(
      NavigatorEntry(
        action: NavigatorAction.pop,
        routeName: route.settings.name,
        widgetType: _resolveWidgetType(route),
        arguments: route.settings.arguments,
      ),
    );
  }

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) {
    super.didReplace(newRoute: newRoute, oldRoute: oldRoute);
    if (newRoute != null && !_isInspectorRoute(newRoute)) {
      _inspector.add(
        NavigatorEntry(
          action: NavigatorAction.replace,
          routeName: newRoute.settings.name,
          widgetType: _resolveWidgetType(newRoute),
          arguments: newRoute.settings.arguments,
        ),
      );
    }
  }

  @override
  void didRemove(Route<dynamic> route, Route<dynamic>? previousRoute) {
    super.didRemove(route, previousRoute);
    if (_isInspectorRoute(route)) return;
    _inspector.add(
      NavigatorEntry(
        action: NavigatorAction.remove,
        routeName: route.settings.name,
        widgetType: _resolveWidgetType(route),
        arguments: route.settings.arguments,
      ),
    );
  }
}
