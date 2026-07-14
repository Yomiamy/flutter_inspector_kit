import 'dart:io';
import 'package:flutter_inspector_kit/src/version.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('packageVersion matches pubspec.yaml version', () {
    final lines = File('pubspec.yaml').readAsLinesSync();
    String? pubspecVersion;
    for (final line in lines) {
      if (line.trim().startsWith('version:')) {
        pubspecVersion = line.split(':').last.trim();
        break;
      }
    }
    expect(pubspecVersion, isNotNull);
    expect(packageVersion, pubspecVersion);
  });
}
