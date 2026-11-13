import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:dio/io.dart';
import 'package:flutter/foundation.dart';

import '../core/flutter_inspector.dart';

/// The overrides this isolate installed; also the once-per-isolate guard.
_InspectorHttpOverrides? _installed;

/// Chains an inspector layer onto the global `HttpOverrides` slot, once per
/// isolate.
///
/// Never restored or set to `null`: the slot is shared, so a later host
/// override simply replaces this layer and the host keeps working.
void installHttpClientCapture(FlutterInspector inspector) {
  if (_installed != null) {
    if (kDebugMode) {
      debugPrint(
        'flutter_inspector_kit: captureHttpClient is already active in this '
        'isolate; this inspector will not capture HttpClient traffic.',
      );
    }
    return;
  }
  // `current` is `zone value ?? global`; read the global slot itself so a
  // zone override is never promoted to apply outside its zone.
  final previous = Zone.root.run(() => HttpOverrides.current);
  final overrides = _InspectorHttpOverrides(previous);
  _installed = overrides;
  HttpOverrides.global = overrides;
}

/// Whether a request from [dio] will pass the layer that strips the marker:
/// this isolate's layer is the current one and [dio] uses
/// `IOHttpClientAdapter`. It proves this for [dio] only, not for whichever
/// Dio actually sends the request.
bool shouldTagDioRequest(Dio? dio) =>
    _installed != null &&
    identical(HttpOverrides.current, _installed) &&
    dio?.httpClientAdapter is IOHttpClientAdapter;

/// Forgets the install guard. Tests restore `HttpOverrides.global` themselves.
@visibleForTesting
void resetHttpClientCaptureForTesting() => _installed = null;

class _InspectorHttpOverrides extends HttpOverrides {
  _InspectorHttpOverrides(this._previous);

  final HttpOverrides? _previous;

  @override
  HttpClient createHttpClient(SecurityContext? context) =>
      _previous?.createHttpClient(context) ?? super.createHttpClient(context);

  // SDK reads this through HttpOverrides.current, so the host's proxy
  // settings would be lost without forwarding it.
  @override
  String findProxyFromEnvironment(Uri url, Map<String, String>? environment) =>
      _previous?.findProxyFromEnvironment(url, environment) ??
      super.findProxyFromEnvironment(url, environment);
}
