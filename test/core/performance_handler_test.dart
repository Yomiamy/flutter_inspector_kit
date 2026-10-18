import 'dart:ui' show FrameTiming;

import 'package:flutter_inspector_kit/src/core/performance_handler.dart';
import 'package:flutter_inspector_kit/src/models/log_level.dart';
import 'package:flutter_test/flutter_test.dart';

FrameTiming createTiming({
  int vsyncStart = 0,
  int buildStart = 50000,
  int buildFinish = 200000,
  int rasterStart = 200000,
  int rasterFinish = 800000, // 800ms totalSpan
  int rasterFinishWallTime = 1600000000000000,
}) {
  return FrameTiming(
    vsyncStart: vsyncStart,
    buildStart: buildStart,
    buildFinish: buildFinish,
    rasterStart: rasterStart,
    rasterFinish: rasterFinish,
    rasterFinishWallTime: rasterFinishWallTime,
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  PerformanceHandler? handler;

  tearDown(() {
    handler?.detach();
    handler = null;
  });

  group('PerformanceHandler', () {
    test('rejects threshold <= Duration.zero', () {
      expect(
        () => PerformanceHandler(
          onLog:
              (
                _, {
                level = LogLevel.info,
                stackTrace,
                data,
                timestamp,
                activeRoute,
              }) {},
          threshold: Duration.zero,
        ),
        throwsArgumentError,
      );
      expect(
        () => PerformanceHandler(
          onLog:
              (
                _, {
                level = LogLevel.info,
                stackTrace,
                data,
                timestamp,
                activeRoute,
              }) {},
          threshold: const Duration(milliseconds: -1),
        ),
        throwsArgumentError,
      );
    });

    test('normal frames under threshold do not produce logs', () {
      var logged = false;
      handler = PerformanceHandler(
        onLog:
            (
              _, {
              level = LogLevel.info,
              stackTrace,
              data,
              timestamp,
              activeRoute,
            }) {
              logged = true;
            },
      );

      // 699ms frame
      handler!.handleTimings([
        createTiming(vsyncStart: 0, rasterFinish: 699000),
      ]);
      handler!.detach();

      expect(logged, isFalse);
    });

    test('single frozen frame is logged with correct data and page suffix', () {
      String? loggedMessage;
      LogLevel? loggedLevel;
      Map<String, dynamic>? loggedData;
      DateTime? loggedTimestamp;
      String? loggedActiveRoute;

      handler = PerformanceHandler(
        onLog:
            (
              message, {
              level = LogLevel.info,
              stackTrace,
              data,
              timestamp,
              activeRoute,
            }) {
              loggedMessage = message;
              loggedLevel = level;
              loggedData = data;
              loggedTimestamp = timestamp;
              loggedActiveRoute = activeRoute;
            },
        topPageLabel: () => 'ProfilePage (/profile)',
        threshold: const Duration(milliseconds: 700),
      );

      final timing = createTiming(
        vsyncStart: 0,
        buildStart: 50000, // 50ms vsync overhead
        buildFinish: 200000, // 150ms build
        rasterStart: 250000,
        rasterFinish: 850000, // 600ms raster, 850ms totalSpan
        rasterFinishWallTime: 1700000000000000,
      );

      // Frozen frame followed by a normal frame to end the streak
      handler!.handleTimings([
        timing,
        createTiming(vsyncStart: 851000, rasterFinish: 860000), // 9ms
      ]);

      expect(loggedLevel, LogLevel.warning);
      expect(loggedMessage, 'Frozen frame (850ms) · ProfilePage (/profile)');
      expect(loggedActiveRoute, 'ProfilePage (/profile)');
      expect(loggedData, {
        'totalSpanMs': 850,
        'vsyncOverheadMs': 50,
        'buildDurationMs': 150,
        'rasterDurationMs': 600,
      });
      expect(
        loggedTimestamp,
        DateTime.fromMicrosecondsSinceEpoch(1700000000000000),
      );
    });

    test('omits page suffix when topPageLabel is empty or null', () {
      String? loggedMessage;
      handler = PerformanceHandler(
        onLog:
            (
              message, {
              level = LogLevel.info,
              stackTrace,
              data,
              timestamp,
              activeRoute,
            }) {
              loggedMessage = message;
            },
        topPageLabel: () => '',
      );

      handler!.handleTimings([
        createTiming(rasterFinish: 750000),
        createTiming(rasterFinish: 10000),
      ]);

      expect(loggedMessage, 'Frozen frame (750ms)');
    });

    test('captures topPageLabel at streak start rather than flush time', () {
      var currentPage = 'PageA (/a)';
      String? loggedMessage;
      String? loggedActiveRoute;

      handler = PerformanceHandler(
        onLog:
            (
              message, {
              level = LogLevel.info,
              stackTrace,
              data,
              timestamp,
              activeRoute,
            }) {
              loggedMessage = message;
              loggedActiveRoute = activeRoute;
            },
        topPageLabel: () => currentPage,
      );

      // Freeze occurs on PageA
      handler!.handleTimings([
        createTiming(vsyncStart: 0, rasterFinish: 800000),
      ]);

      // Navigation happens before the next normal frame flushes the streak
      currentPage = 'PageB (/b)';
      handler!.handleTimings([
        createTiming(vsyncStart: 801000, rasterFinish: 810000),
      ]);

      expect(loggedMessage, 'Frozen frame (800ms) · PageA (/a)');
      expect(loggedActiveRoute, 'PageA (/a)');
    });

    test('consecutive frozen frames are merged into a single streak event', () {
      final messages = <String>[];
      final dataList = <Map<String, dynamic>?>[];

      handler = PerformanceHandler(
        onLog:
            (
              message, {
              level = LogLevel.info,
              stackTrace,
              data,
              timestamp,
              activeRoute,
            }) {
              messages.add(message);
              dataList.add(data);
            },
        threshold: const Duration(milliseconds: 700),
      );

      // Frame 1: 800ms (0 to 800,000)
      // Frame 2: 750ms (801,000 to 1,551,000)
      // Frame 3: 900ms (1,552,000 to 2,452,000)
      // Normal Frame 4: 16ms (2,453,000 to 2,469,000)
      handler!.handleTimings([
        createTiming(
          vsyncStart: 0,
          buildStart: 10000,
          buildFinish: 100000,
          rasterStart: 100000,
          rasterFinish: 800000,
        ),
        createTiming(
          vsyncStart: 801000,
          buildStart: 810000,
          buildFinish: 900000,
          rasterStart: 900000,
          rasterFinish: 1551000,
        ),
        createTiming(
          vsyncStart: 1552000,
          buildStart: 1560000,
          buildFinish: 1700000,
          rasterStart: 1700000,
          rasterFinish: 2452000,
        ),
        createTiming(
          vsyncStart: 2453000,
          buildStart: 2454000,
          buildFinish: 2460000,
          rasterStart: 2460000,
          rasterFinish: 2469000,
        ),
      ]);

      expect(messages.length, 1);
      expect(messages.first, 'Frozen frame (2450ms, 3 frames)');
      expect(dataList.first?['frameCount'], 3);
      expect(dataList.first?['totalSpanMs'], 2450);
    });

    test('non-consecutive frozen frames (large gap) are logged separately', () {
      final messages = <String>[];

      handler = PerformanceHandler(
        onLog:
            (
              message, {
              level = LogLevel.info,
              stackTrace,
              data,
              timestamp,
              activeRoute,
            }) {
              messages.add(message);
            },
        threshold: const Duration(milliseconds: 700),
      );

      // Frame 1: 800ms
      // Gap: 500ms (> 300ms gap)
      // Frame 2: 750ms
      // Normal frame
      handler!.handleTimings([
        createTiming(vsyncStart: 0, rasterFinish: 800000),
        createTiming(vsyncStart: 1300000, rasterFinish: 2050000),
        createTiming(vsyncStart: 2051000, rasterFinish: 2060000),
      ]);

      expect(messages.length, 2);
      expect(messages[0], 'Frozen frame (800ms)');
      expect(messages[1], 'Frozen frame (750ms)');
    });

    test('detach() flushes any unflushed frozen frame streak', () {
      String? loggedMessage;
      handler = PerformanceHandler(
        onLog:
            (
              message, {
              level = LogLevel.info,
              stackTrace,
              data,
              timestamp,
              activeRoute,
            }) {
              loggedMessage = message;
            },
      );

      handler!.handleTimings([createTiming(rasterFinish: 900000)]);
      expect(loggedMessage, isNull);

      handler!.detach();
      expect(loggedMessage, 'Frozen frame (900ms)');
    });

    test('markSelfInducedReassemble() ignores the self-induced frame', () {
      final messages = <String>[];
      handler = PerformanceHandler(
        onLog:
            (
              message, {
              level = LogLevel.info,
              stackTrace,
              data,
              timestamp,
              activeRoute,
            }) {
              messages.add(message);
            },
      );

      handler!.markSelfInducedReassemble();
      handler!.handleTimings([
        createTiming(vsyncStart: 0, rasterFinish: 10000), // normal pre-frame
        createTiming(
          vsyncStart: 11000,
          rasterFinish: 1211000,
        ), // 1.2s freeze during reassemble
        createTiming(
          vsyncStart: 1212000,
          rasterFinish: 1222000,
        ), // normal frame
      ]);

      expect(messages, isEmpty);

      // Subsequent genuine frozen frame is logged normally
      handler!.handleTimings([
        createTiming(vsyncStart: 2000000, rasterFinish: 2850000), // 850ms
        createTiming(vsyncStart: 2851000, rasterFinish: 2861000), // normal
      ]);
      handler!.detach();

      expect(messages, ['Frozen frame (850ms)']);
    });

    test('falls back to clock when wall-time is zero or negative', () {
      final fixedTime = DateTime(2026, 10, 17, 12, 0, 0);
      DateTime? capturedTimestamp;

      handler = PerformanceHandler(
        onLog:
            (
              _, {
              level = LogLevel.info,
              stackTrace,
              data,
              timestamp,
              activeRoute,
            }) {
              capturedTimestamp = timestamp;
            },
        clock: () => fixedTime,
      );

      handler!.handleTimings([
        createTiming(rasterFinish: 800000, rasterFinishWallTime: 0),
        createTiming(rasterFinish: 10000),
      ]);

      expect(capturedTimestamp, fixedTime);
    });

    test('attach() and detach() can be called safely and idempotently', () {
      handler = PerformanceHandler(
        onLog:
            (
              _, {
              level = LogLevel.info,
              stackTrace,
              data,
              timestamp,
              activeRoute,
            }) {},
      );

      handler!.attach();
      handler!.attach(); // idempotent
      handler!.detach();
      handler!.detach(); // safe
    });
  });
}
