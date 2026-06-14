import 'package:flutter_inspector_kit/flutter_inspector_kit.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('FlutterInspector', () {
    test('can be instantiated', () {
      final inspector = FlutterInspector();
      expect(inspector, isA<FlutterInspector>());
    });

    test('exposes the package version', () {
      expect(FlutterInspector.version, '0.2.2');
    });
  });
}
