import 'package:flutter/widgets.dart';
import 'package:flutter_inspector_kit/src/core/flutter_inspector.dart';
import 'package:flutter_inspector_kit/src/models/log_level.dart';
import 'package:flutter_inspector_kit/src/models/navigator_action.dart';
import 'package:flutter_inspector_kit/src/models/navigator_entry.dart';
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

  test('lifecycle log names the current top page from the nav stack', () {
    final inspector = FlutterInspector(captureLifecycleEvents: true);
    currentInspector = inspector;

    // 推一筆 push 進 navigator buffer，讓 resolver 有 top page 可推導。
    inspector.registry.navigator.add(
      NavigatorEntry(action: NavigatorAction.push, routeName: '/home'),
    );

    WidgetsBinding.instance.handleAppLifecycleStateChanged(
      AppLifecycleState.paused,
    );

    // routeName 有值 → message 尾巴帶 (routeName)；此 entry 無 widgetType，
    // displayName 退回 routeName，故格式為 "/home (/home)"。
    expect(inspector.logEntries.single.message, contains('paused'));
    expect(inspector.logEntries.single.message, contains('/home'));
  });

  test('empty nav stack yields a bare lifecycle message', () {
    final inspector = FlutterInspector(captureLifecycleEvents: true);
    currentInspector = inspector;

    // 未推任何 navigator 事件 → resolver 回空 → 不加尾巴。
    WidgetsBinding.instance.handleAppLifecycleStateChanged(
      AppLifecycleState.resumed,
    );

    expect(inspector.logEntries.single.message, 'App lifecycle: resumed');
  });
}
