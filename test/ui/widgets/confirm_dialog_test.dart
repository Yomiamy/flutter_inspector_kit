import 'package:flutter/material.dart';
import 'package:flutter_inspector_kit/src/ui/widgets/confirm_dialog.dart';
import 'package:flutter_test/flutter_test.dart';

/// Pumps a button that opens the dialog and records what it resolved to.
Future<void> pumpHost(
  WidgetTester tester, {
  required List<bool> results,
  bool destructive = false,
  String confirmLabel = 'Confirm',
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) => ElevatedButton(
            onPressed: () async {
              final ok = await showInspectorConfirm(
                context,
                title: 'Clear all',
                message: 'This removes every key.',
                confirmLabel: confirmLabel,
                destructive: destructive,
              );
              results.add(ok);
            },
            child: const Text('open'),
          ),
        ),
      ),
    ),
  );
}

void main() {
  group('showInspectorConfirm', () {
    testWidgets('shows the title and message', (tester) async {
      final results = <bool>[];
      await pumpHost(tester, results: results);

      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      expect(find.text('Clear all'), findsOneWidget);
      expect(find.text('This removes every key.'), findsOneWidget);
    });

    testWidgets('resolves true when confirmed', (tester) async {
      final results = <bool>[];
      await pumpHost(tester, results: results);

      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Confirm'));
      await tester.pumpAndSettle();

      expect(results, [true]);
      expect(find.byType(AlertDialog), findsNothing);
    });

    testWidgets('resolves false when cancelled', (tester) async {
      final results = <bool>[];
      await pumpHost(tester, results: results);

      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();

      expect(results, [false]);
      expect(find.byType(AlertDialog), findsNothing);
    });

    testWidgets('resolves false when dismissed by barrier tap', (tester) async {
      final results = <bool>[];
      await pumpHost(tester, results: results);

      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      // Tap well outside the dialog to hit the modal barrier.
      await tester.tapAt(const Offset(10, 10));
      await tester.pumpAndSettle();

      // Never null: the bool? from showDialog is collapsed inside the helper.
      expect(results, [false]);
    });

    testWidgets('uses a custom confirm label', (tester) async {
      final results = <bool>[];
      await pumpHost(tester, results: results, confirmLabel: 'Delete');

      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      expect(find.text('Delete'), findsOneWidget);
      expect(find.text('Confirm'), findsNothing);
    });

    testWidgets('destructive only recolors, keeping one confirm action', (
      tester,
    ) async {
      final results = <bool>[];
      await pumpHost(tester, results: results, destructive: true);

      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      // Same two actions as the non-destructive case — no extra branch.
      expect(find.widgetWithText(TextButton, 'Cancel'), findsOneWidget);
      expect(find.widgetWithText(TextButton, 'Confirm'), findsOneWidget);

      await tester.tap(find.text('Confirm'));
      await tester.pumpAndSettle();
      expect(results, [true]);
    });
  });
}
