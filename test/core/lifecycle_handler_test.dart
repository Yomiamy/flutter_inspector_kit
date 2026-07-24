import 'package:flutter/widgets.dart';
import 'package:flutter_inspector_kit/src/core/lifecycle_handler.dart';
import 'package:flutter_inspector_kit/src/models/log_level.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  LifecycleHandler? handler;

  tearDown(() {
    handler?.detach();
    handler = null;
  });

  test('attach: state change produces one info log with the state name', () {
    var callCount = 0;
    LogLevel? lastLevel;
    String? lastMessage;
    final h = LifecycleHandler(
      onLog: (message, {level = LogLevel.info, stackTrace, data}) {
        callCount++;
        lastLevel = level;
        lastMessage = message;
      },
    );
    handler = h;
    h.attach();

    WidgetsBinding.instance.handleAppLifecycleStateChanged(
      AppLifecycleState.resumed,
    );

    expect(callCount, 1);
    expect(lastLevel, LogLevel.info);
    expect(lastMessage, contains('resumed'));
  });

  test('all five states are recorded', () {
    final messages = <String>[];
    final h = LifecycleHandler(
      onLog: (message, {level = LogLevel.info, stackTrace, data}) {
        messages.add(message);
      },
    );
    handler = h;
    h.attach();

    const states = [
      AppLifecycleState.resumed,
      AppLifecycleState.inactive,
      AppLifecycleState.paused,
      AppLifecycleState.detached,
      AppLifecycleState.hidden,
    ];
    for (final state in states) {
      WidgetsBinding.instance.handleAppLifecycleStateChanged(state);
    }

    expect(messages.length, 5);
    for (var i = 0; i < states.length; i++) {
      expect(messages[i], contains(states[i].name));
    }
  });

  test('idempotent: attach twice records a state change once', () {
    var callCount = 0;
    final h = LifecycleHandler(
      onLog: (message, {level = LogLevel.info, stackTrace, data}) {
        callCount++;
      },
    );
    handler = h;
    h.attach();
    h.attach();

    WidgetsBinding.instance.handleAppLifecycleStateChanged(
      AppLifecycleState.resumed,
    );

    expect(callCount, 1);
  });

  test('detach: no further logs after detach', () {
    var callCount = 0;
    final h = LifecycleHandler(
      onLog: (message, {level = LogLevel.info, stackTrace, data}) {
        callCount++;
      },
    );
    handler = h;
    h.attach();

    WidgetsBinding.instance.handleAppLifecycleStateChanged(
      AppLifecycleState.resumed,
    );
    h.detach();
    WidgetsBinding.instance.handleAppLifecycleStateChanged(
      AppLifecycleState.paused,
    );

    expect(callCount, 1);
    expect(h.detach, returnsNormally);
  });

  test('not attached: state change produces no log', () {
    var callCount = 0;
    handler = LifecycleHandler(
      onLog: (message, {level = LogLevel.info, stackTrace, data}) {
        callCount++;
      },
    );

    // 刻意不呼叫 attach()。
    WidgetsBinding.instance.handleAppLifecycleStateChanged(
      AppLifecycleState.resumed,
    );

    expect(callCount, 0);
  });

  test('guard: onLog throws does not propagate', () {
    var hostCalled = false;
    final hostObserver = _HostObserver(() => hostCalled = true);

    final h = LifecycleHandler(
      onLog: (message, {level = LogLevel.info, stackTrace, data}) {
        throw StateError('onLog failed');
      },
    );
    handler = h;

    // 註冊順序刻意讓 handler 排在 hostObserver 之前：binding 的廣播迴圈沒有
    // per-observer try-catch，handler 若讓例外逃逸，迴圈會在 hostObserver
    // 之前中斷。倒過來註冊會讓 hostCalled 恆為 true，測不到 guard 是否存在。
    h.attach();
    WidgetsBinding.instance.addObserver(hostObserver);
    addTearDown(() => WidgetsBinding.instance.removeObserver(hostObserver));

    expect(
      () => WidgetsBinding.instance.handleAppLifecycleStateChanged(
        AppLifecycleState.resumed,
      ),
      returnsNormally,
    );
    expect(hostCalled, isTrue);
  });
}

/// Minimal host observer, proving [LifecycleHandler] never crowds out the
/// other observers registered on the binding.
class _HostObserver with WidgetsBindingObserver {
  _HostObserver(this.onStateChange);

  final VoidCallback onStateChange;

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    onStateChange();
  }
}
