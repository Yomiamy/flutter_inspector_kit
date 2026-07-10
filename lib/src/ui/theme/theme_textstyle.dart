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

/// Bare font-size tokens for call sites that build a [TextStyle] via
/// `copyWith` (color varies by context) rather than a fixed style.
class ThemeFontSize {
  static const double fontSize10 = 10.0;
  static const double fontSize11 = 11.0;
  static const double fontSize12 = 12.0;
}
