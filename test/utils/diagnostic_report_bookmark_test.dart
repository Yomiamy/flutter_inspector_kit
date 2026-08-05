import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_inspector_kit/src/utils/diagnostic_report.dart';
import 'package:flutter_inspector_kit/src/inspectors/log_inspector.dart';
import 'package:flutter_inspector_kit/src/models/log_entry.dart';
import 'package:flutter_inspector_kit/src/models/log_level.dart';
import 'package:flutter_inspector_kit/src/models/network_entry.dart';
import 'package:flutter_inspector_kit/src/models/navigator_entry.dart';
import 'package:flutter_inspector_kit/src/models/navigator_action.dart';
import 'package:flutter_inspector_kit/src/models/database_entry.dart';
import 'package:flutter_inspector_kit/src/models/database_operation.dart';

void main() {
  group('buildDiagnosticReport with Bookmarks', () {
    test('renders 📌 prefix for bookmarked entries in timeline', () {
      final logInspector = LogInspector(bufferSize: 100);
      final log1 = LogEntry(message: 'Regular log', level: LogLevel.info);
      final log2 = LogEntry(message: 'Important log', level: LogLevel.warning);
      logInspector.add(log1);
      logInspector.add(log2);

      final now = DateTime.now();
      final report = buildDiagnosticReport(
        logInspector: logInspector,
        networkEntries: [],
        navigatorEntries: [],
        databaseEntries: [],
        now: now,
        bookmarkedEntries: {log2},
      );

      expect(report.contains('- 📌 ['), true);
      expect(report.contains('Important log'), true);
      expect(report.contains('- ['), true);
    });

    test('renders 📌 prefix for bookmarked network, navigator, and database entries', () {
      final logInspector = LogInspector(bufferSize: 100);
      final netEntry = NetworkEntry(
        url: 'https://example.com/api',
        method: 'GET',
        statusCode: 200,
        duration: const Duration(milliseconds: 150),
      );
      final navEntry = NavigatorEntry(
        action: NavigatorAction.push,
        routeName: '/details',
      );
      final dbEntry = DatabaseEntry(
        operation: DatabaseOperation.query,
        tableName: 'users',
        affectedRows: 5,
      );

      final now = DateTime.now();
      final report = buildDiagnosticReport(
        logInspector: logInspector,
        networkEntries: [netEntry],
        navigatorEntries: [navEntry],
        databaseEntries: [dbEntry],
        now: now,
        bookmarkedEntries: {netEntry, navEntry, dbEntry},
      );

      expect(report.contains('- 📌 ['), true);
      expect(report.contains('[NET] GET /api → 200 (150ms)'), true);
      expect(report.contains('[NAV] push `/details`'), true);
      expect(report.contains('[DB] query `users` (5 rows)'), true);
    });
  });
}
