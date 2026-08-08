import 'package:flutter/widgets.dart';
import 'package:flutter_inspector_kit/src/core/flutter_inspector.dart';
import 'package:flutter_inspector_kit/src/models/database_browser_source.dart';
import 'package:flutter_inspector_kit/src/models/database_operation.dart';
import 'package:flutter_inspector_kit/src/models/diagnostic_info.dart';
import 'package:flutter_inspector_kit/src/models/log_level.dart';
import 'package:flutter_inspector_kit/src/models/network_entry.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('FlutterInspector Core', () {
    test('instances hold isolated registries', () {
      final inspector1 = FlutterInspector(
        navigatorKey: GlobalKey<NavigatorState>(),
        bufferSize: 10,
      );
      final inspector2 = FlutterInspector(
        navigatorKey: GlobalKey<NavigatorState>(),
        bufferSize: 10,
      );

      inspector1.log('Message 1');

      expect(inspector1.registry.log.entries.length, 1);
      expect(inspector2.registry.log.entries.length, 0);
    });

    test('log adds to LogInspector', () {
      final inspector = FlutterInspector(
        navigatorKey: GlobalKey<NavigatorState>(),
      );
      inspector.log('Test message', level: LogLevel.warning);

      final entries = inspector.registry.log.entries;
      expect(entries.length, 1);
      expect(entries.first.message, 'Test message');
      expect(entries.first.level, LogLevel.warning);
    });

    test('logNetwork adds to NetworkInspector', () {
      final inspector = FlutterInspector(
        navigatorKey: GlobalKey<NavigatorState>(),
      );
      inspector.logNetwork(NetworkEntry(method: 'GET', url: '/api'));

      final entries = inspector.registry.network.entries;
      expect(entries.length, 1);
      expect(entries.first.url, '/api');
    });

    test('database adds to DatabaseInspector', () {
      final inspector = FlutterInspector(
        navigatorKey: GlobalKey<NavigatorState>(),
      );
      inspector.database(DatabaseOperation.insert, 'users', affectedRows: 1);

      final entries = inspector.registry.database.entries;
      expect(entries.length, 1);
      expect(entries.first.tableName, 'users');
      expect(entries.first.affectedRows, 1);
    });

    test('provides a NavigatorObserver linked to its NavigatorInspector', () {
      final inspector = FlutterInspector(
        navigatorKey: GlobalKey<NavigatorState>(),
      );
      final observer = inspector.navigatorObserver;
      expect(observer, isNotNull);
    });

    test('redactSensitiveData defaults to true (secure by default)', () {
      final inspector = FlutterInspector(
        navigatorKey: GlobalKey<NavigatorState>(),
      );
      expect(inspector.redactSensitiveData, isTrue);
    });

    test('redactSensitiveData can be disabled explicitly', () {
      final inspector = FlutterInspector(
        navigatorKey: GlobalKey<NavigatorState>(),
        redactSensitiveData: false,
      );
      expect(inspector.redactSensitiveData, isFalse);
    });

    test('rejects negative slowRequestThreshold', () {
      expect(
        () => FlutterInspector(
          navigatorKey: GlobalKey<NavigatorState>(),
          slowRequestThreshold: const Duration(seconds: -1),
        ),
        throwsArgumentError,
      );
    });

    test('accepts zero and positive slowRequestThreshold', () {
      final inspectorZero = FlutterInspector(
        navigatorKey: GlobalKey<NavigatorState>(),
        slowRequestThreshold: Duration.zero,
      );
      expect(inspectorZero.slowRequestThreshold, Duration.zero);

      final inspectorPositive = FlutterInspector(
        navigatorKey: GlobalKey<NavigatorState>(),
        slowRequestThreshold: const Duration(seconds: 5),
      );
      expect(
        inspectorPositive.slowRequestThreshold,
        const Duration(seconds: 5),
      );
    });
  });

  group('Database Browser Sources API', () {
    test('default source is always first and named Operation log', () {
      final inspector = FlutterInspector(
        navigatorKey: GlobalKey<NavigatorState>(),
      );
      expect(inspector.databaseSources.length, 1);
      expect(inspector.databaseSources.first.name, 'Operation log');
    });

    test('constructor injects custom database sources', () {
      final source = FakeDatabaseBrowserSource();
      final inspector = FlutterInspector(
        navigatorKey: GlobalKey<NavigatorState>(),
        databaseSources: [source],
      );
      expect(inspector.databaseSources.length, 2);
      expect(inspector.databaseSources[0].name, 'Operation log');
      expect(inspector.databaseSources[1], source);
    });

    test('registerDatabaseSource registers custom source dynamically', () {
      final inspector = FlutterInspector(
        navigatorKey: GlobalKey<NavigatorState>(),
      );
      final source = FakeDatabaseBrowserSource();
      inspector.registerDatabaseSource(source);
      expect(inspector.databaseSources.length, 2);
      expect(inspector.databaseSources[1], source);
    });

    test('databaseSources returns an unmodifiable list', () {
      final inspector = FlutterInspector(
        navigatorKey: GlobalKey<NavigatorState>(),
      );
      final sources = inspector.databaseSources;
      expect(
        () => (sources as List).add(FakeDatabaseBrowserSource()),
        throwsUnsupportedError,
      );
    });

    test(
      'logs logged to database are visible via OperationLogSource',
      () async {
        final inspector = FlutterInspector(
          navigatorKey: GlobalKey<NavigatorState>(),
        );
        inspector.database(DatabaseOperation.insert, 'users');

        final opLogSource = inspector.databaseSources.first;
        final tables = await opLogSource.listTables();
        expect(tables.length, 1);
        expect(tables.first.name, 'users');
      },
    );
  });

  group('Diagnostic Info Source API', () {
    test('diagnosticInfoSource defaults to null', () {
      expect(
        FlutterInspector(
          navigatorKey: GlobalKey<NavigatorState>(),
          bufferSize: 10,
        ).diagnosticInfoSource,
        isNull,
      );
    });

    test('an injected source is retained and collectable', () async {
      final source = _FakeDiagnosticInfoSource();
      final inspector = FlutterInspector(
        navigatorKey: GlobalKey<NavigatorState>(),
        bufferSize: 10,
        diagnosticInfoSource: source,
      );

      expect(inspector.diagnosticInfoSource, same(source));
      expect(
        await inspector.diagnosticInfoSource!.collect(),
        const DiagnosticInfo(appVersion: '2.3.1+45', osVersion: 'iOS 17.4'),
      );
    });
  });
}

class FakeDatabaseBrowserSource extends DatabaseBrowserSource {
  @override
  String get name => 'FakeSource';

  @override
  Future<List<DatabaseTableInfo>> listTables() async => [];

  @override
  Future<DatabaseTablePage> fetchRows(
    String tableName, {
    int limit = 200,
    int offset = 0,
  }) async {
    return const DatabaseTablePage(columns: [], rows: []);
  }
}

class _FakeDiagnosticInfoSource implements DiagnosticInfoSource {
  @override
  Future<DiagnosticInfo> collect() async =>
      const DiagnosticInfo(appVersion: '2.3.1+45', osVersion: 'iOS 17.4');
}
