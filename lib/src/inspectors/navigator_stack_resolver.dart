import '../models/navigator_action.dart';
import '../models/navigator_entry.dart';

/// Derives the current route stack from a sequence of navigation events.
///
/// This is a pure Dart replayer with no dependency on the Flutter widget tree,
/// so it can be unit tested in isolation. It reads the same event list that the
/// Navigator tab renders and replays the push/pop/replace/remove stack
/// semantics to produce a best-effort snapshot of "the stack right now".
class NavigatorStackResolver {
  /// Replays [entries] and returns the current route stack, top-first.
  ///
  /// [entries] is expected in the shape of `FlutterInspector.navigatorEntries`:
  /// **newest-first** (the most recent event at index 0). The replay must apply
  /// events in the order they occurred, so the first step reverses [entries]
  /// back into chronological (oldest-first) order.
  ///
  /// The returned list is **top-first**: index 0 is the top of the stack (the
  /// current screen) and the last element is the root route.
  List<NavigatorEntry> resolve(List<NavigatorEntry> entries) {
    // Reverse newest-first input back into chronological (oldest-first) order.
    final chronological = entries.reversed.toList();

    // Working stack is bottom-to-top: stack.last is the top of the stack.
    final stack = <NavigatorEntry>[];

    for (final entry in chronological) {
      switch (entry.action) {
        case NavigatorAction.push:
          stack.add(entry);
        case NavigatorAction.pop:
          if (stack.isNotEmpty) {
            stack.removeLast();
          }
        case NavigatorAction.replace:
          if (stack.isNotEmpty) {
            stack[stack.length - 1] = entry;
          } else {
            stack.add(entry);
          }
        case NavigatorAction.remove:
          // Scan from top toward bottom, removing the first matching layer.
          for (var i = stack.length - 1; i >= 0; i--) {
            if (_matches(stack[i], entry)) {
              stack.removeAt(i);
              break;
            }
          }
      }
    }

    // Reverse bottom-to-top working stack into top-first output.
    return stack.reversed.toList();
  }

  /// Two entries refer to the same route layer when both their [routeName] and
  /// [widgetType] match.
  bool _matches(NavigatorEntry a, NavigatorEntry b) =>
      a.routeName == b.routeName && a.widgetType == b.widgetType;
}
