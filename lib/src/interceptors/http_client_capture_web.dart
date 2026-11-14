import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import '../core/flutter_inspector.dart';

/// Web has no `dart:io` HttpClient: the flag is accepted and ignored.
void installHttpClientCapture(FlutterInspector inspector) {}

/// Never tag on web: nothing would strip the marker before it is sent.
bool shouldTagDioRequest(Dio? dio) => false;

/// No state to reset on web.
@visibleForTesting
void resetHttpClientCaptureForTesting() {}
