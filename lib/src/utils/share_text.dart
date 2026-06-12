/// Platform-adaptive text sharing.
///
/// Native platforms delegate to `share_plus`; web builds use the browser
/// Web Share API directly so that the package's web import graph stays free
/// of `dart:io` (keeps the package WASM-compatible).
library;

export 'share_text_io.dart' if (dart.library.js_interop) 'share_text_web.dart';
