/// Platform-adaptive `dart:io` HttpClient capture.
///
/// Native platforms chain an `HttpOverrides` layer; web builds resolve to a
/// no-op stub so the package's web import graph stays free of `dart:io`.
library;

export 'http_client_capture_common.dart';
export 'http_client_capture_io.dart'
    if (dart.library.js_interop) 'http_client_capture_web.dart';
