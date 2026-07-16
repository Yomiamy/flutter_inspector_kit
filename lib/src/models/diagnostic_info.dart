import 'package:flutter/foundation.dart';

/// Device and app metadata shown in the header of a diagnostic report.
///
/// Every field is nullable: the report prints `N/A` for whatever the host does
/// not supply, so a partially-populated (or entirely absent) source still
/// produces a complete report.
@immutable
class DiagnosticInfo {
  /// Creates diagnostic info. Any field may be omitted.
  const DiagnosticInfo({this.appVersion, this.deviceModel, this.osVersion});

  /// Host app version, e.g. `2.3.1+45`.
  final String? appVersion;

  /// Device model identifier, e.g. `iPhone15,2`.
  final String? deviceModel;

  /// Operating system and version, e.g. `iOS 17.4`.
  final String? osVersion;

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is DiagnosticInfo &&
        other.appVersion == appVersion &&
        other.deviceModel == deviceModel &&
        other.osVersion == osVersion;
  }

  @override
  int get hashCode => Object.hash(appVersion, deviceModel, osVersion);

  @override
  String toString() => 'DiagnosticInfo($appVersion, $deviceModel, $osVersion)';
}

/// Supplies device and app metadata for diagnostic reports.
///
/// This package has zero dependency on `device_info_plus` / `package_info_plus`
/// (and never touches `dart:io`, keeping the package WASM-compatible). Hosts
/// that want a populated report header implement this and pass it to
/// `FlutterInspector(diagnosticInfoSource: ...)`; without one, the header
/// degrades to `N/A`.
abstract class DiagnosticInfoSource {
  /// Collects the current device and app metadata.
  Future<DiagnosticInfo> collect();
}
