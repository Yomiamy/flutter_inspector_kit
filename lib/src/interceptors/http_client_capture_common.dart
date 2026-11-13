import 'package:dio/dio.dart';

import '../core/flutter_inspector.dart';

/// Header the Dio interceptor adds so the HttpClient layer skips requests Dio
/// already records. The layer removes it before the headers are sent.
const String kDioMarkerHeader = 'x-flutter-inspector-dio';

/// Live `RequestOptions.headers` of tagged Dio requests, keyed by marker token.
///
/// The HttpClient layer takes the marker back out of the live map as soon as
/// headers are sent, before any response or error interceptor can see it and
/// resend it elsewhere. Values are weak so an orphaned token never keeps a
/// request's headers alive.
final Map<String, WeakReference<Map<String, dynamic>>> liveDioMarkers = {};

var _markerSeq = 0;
const int _kMarkerPruneAt = 64;

/// Registers [headers] under a fresh token and returns the token.
String registerDioMarker(Map<String, dynamic> headers) {
  // Orphans only appear when Dio skips the interceptor's onResponse/onError
  // (an earlier interceptor resolving without following ones); prune lazily.
  if (liveDioMarkers.length >= _kMarkerPruneAt) {
    liveDioMarkers.removeWhere((_, ref) => ref.target == null);
  }
  final token = '${++_markerSeq}';
  liveDioMarkers[token] = WeakReference(headers);
  return token;
}

// `_io` and `_web` must both match these (CLAUDE.md invariant #4);
// test/interceptors/http_client_capture_signature_test.dart checks both.
typedef InstallHttpClientCapture = void Function(FlutterInspector inspector);
typedef ShouldTagDioRequest = bool Function(Dio? dio);
typedef ResetHttpClientCapture = void Function();
