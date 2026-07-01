import 'package:flutter_inspector_kit/src/inspectors/navigator_stack_resolver.dart';
import 'package:flutter_inspector_kit/src/models/navigator_action.dart';
import 'package:flutter_inspector_kit/src/models/navigator_entry.dart';
import 'package:flutter_test/flutter_test.dart';

// Dummy widget types to distinguish routes in tests.
class ScreenA {}

class ScreenB {}

class ScreenC {}

void main() {
  late NavigatorStackResolver resolver;

  setUp(() {
    resolver = NavigatorStackResolver();
  });

  // 1. empty input -> empty stack
  test('returns empty list for empty input', () {
    expect(resolver.resolve([]), isEmpty);
  });

  // 2. single push A -> single layer, top == A
  test('single push yields one-element stack', () {
    final a = NavigatorEntry(
      action: NavigatorAction.push,
      routeName: '/a',
      widgetType: ScreenA,
    );

    // Input is newest-first; single entry is trivial.
    final result = resolver.resolve([a]);

    expect(result, hasLength(1));
    expect(result[0].routeName, '/a');
    expect(result[0].widgetType, ScreenA);
  });

  // 3. push A then push B -> top-first == [B, A]
  test('two pushes yield top-first [B, A]', () {
    final a = NavigatorEntry(
      action: NavigatorAction.push,
      routeName: '/a',
      widgetType: ScreenA,
    );
    final b = NavigatorEntry(
      action: NavigatorAction.push,
      routeName: '/b',
      widgetType: ScreenB,
    );

    // Chronological: push A, push B. Newest-first input: [B, A].
    final result = resolver.resolve([b, a]);

    expect(result, hasLength(2));
    expect(result[0].routeName, '/b');
    expect(result[1].routeName, '/a');
  });

  // 4. push A, push B, pop -> [A]
  test('push A, push B, pop removes top, leaving [A]', () {
    final a = NavigatorEntry(
      action: NavigatorAction.push,
      routeName: '/a',
      widgetType: ScreenA,
    );
    final b = NavigatorEntry(
      action: NavigatorAction.push,
      routeName: '/b',
      widgetType: ScreenB,
    );
    final pop = NavigatorEntry(action: NavigatorAction.pop);

    // Chronological: push A, push B, pop. Newest-first: [pop, B, A].
    final result = resolver.resolve([pop, b, a]);

    expect(result, hasLength(1));
    expect(result[0].routeName, '/a');
  });

  // 5. push A, pop, pop (extra pop on empty) -> empty, no crash
  test('extra pop on empty stack is a no-op, no crash', () {
    final a = NavigatorEntry(
      action: NavigatorAction.push,
      routeName: '/a',
      widgetType: ScreenA,
    );
    final pop1 = NavigatorEntry(action: NavigatorAction.pop);
    final pop2 = NavigatorEntry(action: NavigatorAction.pop);

    // Chronological: push A, pop, pop. Newest-first: [pop2, pop1, A].
    final result = resolver.resolve([pop2, pop1, a]);

    expect(result, isEmpty);
  });

  // 6. push A, replace B -> [B] (depth unchanged, identity swapped)
  test('replace swaps top identity, depth unchanged', () {
    final a = NavigatorEntry(
      action: NavigatorAction.push,
      routeName: '/a',
      widgetType: ScreenA,
    );
    final replaceB = NavigatorEntry(
      action: NavigatorAction.replace,
      routeName: '/b',
      widgetType: ScreenB,
    );

    // Chronological: push A, replace B. Newest-first: [replaceB, A].
    final result = resolver.resolve([replaceB, a]);

    expect(result, hasLength(1));
    expect(result[0].routeName, '/b');
    expect(result[0].widgetType, ScreenB);
  });

  // 7. push A, push B, replace C -> [C, A]
  test('replace only affects top, leaves lower layers intact', () {
    final a = NavigatorEntry(
      action: NavigatorAction.push,
      routeName: '/a',
      widgetType: ScreenA,
    );
    final b = NavigatorEntry(
      action: NavigatorAction.push,
      routeName: '/b',
      widgetType: ScreenB,
    );
    final replaceC = NavigatorEntry(
      action: NavigatorAction.replace,
      routeName: '/c',
      widgetType: ScreenC,
    );

    // Chronological: push A, push B, replace C. Newest-first: [replaceC, B, A].
    final result = resolver.resolve([replaceC, b, a]);

    expect(result, hasLength(2));
    expect(result[0].routeName, '/c');
    expect(result[1].routeName, '/a');
  });

  // 8. replace on empty stack degrades to push
  test('replace on empty stack degrades to push', () {
    final replaceA = NavigatorEntry(
      action: NavigatorAction.replace,
      routeName: '/a',
      widgetType: ScreenA,
    );

    final result = resolver.resolve([replaceA]);

    expect(result, hasLength(1));
    expect(result[0].routeName, '/a');
  });

  // 9. push A, push B, push C, remove B -> [C, A]
  test('remove extracts a non-top layer by match', () {
    final a = NavigatorEntry(
      action: NavigatorAction.push,
      routeName: '/a',
      widgetType: ScreenA,
    );
    final b = NavigatorEntry(
      action: NavigatorAction.push,
      routeName: '/b',
      widgetType: ScreenB,
    );
    final c = NavigatorEntry(
      action: NavigatorAction.push,
      routeName: '/c',
      widgetType: ScreenC,
    );
    final removeB = NavigatorEntry(
      action: NavigatorAction.remove,
      routeName: '/b',
      widgetType: ScreenB,
    );

    // Chronological: push A, push B, push C, remove B.
    // Newest-first: [removeB, C, B, A].
    final result = resolver.resolve([removeB, c, b, a]);

    expect(result, hasLength(2));
    expect(result[0].routeName, '/c');
    expect(result[0].widgetType, ScreenC);
    expect(result[1].routeName, '/a');
    expect(result[1].widgetType, ScreenA);
  });

  // 10. remove a route not present -> stack unchanged
  test('remove of absent route is a no-op', () {
    final a = NavigatorEntry(
      action: NavigatorAction.push,
      routeName: '/a',
      widgetType: ScreenA,
    );
    final removeZ = NavigatorEntry(
      action: NavigatorAction.remove,
      routeName: '/z',
      widgetType: int,
    );

    // Chronological: push A, remove Z. Newest-first: [removeZ, A].
    final result = resolver.resolve([removeZ, a]);

    expect(result, hasLength(1));
    expect(result[0].routeName, '/a');
  });

  // 11. duplicate same route stacked twice, remove -> only topmost removed
  test('remove only strips the topmost matching duplicate', () {
    final a1 = NavigatorEntry(
      action: NavigatorAction.push,
      routeName: '/dup',
      widgetType: ScreenA,
    );
    final a2 = NavigatorEntry(
      action: NavigatorAction.push,
      routeName: '/dup',
      widgetType: ScreenA,
    );
    final c = NavigatorEntry(
      action: NavigatorAction.push,
      routeName: '/c',
      widgetType: ScreenC,
    );
    final removeDup = NavigatorEntry(
      action: NavigatorAction.remove,
      routeName: '/dup',
      widgetType: ScreenA,
    );

    // Chronological: push a1, push a2, push c, remove dup.
    // Stack before remove: [a1, a2, c] (bottom-to-top).
    // Remove scans from top: c doesn't match, a2 matches -> removed.
    // Stack after: [a1, c] (bottom-to-top).
    // Newest-first input: [removeDup, c, a2, a1].
    final result = resolver.resolve([removeDup, c, a2, a1]);

    // Output top-first: [c, a1].
    expect(result, hasLength(2));
    expect(result[0].routeName, '/c');
    expect(result[0].widgetType, ScreenC);
    expect(result[1].routeName, '/dup');
    expect(result[1].widgetType, ScreenA);
  });
}
