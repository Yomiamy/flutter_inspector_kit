import 'package:flutter_inspector_kit/src/models/database_operation.dart';
import 'package:flutter_inspector_kit/src/models/database_entry.dart';
import 'package:flutter_inspector_kit/src/models/log_entry.dart';
import 'package:flutter_inspector_kit/src/models/log_level.dart';
import 'package:flutter_inspector_kit/src/models/navigator_action.dart';
import 'package:flutter_inspector_kit/src/models/navigator_entry.dart';
import 'package:flutter_inspector_kit/src/models/network_entry.dart';
import 'package:flutter_inspector_kit/src/models/timestamped_entry.dart';
import 'package:flutter_inspector_kit/src/utils/agent_prompt.dart';
import 'package:flutter_test/flutter_test.dart';

class _Data {
  static const String route = '/checkout';
  static const String otherRoute = '/basket';
  static final DateTime t0 = DateTime(2026, 9, 12, 14, 30, 0);

  /// A timestamp [seconds] after [t0], for building ordered fixtures.
  static DateTime at(int seconds) => t0.add(Duration(seconds: seconds));

  static LogEntry error({String route = _Data.route, String? stack}) =>
      LogEntry(
        level: LogLevel.error,
        message: 'Failed to load cart',
        timestamp: at(10),
        activeRoute: route,
        stackTrace: stack,
      );

  static const String rawStack = '''
#0      CartController._load (package:my_app/cart_controller.dart:88:7)
#1      StatefulElement.build (package:flutter/src/widgets/framework.dart:1:1)
#2      _rootRun (dart:async/zone.dart:1:1)
#3      _CustomZone.run (dart:async/zone.dart:2:2)
#4      Future._propagateToListeners (dart:async/future_impl.dart:3:3)
#5      ApiClient.get (package:my_app/api_client.dart:142:3)''';
}

/// Newest-first, matching `mergedTimeline()`'s ordering contract.
List<TimestampedEntry> _timeline(List<TimestampedEntry> entries) =>
    entries.toList()..sort((a, b) => b.timestamp.compareTo(a.timestamp));

void main() {
  group('buildAgentPrompt — invariants', () {
    test('boundary notice is always present', () {
      final prompt = buildAgentPrompt(_Data.error(), timeline: const []);
      expect(prompt, contains('not a static-analysis conclusion'));
      expect(prompt, contains('Do not assume the failing line is the faulty'));
    });

    test('closing task is fixed and present', () {
      final prompt = buildAgentPrompt(_Data.error(), timeline: const []);
      expect(
        prompt,
        contains('Investigate the cause in this codebase and propose a fix.'),
      );
    });

    test('omits the Where section entirely when no stack trace exists', () {
      final prompt = buildAgentPrompt(_Data.error(), timeline: const []);
      expect(prompt, isNot(contains('### Where')));
      expect(prompt, isNot(contains('(none)')));
    });

    test('includes normalized stack trace when one exists', () {
      final prompt = buildAgentPrompt(
        _Data.error(stack: _Data.rawStack),
        timeline: const [],
      );
      expect(prompt, contains('### Where'));
      expect(prompt, contains('CartController._load'));
      // Framework frames collapse rather than being listed one by one.
      expect(prompt, contains('frames of framework internals'));
    });

    test('states no cause of its own', () {
      final prompt = buildAgentPrompt(
        _Data.error(stack: _Data.rawStack),
        timeline: const [],
      );
      for (final hedge in ['likely caused', 'probably', 'suggests that']) {
        expect(prompt.toLowerCase(), isNot(contains(hedge)));
      }
    });
  });

  group('buildAgentPrompt — redaction', () {
    NetworkEntry failing({Map<String, dynamic>? headers}) => NetworkEntry(
      method: 'POST',
      url: 'https://api.example.com/orders',
      statusCode: 500,
      timestamp: _Data.at(10),
      activeRoute: _Data.route,
      isComplete: true,
      requestHeaders: headers,
    );

    test('masks sensitive headers by default', () {
      final prompt = buildAgentPrompt(
        failing(headers: {'authorization': 'Bearer secret-token'}),
        timeline: const [],
      );
      expect(prompt, isNot(contains('secret-token')));
      expect(prompt, contains('authorization'));
    });

    test('leaves headers intact when redaction is off', () {
      final prompt = buildAgentPrompt(
        failing(headers: {'authorization': 'Bearer secret-token'}),
        timeline: const [],
        redact: false,
      );
      expect(prompt, contains('secret-token'));
    });
  });

  group('buildAgentPrompt — trace-back exits', () {
    test('exit 1: stops at the route entry point without disclosure', () {
      final timeline = _timeline([
        NavigatorEntry(
          action: NavigatorAction.push,
          routeName: '/checkout',
          timestamp: _Data.at(1),
        ),
        LogEntry(
          level: LogLevel.info,
          message: 'Cart cache miss',
          timestamp: _Data.at(5),
          activeRoute: _Data.route,
        ),
        _Data.error(),
      ]);

      final prompt = buildAgentPrompt(_Data.error(), timeline: timeline);
      expect(prompt, contains('Cart cache miss'));
      expect(prompt, contains('[NAV] push'));
      expect(prompt, isNot(contains('showing the')));
      expect(prompt, isNot(contains('no route entry point')));
    });

    test('exit 1: `replace` counts as an entry point', () {
      final timeline = _timeline([
        NavigatorEntry(
          action: NavigatorAction.replace,
          routeName: '/checkout',
          timestamp: _Data.at(1),
        ),
        LogEntry(
          level: LogLevel.info,
          message: 'after replace',
          timestamp: _Data.at(5),
          activeRoute: _Data.route,
        ),
        LogEntry(
          level: LogLevel.info,
          message: 'before replace',
          timestamp: _Data.at(0),
          activeRoute: _Data.route,
        ),
      ]);

      final prompt = buildAgentPrompt(_Data.error(), timeline: timeline);
      expect(prompt, contains('after replace'));
      expect(prompt, contains('[NAV] replace'));
      expect(prompt, isNot(contains('before replace')));
      expect(prompt, isNot(contains('no route entry point')));
    });

    test('exit 2: discloses truncation with the true total', () {
      // 9 events, all before the anchor at t+10, with no entry point among
      // them — the cap of 5 is what stops the walk.
      final noise = List.generate(
        9,
        (i) => LogEntry(
          level: LogLevel.debug,
          message: 'noise $i',
          timestamp: _Data.at(i),
          activeRoute: _Data.route,
        ),
      );
      final prompt = buildAgentPrompt(
        _Data.error(),
        timeline: _timeline(noise),
        maxTraceBackEntries: 5,
      );
      expect(prompt, contains('showing the 5 most recent of 9 events'));
    });

    test('exit 2: discloses a cap that lands on the last candidate', () {
      // The cap is exactly the candidate count, so the walk stops without ever
      // examining whether an entry point sat just beyond it. Reporting "all N"
      // here would claim a completeness that was never checked.
      final noise = List.generate(
        5,
        (i) => LogEntry(
          level: LogLevel.debug,
          message: 'noise $i',
          timestamp: _Data.at(i),
          activeRoute: _Data.route,
        ),
      );

      final prompt = buildAgentPrompt(
        _Data.error(),
        timeline: _timeline(noise),
        maxTraceBackEntries: 5,
      );
      expect(prompt, contains('showing the 5 most recent of 5 events'));
      expect(prompt, isNot(contains('showing all')));
    });

    test('exit 3: discloses a missing entry point', () {
      final timeline = _timeline([
        LogEntry(
          level: LogLevel.info,
          message: 'orphan event',
          timestamp: _Data.at(5),
          activeRoute: _Data.route,
        ),
      ]);

      final prompt = buildAgentPrompt(_Data.error(), timeline: timeline);
      expect(prompt, contains('no route entry point in buffer'));
      expect(prompt, contains('orphan event'));
    });

    test('stops at the most recent entry point, not an earlier visit', () {
      final timeline = _timeline([
        NavigatorEntry(
          action: NavigatorAction.push,
          routeName: '/checkout',
          timestamp: _Data.at(0),
        ),
        LogEntry(
          level: LogLevel.info,
          message: 'first visit event',
          timestamp: _Data.at(1),
          activeRoute: _Data.route,
        ),
        NavigatorEntry(
          action: NavigatorAction.push,
          routeName: '/checkout',
          timestamp: _Data.at(6),
        ),
        LogEntry(
          level: LogLevel.info,
          message: 'second visit event',
          timestamp: _Data.at(7),
          activeRoute: _Data.route,
        ),
      ]);

      final prompt = buildAgentPrompt(_Data.error(), timeline: timeline);
      expect(prompt, contains('second visit event'));
      expect(prompt, isNot(contains('first visit event')));
    });
  });

  group('buildAgentPrompt — trace-back filtering', () {
    test('excludes events from other routes', () {
      final timeline = _timeline([
        LogEntry(
          level: LogLevel.info,
          message: 'on another page',
          timestamp: _Data.at(5),
          activeRoute: _Data.otherRoute,
        ),
        LogEntry(
          level: LogLevel.info,
          message: 'on this page',
          timestamp: _Data.at(5),
          activeRoute: _Data.route,
        ),
      ]);

      final prompt = buildAgentPrompt(_Data.error(), timeline: timeline);
      expect(prompt, contains('on this page'));
      expect(prompt, isNot(contains('on another page')));
    });

    test('excludes events that follow the anchor', () {
      final timeline = _timeline([
        LogEntry(
          level: LogLevel.info,
          message: 'before the error',
          timestamp: _Data.at(5),
          activeRoute: _Data.route,
        ),
        LogEntry(
          level: LogLevel.info,
          message: 'after the error',
          timestamp: _Data.at(20),
          activeRoute: _Data.route,
        ),
      ]);

      final prompt = buildAgentPrompt(_Data.error(), timeline: timeline);
      expect(prompt, contains('before the error'));
      expect(prompt, isNot(contains('after the error')));
    });

    test('trace-back lines drop the per-line Active Route suffix', () {
      final timeline = _timeline([
        LogEntry(
          level: LogLevel.info,
          message: 'earlier event',
          timestamp: _Data.at(5),
          activeRoute: _Data.route,
        ),
      ]);

      final prompt = buildAgentPrompt(_Data.error(), timeline: timeline);
      expect(prompt, contains('earlier event'));
      expect(prompt, isNot(contains('(Active Route: ')));
      // The route is still named once, in the section heading.
      expect(prompt, contains('### Earlier on this route (${_Data.route})'));
    });

    test('includes database events on the same route', () {
      final timeline = _timeline([
        NavigatorEntry(
          action: NavigatorAction.push,
          routeName: '/checkout',
          timestamp: _Data.at(1),
        ),
        DatabaseEntry(
          operation: DatabaseOperation.query,
          tableName: 'cart_items',
          affectedRows: 12,
          timestamp: _Data.at(5),
          activeRoute: _Data.route,
        ),
      ]);

      final prompt = buildAgentPrompt(_Data.error(), timeline: timeline);
      expect(prompt, contains('[DB]'));
      expect(prompt, contains('cart_items'));
      expect(prompt, contains('12 rows'));
    });
  });

  group('buildAgentPrompt — anchor types', () {
    test('network anchor renders status, bodies and route', () {
      final entry = NetworkEntry(
        method: 'POST',
        url: 'https://api.example.com/orders',
        statusCode: 500,
        timestamp: _Data.at(10),
        activeRoute: _Data.route,
        isComplete: true,
        responseBody: '{"error":"coupon_expired"}',
      );

      final prompt = buildAgentPrompt(entry, timeline: const []);
      expect(prompt, contains('POST'));
      expect(prompt, contains('500'));
      expect(prompt, contains('coupon_expired'));
      expect(prompt, contains('Active Route: ${_Data.route}'));
    });

    test('log anchor renders its structured data', () {
      final entry = LogEntry(
        level: LogLevel.error,
        message: 'Failed to load cart',
        timestamp: _Data.at(10),
        activeRoute: _Data.route,
        data: const {'cartId': 8842},
      );

      final prompt = buildAgentPrompt(entry, timeline: const []);
      expect(prompt, contains('Data:'));
      expect(prompt, contains('cartId: 8842'));
    });

    test('anchor without a route omits the trace-back section', () {
      final entry = LogEntry(
        level: LogLevel.error,
        message: 'no route yet',
        timestamp: _Data.at(10),
      );

      final prompt = buildAgentPrompt(entry, timeline: const []);
      expect(prompt, isNot(contains('### Earlier on this route')));
      expect(prompt, contains('### Task'));
    });
  });
}
