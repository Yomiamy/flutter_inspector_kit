import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_inspector_kit/src/core/uncaught_error_handler.dart';
import 'package:flutter_inspector_kit/src/models/log_level.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('parseRenderFlexOverflow', () {
    test('extracts overflow pixels and direction correctly', () {
      const message = 'A RenderFlex overflowed by 24.0 pixels on the bottom.';
      final result = parseRenderFlexOverflow(message);

      expect(result, isNotNull);
      expect(result!['isRenderFlexOverflow'], isTrue);
      expect(result['overflowPixels'], 24.0);
      expect(result['overflowDirection'], 'bottom');
    });

    test('extracts integer overflow pixels and right direction', () {
      const message = 'A RenderFlex overflowed by 112 pixels on the right.';
      final result = parseRenderFlexOverflow(message);

      expect(result, isNotNull);
      expect(result!['isRenderFlexOverflow'], isTrue);
      expect(result['overflowPixels'], 112.0);
      expect(result['overflowDirection'], 'right');
    });

    test('case-insensitive match', () {
      const message = 'a renderflex overflowed by 15.5 pixels on the top';
      final result = parseRenderFlexOverflow(message);

      expect(result, isNotNull);
      expect(result!['isRenderFlexOverflow'], isTrue);
      expect(result['overflowPixels'], 15.5);
      expect(result['overflowDirection'], 'top');
    });

    test('extracts scientific notation overflow pixels correctly', () {
      const message =
          'A RenderFlex overflowed by 1.00e-7 pixels on the bottom.';
      final result = parseRenderFlexOverflow(message);

      expect(result, isNotNull);
      expect(result!['isRenderFlexOverflow'], isTrue);
      expect(result['overflowPixels'], 1.00e-7);
      expect(result['overflowDirection'], 'bottom');
    });

    test('returns null for unrelated errors', () {
      expect(
        parseRenderFlexOverflow('FormatException: Unexpected character'),
        isNull,
      );
      expect(
        parseRenderFlexOverflow('RangeError (index): Invalid value'),
        isNull,
      );
    });

    test('returns null for malformed numbers', () {
      expect(
        parseRenderFlexOverflow(
          'A RenderFlex overflowed by ABC pixels on the bottom.',
        ),
        isNull,
      );
    });
  });

  group('parseErrorCausingWidget', () {
    test('extracts widget and file location from single-line widget string', () {
      const message =
          'The relevant error-causing widget was:\n'
          '    Row Row:file:///Users/yomiry/StudioWorkspace/flutter_inspector/example/lib/main.dart:322:13';
      final result = parseErrorCausingWidget(message);

      expect(result, isNotNull);
      expect(result!['errorCausingWidget'], 'Row');
      expect(
        result['errorLocation'],
        'file:///Users/yomiry/StudioWorkspace/flutter_inspector/example/lib/main.dart:322:13',
      );
    });

    test('extracts widget and location from multiline string', () {
      const message =
          'The relevant error-causing widget was:\n'
          '  Row\n'
          '  Row:file:///Users/yomiry/StudioWorkspace/flutter_inspector/example/lib/main.dart:322:13';
      final result = parseErrorCausingWidget(message);

      expect(result, isNotNull);
      expect(result!['errorCausingWidget'], 'Row');
      expect(
        result['errorLocation'],
        'file:///Users/yomiry/StudioWorkspace/flutter_inspector/example/lib/main.dart:322:13',
      );
    });

    test('extracts widget and package URI location', () {
      const message =
          'The relevant error-causing widget was:\n'
          '  Column:package:my_app/widgets/home.dart:45:10';
      final result = parseErrorCausingWidget(message);

      expect(result, isNotNull);
      expect(result!['errorCausingWidget'], 'Column');
      expect(result['errorLocation'], 'package:my_app/widgets/home.dart:45:10');
    });

    test('extracts location with Windows drive letter in file URI', () {
      const message =
          'The relevant error-causing widget was:\n'
          '  Row Row:file:///C:/work/lib/main.dart:12:3';
      final result = parseErrorCausingWidget(message);

      expect(result, isNotNull);
      expect(result!['errorCausingWidget'], 'Row');
      expect(result['errorLocation'], 'file:///C:/work/lib/main.dart:12:3');
    });

    test('returns null when no error-causing widget is present', () {
      expect(
        parseErrorCausingWidget('A RenderFlex overflowed by 24 pixels'),
        isNull,
      );
      expect(parseErrorCausingWidget('NullPointerException'), isNull);
    });
  });

  group('UncaughtErrorHandler RenderFlex integration', () {
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

    test('injects overflow and error-causing widget metadata into data map', () {
      Map<String, dynamic>? capturedData;

      final handler = UncaughtErrorHandler(
        onLog: (message, {level = LogLevel.info, stackTrace, data}) {
          capturedData = data;
        },
      );
      handler.attach();

      final details = FlutterErrorDetails(
        exception: FlutterError(
          'A RenderFlex overflowed by 48.0 pixels on the bottom.\n'
          'The relevant error-causing widget was:\n'
          '    Row Row:file:///Users/yomiry/StudioWorkspace/flutter_inspector/example/lib/main.dart:322:13',
        ),
        stack: StackTrace.current,
        library: 'rendering library',
      );

      FlutterError.onError!(details);

      expect(capturedData, isNotNull);
      expect(capturedData!['source'], 'flutterError');
      expect(capturedData!['isRenderFlexOverflow'], isTrue);
      expect(capturedData!['overflowPixels'], 48.0);
      expect(capturedData!['overflowDirection'], 'bottom');
      expect(capturedData!['errorCausingWidget'], 'Row');
      expect(
        capturedData!['errorLocation'],
        'file:///Users/yomiry/StudioWorkspace/flutter_inspector/example/lib/main.dart:322:13',
      );
    });

    test('does not inject overflow metadata for standard exceptions', () {
      Map<String, dynamic>? capturedData;

      final handler = UncaughtErrorHandler(
        onLog: (message, {level = LogLevel.info, stackTrace, data}) {
          capturedData = data;
        },
      );
      handler.attach();

      final details = FlutterErrorDetails(
        exception: StateError('Standard state error'),
        stack: StackTrace.current,
      );

      FlutterError.onError!(details);

      expect(capturedData, isNotNull);
      expect(capturedData!.containsKey('isRenderFlexOverflow'), isFalse);
      expect(capturedData!.containsKey('errorCausingWidget'), isFalse);
    });
  });
}
