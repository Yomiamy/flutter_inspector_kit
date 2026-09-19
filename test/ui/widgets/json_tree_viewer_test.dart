import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_inspector_kit/src/ui/widgets/json_tree_viewer.dart';
import 'package:flutter_test/flutter_test.dart';

class Foo {
  @override
  String toString() => 'FOO';
}

class _Data {
  static const Map<String, Object?> nested = {
    'data': {
      'users': [
        {'id': 1, 'name': 'ann'},
      ],
    },
  };

  /// Same shape as [nested] but padded past the search-field threshold, so
  /// the field is rendered and search behaviour can be exercised.
  static Map<String, Object?> get searchable => {
    ...nested,
    'pad': {for (var i = 0; i < 20; i++) 'p$i': i},
  };

  static const Map<String, Object?> collision = {
    'a.b': {'c': 1},
    'a': {
      'b': {'c': 2},
    },
  };

  static final Map<String, Object?> mixedTypes = {
    'when': DateTime.utc(2020),
    'foo': Foo(),
    'nothing': null,
    'count': 7,
    'flag': true,
  };

  static Map<String, Object?> deep(int levels) {
    Object? node = 'bottom';
    for (var i = 0; i < levels; i++) {
      node = {'k$i': node};
    }
    return node as Map<String, Object?>;
  }

  static Map<String, Object?> cyclic() {
    final m = <String, Object?>{};
    m['self'] = m;
    return m;
  }

  static Map<String, Object?> wide(int n) => {
    for (var i = 0; i < n; i++) 'key$i': 'value$i',
  };
}

Widget _host(Widget child) => MaterialApp(
  home: Scaffold(body: SizedBox(height: 600, child: child)),
);

void main() {
  group('flattenJson', () {
    test('flattens a map pre-order with parents before descendants', () {
      final nodes = flattenJson(_Data.nested);
      expect(nodes.first.depth, 0);
      expect(nodes.first.kind, JsonKind.map);
      expect(nodes.first.parentId, '');
      final paths = nodes.map((n) => n.path).toList();
      expect(paths, [
        '',
        'data',
        'data.users',
        'data.users[0]',
        'data.users[0].id',
        'data.users[0].name',
      ]);
      for (final n in nodes.skip(1)) {
        final parentIndex = nodes.indexWhere((p) => p.id == n.parentId);
        expect(parentIndex, lessThan(nodes.indexOf(n)));
      }
    });

    test('list root labels elements by index', () {
      final nodes = flattenJson([10, 20]);
      expect(nodes.first.kind, JsonKind.list);
      expect(nodes.map((n) => n.label), ['', '[0]', '[1]']);
      expect(nodes.map((n) => n.path), ['', '[0]', '[1]']);
    });

    test('primitive root is a single leaf', () {
      final nodes = flattenJson(42);
      expect(nodes, hasLength(1));
      expect(nodes.single.kind, JsonKind.leaf);
      expect(nodes.single.valueText, '42');
    });

    test('keys containing dots share a path but keep distinct ids', () {
      final nodes = flattenJson(_Data.collision);
      final leaves = nodes.where((n) => n.path == 'a.b.c').toList();
      expect(leaves, hasLength(2));
      expect(leaves[0].id, isNot(leaves[1].id));
    });

    test('stops at the depth limit', () {
      final nodes = flattenJson(_Data.deep(40));
      expect(nodes.length, lessThan(40));
      expect(
        nodes.where((n) => n.valueText == '… (max depth reached)'),
        isNotEmpty,
      );
    });

    test('detects cycles without hanging', () {
      final nodes = flattenJson(_Data.cyclic());
      expect(nodes, hasLength(2));
      expect(nodes.last.valueText, '… (circular reference)');
      expect(nodes.last.kind, JsonKind.leaf);
    });

    test('a shared child object is not reported as a cycle', () {
      final shared = {'x': 1};
      final nodes = flattenJson({'a': shared, 'b': shared});
      expect(
        nodes.where((n) => n.valueText == '… (circular reference)'),
        isEmpty,
      );
    });

    test('non-JSON values fall back to toString', () {
      final nodes = flattenJson(_Data.mixedTypes);
      String textOf(String label) =>
          nodes.firstWhere((n) => n.label == label).valueText;
      expect(nodes.skip(1).every((n) => n.kind == JsonKind.leaf), isTrue);
      expect(textOf('when'), DateTime.utc(2020).toString());
      expect(textOf('foo'), 'FOO');
      expect(textOf('nothing'), 'null');
      expect(textOf('count'), '7');
      expect(textOf('flag'), 'true');
    });

    test('recognises non-string-keyed maps', () {
      final nodes = flattenJson(<dynamic, dynamic>{
        'a': <dynamic, dynamic>{1: 'x'},
      });
      expect(nodes[1].kind, JsonKind.map);
      expect(nodes[2].path, 'a.1');
    });
  });

  group('JsonTreeViewer', () {
    testWidgets('expands two levels by default', (tester) async {
      await tester.pumpWidget(_host(const JsonTreeViewer(_Data.nested)));
      expect(find.text('data: {1}'), findsOneWidget);
      expect(find.text('users: [1]'), findsOneWidget);
      // depth 3+ starts hidden
      expect(find.text('id: 1'), findsNothing);
    });

    testWidgets('tapping toggles expansion', (tester) async {
      await tester.pumpWidget(_host(const JsonTreeViewer(_Data.nested)));
      await tester.tap(find.text('users: [1]'));
      await tester.pumpAndSettle();
      expect(find.text('[0]: {2}'), findsOneWidget);

      await tester.tap(find.text('users: [1]'));
      await tester.pumpAndSettle();
      expect(find.text('[0]: {2}'), findsNothing);
    });

    testWidgets('leaves offer no expand affordance', (tester) async {
      await tester.pumpWidget(_host(const JsonTreeViewer({'a': 1})));
      final row = tester.widget<JsonNodeRow>(
        find.widgetWithText(JsonNodeRow, 'a: 1'),
      );
      expect(row.onToggle, isNull);
    });

    testWidgets('search keeps hits and their ancestors', (tester) async {
      await tester.pumpWidget(_host(JsonTreeViewer(_Data.searchable)));
      await tester.enterText(find.byType(TextField), 'ANN');
      await tester.pumpAndSettle();

      // The hit plus its ancestor chain (root > data > users > [0] > name).
      expect(find.byType(JsonNodeRow), findsNWidgets(5));
      expect(find.widgetWithText(JsonNodeRow, 'name: ann'), findsOneWidget);
      expect(find.widgetWithText(JsonNodeRow, 'id: 1'), findsNothing);
    });

    testWidgets('clearing search restores the prior collapse state', (
      tester,
    ) async {
      await tester.pumpWidget(_host(JsonTreeViewer(_Data.searchable)));
      await tester.tap(find.text('users: [1]'));
      await tester.pumpAndSettle();
      expect(find.text('[0]: {2}'), findsOneWidget);

      await tester.enterText(find.byType(TextField), 'ann');
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), '');
      await tester.pumpAndSettle();

      expect(find.text('[0]: {2}'), findsOneWidget);
      expect(find.text('id: 1'), findsNothing);
    });

    testWidgets('colliding paths expand independently', (tester) async {
      await tester.pumpWidget(_host(const JsonTreeViewer(_Data.collision)));
      // Both leaves render path 'a.b.c' but live at different depths, so
      // only the shallower one is visible under the default expansion.
      expect(find.text('c: 1'), findsOneWidget);
      expect(find.text('c: 2'), findsNothing);

      // Collapsing 'a.b' must not affect the sibling 'a' > 'b' subtree.
      await tester.tap(find.text('a.b: {1}'));
      await tester.pumpAndSettle();
      expect(find.text('c: 1'), findsNothing);

      await tester.tap(find.text('b: {1}'));
      await tester.pumpAndSettle();
      expect(find.text('c: 2'), findsOneWidget);
      expect(find.text('c: 1'), findsNothing);
    });

    testWidgets('highlights matches only while searching', (tester) async {
      await tester.pumpWidget(_host(JsonTreeViewer(_Data.searchable)));
      expect(find.byType(RichText), findsWidgets);
      await tester.enterText(find.byType(TextField), 'user');
      await tester.pumpAndSettle();

      final rich = tester
          .widgetList<Text>(find.byType(Text))
          .firstWhere(
            (t) =>
                t.textSpan != null &&
                '${t.textSpan?.toPlainText()}'.contains('users'),
          );
      final span = rich.textSpan;
      expect(span, isA<TextSpan>());
      expect((span as TextSpan).children, hasLength(greaterThan(1)));
      expect(
        span.children?.any(
          (c) => c is TextSpan && c.style?.backgroundColor != null,
        ),
        isTrue,
      );
    });

    testWidgets('long press copies path and value', (tester) async {
      String? copied;
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async {
          if (call.method == 'Clipboard.setData') {
            copied = (call.arguments as Map)['text'] as String?;
          }
          return null;
        },
      );

      await tester.pumpWidget(_host(const JsonTreeViewer(_Data.nested)));
      await tester.tap(find.text('users: [1]'));
      await tester.pumpAndSettle();
      await tester.longPress(find.text('[0]: {2}'));
      await tester.pumpAndSettle();

      expect(copied, 'data.users[0]: {2}');
    });

    testWidgets('shows emptyLabel for null data', (tester) async {
      await tester.pumpWidget(
        _host(const JsonTreeViewer(null, emptyLabel: '(no data)')),
      );
      expect(find.text('(no data)'), findsOneWidget);
      expect(find.byType(TextField), findsNothing);
    });

    testWidgets('shows emptyLabel for an empty container', (tester) async {
      await tester.pumpWidget(
        _host(const JsonTreeViewer(<String, Object?>{}, emptyLabel: '(none)')),
      );
      expect(find.text('(none)'), findsOneWidget);
    });

    testWidgets('builds only visible rows for a large payload', (tester) async {
      await tester.pumpWidget(_host(JsonTreeViewer(_Data.wide(1000))));
      expect(flattenJson(_Data.wide(1000)), hasLength(1001));
      expect(tester.widgetList(find.byType(JsonNodeRow)).length, lessThan(200));
    });

    testWidgets('rebuilds when data changes', (tester) async {
      await tester.pumpWidget(_host(const JsonTreeViewer({'a': 1})));
      expect(find.text('a: 1'), findsOneWidget);
      await tester.pumpWidget(_host(const JsonTreeViewer({'b': 2})));
      await tester.pumpAndSettle();
      expect(find.text('a: 1'), findsNothing);
      expect(find.text('b: 2'), findsOneWidget);
    });

    testWidgets('hides the search field for a small tree', (tester) async {
      await tester.pumpWidget(_host(const JsonTreeViewer(_Data.nested)));
      expect(find.byType(TextField), findsNothing);
      expect(find.text('users: [1]'), findsOneWidget);
    });

    testWidgets('shows the search field once the tree is large', (
      tester,
    ) async {
      await tester.pumpWidget(_host(JsonTreeViewer(_Data.wide(20))));
      expect(find.byType(TextField), findsOneWidget);
    });

    testWidgets('drops a stale query when new data hides the field', (
      tester,
    ) async {
      await tester.pumpWidget(_host(JsonTreeViewer(_Data.wide(30))));
      await tester.enterText(find.byType(TextField), 'key7');
      await tester.pumpAndSettle();
      expect(find.text('key1: value1'), findsNothing);

      // Shrinking below the threshold removes the field, so the query must
      // go with it or the tree stays filtered with no way to clear it.
      await tester.pumpWidget(_host(const JsonTreeViewer(_Data.nested)));
      await tester.pumpAndSettle();
      expect(find.byType(TextField), findsNothing);
      expect(find.text('users: [1]'), findsOneWidget);
    });
  });
}
