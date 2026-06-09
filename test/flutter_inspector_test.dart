import 'package:flutter_inspector/flutter_inspector.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('FlutterInspector', () {
    test('can be instantiated', () {
      const inspector = FlutterInspector();
      expect(inspector, isA<FlutterInspector>());
    });

    test('exposes the package version', () {
      expect(FlutterInspector.version, '0.0.1');
    });
  });
}
