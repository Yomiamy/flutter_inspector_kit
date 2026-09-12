import 'package:flutter/foundation.dart';

import 'navigator_action.dart';
import 'timestamped_entry.dart';

/// An immutable record of a navigation event, displayed in the Navigator tab.
@immutable
class NavigatorEntry implements TimestampedEntry {
  /// Creates a navigator entry. [timestamp] defaults to the moment of creation.
  NavigatorEntry({
    required this.action,
    this.routeName,
    this.widgetType,
    this.arguments,
    DateTime? timestamp,
  }) : timestamp = timestamp ?? DateTime.now();

  /// When the navigation event occurred.
  @override
  final DateTime timestamp;

  /// The kind of navigation event.
  final NavigatorAction action;

  /// The name of the affected route, if any.
  final String? routeName;

  /// The best-effort runtime type of the page widget behind the route, if it
  /// could be resolved. May be null when the route is not backed by a
  /// resolvable widget (e.g. a dialog, or a [MaterialPageRoute] whose builder
  /// was not run for safety reasons).
  final Type? widgetType;

  /// The arguments passed to the route, if any.
  final Object? arguments;

  /// A human-readable label for the affected destination.
  ///
  /// Prefers the resolved [widgetType], then the explicit [routeName], and
  /// finally a generic placeholder.
  String get displayName =>
      widgetType?.toString() ?? routeName ?? 'Unknown Route';

  /// The label identifying this entry's destination, matching the format
  /// stamped onto [LogEntry.activeRoute] and its network/database
  /// counterparts.
  ///
  /// This is the single source of truth for that format: comparing an entry's
  /// `activeRoute` against a navigation event means both sides must spell the
  /// route the same way, so `FlutterInspector` builds its anchor by calling
  /// this getter rather than restating the formula.
  ///
  /// Degrades to a bare [displayName] when the two would be the same string:
  /// with no resolved [widgetType], `displayName` already *is* the route name,
  /// and appending it again reads as `/checkout (/checkout)`.
  String get routeLabel {
    final route = routeName;
    if (route == null || route.isEmpty || route == displayName) {
      return displayName;
    }
    return '$displayName ($route)';
  }

  /// Returns a copy of this entry with the given fields replaced.
  NavigatorEntry copyWith({
    DateTime? timestamp,
    NavigatorAction? action,
    String? routeName,
    Type? widgetType,
    Object? arguments,
  }) {
    return NavigatorEntry(
      timestamp: timestamp ?? this.timestamp,
      action: action ?? this.action,
      routeName: routeName ?? this.routeName,
      widgetType: widgetType ?? this.widgetType,
      arguments: arguments ?? this.arguments,
    );
  }

  @override
  bool operator ==(Object other) {
    return other is NavigatorEntry &&
        other.timestamp == timestamp &&
        other.action == action &&
        other.routeName == routeName &&
        other.widgetType == widgetType &&
        other.arguments == arguments;
  }

  @override
  int get hashCode =>
      Object.hash(timestamp, action, routeName, widgetType, arguments);

  @override
  String toString() =>
      'NavigatorEntry(${action.name}, $displayName, $timestamp)';
}
