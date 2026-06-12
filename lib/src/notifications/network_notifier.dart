/// Platform-adaptive network notification support.
///
/// Native platforms use `flutter_local_notifications`; web builds resolve to
/// a no-op stub so the package's web import graph stays free of `dart:io`
/// (keeps the package WASM-compatible). This matches the existing behaviour:
/// the notifier never configured web initialization settings, so the web
/// build has never shown notifications.
library;

export 'network_notifier_io.dart'
    if (dart.library.js_interop) 'network_notifier_web.dart';
