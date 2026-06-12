import 'package:share_plus/share_plus.dart';

/// Shares [text] through the platform share sheet.
Future<void> shareText(String text) async {
  await SharePlus.instance.share(ShareParams(text: text));
}
