import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_inspector_kit/src/core/flutter_inspector.dart';
import 'package:flutter_inspector_kit/src/models/key_value_browser_source.dart';
import 'package:flutter_inspector_kit/src/models/log_entry.dart';
import 'package:flutter_inspector_kit/src/models/log_level.dart';
import 'package:flutter_inspector_kit/src/ui/dashboard/tabs/storage_tab.dart';
import 'package:flutter_inspector_kit/src/ui/widgets/error_card.dart';
import 'package:flutter_test/flutter_test.dart';

class FakeKeyValueSource implements KeyValueBrowserSource {
  FakeKeyValueSource({
    this.sourceName = 'Fake',
    List<KeyValueEntry>? entries,
    this.gate,
  }) : entries = entries ?? <KeyValueEntry>[];

  /// When set, listAll() blocks until completed — lets a test hold one load
  /// in flight while triggering another.
  final Completer<void>? gate;
  final String sourceName;
  List<KeyValueEntry> entries;
  bool throwOnList = false;
  bool throwOnWrite = false;
  int listAllCount = 0;
  final List<({String key, Object? value})> setValueCalls = [];
  final List<String> removeCalls = [];
  int clearCount = 0;

  @override
  String get name => sourceName;

  @override
  Future<List<KeyValueEntry>> listAll() async {
    listAllCount++;
    // Snapshot before awaiting: a response must carry the data as it was when
    // the request was issued, otherwise every response returns the latest data
    // and a stale-response test cannot fail.
    final snapshot = entries;
    if (gate != null) await gate!.future;
    if (throwOnList) throw StateError('boom');
    return snapshot;
  }

  @override
  Future<void> setValue(String key, Object? value) async {
    setValueCalls.add((key: key, value: value));
    if (throwOnWrite) throw StateError('write failed');
    entries = [
      for (final e in entries)
        if (e.key == key)
          KeyValueEntry(key: e.key, value: value, type: e.type)
        else
          e,
    ];
  }

  @override
  Future<void> remove(String key) async {
    removeCalls.add(key);
    entries = [
      for (final e in entries)
        if (e.key != key) e,
    ];
  }

  @override
  Future<void> clear() async {
    clearCount++;
    entries = [];
  }
}

FlutterInspector buildInspector(List<KeyValueBrowserSource> sources) {
  return FlutterInspector(
    navigatorKey: GlobalKey<NavigatorState>(),
    keyValueSources: sources,
  );
}

Future<void> pumpTab(WidgetTester tester, FlutterInspector inspector) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(body: StorageTab(inspector: inspector)),
    ),
  );
  await tester.pumpAndSettle();
}

/// Opens the edit dialog for [key] and types [newValue] into it.
Future<void> openEditAndType(
  WidgetTester tester,
  String key,
  String newValue,
) async {
  // Target the row for [key], not merely the first one, so a future
  // multi-entry test cannot silently edit the wrong entry.
  await tester.tap(
    find.descendant(
      of: find.ancestor(of: find.text(key), matching: find.byType(ListTile)),
      matching: find.byIcon(Icons.edit),
    ),
  );
  await tester.pumpAndSettle();
  await tester.enterText(find.byType(TextField).last, newValue);
  await tester.pumpAndSettle();
  await tester.tap(find.text('Next'));
  await tester.pumpAndSettle();
}

void main() {
  group('StorageTab inline edit', () {
    testWidgets('does not write until the confirm step is accepted', (
      tester,
    ) async {
      final source = FakeKeyValueSource(
        entries: const [
          KeyValueEntry(key: 'token', value: 'old', type: KeyValueType.string),
        ],
      );
      await pumpTab(tester, buildInspector([source]));

      await openEditAndType(tester, 'token', 'new');

      // Confirm step is showing, but nothing has been written yet.
      expect(source.setValueCalls, isEmpty);

      await tester.tap(find.text('Confirm'));
      await tester.pumpAndSettle();

      expect(source.setValueCalls, [(key: 'token', value: 'new')]);
    });

    testWidgets('cancelling the confirm step writes nothing', (tester) async {
      final source = FakeKeyValueSource(
        entries: const [
          KeyValueEntry(key: 'token', value: 'old', type: KeyValueType.string),
        ],
      );
      await pumpTab(tester, buildInspector([source]));

      await openEditAndType(tester, 'token', 'new');
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();

      expect(source.setValueCalls, isEmpty);
      expect(find.text('old'), findsOneWidget);
    });

    testWidgets('list shows the new value after a successful write', (
      tester,
    ) async {
      final source = FakeKeyValueSource(
        entries: const [
          KeyValueEntry(key: 'token', value: 'old', type: KeyValueType.string),
        ],
      );
      await pumpTab(tester, buildInspector([source]));

      await openEditAndType(tester, 'token', 'new');
      await tester.tap(find.text('Confirm'));
      await tester.pumpAndSettle();

      expect(find.text('new'), findsOneWidget);
      expect(find.text('old'), findsNothing);
    });

    testWidgets('rejects input that cannot parse to the original type', (
      tester,
    ) async {
      final source = FakeKeyValueSource(
        entries: const [
          KeyValueEntry(key: 'retries', value: 3, type: KeyValueType.int),
        ],
      );
      await pumpTab(tester, buildInspector([source]));

      await openEditAndType(tester, 'retries', 'abc');

      // Stays on the edit dialog with an error; never reaches confirm.
      expect(find.textContaining('Not a valid'), findsOneWidget);
      expect(find.text('Confirm'), findsNothing);
      expect(source.setValueCalls, isEmpty);
    });

    testWidgets('surfaces a write failure without leaving a spinner', (
      tester,
    ) async {
      final source = FakeKeyValueSource(
        entries: const [
          KeyValueEntry(key: 'token', value: 'old', type: KeyValueType.string),
        ],
      )..throwOnWrite = true;
      await pumpTab(tester, buildInspector([source]));

      await openEditAndType(tester, 'token', 'new');
      await tester.tap(find.text('Confirm'));
      await tester.pumpAndSettle();

      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(find.textContaining('write failed'), findsWidgets);
    });
  });

  group('StorageTab delete', () {
    testWidgets('does not remove until confirmed', (tester) async {
      final source = FakeKeyValueSource(
        entries: const [
          KeyValueEntry(key: 'token', value: 'abc', type: KeyValueType.string),
        ],
      );
      await pumpTab(tester, buildInspector([source]));

      await tester.tap(find.byIcon(Icons.delete_outline).first);
      await tester.pumpAndSettle();

      expect(source.removeCalls, isEmpty);

      await tester.tap(find.text('Delete'));
      await tester.pumpAndSettle();

      expect(source.removeCalls, ['token']);
      expect(find.text('token'), findsNothing);
    });

    testWidgets('cancelling keeps the entry', (tester) async {
      final source = FakeKeyValueSource(
        entries: const [
          KeyValueEntry(key: 'token', value: 'abc', type: KeyValueType.string),
        ],
      );
      await pumpTab(tester, buildInspector([source]));

      await tester.tap(find.byIcon(Icons.delete_outline).first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();

      expect(source.removeCalls, isEmpty);
      expect(find.text('token'), findsOneWidget);
    });
  });

  group('StorageTab clear all', () {
    testWidgets('confirm dialog names the source and the entry count', (
      tester,
    ) async {
      final source = FakeKeyValueSource(
        sourceName: 'Prefs',
        entries: const [
          KeyValueEntry(key: 'a', value: '1', type: KeyValueType.string),
          KeyValueEntry(key: 'b', value: '2', type: KeyValueType.string),
        ],
      );
      await pumpTab(tester, buildInspector([source]));

      await tester.tap(find.byIcon(Icons.delete_sweep));
      await tester.pumpAndSettle();

      // Both facts must be visible before wiping a store.
      expect(find.textContaining('Prefs'), findsWidgets);
      expect(find.textContaining('2'), findsWidgets);
      expect(source.clearCount, 0);
    });

    testWidgets('cancelling does not clear', (tester) async {
      final source = FakeKeyValueSource(
        entries: const [
          KeyValueEntry(key: 'a', value: '1', type: KeyValueType.string),
        ],
      );
      await pumpTab(tester, buildInspector([source]));

      await tester.tap(find.byIcon(Icons.delete_sweep));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();

      expect(source.clearCount, 0);
      expect(find.text('a'), findsOneWidget);
    });

    testWidgets('confirming clears and shows the empty state', (tester) async {
      final source = FakeKeyValueSource(
        entries: const [
          KeyValueEntry(key: 'a', value: '1', type: KeyValueType.string),
        ],
      );
      await pumpTab(tester, buildInspector([source]));

      await tester.tap(find.byIcon(Icons.delete_sweep));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Clear all'));
      await tester.pumpAndSettle();

      expect(source.clearCount, 1);
      expect(find.textContaining('No entries'), findsOneWidget);
    });
  });

  group('StorageTab concurrent loads', () {
    testWidgets(
      'switching source while a load is in flight loads the new one',
      (tester) async {
        final gate = Completer<void>();
        final prefs = FakeKeyValueSource(
          sourceName: 'Prefs',
          entries: const [
            KeyValueEntry(
              key: 'prefs_key',
              value: 'p',
              type: KeyValueType.string,
            ),
          ],
          gate: gate,
        );
        final secure = FakeKeyValueSource(
          sourceName: 'Secure',
          entries: const [
            KeyValueEntry(
              key: 'secure_key',
              value: 's',
              type: KeyValueType.string,
            ),
          ],
        );
        final inspector = buildInspector([prefs, secure]);

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(body: StorageTab(inspector: inspector)),
          ),
        );
        await tester.pump(); // Prefs is still blocked on the gate.

        await tester.tap(find.byType(DropdownButton<KeyValueBrowserSource>));
        await tester.pump(const Duration(seconds: 1));
        await tester.tap(find.text('Secure').last);
        await tester.pump();

        // The switch must not be swallowed by the in-flight Prefs load.
        expect(secure.listAllCount, 1);

        gate.complete();
        await tester.pump(const Duration(seconds: 1));

        // The stale Prefs response must not land on top of the new source.
        expect(find.text('secure_key'), findsOneWidget);
        expect(find.text('prefs_key'), findsNothing);
      },
    );

    testWidgets('a stale response cannot overwrite a newer one', (
      tester,
    ) async {
      final gate = Completer<void>();
      final slow = FakeKeyValueSource(
        sourceName: 'Slow',
        entries: const [
          KeyValueEntry(key: 'stale', value: 'x', type: KeyValueType.string),
        ],
        gate: gate,
      );
      final inspector = buildInspector([slow]);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: StorageTab(inspector: inspector)),
        ),
      );
      await tester.pump();

      // Change the data before refreshing, so the two in-flight responses
      // carry different snapshots and the winner is observable.
      slow.entries = const [
        KeyValueEntry(key: 'fresh', value: 'y', type: KeyValueType.string),
      ];
      await tester.tap(find.byIcon(Icons.refresh));
      await tester.pump();
      expect(slow.listAllCount, 2);

      gate.complete();
      await tester.pump(const Duration(seconds: 1));

      // The second response wins even though both arrive together.
      expect(find.text('fresh'), findsOneWidget);
      expect(find.text('stale'), findsNothing);
    });
  });

  group('StorageTab destructive actions during a load', () {
    testWidgets('clear all is unavailable while a source is loading', (
      tester,
    ) async {
      final gate = Completer<void>();
      final prefs = FakeKeyValueSource(
        sourceName: 'Prefs',
        entries: const [
          KeyValueEntry(key: 'a', value: '1', type: KeyValueType.string),
          KeyValueEntry(key: 'b', value: '2', type: KeyValueType.string),
        ],
      );
      final secure = FakeKeyValueSource(sourceName: 'Secure', gate: gate);
      await pumpTab(tester, buildInspector([prefs, secure]));

      await tester.tap(find.byType(DropdownButton<KeyValueBrowserSource>));
      await tester.pump(const Duration(seconds: 1));
      await tester.tap(find.text('Secure').last);
      await tester.pump();

      // Prefs' rows must not authorise clearing Secure.
      final button = tester.widget<IconButton>(
        find.ancestor(
          of: find.byIcon(Icons.delete_sweep),
          matching: find.byType(IconButton),
        ),
      );
      expect(button.onPressed, isNull);

      gate.complete();
      await tester.pumpAndSettle();
    });

    testWidgets('stale rows are dropped as soon as a load starts', (
      tester,
    ) async {
      final gate = Completer<void>();
      final prefs = FakeKeyValueSource(
        sourceName: 'Prefs',
        entries: const [
          KeyValueEntry(
            key: 'prefs_key',
            value: '1',
            type: KeyValueType.string,
          ),
        ],
      );
      final secure = FakeKeyValueSource(sourceName: 'Secure', gate: gate);
      await pumpTab(tester, buildInspector([prefs, secure]));
      expect(find.text('prefs_key'), findsOneWidget);

      await tester.tap(find.byType(DropdownButton<KeyValueBrowserSource>));
      await tester.pump(const Duration(seconds: 1));
      await tester.tap(find.text('Secure').last);
      await tester.pump();

      expect(find.text('prefs_key'), findsNothing);

      gate.complete();
      await tester.pumpAndSettle();
    });
  });

  group('StorageTab audit log', () {
    /// KV audit entries only — ignores unrelated logs the inspector may hold.
    List<LogEntry> kvLogs(FlutterInspector inspector) =>
        inspector.logEntries.where((e) => e.message.contains('[KV]')).toList();

    testWidgets('a successful edit logs exactly one info entry', (
      tester,
    ) async {
      final source = FakeKeyValueSource(
        sourceName: 'Prefs',
        entries: const [
          KeyValueEntry(key: 'token', value: 'old', type: KeyValueType.string),
        ],
      );
      final inspector = buildInspector([source]);
      await pumpTab(tester, inspector);

      await openEditAndType(tester, 'token', 'new');
      await tester.tap(find.text('Confirm'));
      await tester.pumpAndSettle();

      final logs = kvLogs(inspector);
      expect(logs, hasLength(1));
      expect(logs.single.level, LogLevel.info);
      expect(logs.single.message, contains('token'));
      expect(logs.single.message, contains('Prefs'));
      // Old value belongs in data, so the message stays readable.
      // Masked here because redaction is on by default — see the redaction
      // tests below for both settings.
      expect(logs.single.data?['oldValue'], '***');
      expect(logs.single.data?['newValue'], '***');
    });

    testWidgets('a successful delete logs exactly one info entry', (
      tester,
    ) async {
      final source = FakeKeyValueSource(
        sourceName: 'Prefs',
        entries: const [
          KeyValueEntry(key: 'token', value: 'abc', type: KeyValueType.string),
        ],
      );
      final inspector = buildInspector([source]);
      await pumpTab(tester, inspector);

      await tester.tap(find.byIcon(Icons.delete_outline).first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Delete'));
      await tester.pumpAndSettle();

      final logs = kvLogs(inspector);
      expect(logs, hasLength(1));
      expect(logs.single.level, LogLevel.info);
      expect(logs.single.message, contains('token'));
    });

    testWidgets('a successful clear logs exactly one info entry', (
      tester,
    ) async {
      final source = FakeKeyValueSource(
        sourceName: 'Prefs',
        entries: const [
          KeyValueEntry(key: 'a', value: '1', type: KeyValueType.string),
        ],
      );
      final inspector = buildInspector([source]);
      await pumpTab(tester, inspector);

      await tester.tap(find.byIcon(Icons.delete_sweep));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Clear all'));
      await tester.pumpAndSettle();

      final logs = kvLogs(inspector);
      expect(logs, hasLength(1));
      expect(logs.single.level, LogLevel.info);
      expect(logs.single.message, contains('Prefs'));
    });

    testWidgets('masks values when redaction is on, keeping key and source', (
      tester,
    ) async {
      final source = FakeKeyValueSource(
        sourceName: 'Secure',
        entries: const [
          KeyValueEntry(
            key: 'token',
            value: 'secret',
            type: KeyValueType.string,
          ),
        ],
      );
      // redactSensitiveData defaults to true.
      final inspector = FlutterInspector(
        navigatorKey: GlobalKey<NavigatorState>(),
        keyValueSources: [source],
      );
      await pumpTab(tester, inspector);

      await openEditAndType(tester, 'token', 'newsecret');
      await tester.tap(find.text('Confirm'));
      await tester.pumpAndSettle();

      final log = kvLogs(inspector).single;
      // Values reach the clipboard via buildLogPlainText, so they are masked.
      expect(log.data?['oldValue'], '***');
      expect(log.data?['newValue'], '***');
      // The trail is still useful without them.
      expect(log.data?['key'], 'token');
      expect(log.data?['source'], 'Secure');
    });

    testWidgets('keeps values when the host opts out of redaction', (
      tester,
    ) async {
      final source = FakeKeyValueSource(
        entries: const [
          KeyValueEntry(key: 'token', value: 'old', type: KeyValueType.string),
        ],
      );
      final inspector = FlutterInspector(
        navigatorKey: GlobalKey<NavigatorState>(),
        keyValueSources: [source],
        redactSensitiveData: false,
      );
      await pumpTab(tester, inspector);

      await openEditAndType(tester, 'token', 'new');
      await tester.tap(find.text('Confirm'));
      await tester.pumpAndSettle();

      final log = kvLogs(inspector).single;
      expect(log.data?['oldValue'], 'old');
      expect(log.data?['newValue'], 'new');
    });

    testWidgets('a failed write logs nothing', (tester) async {
      final source = FakeKeyValueSource(
        entries: const [
          KeyValueEntry(key: 'token', value: 'old', type: KeyValueType.string),
        ],
      )..throwOnWrite = true;
      final inspector = buildInspector([source]);
      await pumpTab(tester, inspector);

      await openEditAndType(tester, 'token', 'new');
      await tester.tap(find.text('Confirm'));
      await tester.pumpAndSettle();

      // Nothing happened, so nothing may claim it did.
      expect(kvLogs(inspector), isEmpty);
    });

    testWidgets('cancelling logs nothing', (tester) async {
      final source = FakeKeyValueSource(
        entries: const [
          KeyValueEntry(key: 'token', value: 'old', type: KeyValueType.string),
        ],
      );
      final inspector = buildInspector([source]);
      await pumpTab(tester, inspector);

      await openEditAndType(tester, 'token', 'new');
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();

      expect(kvLogs(inspector), isEmpty);
    });
  });

  group('StorageTab read-only view', () {
    testWidgets('lists entries with key, value and type', (tester) async {
      final source = FakeKeyValueSource(
        entries: const [
          KeyValueEntry(key: 'token', value: 'abc', type: KeyValueType.string),
          KeyValueEntry(key: 'retries', value: 3, type: KeyValueType.int),
          KeyValueEntry(key: 'beta', value: true, type: KeyValueType.bool),
        ],
      );
      await pumpTab(tester, buildInspector([source]));

      expect(find.text('token'), findsOneWidget);
      expect(find.text('abc'), findsOneWidget);
      expect(find.text('retries'), findsOneWidget);
      expect(find.text('3'), findsOneWidget);
      expect(find.text('beta'), findsOneWidget);
      // Type is surfaced so an RD can tell how the value is stored.
      expect(find.textContaining('string'), findsWidgets);
    });

    testWidgets('shows an empty state when the source has no keys', (
      tester,
    ) async {
      await pumpTab(tester, buildInspector([FakeKeyValueSource()]));

      expect(find.textContaining('No entries'), findsOneWidget);
      expect(find.byType(ErrorCard), findsNothing);
    });

    testWidgets('shows ErrorCard when listAll throws, and retry re-fetches', (
      tester,
    ) async {
      final source = FakeKeyValueSource()..throwOnList = true;
      await pumpTab(tester, buildInspector([source]));

      expect(find.byType(ErrorCard), findsOneWidget);
      expect(source.listAllCount, 1);

      // Recover, then retry: the card must trigger another fetch.
      source.throwOnList = false;
      source.entries = const [
        KeyValueEntry(key: 'token', value: 'abc', type: KeyValueType.string),
      ];
      await tester.tap(find.text('Retry'));
      await tester.pumpAndSettle();

      expect(source.listAllCount, 2);
      expect(find.byType(ErrorCard), findsNothing);
      expect(find.text('token'), findsOneWidget);
    });

    testWidgets('refresh re-reads the source', (tester) async {
      final source = FakeKeyValueSource();
      await pumpTab(tester, buildInspector([source]));
      expect(source.listAllCount, 1);

      await tester.tap(find.byIcon(Icons.refresh));
      await tester.pumpAndSettle();

      expect(source.listAllCount, 2);
    });

    // Split in two: re-pumping StorageTab in one test reuses the same element,
    // so initState never re-runs against the second inspector.
    testWidgets('hides the dropdown when only one source is registered', (
      tester,
    ) async {
      await pumpTab(tester, buildInspector([FakeKeyValueSource()]));

      expect(find.byType(DropdownButton<KeyValueBrowserSource>), findsNothing);
    });

    testWidgets('shows the dropdown when several sources are registered', (
      tester,
    ) async {
      await pumpTab(
        tester,
        buildInspector([
          FakeKeyValueSource(sourceName: 'Prefs'),
          FakeKeyValueSource(sourceName: 'Secure'),
        ]),
      );

      expect(
        find.byType(DropdownButton<KeyValueBrowserSource>),
        findsOneWidget,
      );
    });

    testWidgets('filters by key and by value, and restores when cleared', (
      tester,
    ) async {
      final source = FakeKeyValueSource(
        entries: const [
          KeyValueEntry(
            key: 'auth_token',
            value: 'xyz',
            type: KeyValueType.string,
          ),
          KeyValueEntry(key: 'retries', value: 3, type: KeyValueType.int),
          KeyValueEntry(
            key: 'theme',
            value: 'token-dark',
            type: KeyValueType.string,
          ),
        ],
      );
      await pumpTab(tester, buildInspector([source]));

      await tester.enterText(find.byType(TextField), 'token');
      await tester.pumpAndSettle();

      // Matches on key (auth_token) and on value (token-dark).
      expect(find.text('auth_token'), findsOneWidget);
      expect(find.text('theme'), findsOneWidget);
      expect(find.text('retries'), findsNothing);

      await tester.enterText(find.byType(TextField), '');
      await tester.pumpAndSettle();

      expect(find.text('retries'), findsOneWidget);
    });

    testWidgets('search is case-insensitive', (tester) async {
      final source = FakeKeyValueSource(
        entries: const [
          KeyValueEntry(
            key: 'auth_token',
            value: 'xyz',
            type: KeyValueType.string,
          ),
          KeyValueEntry(key: 'retries', value: 3, type: KeyValueType.int),
        ],
      );
      await pumpTab(tester, buildInspector([source]));

      await tester.enterText(find.byType(TextField), 'TOKEN');
      await tester.pumpAndSettle();

      expect(find.text('auth_token'), findsOneWidget);
      expect(find.text('retries'), findsNothing);
    });

    testWidgets('shows a no-match message rather than the empty state', (
      tester,
    ) async {
      final source = FakeKeyValueSource(
        entries: const [
          KeyValueEntry(key: 'token', value: 'abc', type: KeyValueType.string),
        ],
      );
      await pumpTab(tester, buildInspector([source]));

      await tester.enterText(find.byType(TextField), 'zzz');
      await tester.pumpAndSettle();

      // "No entries" would wrongly imply the store itself is empty.
      expect(find.textContaining('No matching'), findsOneWidget);
    });

    testWidgets('switching source loads the newly selected one', (
      tester,
    ) async {
      final prefs = FakeKeyValueSource(
        sourceName: 'Prefs',
        entries: const [
          KeyValueEntry(key: 'token', value: 'abc', type: KeyValueType.string),
        ],
      );
      final secure = FakeKeyValueSource(
        sourceName: 'Secure',
        entries: const [
          KeyValueEntry(key: 'pin', value: '1234', type: KeyValueType.string),
        ],
      );
      await pumpTab(tester, buildInspector([prefs, secure]));
      expect(find.text('token'), findsOneWidget);

      await tester.tap(find.byType(DropdownButton<KeyValueBrowserSource>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Secure').last);
      await tester.pumpAndSettle();

      expect(secure.listAllCount, 1);
      expect(find.text('pin'), findsOneWidget);
      expect(find.text('token'), findsNothing);
    });
  });
}
