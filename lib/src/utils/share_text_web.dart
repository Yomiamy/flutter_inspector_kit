import 'dart:js_interop';

import 'package:web/web.dart' as web;

/// Shares [text] through the browser Web Share API.
///
/// Throws when the browser does not expose `navigator.share` (e.g. insecure
/// contexts or older desktop browsers); callers are expected to fall back to
/// the clipboard. Dismissing the share sheet rejects with `AbortError`,
/// which is a cancel rather than a failure, so it is swallowed here to keep
/// the caller's clipboard fallback for real failures only.
Future<void> shareText(String text) async {
  try {
    await web.window.navigator.share(web.ShareData(text: text)).toDart;
  } on web.DOMException catch (e) {
    if (e.name == 'AbortError') return;
    rethrow;
  }
}
