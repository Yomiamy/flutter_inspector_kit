import 'package:flutter/foundation.dart';

import 'navigator_action.dart';

/// An immutable record of a navigation event, displayed in the Navigator tab.
@immutable
class NavigatorEntry {
  /// Creates a navigator entry. [timestamp] defaults to the moment of creation.
  NavigatorEntry({
    required this.action,
    this.routeName,
    this.widgetType,
    this.arguments,
    DateTime? timestamp,
  }) : timestamp = timestamp ?? DateTime.now();

  /// When the navigation event occurred.
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
