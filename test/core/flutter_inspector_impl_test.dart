import 'package:flutter_inspector/src/core/flutter_inspector_impl.dart';
import 'package:flutter_inspector/src/models/database_operation.dart';
import 'package:flutter_inspector/src/models/log_level.dart';
import 'package:flutter_inspector/src/models/network_entry.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('FlutterInspector Core', () {
    test('instances hold isolated registries', () {
      final inspector1 = FlutterInspector(bufferSize: 10);
      final inspector2 = FlutterInspector(bufferSize: 10);

      inspector1.log('Message 1');

      expect(inspector1.registry.log.entries.length, 1);
      expect(inspector2.registry.log.entries.length, 0);
    });

    test('log adds to LogInspector', () {
      final inspector = FlutterInspector();
      inspector.log('Test message', level: LogLevel.warning);

      final entries = inspector.registry.log.entries;
      expect(entries.length, 1);
      expect(entries.first.message, 'Test message');
      expect(entries.first.level, LogLevel.warning);
    });

    test('logNetwork adds to NetworkInspector', () {
      final inspector = FlutterInspector();
      inspector.logNetwork(NetworkEntry(method: 'GET', url: '/api'));

      final entries = inspector.registry.network.entries;
      expect(entries.length, 1);
      expect(entries.first.url, '/api');
    });

    test('database adds to DatabaseInspector', () {
      final inspector = FlutterInspector();
      inspector.database(DatabaseOperation.insert, 'users', affectedRows: 1);

      final entries = inspector.registry.database.entries;
      expect(entries.length, 1);
      expect(entries.first.tableName, 'users');
      expect(entries.first.affectedRows, 1);
    });

    test('provides a NavigatorObserver linked to its NavigatorInspector', () {
      final inspector = FlutterInspector();
      final observer = inspector.navigatorObserver;
      expect(observer, isNotNull);
    });
  });
}
