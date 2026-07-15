import 'package:flutter_inspector_kit/src/models/diagnostic_info.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('DiagnosticInfo', () {
    test('can be constructed with no fields at all', () {
      const info = DiagnosticInfo();
      expect(info.appVersion, isNull);
      expect(info.deviceModel, isNull);
      expect(info.osVersion, isNull);
    });

    test('holds the values it was given', () {
      const info = DiagnosticInfo(
        appVersion: '2.3.1+45',
        deviceModel: 'iPhone15,2',
        osVersion: 'iOS 17.4',
      );
      expect(info.appVersion, '2.3.1+45');
      expect(info.deviceModel, 'iPhone15,2');
      expect(info.osVersion, 'iOS 17.4');
    });

    test('has value equality', () {
      const a = DiagnosticInfo(appVersion: '1.0.0', deviceModel: 'Pixel 8');
      const b = DiagnosticInfo(appVersion: '1.0.0', deviceModel: 'Pixel 8');
      const different = DiagnosticInfo(appVersion: '1.0.1', deviceModel: 'Pixel 8');

      expect(a, equals(b));
      expect(a.hashCode, equals(b.hashCode));
      expect(a, isNot(equals(different)));
    });

    test('a partially populated instance differs from an empty one', () {
      const empty = DiagnosticInfo();
      const partial = DiagnosticInfo(osVersion: 'Android 14');

      expect(partial, isNot(equals(empty)));
    });
  });

  group('DiagnosticInfoSource', () {
    test('a host implementation supplies info through collect()', () async {
      final source = _FakeDiagnosticInfoSource();

      expect(
        await source.collect(),
        const DiagnosticInfo(
          appVersion: '2.3.1+45',
          deviceModel: 'iPhone15,2',
          osVersion: 'iOS 17.4',
        ),
      );
    });
  });
}

class _FakeDiagnosticInfoSource implements DiagnosticInfoSource {
  @override
  Future<DiagnosticInfo> collect() async => const DiagnosticInfo(
    appVersion: '2.3.1+45',
    deviceModel: 'iPhone15,2',
    osVersion: 'iOS 17.4',
  );
}
