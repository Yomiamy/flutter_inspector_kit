import 'package:flutter_inspector_kit/src/inspectors/navigator_inspector.dart';
import 'package:flutter_inspector_kit/src/models/navigator_action.dart';
import 'package:flutter_inspector_kit/src/models/navigator_entry.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('NavigatorInspector', () {
    late NavigatorInspector inspector;

    setUp(() {
      inspector = NavigatorInspector(bufferCapacity: 3);
    });

    test('adds navigator entries and returns newest first', () {
      final entry1 = NavigatorEntry(
        action: NavigatorAction.push,
        routeName: '/home',
      );
      final entry2 = NavigatorEntry(
        action: NavigatorAction.pop,
        routeName: '/home',
      );

      inspector.add(entry1);
      inspector.add(entry2);

      expect(inspector.entries, [entry2, entry1]);
    });

    test('clears buffer', () {
      inspector.add(NavigatorEntry(action: NavigatorAction.push));
      inspector.clear();
      expect(inspector.entries, isEmpty);
    });
  });
}
