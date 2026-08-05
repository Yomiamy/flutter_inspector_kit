import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_inspector_kit/src/core/flutter_inspector.dart';
import 'package:flutter_inspector_kit/src/ui/dashboard/tabs/console_tab.dart';

void main() {
  testWidgets('Long press on timeline entry toggles bookmark icon and filters list', (tester) async {
    final inspector = FlutterInspector();
    inspector.log('Test message 1');
    inspector.log('Test message 2');

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: ConsoleTab(inspector: inspector),
      ),
    ));

    expect(find.byIcon(Icons.push_pin), findsNothing);

    // Long press to toggle bookmark
    await tester.longPress(find.text('Test message 1'));
    await tester.pumpAndSettle();

    expect(find.byIcon(Icons.push_pin), findsOneWidget);
    expect(inspector.bookmarkedEntries.length, 1);

    // Tap Bookmarks FilterChip
    await tester.tap(find.text('📌 Bookmarks'));
    await tester.pumpAndSettle();

    expect(find.text('Test message 1'), findsOneWidget);
    expect(find.text('Test message 2'), findsNothing);

    // Toggle bookmark off
    await tester.longPress(find.text('Test message 1'));
    await tester.pumpAndSettle();

    expect(find.text('No bookmarked entries'), findsOneWidget);
  });

  testWidgets('Selecting a source chip restores visibility of non-bookmarked entries', (tester) async {
    final inspector = FlutterInspector();
    inspector.log('Test message 1');
    inspector.log('Test message 2');

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: ConsoleTab(inspector: inspector),
      ),
    ));

    // Toggle bookmark on message 1
    await tester.longPress(find.text('Test message 1'));
    await tester.pumpAndSettle();

    // Enable bookmarks filter
    await tester.tap(find.text('📌 Bookmarks'));
    await tester.pumpAndSettle();

    expect(find.text('Test message 2'), findsNothing);

    // Tap All chip
    await tester.tap(find.text('All'));
    await tester.pumpAndSettle();

    // Verify filter is reset and message 2 is visible again
    expect(find.text('Test message 2'), findsOneWidget);
  });
}
