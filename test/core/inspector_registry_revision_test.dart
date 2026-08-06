import 'package:flutter_inspector_kit/src/core/inspector_registry.dart';
import 'package:flutter_inspector_kit/src/models/database_entry.dart';
import 'package:flutter_inspector_kit/src/models/database_operation.dart';
import 'package:flutter_inspector_kit/src/models/log_entry.dart';
import 'package:flutter_inspector_kit/src/models/log_level.dart';
import 'package:flutter_inspector_kit/src/models/navigator_action.dart';
import 'package:flutter_inspector_kit/src/models/navigator_entry.dart';
import 'package:flutter_inspector_kit/src/models/network_entry.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('InspectorRegistry revision', () {
    test('revision starts at 0', () {
      final registry = InspectorRegistry();
      expect(registry.revision.value, 0);
    });

    test('revision bumps on log add', () {
      final registry = InspectorRegistry();
      registry.log.add(LogEntry(message: 'hi', level: LogLevel.info));
      expect(registry.revision.value, 1);
    });

    test('revision bumps on network add', () {
      final registry = InspectorRegistry();
      registry.network.add(NetworkEntry(method: 'GET', url: '/1'));
      expect(registry.revision.value, 1);
    });

    test('revision bumps on navigator add', () {
      final registry = InspectorRegistry();
      registry.navigator.add(
        NavigatorEntry(action: NavigatorAction.push, routeName: '/home'),
      );
      expect(registry.revision.value, 1);
    });

    test('revision bumps on database add', () {
      final registry = InspectorRegistry();
      registry.database.add(
        DatabaseEntry(operation: DatabaseOperation.insert, tableName: 'users'),
      );
      expect(registry.revision.value, 1);
    });

    test('revision bumps on each of the four clears', () {
      final registry = InspectorRegistry()
        ..log.add(LogEntry(message: 'hi', level: LogLevel.info))
        ..network.add(NetworkEntry(method: 'GET', url: '/1'))
        ..navigator.add(
          NavigatorEntry(action: NavigatorAction.push, routeName: '/home'),
        )
        ..database.add(
          DatabaseEntry(
            operation: DatabaseOperation.insert,
            tableName: 'users',
          ),
        );
      expect(registry.revision.value, 4);

      registry.log.clear();
      expect(registry.revision.value, 5);
      registry.network.clear();
      expect(registry.revision.value, 6);
      registry.navigator.clear();
      expect(registry.revision.value, 7);
      registry.database.clear();
      expect(registry.revision.value, 8);
    });

    test('revision bumps on network replace', () {
      final registry = InspectorRegistry();
      final pending = registry.network.add(
        NetworkEntry(method: 'GET', url: '/1'),
      );
      expect(registry.revision.value, 1);

      registry.network.add(
        NetworkEntry(method: 'GET', url: '/1', statusCode: 200),
        replaces: pending,
      );
      expect(registry.revision.value, 2);
    });

    test('badge notification does not steal NetworkInspector.onAdd', () {
      final registry = InspectorRegistry();
      final addCalls = <String>[];
      registry.network.onAdd = (entry, total) => addCalls.add(entry.url);

      registry.network.add(NetworkEntry(method: 'GET', url: '/1'));

      expect(addCalls, ['/1']);
      expect(registry.revision.value, 1);
    });
  });
}
