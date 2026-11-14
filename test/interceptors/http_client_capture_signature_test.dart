import 'dart:io' show HttpOverrides;

import 'package:dio/dio.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_inspector_kit/src/core/flutter_inspector.dart';
import 'package:flutter_inspector_kit/src/interceptors/http_client_capture_common.dart';
import 'package:flutter_inspector_kit/src/interceptors/http_client_capture_io.dart'
    as io;
import 'package:flutter_inspector_kit/src/interceptors/http_client_capture_web.dart'
    as web;
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('io and web expose the same signatures (invariant #4)', () {
    // Compile-time guard: a drifted signature fails to compile this file.
    const installs = <InstallHttpClientCapture>[
      io.installHttpClientCapture,
      web.installHttpClientCapture,
    ];
    const tags = <ShouldTagDioRequest>[
      io.shouldTagDioRequest,
      web.shouldTagDioRequest,
    ];
    const resets = <ResetHttpClientCapture>[
      io.resetHttpClientCaptureForTesting,
      web.resetHttpClientCaptureForTesting,
    ];
    expect([installs, tags, resets].map((l) => l.length), [2, 2, 2]);
    // Assignability is subtyping: one side gaining an optional parameter
    // still compiles above. Exact runtime types catch that too.
    expect(
      io.installHttpClientCapture.runtimeType,
      web.installHttpClientCapture.runtimeType,
    );
    expect(
      io.shouldTagDioRequest.runtimeType,
      web.shouldTagDioRequest.runtimeType,
    );
    expect(
      io.resetHttpClientCaptureForTesting.runtimeType,
      web.resetHttpClientCaptureForTesting.runtimeType,
    );
  });

  test('web stub does nothing and never tags (5-2)', () {
    final before = HttpOverrides.current;
    web.installHttpClientCapture(
      FlutterInspector(navigatorKey: GlobalKey<NavigatorState>()),
    );
    expect(identical(HttpOverrides.current, before), isTrue);
    expect(web.shouldTagDioRequest(Dio()), isFalse);
  });
}
