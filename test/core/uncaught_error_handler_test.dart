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

  test('dedup: same FlutterErrorDetails logged once across both hooks', () {
    var callCount = 0;
    final handler = UncaughtErrorHandler(
      onLog: (message, {level = LogLevel.info, stackTrace, data}) {
        callCount++;
      },
    );
    handler.attach();

    // 同一次 build 崩潰：framework 建立單一 details，先觸發 FlutterError.onError，
    // 再把「同一物件」傳給 ErrorWidget.builder。應只記錄一筆。
    final details = buildDetails(StateError('boom'));
    FlutterError.onError!(details);
    ErrorWidget.builder(details);

    expect(callCount, 1);
  });

  test('no dedup: distinct FlutterErrorDetails are each logged', () {
    var callCount = 0;
    final handler = UncaughtErrorHandler(
      onLog: (message, {level = LogLevel.info, stackTrace, data}) {
        callCount++;
      },
    );
    handler.attach();

    // 兩次獨立崩潰 = 兩個不同的 details 物件（identical 為 false）→ 各自記錄。
    // 這也涵蓋「同一 bug 反覆崩潰不該被吞」的情境。
    FlutterError.onError!(buildDetails(StateError('a')));
    ErrorWidget.builder(buildDetails(StateError('b')));

    expect(callCount, 2);
  });
}
