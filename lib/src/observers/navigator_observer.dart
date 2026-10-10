import 'package:flutter/widgets.dart';

import '../core/flutter_inspector.dart';
import '../models/navigator_action.dart';
import '../models/navigator_entry.dart';
import '../utils/redaction.dart';
import '../utils/routing_param_extractor.dart';
import 'inspector_route_names.dart';

/// An observer that records navigation events into the inspector.
///
/// Each navigation event is buffered into the navigator inspector so that
/// route changes are visible in the Navigator tab.
class FlutterInspectorNavigatorObserver extends NavigatorObserver {
  /// Creates an observer that feeds events into [_inspector].
  FlutterInspectorNavigatorObserver(this._inspector);

  final FlutterInspector _inspector;

  /// Whether [route] belongs to the inspector's own UI.
  ///
  /// A `null` name means the host app pushed an unnamed route — that must be
  /// recorded, so null resolves to `false` (not filtered). Dropping unnamed
  /// routes would lose user data, which is worse than the bug this fixes.
  bool _isInspectorRoute(Route<dynamic> route) =>
      route.settings.name?.startsWith(kInspectorRoutePrefix) ?? false;

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
    final rawRouteName = route.settings.name;
    final redact = _inspector.redactSensitiveData;
    final routeName = _displayRouteName(rawRouteName, redact: redact);
    final widgetType = _resolveWidgetType(route);
    final routingParams = extractRoutingParams(
      routeName: rawRouteName,
      arguments: route.settings.arguments,
      redact: redact,
    );
    final sanitizedArgs = _sanitizeArguments(
      route.settings.arguments,
      redact: redact,
    );
    _inspector.navigatorInspector.add(
      NavigatorEntry(
        action: action,
        routeName: routeName,
        widgetType: widgetType,
        arguments: sanitizedArgs,
        routingParams: routingParams,
      ),
    );
  }

  String? _displayRouteName(String? routeName, {required bool redact}) {
    if (!redact || routeName == null) return routeName;
    final queryStart = routeName.indexOf('?');
    return queryStart < 0 ? routeName : routeName.substring(0, queryStart);
  }

  Object? _sanitizeArguments(Object? arguments, {required bool redact}) {
    if (!redact || arguments == null) return arguments;
    return _redactArgument(arguments);
  }

  static const int _kMaxRedactionDepth = 8;

  static Object? _redactArgument(
    Object? value, [
    Set<Object>? visited,
    int depth = 0,
  ]) {
    if (value == null) return null;
    if (depth >= _kMaxRedactionDepth) return '<deep>';

    if (value is Map || value is List || value is Set) {
      if (visited != null && visited.contains(value)) return '<circular>';
      final activeVisited = visited ?? Set<Object>.identity();
      activeVisited.add(value);
      try {
        if (value is Map) {
          return value.map((k, v) {
            final keyStr = k?.toString() ?? '';
            if (isSensitiveRoutingKey(keyStr)) {
              return MapEntry(k, kRedactedValue);
            }
            return MapEntry(k, _redactArgument(v, activeVisited, depth + 1));
          });
        } else if (value is Set) {
          return (value as Set)
              .map((item) => _redactArgument(item, activeVisited, depth + 1))
              .toSet();
        } else {
          return (value as List)
              .map((item) => _redactArgument(item, activeVisited, depth + 1))
              .toList();
        }
      } finally {
        activeVisited.remove(value);
      }
    }
    if (value is Uri) {
      try {
        if (!value.hasQuery) return value;
        final sanitizedParams = _sanitizeQueryParams(value.queryParametersAll);
        return value.replace(queryParameters: sanitizedParams);
      } catch (_) {
        return value.replace(query: '');
      }
    }
    if (value is String) {
      if (value.contains('?')) {
        try {
          final uri = Uri.tryParse(value);
          if (uri != null && uri.hasQuery) {
            final sanitizedParams = _sanitizeQueryParams(
              uri.queryParametersAll,
            );
            return uri.replace(queryParameters: sanitizedParams).toString();
          }
        } catch (_) {
          final idx = value.indexOf('?');
          return value.substring(0, idx);
        }
        final idx = value.indexOf('?');
        return value.substring(0, idx);
      }
      return value;
    }
    return value;
  }

  static Map<String, List<String>> _sanitizeQueryParams(
    Map<String, List<String>> params,
  ) {
    return params.map((k, v) {
      final isSensitive = isSensitiveRoutingKey(k);
      return MapEntry(
        k,
        isSensitive ? v.map((_) => kRedactedValue).toList() : v,
      );
    });
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
