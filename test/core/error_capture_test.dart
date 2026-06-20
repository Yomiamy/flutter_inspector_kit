import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_inspector_kit/src/core/flutter_inspector.dart';
import 'package:flutter_inspector_kit/src/models/log_level.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // The three error hooks are process-global state. Save them before each test
  // and restore them after, so attaching/replacing in one test never pollutes
  // the next one.
  late FlutterExceptionHandler? savedFlutterOnError;
  late ErrorCallback? savedPlatformOnError;
  late Widget Function(FlutterErrorDetails) savedErrorWidgetBuilder;

  setUp(() {
    savedFlutterOnError = FlutterError.onError;
    savedPlatformOnError = PlatformDispatcher.instance.onError;
    savedErrorWidgetBuilder = ErrorWidget.builder;
  });

  tearDown(() {
    FlutterError.onError = savedFlutterOnError;
    PlatformDispatcher.instance.onError = savedPlatformOnError;
    ErrorWidget.builder = savedErrorWidgetBuilder;
  });

  FlutterErrorDetails buildDetails(Object exception) {
    return FlutterErrorDetails(
      exception: exception,
      stack: StackTrace.current,
      library: 'test library',
      context: ErrorDescription('while testing'),
    );
  }

  group('default off (Never break userspace)', () {
    test('captureUncaughtErrors:false does not touch any hook', () {
      final beforeFlutter = FlutterError.onError;
      final beforePlatform = PlatformDispatcher.instance.onError;
      final beforeWidget = ErrorWidget.builder;

      FlutterInspector();

      expect(FlutterError.onError, same(beforeFlutter));
      expect(PlatformDispatcher.instance.onError, same(beforePlatform));
      expect(ErrorWidget.builder, same(beforeWidget));
    });

    test('captureUncaughtErrors:true replaces all three hooks', () {
      final beforeFlutter = FlutterError.onError;
      final beforePlatform = PlatformDispatcher.instance.onError;
      final beforeWidget = ErrorWidget.builder;

      FlutterInspector(captureUncaughtErrors: true);

      expect(FlutterError.onError, isNot(same(beforeFlutter)));
      expect(PlatformDispatcher.instance.onError, isNot(same(beforePlatform)));
      expect(ErrorWidget.builder, isNot(same(beforeWidget)));
    });
  });

  group('FlutterError.onError capture + chain', () {
    test('captures details as a LogLevel.error entry with stackTrace', () {
      // Host handler set to a no-op so the default test binding does not
      // re-report the error as test noise.
      FlutterError.onError = (_) {};
      final inspector = FlutterInspector(captureUncaughtErrors: true);

      FlutterError.onError!(buildDetails(StateError('build boom')));

      final errors =
          inspector.logEntries.where((e) => e.level == LogLevel.error).toList();
      expect(errors, hasLength(1));
      expect(errors.first.message, contains('build boom'));
      expect(errors.first.stackTrace, isNotNull);
      expect(errors.first.data?['source'], 'flutterError');
      // The detail view relies on these being populated.
      expect(errors.first.data?['exceptionType'], 'StateError');
      expect(errors.first.data?['library'], 'test library');
    });

    test('chains the existing host handler (error forwarded downstream)', () {
      var hostCalled = false;
      FlutterError.onError = (_) => hostCalled = true;

      final inspector = FlutterInspector(captureUncaughtErrors: true);
      FlutterError.onError!(buildDetails(StateError('boom')));

      expect(hostCalled, isTrue);
      expect(
        inspector.logEntries.where((e) => e.level == LogLevel.error),
        hasLength(1),
      );
    });
  });

  group('PlatformDispatcher.onError return semantics', () {
    test('host return true is preserved AND the host handler is invoked', () {
      // Flip a flag in the host handler so we assert the chain side effect,
      // not just a return value that happens to coincide.
      var hostCalled = false;
      PlatformDispatcher.instance.onError = (error, stack) {
        hostCalled = true;
        return true;
      };
      final inspector = FlutterInspector(captureUncaughtErrors: true);

      final handled = PlatformDispatcher.instance.onError!(
        StateError('async boom'),
        StackTrace.current,
      );

      expect(handled, isTrue);
      expect(hostCalled, isTrue);
      final errors =
          inspector.logEntries.where((e) => e.level == LogLevel.error).toList();
      expect(errors, hasLength(1));
      expect(errors.first.data?['source'], 'platformDispatcher');
    });

    test('host return false is preserved (never upgrades to handled)', () {
      // The most regression-prone path: a careless change to `return true`
      // would silently swallow an error the host explicitly left unhandled.
      var hostCalled = false;
      PlatformDispatcher.instance.onError = (error, stack) {
        hostCalled = true;
        return false;
      };
      final inspector = FlutterInspector(captureUncaughtErrors: true);

      final handled = PlatformDispatcher.instance.onError!(
        StateError('async boom'),
        StackTrace.current,
      );

      expect(handled, isFalse);
      expect(hostCalled, isTrue);
      expect(
        inspector.logEntries.where((e) => e.level == LogLevel.error),
        hasLength(1),
      );
    });

    test('returns false when host has no handler (never swallows)', () {
      PlatformDispatcher.instance.onError = null;
      FlutterInspector(captureUncaughtErrors: true);

      final handled = PlatformDispatcher.instance.onError!(
        StateError('async boom'),
        StackTrace.current,
      );

      expect(handled, isFalse);
    });
  });

  group('ErrorWidget.builder wrap', () {
    test('logs then delegates to original builder', () {
      final originalBuilder = ErrorWidget.builder;
      final inspector = FlutterInspector(captureUncaughtErrors: true);

      final details = buildDetails(StateError('widget boom'));
      final widget = ErrorWidget.builder(details);

      // Original builder still produced the placeholder widget.
      expect(widget, isA<Widget>());
      expect(widget.runtimeType, originalBuilder(details).runtimeType);

      final errors =
          inspector.logEntries.where((e) => e.level == LogLevel.error).toList();
      expect(errors, hasLength(1));
      expect(errors.first.data?['source'], 'errorWidget');
    });
  });

  group('dedup flag', () {
    test('calling setupErrorHandlers twice attaches hooks only once', () {
      FlutterError.onError = (_) {};
      final inspector = FlutterInspector(captureUncaughtErrors: true);
      // Second explicit call must be a no-op.
      inspector.setupErrorHandlers();

      FlutterError.onError!(buildDetails(StateError('boom')));

      expect(
        inspector.logEntries.where((e) => e.level == LogLevel.error),
        hasLength(1),
      );
    });
  });

  group('dedup (T2)', () {
    test(
        'captureUncaughtErrors:true then a manual setupErrorHandlers attaches '
        'hooks once', () {
      FlutterError.onError = (_) {};
      final inspector = FlutterInspector(captureUncaughtErrors: true);

      // A second setupErrorHandlers call must be a no-op; the flag must prevent
      // re-attaching the hooks.
      inspector.setupErrorHandlers();

      FlutterError.onError!(buildDetails(StateError('boom')));

      // A single FlutterError trigger yields exactly one log (hooks not doubled).
      expect(
        inspector.logEntries.where((e) => e.level == LogLevel.error),
        hasLength(1),
      );
    });
  });
}
