import 'dart:typed_data';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_inspector_kit/src/core/flutter_inspector.dart';
import 'package:flutter_inspector_kit/src/models/log_entry.dart';
import 'package:flutter_inspector_kit/src/models/log_level.dart';
import 'package:flutter_inspector_kit/src/models/network_entry.dart';

void main() {
  group('FlutterInspector Bookmarks', () {
    test('should toggle bookmark state correctly', () {
      final inspector = FlutterInspector(
        navigatorKey: GlobalKey<NavigatorState>(),
      );
      final entry = LogEntry(message: 'Test log', level: LogLevel.info);

      expect(inspector.isBookmarked(entry), false);
      expect(inspector.bookmarkedEntries, isEmpty);

      inspector.toggleBookmark(entry);
      expect(inspector.isBookmarked(entry), true);
      expect(inspector.bookmarkedEntries.contains(entry), true);

      inspector.toggleBookmark(entry);
      expect(inspector.isBookmarked(entry), false);
      expect(inspector.bookmarkedEntries, isEmpty);
    });

    test('a bookmarked network entry drops its preview bytes but still '
        'matches (outside the 50 MB budget otherwise)', () {
      final inspector = FlutterInspector(
        navigatorKey: GlobalKey<NavigatorState>(),
      );
      final entry = NetworkEntry(
        method: 'GET',
        url: 'https://a.test/i.png',
        responseImageBytes: Uint8List(1024),
        isComplete: true,
      );

      inspector.toggleBookmark(entry);

      expect(inspector.isBookmarked(entry), isTrue);
      expect(
        (inspector.bookmarkedEntries.single as NetworkEntry).responseImageBytes,
        isNull,
      );
      expect(entry.responseImageBytes, isNotNull); // the original is untouched

      inspector.toggleBookmark(entry);
      expect(inspector.bookmarkedEntries, isEmpty);
    });

    test('clearBookmarks and clearLogs should reset bookmarks', () {
      final inspector = FlutterInspector(
        navigatorKey: GlobalKey<NavigatorState>(),
      );
      final entry = LogEntry(message: 'Test log', level: LogLevel.info);
      inspector.toggleBookmark(entry);
      expect(inspector.isBookmarked(entry), true);

      inspector.clearBookmarks();
      expect(inspector.bookmarkedEntries, isEmpty);

      inspector.toggleBookmark(entry);
      inspector.clearLogs();
      expect(inspector.bookmarkedEntries, isEmpty);
    });
  });
}
