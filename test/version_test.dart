import 'dart:io';

import 'package:flutter_inspector_kit/src/version.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Release version consistency across all four canonical files', () {
    String? pubspecVersion;

    setUpAll(() {
      final lines = File('pubspec.yaml').readAsLinesSync();
      for (final line in lines) {
        if (line.startsWith('version:')) {
          pubspecVersion = line.split(':').last.trim();
          break;
        }
      }
    });

    test('pubspec.yaml specifies a valid semantic version', () {
      expect(
        pubspecVersion,
        isNotNull,
        reason: 'pubspec.yaml must define a "version:" entry',
      );
      expect(
        pubspecVersion,
        isNotEmpty,
        reason: 'pubspec.yaml must define a non-empty version',
      );
      final semverPattern = RegExp(
        r'^(0|[1-9]\d*)\.(0|[1-9]\d*)\.(0|[1-9]\d*)'
        r'(?:-((?:0|[1-9]\d*|[0-9a-zA-Z-]*[a-zA-Z-][0-9a-zA-Z-]*)(?:\.(?:0|[1-9]\d*|[0-9a-zA-Z-]*[a-zA-Z-][0-9a-zA-Z-]*))*))?'
        r'(?:\+([0-9a-zA-Z-]+(?:\.[0-9a-zA-Z-]+)*))?$',
      );
      expect(
        semverPattern.hasMatch(pubspecVersion!),
        isTrue,
        reason: 'pubspec.yaml version "$pubspecVersion" must follow semver',
      );
    });

    test('lib/src/version.dart matches pubspec.yaml version', () {
      expect(
        packageVersion,
        pubspecVersion,
        reason:
            'packageVersion in lib/src/version.dart ("$packageVersion") '
            'must match pubspec.yaml version ("$pubspecVersion")',
      );
    });

    test(
      'README.md dependency installation example matches pubspec.yaml version',
      () {
        final readme = File('README.md').readAsStringSync();
        final match = RegExp(
          r'flutter_inspector_kit:\s*\^([^\s\n]+)',
        ).firstMatch(readme);
        expect(
          match,
          isNotNull,
          reason:
              'README.md must specify flutter_inspector_kit dependency installation',
        );
        final readmeVersion = match!.group(1);
        expect(
          readmeVersion,
          pubspecVersion,
          reason:
              'README.md dependency installation version ("$readmeVersion") '
              'must match pubspec.yaml version ("$pubspecVersion")',
        );
      },
    );

    test('CHANGELOG.md top release header matches pubspec.yaml version', () {
      final lines = File('CHANGELOG.md').readAsLinesSync();
      String? latestVersionHeader;
      for (final line in lines) {
        final trimmed = line.trim();
        if (trimmed.startsWith('## ')) {
          latestVersionHeader = trimmed.substring(3).trim();
          break;
        }
      }
      expect(
        latestVersionHeader,
        pubspecVersion,
        reason:
            'CHANGELOG.md top release section ("## $latestVersionHeader") '
            'must match pubspec.yaml version ("## $pubspecVersion")',
      );
    });
  });
}
