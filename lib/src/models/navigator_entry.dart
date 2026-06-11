import 'package:flutter/foundation.dart';

import 'navigator_action.dart';

/// An immutable record of a navigation event, displayed in the Navigator tab.
@immutable
class NavigatorEntry {
  /// Creates a navigator entry. [timestamp] defaults to the moment of creation.
  NavigatorEntry({
    required this.action,
    this.routeName,
    this.arguments,
    DateTime? timestamp,
  }) : timestamp = timestamp ?? DateTime.now();

  /// When the navigation event occurred.
  final DateTime timestamp;

  /// The kind of navigation event.
  final NavigatorAction action;

  /// The name of the affected route, if any.
  final String? routeName;

  /// The arguments passed to the route, if any.
  final Object? arguments;

  /// Returns a copy of this entry with the given fields replaced.
  NavigatorEntry copyWith({
    DateTime? timestamp,
    NavigatorAction? action,
    String? routeName,
    Object? arguments,
  }) {
    return NavigatorEntry(
      timestamp: timestamp ?? this.timestamp,
      action: action ?? this.action,
      routeName: routeName ?? this.routeName,
      arguments: arguments ?? this.arguments,
    );
  }

  @override
  bool operator ==(Object other) {
    return other is NavigatorEntry &&
        other.timestamp == timestamp &&
        other.action == action &&
        other.routeName == routeName &&
        other.arguments == arguments;
  }

  @override
  int get hashCode => Object.hash(timestamp, action, routeName, arguments);

  @override
  String toString() => 'NavigatorEntry(${action.name}, $routeName, $timestamp)';
}
