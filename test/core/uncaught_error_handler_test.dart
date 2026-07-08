import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_inspector_kit/src/core/uncaught_error_handler.dart';
import 'package:flutter_inspector_kit/src/models/log_level.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

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

  test('idempotent: attach twice only attaches hooks once', () {
    var callCount = 0;
    final handler = UncaughtErrorHandler(
      onLog: (message, {level = LogLevel.info, stackTrace, data}) {
        callCount++;
      },
    );
    
    FlutterError.onError = (_) {};

    handler.attach();
    handler.attach();

    FlutterError.onError!(buildDetails(StateError('boom')));
    expect(callCount, 1);
  });

  test('chain: existing handlers are called', () {
    var hostFlutterCalled = false;
    var hostPlatformCalled = false;
    var onLogCalledCount = 0;

    FlutterError.onError = (_) {
      hostFlutterCalled = true;
    };
    PlatformDispatcher.instance.onError = (e, s) {
      hostPlatformCalled = true;
      return true;
    };
    final originalBuilder = ErrorWidget.builder;

    final handler = UncaughtErrorHandler(
      onLog: (message, {level = LogLevel.info, stackTrace, data}) {
        onLogCalledCount++;
      },
    );
    handler.attach();

    FlutterError.onError!(buildDetails(StateError('boom')));
    expect(hostFlutterCalled, isTrue);

    PlatformDispatcher.instance.onError!(StateError('boom'), StackTrace.current);
    expect(hostPlatformCalled, isTrue);

    final widget = ErrorWidget.builder(buildDetails(StateError('boom')));
    expect(widget.runtimeType, originalBuilder(buildDetails(StateError('boom'))).runtimeType);

    expect(onLogCalledCount, 3);
  });

  test('guard: onLog throws, host handler is still called', () {
    var hostFlutterCalled = false;
    var hostPlatformCalled = false;

    FlutterError.onError = (_) {
      hostFlutterCalled = true;
    };
    PlatformDispatcher.instance.onError = (e, s) {
      hostPlatformCalled = true;
      return true;
    };
    final originalBuilder = ErrorWidget.builder;

    final handler = UncaughtErrorHandler(
      onLog: (message, {level = LogLevel.info, stackTrace, data}) {
        throw StateError('onLog failed');
      },
    );
    handler.attach();

    FlutterError.onError!(buildDetails(StateError('boom')));
    expect(hostFlutterCalled, isTrue);

    final handled = PlatformDispatcher.instance.onError!(
      StateError('boom'),
      StackTrace.current,
    );
    expect(hostPlatformCalled, isTrue);
    // onLog 丟例外時，host 回傳的 handled 語意不得被改變（重構核心不變式）。
    expect(handled, isTrue);

    final widget = ErrorWidget.builder(buildDetails(StateError('boom')));
    expect(widget.runtimeType, originalBuilder(buildDetails(StateError('boom'))).runtimeType);
  });
}
