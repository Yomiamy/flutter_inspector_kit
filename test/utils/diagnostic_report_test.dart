import 'package:flutter_inspector_kit/src/inspectors/log_inspector.dart';
import 'package:flutter_inspector_kit/src/models/database_entry.dart';
import 'package:flutter_inspector_kit/src/models/database_operation.dart';
import 'package:flutter_inspector_kit/src/models/diagnostic_info.dart';
import 'package:flutter_inspector_kit/src/models/log_entry.dart';
import 'package:flutter_inspector_kit/src/models/log_level.dart';
import 'package:flutter_inspector_kit/src/models/navigator_action.dart';
import 'package:flutter_inspector_kit/src/models/navigator_entry.dart';
import 'package:flutter_inspector_kit/src/models/network_entry.dart';
import 'package:flutter_inspector_kit/src/models/timestamped_entry.dart';
import 'package:flutter_inspector_kit/src/utils/diagnostic_report.dart';
import 'package:flutter_inspector_kit/src/version.dart';
import 'package:flutter_test/flutter_test.dart';

/// Fixed clock so time-window assertions are deterministic.
final _now = DateTime(2026, 7, 15, 12, 0, 0);
DateTime _minutesAgo(int m) => _now.subtract(Duration(minutes: m));

String _report({
  LogInspector? logInspector,
  List<NetworkEntry> network = const [],
  List<NavigatorEntry> nav = const [],
  List<DatabaseEntry> db = const [],
  DiagnosticInfo? info,
  Duration? timeRange,
  Set<TimelineSource>? sections,
  bool errorsOnly = false,
  bool redact = true,
}) {
  return buildDiagnosticReport(
    logInspector: logInspector ?? LogInspector(),
    networkEntries: network,
    navigatorEntries: nav,
    databaseEntries: db,
    now: _now,
    info: info,
    timeRange: timeRange,
    sections: sections ?? TimelineSource.values.toSet(),
    errorsOnly: errorsOnly,
    redact: redact,
  );
}

/// Walks [markdown] the way CommonMark does: a fence line only *closes* a block
/// if it is at least as long as the fence that opened it. Counting fence lines
/// and checking parity would be wrong — a 3-backtick line sitting inside a
/// 4-backtick block is just content.
bool _fencesBalanced(String markdown) {
  int? openLength;
  for (final line in markdown.split('\n')) {
    final match = RegExp(r'^\s{0,3}(`{3,})\s*$').firstMatch(line);
    if (match == null) continue;

    final length = match[1]!.length;
    if (openLength == null) {
      openLength = length;
    } else if (length >= openLength) {
      openLength = null;
    }
  }
  return openLength == null;
}

void main() {
  group('header (AC-2, AC-3, AC-4, AC-5, AC-17)', () {
    test('prints the package version from the single source of truth', () {
      expect(_report(), contains('flutter_inspector_kit $packageVersion'));
    });

    test('degrades every device field to N/A when no info is injected', () {
      final report = _report();

      expect(report, contains('| App version | N/A |'));
      expect(report, contains('| Device | N/A |'));
      expect(report, contains('| OS | N/A |'));
    });

    test('shows the host-supplied values when info is injected', () {
      final report = _report(
        info: const DiagnosticInfo(
          appVersion: '2.3.1+45',
          deviceModel: 'iPhone15,2',
          osVersion: 'iOS 17.4',
        ),
      );

      expect(report, contains('| App version | 2.3.1+45 |'));
      expect(report, contains('| Device | iPhone15,2 |'));
      expect(report, contains('| OS | iOS 17.4 |'));
    });

    test('a partially-populated source still degrades only the missing fields', () {
      final report = _report(info: const DiagnosticInfo(osVersion: 'Android 14'));

      expect(report, contains('| OS | Android 14 |'));
      expect(report, contains('| App version | N/A |'));
    });

    test('states the redaction status honestly', () {
      expect(_report(), contains('| Redaction | enabled |'));
      expect(_report(redact: false), contains('| Redaction | disabled |'));
    });

    test('states the time range, with null rendered as "all"', () {
      expect(_report(), contains('| Time range | all |'));
      expect(
        _report(timeRange: const Duration(minutes: 5)),
        contains('| Time range | last 5m |'),
      );
      expect(
        _report(timeRange: const Duration(hours: 1)),
        contains('| Time range | last 1h |'),
      );
    });
  });

  group('time window (AC-8)', () {
    LogInspector spanningLogs() {
      return LogInspector()
        ..add(LogEntry(message: 'recent', timestamp: _minutesAgo(2)))
        ..add(LogEntry(message: 'mid', timestamp: _minutesAgo(30)))
        ..add(LogEntry(message: 'ancient', timestamp: _minutesAgo(180)));
    }

    test('null includes everything', () {
      final report = _report(logInspector: spanningLogs());

      expect(report, contains('recent'));
      expect(report, contains('mid'));
      expect(report, contains('ancient'));
    });

    test('5m keeps only entries inside the window', () {
      final report = _report(
        logInspector: spanningLogs(),
        timeRange: const Duration(minutes: 5),
      );

      expect(report, contains('recent'));
      expect(report, isNot(contains('mid')));
      expect(report, isNot(contains('ancient')));
    });

    test('1h keeps entries inside the hour but drops older ones', () {
      final report = _report(
        logInspector: spanningLogs(),
        timeRange: const Duration(hours: 1),
      );

      expect(report, contains('recent'));
      expect(report, contains('mid'));
      expect(report, isNot(contains('ancient')));
    });
  });

  group('section selection (AC-9, AC-14)', () {
    test('an unselected source is absent entirely — not even its heading', () {
      final report = _report(
        network: [NetworkEntry(method: 'GET', url: 'https://api.test/x')],
        sections: {TimelineSource.log},
      );

      expect(report, isNot(contains('## Network')));
      expect(report, isNot(contains('https://api.test/x')));
      expect(report, contains('## Logs'));
    });

    test('a selected but empty source renders (none), not a blank block', () {
      final report = _report(sections: {TimelineSource.db});

      expect(report, contains('## Database'));
      expect(report, contains('(none)'));
    });

    test('an entry outside the time window leaves its section empty, not absent', () {
      final report = _report(
        db: [
          DatabaseEntry(
            operation: DatabaseOperation.insert,
            tableName: 'users',
            timestamp: _minutesAgo(180),
          ),
        ],
        sections: {TimelineSource.db},
        timeRange: const Duration(minutes: 5),
      );

      expect(report, contains('## Database'));
      expect(report, contains('(none)'));
      expect(report, isNot(contains('users')));
    });
  });

  group('redaction red line (AC-15, AC-16, AC-18)', () {
    NetworkEntry secretRequest() => NetworkEntry(
      method: 'POST',
      url: 'https://api.test/login',
      requestHeaders: const {
        'Authorization': 'Bearer super-secret-token',
        'Content-Type': 'application/json',
      },
      timestamp: _minutesAgo(1),
    );

    test('redact: true masks the secret header and never leaks the plaintext', () {
      final report = _report(network: [secretRequest()]);

      expect(report, isNot(contains('super-secret-token')));
      expect(report, isNot(contains('Bearer')));
      expect(report, contains('••••'));
      // Non-sensitive headers survive.
      expect(report, contains('application/json'));
    });

    test('redact: false emits the plaintext, matching single-entry share', () {
      final report = _report(network: [secretRequest()], redact: false);

      expect(report, contains('Bearer super-secret-token'));
      expect(report, isNot(contains('••••')));
    });
  });

  group('current route stack (AC-7)', () {
    test('renders the resolved stack top-first with the current route marked', () {
      final report = _report(
        nav: [
          // newest-first, as FlutterInspector.navigatorEntries yields.
          NavigatorEntry(
            action: NavigatorAction.push,
            routeName: '/checkout',
            timestamp: _minutesAgo(1),
          ),
          NavigatorEntry(
            action: NavigatorAction.push,
            routeName: '/cart',
            timestamp: _minutesAgo(2),
          ),
        ],
        sections: {TimelineSource.nav},
      );

      expect(report, contains('### Current route stack'));
      expect(report, contains('1. `/checkout` ← current'));
      expect(report, contains('2. `/cart`'));
    });

    test(
      'REGRESSION: the stack replays the full buffer, not the time-windowed list — '
      'a push outside the window must not be dropped, or its pop would corrupt the stack',
      () {
        final report = _report(
          nav: [
            // pop INSIDE the 5m window...
            NavigatorEntry(
              action: NavigatorAction.pop,
              routeName: '/detail',
              timestamp: _minutesAgo(1),
            ),
            // ...whose matching pushes are OUTSIDE it.
            NavigatorEntry(
              action: NavigatorAction.push,
              routeName: '/detail',
              timestamp: _minutesAgo(90),
            ),
            NavigatorEntry(
              action: NavigatorAction.push,
              routeName: '/home',
              timestamp: _minutesAgo(120),
            ),
          ],
          sections: {TimelineSource.nav},
          timeRange: const Duration(minutes: 5),
        );

        // /detail was pushed then popped → the stack is just /home.
        // If the resolver had been fed the windowed list (pop only), it would
        // have popped a route that was never pushed and derived a wrong stack.
        expect(report, contains('1. `/home` ← current'));
        expect(report, isNot(contains('1. `/detail`')));

        // The event list itself IS time-windowed: only the pop is recent.
        expect(report, contains('### Navigation events'));
      },
    );
  });

  group('markdown integrity: payloads that contain their own fences', () {
    // The whole point of this feature is pasting the report into a GitHub or
    // Jira issue. A payload carrying its own ``` (LLM output, CMS content, a
    // pasted snippet) must not be able to break out of its code block.

    test('a log message containing a fenced block stays inside its block', () {
      final report = _report(
        logInspector: LogInspector()
          ..add(LogEntry(
            message: 'llm replied:\n```\nprint("hi");\n```\ndone',
            timestamp: _minutesAgo(1),
          )),
        sections: {TimelineSource.log},
      );

      // The outer fence must outrun the payload's own 3-backtick run.
      expect(report, contains('````'));
      expect(report, contains('print("hi");'));
    });

    test('an unbalanced fence does not swallow the sections that follow', () {
      final report = _report(
        logInspector: LogInspector()
          // A truncated LLM response: one lone opening fence, never closed.
          ..add(LogEntry(
            message: 'output was cut off:\n```\nvoid main() {}',
            timestamp: _minutesAgo(1),
          )),
        db: [
          DatabaseEntry(
            operation: DatabaseOperation.insert,
            tableName: 'users',
            timestamp: _minutesAgo(1),
          ),
        ],
        sections: {TimelineSource.log, TimelineSource.db},
      );

      // With a fixed 3-backtick fence, the payload's stray fence flips parity
      // and everything after it is eaten — headings included.
      expect(report, contains('## Database'));
      expect(report, contains('users'));
      expect(_fencesBalanced(report), isTrue, reason: 'a fence was left open');
    });

    test('inline backticks are harmless and need no wider fence', () {
      final report = _report(
        logInspector: LogInspector()
          ..add(LogEntry(
            message: 'the `id` field was null',
            timestamp: _minutesAgo(1),
          )),
        sections: {TimelineSource.log},
      );

      expect(report, contains('the `id` field was null'));
      expect(report, isNot(contains('````')));
    });
  });

  group('errors-only (AC-10, AC-11, AC-12, AC-13)', () {
    // The warning is deliberately NEWER than the error. errors-only merges two
    // entriesAtLevel() calls, each newest-first on its own; concatenating them
    // yields [error, warning], which is only correctly ordered if the merge
    // re-sorts. Put the error first and the sort becomes a no-op — the test
    // would pass with the sort deleted, which is exactly the identity-assertion
    // trap that let FlutterInspector.version rot for three releases.
    LogInspector mixedLevels() {
      return LogInspector()
        ..add(LogEntry(
          message: 'boom',
          level: LogLevel.error,
          timestamp: _minutesAgo(5),
        ))
        ..add(LogEntry(
          message: 'careful',
          level: LogLevel.warning,
          timestamp: _minutesAgo(1),
        ))
        ..add(LogEntry(
          message: 'just-fyi',
          level: LogLevel.info,
          timestamp: _minutesAgo(3),
        ))
        ..add(LogEntry(
          message: 'noisy',
          level: LogLevel.debug,
          timestamp: _minutesAgo(4),
        ));
    }

    test('off by default: every level is included', () {
      final report = _report(logInspector: mixedLevels());

      expect(report, contains('boom'));
      expect(report, contains('careful'));
      expect(report, contains('just-fyi'));
      expect(report, contains('noisy'));
    });

    test('on: keeps error and warning, drops info and debug', () {
      final report = _report(logInspector: mixedLevels(), errorsOnly: true);

      expect(report, contains('boom'));
      expect(report, contains('careful'));
      expect(report, isNot(contains('just-fyi')));
      expect(report, isNot(contains('noisy')));
      expect(report, contains('Logs (errors & warnings only)'));
    });

    test('on: the surviving logs stay newest-first after the level merge', () {
      final report = _report(logInspector: mixedLevels(), errorsOnly: true);

      // 'careful' (warning, 1m ago) is newer than 'boom' (error, 5m ago), so a
      // correct merge puts it first. Deleting the sort in the builder flips
      // this — which is the point of the fixture.
      expect(report.indexOf('careful'), lessThan(report.indexOf('boom')));
    });

    test('does not touch the network / nav / db sections', () {
      final report = _report(
        logInspector: mixedLevels(),
        network: [
          NetworkEntry(
            method: 'GET',
            url: 'https://api.test/ok',
            statusCode: 200,
            timestamp: _minutesAgo(1),
          ),
        ],
        db: [
          DatabaseEntry(
            operation: DatabaseOperation.query,
            tableName: 'users',
            timestamp: _minutesAgo(1),
          ),
        ],
        errorsOnly: true,
      );

      // A 200 is not an error, but errorsOnly is a *log-level* filter only.
      expect(report, contains('https://api.test/ok'));
      expect(report, contains('users'));
    });
  });
}
