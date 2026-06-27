import 'package:flutter_inspector_kit/src/core/flutter_inspector.dart';
import 'package:flutter_inspector_kit/src/core/inspector_registry.dart';
import 'package:flutter_inspector_kit/src/models/database_entry.dart';
import 'package:flutter_inspector_kit/src/models/database_operation.dart';
import 'package:flutter_inspector_kit/src/models/log_entry.dart';
import 'package:flutter_inspector_kit/src/models/navigator_action.dart';
import 'package:flutter_inspector_kit/src/models/navigator_entry.dart';
import 'package:flutter_inspector_kit/src/models/network_entry.dart';
import 'package:flutter_inspector_kit/src/models/timestamped_entry.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  // Fixed, staggered timestamps so ordering is deterministic.
  final tLog = DateTime(2026, 6, 26, 10, 0, 0); // oldest
  final tNav = DateTime(2026, 6, 26, 10, 0, 1);
  final tNetwork = DateTime(2026, 6, 26, 10, 0, 2);
  final tDb = DateTime(2026, 6, 26, 10, 0, 3); // newest

  /// Seeds one entry into each of the four buffers with the fixed timestamps.
  void seedAll(InspectorRegistry registry) {
    registry.log.add(LogEntry(message: 'log msg', timestamp: tLog));
    registry.network.add(
      NetworkEntry(method: 'GET', url: '/api', timestamp: tNetwork),
    );
    registry.navigator.add(
      NavigatorEntry(
        action: NavigatorAction.push,
        routeName: '/home',
        timestamp: tNav,
      ),
    );
    registry.database.add(
      DatabaseEntry(
        operation: DatabaseOperation.insert,
        tableName: 'users',
        timestamp: tDb,
      ),
    );
  }

  group('InspectorRegistry.mergedTimeline', () {
    test('default returns all four entries sorted by timestamp descending', () {
      final inspector = FlutterInspector();
      seedAll(inspector.registry);

      final result = inspector.registry.mergedTimeline();

      expect(result.length, 4);
      expect(result[0].timestamp, tDb); // newest first
      expect(result[1].timestamp, tNetwork);
      expect(result[2].timestamp, tNav);
      expect(result[3].timestamp, tLog); // oldest last
    });

    test('single source {network} returns only the network entry', () {
      final inspector = FlutterInspector();
      seedAll(inspector.registry);

      final result = inspector.registry.mergedTimeline(
        sources: {TimelineSource.network},
      );

      expect(result.length, 1);
      expect(result.single, isA<NetworkEntry>());
      expect(result.single.timestamp, tNetwork);
    });

    test('sources {log, nav} returns two entries, still descending', () {
      final inspector = FlutterInspector();
      seedAll(inspector.registry);

      final result = inspector.registry.mergedTimeline(
        sources: {TimelineSource.log, TimelineSource.nav},
      );

      expect(result.length, 2);
      expect(result[0].timestamp, tNav); // nav (10:00:01) before log (10:00:00)
      expect(result[1].timestamp, tLog);
      expect(result[0], isA<NavigatorEntry>());
      expect(result[1], isA<LogEntry>());
    });

    test('empty buffers return an empty list', () {
      final inspector = FlutterInspector();

      expect(inspector.registry.mergedTimeline(), isEmpty);
    });
  });

  group('FlutterInspector.mergedTimeline thin forward', () {
    test('default returns all four entries sorted descending', () {
      final inspector = FlutterInspector();
      seedAll(inspector.registry);

      final result = inspector.mergedTimeline();

      expect(result.length, 4);
      expect(result[0].timestamp, tDb);
      expect(result[3].timestamp, tLog);
    });

    test('single source {network} returns only the network entry', () {
      final inspector = FlutterInspector();
      seedAll(inspector.registry);

      final result = inspector.mergedTimeline(
        sources: {TimelineSource.network},
      );

      expect(result.length, 1);
      expect(result.single, isA<NetworkEntry>());
    });

    test('empty buffers return an empty list', () {
      final inspector = FlutterInspector();

      expect(inspector.mergedTimeline(), isEmpty);
    });

    test('forward is equivalent to registry.mergedTimeline (default)', () {
      final inspector = FlutterInspector();
      seedAll(inspector.registry);

      final viaInspector = inspector.mergedTimeline();
      final viaRegistry = inspector.registry.mergedTimeline();

      expect(viaInspector, equals(viaRegistry));
      // Same identity-order entries (thin forward returns the same pointers).
      for (var i = 0; i < viaInspector.length; i++) {
        expect(identical(viaInspector[i], viaRegistry[i]), isTrue);
      }
    });
  });
}
