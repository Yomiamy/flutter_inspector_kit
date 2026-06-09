import 'package:flutter_inspector/src/inspectors/network_inspector.dart';
import 'package:flutter_inspector/src/models/network_entry.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('NetworkInspector', () {
    late NetworkInspector inspector;

    setUp(() {
      inspector = NetworkInspector(bufferCapacity: 3);
    });

    test('adds network entries and returns newest first', () {
      final entry1 = NetworkEntry(method: 'GET', url: '/1');
      final entry2 = NetworkEntry(method: 'POST', url: '/2');

      inspector.add(entry1);
      inspector.add(entry2);

      expect(inspector.entries, [entry2, entry1]);
    });

    test('truncates bodies larger than kNetworkBodyMaxLength', () {
      final longBody = 'a' * (kNetworkBodyMaxLength + 100);
      final entry = NetworkEntry(
          method: 'GET',
          url: '/1',
          requestBody: longBody,
          responseBody: longBody);

      inspector.add(entry);

      final addedEntry = inspector.entries.first;
      expect(addedEntry.requestBody, endsWith(kTruncatedMarker));
      expect(addedEntry.requestBody!.length,
          kNetworkBodyMaxLength + kTruncatedMarker.length);
      expect(addedEntry.responseBody, endsWith(kTruncatedMarker));
    });

    test('clears buffer', () {
      inspector.add(NetworkEntry(method: 'GET', url: '/1'));
      inspector.clear();
      expect(inspector.entries, isEmpty);
    });

    test('onAdd fires with entry and running total', () {
      final calls = <(String, int)>[];
      inspector.onAdd = (entry, total) => calls.add((entry.url, total));

      inspector.add(NetworkEntry(method: 'GET', url: '/1'));
      inspector.add(NetworkEntry(method: 'GET', url: '/2'));

      expect(calls, [('/1', 1), ('/2', 2)]);
    });

    test('no callback wired by default', () {
      // add() must not throw when onAdd is null.
      expect(() => inspector.add(NetworkEntry(method: 'GET', url: '/x')),
          returnsNormally);
    });
  });
}
