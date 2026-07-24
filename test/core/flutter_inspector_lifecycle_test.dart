import 'package:flutter/widgets.dart';
import 'package:flutter_inspector_kit/src/core/flutter_inspector.dart';
import 'package:flutter_inspector_kit/src/models/log_level.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  FlutterInspector? currentInspector;

  tearDown(() {
    currentInspector?.detach();
    currentInspector = null;
  });

  test('default off: no lifecycle log in logEntries', () {
    final inspector = FlutterInspector();
    currentInspector = inspector;

    WidgetsBinding.instance.handleAppLifecycleStateChanged(
      AppLifecycleState.paused,
    );

    expect(inspector.logEntries, isEmpty);
  });

  test('opt-in: lifecycle transition appears in logEntries', () {
    final inspector = FlutterInspector(captureLifecycleEvents: true);
    currentInspector = inspector;

    WidgetsBinding.instance.handleAppLifecycleStateChanged(
      AppLifecycleState.paused,
    );

    final entries = inspector.logEntries;
    expect(entries, hasLength(1));

    final entry = entries.single;
    expect(entry.message, contains('paused'));
    expect(entry.level, LogLevel.info);
    expect(entry.data, isNull);
  });

  test('detach stops lifecycle logging', () {
    final inspector = FlutterInspector(captureLifecycleEvents: true);
    currentInspector = inspector;

    WidgetsBinding.instance.handleAppLifecycleStateChanged(
      AppLifecycleState.resumed,
    );
    expect(inspector.logEntries, hasLength(1));

    inspector.detach();

    WidgetsBinding.instance.handleAppLifecycleStateChanged(
      AppLifecycleState.paused,
    );
    expect(inspector.logEntries, hasLength(1));
  });
}
