import 'package:flutter/material.dart';

class InspectorTheme {
  // Spacing (SizedBox heights/widths)
  static const double spacingXs = 4.0;
  static const double spacingSm = 8.0;
  static const double spacingMd = 12.0;
  static const double spacingLg = 16.0;
  static const double spacingXl = 24.0;

  // Border radii
  static const double radiusSm = 4.0;

  // Paddings
  static const EdgeInsets paddingXs = EdgeInsets.all(spacingXs);
  static const EdgeInsets paddingSm = EdgeInsets.all(spacingSm);
  static const EdgeInsets paddingMd = EdgeInsets.all(spacingMd);
  static const EdgeInsets paddingLg = EdgeInsets.all(spacingLg);
  static const EdgeInsets paddingXl = EdgeInsets.all(spacingXl);

  static const EdgeInsets paddingSmHorizontal = EdgeInsets.symmetric(
    horizontal: spacingSm,
  );
  static const EdgeInsets paddingMdHorizontal = EdgeInsets.symmetric(
    horizontal: spacingMd,
  );
  static const EdgeInsets paddingLgHorizontal = EdgeInsets.symmetric(
    horizontal: spacingLg,
  );

  static const EdgeInsets paddingSmVertical = EdgeInsets.symmetric(
    vertical: spacingSm,
  );
  static const EdgeInsets paddingLgHorizontalSmVertical = EdgeInsets.symmetric(
    horizontal: spacingLg,
    vertical: spacingSm,
  );
  static const EdgeInsets paddingLgHorizontalMdVertical = EdgeInsets.symmetric(
    horizontal: spacingLg,
    vertical: spacingMd,
  );
  static const EdgeInsets paddingMdHorizontalSmVertical = EdgeInsets.symmetric(
    horizontal: spacingMd,
    vertical: spacingSm,
  );

  // Colors
  static const Color textMuted = Colors.grey;
  static const Color errorColor = Colors.red;
  static const Color warningColor = Colors.orange;
  static const Color infoColor = Colors.blue;
  static const Color successColor = Colors.green;
  static const Color dividerColor = Colors.grey;

  // Status Colors (mapped from HTTP status codes)
  static Color statusColor(int? statusCode, {bool hasError = false}) {
    if (hasError && statusCode == null) return errorColor;
    if (statusCode == null) return textMuted;
    if (statusCode >= 500) return errorColor;
    if (statusCode >= 400) return warningColor;
    if (statusCode >= 300) return infoColor;
    if (statusCode >= 200) return successColor;
    return textMuted;
  }

  // Text Styles
  static const TextStyle monospaceStyle = TextStyle(
    fontFamily: 'monospace',
    fontSize: 12,
  );
  static const TextStyle boldStyle = TextStyle(fontWeight: FontWeight.bold);
  static const TextStyle mutedStyle = TextStyle(color: textMuted);
  static const TextStyle mutedSmallStyle = TextStyle(
    color: textMuted,
    fontSize: 12,
  );
}
