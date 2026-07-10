import 'package:flutter/widgets.dart';

import 'theme_color.dart';

/// Text-style tokens shared across the inspector UI.
class ThemeTextStyle {
  static const TextStyle monospaceStyle = TextStyle(
    fontFamily: 'monospace',
    fontSize: 12,
  );
  static const TextStyle boldStyle = TextStyle(fontWeight: FontWeight.bold);
  static const TextStyle mutedStyle = TextStyle(color: ThemeColor.color9E9E9E);
  static const TextStyle mutedSmallStyle = TextStyle(
    color: ThemeColor.color9E9E9E,
    fontSize: 12,
  );
}
