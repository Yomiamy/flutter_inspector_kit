import 'dart:typed_data';

import 'package:flutter_inspector_kit/src/inspectors/network_inspector.dart';
import 'package:flutter_inspector_kit/src/models/network_entry.dart';
import 'package:flutter_inspector_kit/src/utils/image_bytes.dart';
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
        responseBody: longBody,
      );

      inspector.add(entry);

      final addedEntry = inspector.entries.first;
      expect(addedEntry.requestBody, endsWith(kTruncatedMarker));
      expect(
        addedEntry.requestBody!.length,
        kNetworkBodyMaxLength + kTruncatedMarker.length,
      );
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
      expect(
        () => inspector.add(NetworkEntry(method: 'GET', url: '/x')),
        returnsNormally,
      );
    });

    test('add with replaces swaps the pending entry in place', () {
      final other = inspector.add(NetworkEntry(method: 'GET', url: '/other'));
      final pending = inspector.add(NetworkEntry(method: 'GET', url: '/1'));
      final completed = NetworkEntry(
        method: 'GET',
        url: '/1',
        statusCode: 200,
        isComplete: true,
      );

      inspector.add(completed, replaces: pending);

      expect(inspector.entries, [completed, other]);
    });

    test('add with replaces falls back to append when entry was evicted', () {
      final pending = inspector.add(NetworkEntry(method: 'GET', url: '/1'));
      // Capacity is 3 — push the pending entry out of the buffer.
      for (var i = 0; i < 3; i++) {
        inspector.add(NetworkEntry(method: 'GET', url: '/fill$i'));
      }
      final completed = NetworkEntry(
        method: 'GET',
        url: '/1',
        statusCode: 200,
        isComplete: true,
      );

      inspector.add(completed, replaces: pending);

      expect(inspector.entries.first, completed);
      expect(inspector.entries.length, 3);
    });

    test('add returns the stored (possibly truncated) entry', () {
      final longBody = 'a' * (kNetworkBodyMaxLength + 100);
      final stored = inspector.add(
        NetworkEntry(method: 'POST', url: '/1', requestBody: longBody),
      );

      expect(stored.requestBody, endsWith(kTruncatedMarker));
      expect(inspector.entries.first, stored);
    });

    test('a truncated body keeps its real size; a known length is kept', () {
      final long = 'é' * (kNetworkBodyMaxLength + 100); // 2 UTF-8 bytes each

      final stored = inspector.add(
        NetworkEntry(
          method: 'POST',
          url: '/1',
          requestBody: long,
          responseBody: long,
          responseBodyLength: 123456,
        ),
      );

      expect(stored.requestBody, endsWith(kTruncatedMarker));
      expect(stored.requestBodyLength, 2 * long.length);
      expect(stored.requestSizeBytes, 2 * long.length);
      expect(stored.responseSizeBytes, 123456);
    });

    test('a body that fits gets no recorded length', () {
      final stored = inspector.add(
        NetworkEntry(method: 'POST', url: '/1', requestBody: 'abc'),
      );

      expect(stored.requestBodyLength, isNull);
      expect(stored.responseBodyLength, isNull);
      expect(stored.requestSizeBytes, 3);
    });

    test('an oversized summary is not measured as if it were the body', () {
      // A long FormData summary already carries the marker: its own length
      // is not the payload size, so the size stays unknown.
      final summary = '${'field\n' * 2000}$kTruncatedMarker';
      final stored = inspector.add(
        NetworkEntry(method: 'POST', url: '/1', requestBody: summary),
      );

      expect(stored.requestBody, isNot(summary));
      expect(stored.requestBodyLength, isNull);
    });

    test('a cut body is measured in UTF-8 bytes', () {
      // 2-, 3- and 4-byte characters plus a lone surrogate (encoded as
      // U+FFFD, 3 bytes).
      final long = 'é€😀\uD800' * kNetworkBodyMaxLength;
      final stored = inspector.add(
        NetworkEntry(method: 'POST', url: '/1', requestBody: long),
      );

      expect(stored.requestBodyLength, (2 + 3 + 4 + 3) * kNetworkBodyMaxLength);
    });

    test('add with replaces finds a pending entry whose body was cut', () {
      final long = 'a' * (kNetworkBodyMaxLength + 100);
      final pending = inspector.add(
        NetworkEntry(method: 'POST', url: '/1', requestBody: long),
      );
      expect(pending.requestBodyLength, long.length);

      final done = inspector.add(
        NetworkEntry(
          method: 'POST',
          url: '/1',
          requestBody: long,
          statusCode: 200,
          isComplete: true,
        ),
        replaces: pending,
      );

      expect(inspector.entries, [done]);
      expect(done.requestSizeBytes, long.length);
    });

    test('onAdd fires on replace with unchanged total', () {
      final calls = <(String, int)>[];
      inspector.onAdd = (entry, total) => calls.add((entry.url, total));

      final pending = inspector.add(NetworkEntry(method: 'GET', url: '/1'));
      inspector.add(
        NetworkEntry(method: 'GET', url: '/1', isComplete: true),
        replaces: pending,
      );

      expect(calls, [('/1', 1), ('/1', 1)]);
    });

    test('onMutate and onAdd both fire independently', () {
      var mutateCount = 0;
      final addCalls = <String>[];
      final withMutate = NetworkInspector(
        bufferCapacity: 3,
        onMutate: () => mutateCount++,
      )..onAdd = (entry, total) => addCalls.add(entry.url);

      withMutate.add(NetworkEntry(method: 'GET', url: '/1'));

      expect(mutateCount, 1);
      expect(addCalls, ['/1']);
    });
  });

  group('image bytes budget', () {
    const summary = '[image/png, 5.0 MB]$kTruncatedMarker';
    // One shared 5 MB object: the budget sums lengths, so reusing it costs no
    // extra memory. Every url differs so RingBuffer.replace (==) never lands
    // on another entry.
    final png = Uint8List(kImageMaxBytes)
      ..setAll(0, [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]);

    NetworkEntry imageEntry(int i, {Uint8List? bytes}) => NetworkEntry(
      method: 'GET',
      url: '/img/$i',
      responseBody: summary,
      responseImageBytes: bytes ?? png,
      isComplete: true,
    );

    test('keeps kImageMaxBytes, drops one byte more (6-4)', () {
      final net = NetworkInspector();

      final kept = net.add(imageEntry(0));
      final dropped = net.add(
        imageEntry(1, bytes: Uint8List(kImageMaxBytes + 1)),
      );

      expect(kept.responseImageBytes, same(png));
      expect(dropped.responseImageBytes, isNull);
      expect(dropped.responseBody, summary);
      expect(net.entries.first.responseImageBytes, isNull);
      expect(net.entries.last.responseImageBytes, same(png));
    });

    test('drops the oldest preview once the total passes 50 MB (6-5)', () {
      final net = NetworkInspector(bufferCapacity: 20);
      for (var i = 0; i < 10; i++) {
        net.add(imageEntry(i));
      }
      expect(
        net.entries.where((e) => e.responseImageBytes != null),
        hasLength(10),
      );

      net.add(imageEntry(10));

      final oldestFirst = net.entries.reversed.toList();
      expect(oldestFirst, hasLength(11));
      expect(oldestFirst.first.url, '/img/0');
      expect(oldestFirst.first.responseImageBytes, isNull);
      expect(
        oldestFirst.skip(1).every((e) => e.responseImageBytes != null),
        isTrue,
      );
    });

    test('eviction runs outside onMutate and never re-enters it (6-6)', () {
      var inMutate = false;
      var mutations = 0;
      var adds = 0;
      var lastTotal = 0;
      late final NetworkInspector net;
      net = NetworkInspector(
        bufferCapacity: 20,
        onMutate: () {
          expect(inMutate, isFalse, reason: 'onMutate re-entered');
          inMutate = true;
          mutations++;
          // Reading inside onMutate is allowed.
          lastTotal = net.entries.fold(
            0,
            (sum, e) => sum + (e.responseImageBytes?.length ?? 0),
          );
          inMutate = false;
        },
      )..onAdd = (_, _) => adds++;
      for (var i = 0; i < 10; i++) {
        net.add(imageEntry(i));
      }
      mutations = 0;
      adds = 0;

      net.add(imageEntry(10));

      expect(mutations, 2, reason: 'one add, one replace');
      expect(adds, 1);
      expect(lastTotal, lessThanOrEqualTo(kImageBudgetBytes));
    });

    test('a pending entry is replaced in place by one with bytes', () {
      final net = NetworkInspector(bufferCapacity: 20);
      final pending = net.add(NetworkEntry(method: 'GET', url: '/img/p'));
      final newer = net.add(NetworkEntry(method: 'GET', url: '/other'));

      final done = net.add(
        pending.copyWith(
          responseBody: summary,
          responseImageBytes: png,
          isComplete: true,
        ),
        replaces: pending,
      );

      expect(net.entries, [newer, done]);
      expect(net.entries.last.responseImageBytes, same(png));
    });
  });
}
