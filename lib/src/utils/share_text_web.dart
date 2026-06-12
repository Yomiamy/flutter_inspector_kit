import 'dart:js_interop';

import 'package:web/web.dart' as web;

/// Shares [text] through the browser Web Share API.
///
/// Throws when the browser does not expose `navigator.share` (e.g. insecure
/// contexts or older desktop browsers); callers are expected to fall back to
/// the clipboard.
Future<void> shareText(String text) async {
  await web.window.navigator.share(web.ShareData(text: text)).toDart;
}
