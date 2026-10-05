import 'dart:async';

import 'package:example/bridges/logger_bridge.dart';
import 'package:example/bridges/logging_bridge.dart';
import 'package:example/bridges/talker_bridge.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_inspector_kit/flutter_inspector_kit.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:logger/logger.dart' as logger_pkg;
import 'package:logging/logging.dart' as logging_pkg;
import 'package:talker/talker.dart' as talker_pkg;

FlutterInspector _newInspector() =>
    FlutterInspector(navigatorKey: GlobalKey<NavigatorState>());

/// Levels of every log entry, oldest first (logEntries is newest first).
List<LogLevel> _levels(FlutterInspector inspector) =>
    inspector.logEntries.reversed.map((e) => e.level).toList();

/// Logs a marker right after a bridged record, then checks the record is
/// already on the timeline and stamped no later than the marker. An async
/// bridge (e.g. talker.stream) would not have delivered it yet.
void _expectNotAfterMarker(FlutterInspector inspector, String bridged) {
  inspector.log('marker');
  final logs = inspector.mergedTimeline().whereType<LogEntry>();
  final source = logs.singleWhere((e) => e.message == bridged);
  final marker = logs.singleWhere((e) => e.message == 'marker');
  expect(source.timestamp.isAfter(marker.timestamp), isFalse);
}

void main() {
  // AC 6, 7, 8, 9, 10, 13, 14
  group('logger bridge', () {
    late FlutterInspector inspector;
    late void Function(logger_pkg.OutputEvent) bridge;

    setUp(() {
      inspector = _newInspector();
      bridge = (event) => forwardLoggerEvent(inspector, event);
      logger_pkg.Logger.addOutputListener(bridge);
    });

    tearDown(() => logger_pkg.Logger.removeOutputListener(bridge));

    test('a multi-line PrettyPrinter event becomes one clean entry', () {
      final lines = logger_pkg.PrettyPrinter().log(
        logger_pkg.LogEvent(logger_pkg.Level.info, 'hello'),
      );
      expect(lines.length, greaterThan(1)); // premise: the printer boxes it

      logger_pkg.Logger().i('hello');

      // Equality also rules out ANSI escapes and box glyphs.
      expect(inspector.logEntries.map((e) => e.message), ['hello']);
    });

    test('maps every non-deprecated level by threshold', () {
      logger_pkg.Logger(level: logger_pkg.Level.trace)
        ..t('t')
        ..d('d')
        ..i('i')
        ..w('w')
        ..e('e')
        ..f('f');

      expect(_levels(inspector), [
        LogLevel.verbose,
        LogLevel.debug,
        LogLevel.info,
        LogLevel.warning,
        LogLevel.error,
        LogLevel.error,
      ]);
    });

    test('error joins the message, stack trace becomes a string', () {
      final error = StateError('boom');
      final stackTrace = StackTrace.current;

      logger_pkg.Logger()
        ..e('failed', error: error, stackTrace: stackTrace)
        ..i(() => 'lazy');

      final [lazy, failed] = inspector.logEntries;
      expect(failed.message, 'failed\n$error');
      expect(failed.stackTrace, stackTrace.toString());
      expect(lazy.message, 'lazy');
      expect(lazy.stackTrace, isNull);
    });

    test('records muted by the host level never reach the timeline', () {
      logger_pkg.Logger(level: logger_pkg.Level.warning)
        ..i('muted')
        ..w('kept');

      expect(inspector.logEntries.map((e) => e.message), ['kept']);
    });

    test('delivers synchronously', () {
      logger_pkg.Logger().i('bridged');
      _expectNotAfterMarker(inspector, 'bridged');
    });
  });

  // AC 8, 9, 10, 12, 13
  group('talker bridge', () {
    late FlutterInspector inspector;
    late talker_pkg.Talker talker;

    setUp(() {
      inspector = _newInspector();
      talker = talker_pkg.Talker(observer: InspectorTalkerObserver(inspector));
    });

    test('maps every level; a record without one falls back to debug', () {
      talker
        ..verbose('v')
        ..debug('d')
        ..info('i')
        ..warning('w')
        ..error('e')
        ..critical('c')
        ..logCustom(talker_pkg.TalkerLog('no level'));

      expect(_levels(inspector), [
        LogLevel.verbose,
        LogLevel.debug,
        LogLevel.info,
        LogLevel.warning,
        LogLevel.error,
        LogLevel.error,
        LogLevel.debug,
      ]);
    });

    test('handle() reaches onException and onError', () {
      final exception = Exception('offline');
      final error = StateError('bad state');
      final stackTrace = StackTrace.current;

      talker
        ..handle(exception, stackTrace)
        ..handle(error, null, 'while saving');

      final [fromError, fromException] = inspector.logEntries;
      expect(fromException.level, LogLevel.error);
      expect(fromException.message, '$exception');
      expect(fromException.stackTrace, stackTrace.toString());
      expect(fromError.level, LogLevel.error);
      expect(fromError.message, 'while saving\n$error');
    });

    test('message and exception are joined; no stack trace gives null', () {
      final exception = Exception('timeout');

      talker
        ..info('plain')
        ..error('request failed', exception);

      final [failed, plain] = inspector.logEntries;
      expect(plain.message, 'plain');
      expect(plain.stackTrace, isNull);
      expect(failed.message, 'request failed\n$exception');
    });

    test('delivers synchronously', () {
      talker.info('bridged');
      _expectNotAfterMarker(inspector, 'bridged');
    });
  });

  // AC 8, 9, 10, 11, 13
  group('logging bridge', () {
    late FlutterInspector inspector;
    late StreamSubscription<logging_pkg.LogRecord> subscription;

    setUp(() {
      inspector = _newInspector();
      logging_pkg.Logger.root.level = logging_pkg.Level.ALL;
      subscription = logging_pkg.Logger.root.onRecord.listen(
        (r) => forwardLogRecord(inspector, r),
      );
    });

    tearDown(() async {
      await subscription.cancel();
      logging_pkg.Logger.root.level = logging_pkg.defaultLevel;
    });

    test('maps every level by threshold', () {
      logging_pkg.Logger('Auth')
        ..finest('1')
        ..finer('2')
        ..fine('3')
        ..config('4')
        ..info('5')
        ..warning('6')
        ..severe('7')
        ..shout('8');

      expect(_levels(inspector), [
        LogLevel.verbose,
        LogLevel.verbose,
        LogLevel.debug,
        LogLevel.debug,
        LogLevel.info,
        LogLevel.warning,
        LogLevel.error,
        LogLevel.error,
      ]);
    });

    test('loggerName prefixes the message; the root logger adds none', () {
      logging_pkg.Logger('Auth').info('token expired');
      logging_pkg.Logger.root.info('root message');

      final [root, auth] = inspector.logEntries;
      expect(auth.message, '[Auth] token expired');
      expect(root.message, 'root message');
    });

    test('error joins the message, stack trace becomes a string', () {
      final error = StateError('denied');
      final stackTrace = StackTrace.current;

      logging_pkg.Logger('Auth')
        ..severe('login failed', error, stackTrace)
        ..info('plain');

      final [plain, failed] = inspector.logEntries;
      expect(failed.message, '[Auth] login failed\n$error');
      expect(failed.stackTrace, stackTrace.toString());
      expect(plain.stackTrace, isNull);
    });

    test('delivers synchronously', () {
      logging_pkg.Logger('Auth').info('bridged');
      _expectNotAfterMarker(inspector, '[Auth] bridged');
    });
  });
}
