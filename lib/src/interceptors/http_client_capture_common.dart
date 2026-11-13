import 'package:dio/dio.dart';

import '../core/flutter_inspector.dart';

/// Header the Dio interceptor adds so the HttpClient layer skips requests Dio
/// already records. The layer removes it before the headers are sent.
const String kDioMarkerHeader = 'x-flutter-inspector-dio';

/// Value of [kDioMarkerHeader]; Dio drops null header values.
const String kDioMarkerValue = '1';

// `_io` and `_web` must both match these (CLAUDE.md invariant #4);
// test/interceptors/http_client_capture_signature_test.dart checks both.
typedef InstallHttpClientCapture = void Function(FlutterInspector inspector);
typedef ShouldTagDioRequest = bool Function(Dio? dio);
typedef ResetHttpClientCapture = void Function();
