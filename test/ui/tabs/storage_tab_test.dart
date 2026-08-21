import 'package:flutter/material.dart';
import 'package:flutter_inspector_kit/src/core/flutter_inspector.dart';
import 'package:flutter_inspector_kit/src/models/key_value_browser_source.dart';
import 'package:flutter_inspector_kit/src/ui/dashboard/tabs/storage_tab.dart';
import 'package:flutter_inspector_kit/src/ui/widgets/error_card.dart';
import 'package:flutter_test/flutter_test.dart';

class FakeKeyValueSource implements KeyValueBrowserSource {
  FakeKeyValueSource({this.sourceName = 'Fake', List<KeyValueEntry>? entries})
    : entries = entries ?? <KeyValueEntry>[];

  final String sourceName;
  List<KeyValueEntry> entries;
  bool throwOnList = false;
  int listAllCount = 0;

  @override
  String get name => sourceName;

  @override
  Future<List<KeyValueEntry>> listAll() async {
    listAllCount++;
    if (throwOnList) throw StateError('boom');
    return entries;
  }

  @override
  Future<void> setValue(String key, Object? value) async {}

  @override
  Future<void> remove(String key) async {}

  @override
  Future<void> clear() async {}
}

FlutterInspector buildInspector(List<KeyValueBrowserSource> sources) {
  return FlutterInspector(
    navigatorKey: GlobalKey<NavigatorState>(),
    keyValueSources: sources,
  );
}

Future<void> pumpTab(WidgetTester tester, FlutterInspector inspector) async {
  await tester.pumpWidget(
    MaterialApp(home: Scaffold(body: StorageTab(inspector: inspector))),
  );
  await tester.pumpAndSettle();
}

void main() {
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
