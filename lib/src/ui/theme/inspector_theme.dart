import 'package:flutter/material.dart';

/// Design tokens for the inspector UI.
///
/// Naming convention: the numeric value goes straight into the name
/// (`spacing8`, `radius4`, `size20`, `colorF44336`) so a token needs no
/// lookup table to read — the name *is* the value. Roles/semantics live in
/// the trailing comment, not the name, since the same unit often serves
/// different purposes across pages.
class InspectorTheme {
  // Spacing (SizedBox heights/widths, gaps)
  static const double spacing4 = 4.0;
  static const double spacing8 = 8.0;
  static const double spacing12 = 12.0;
  static const double spacing16 = 16.0;

  // Border radii (shared corner scale)
  static const double radius4 = 4.0;
  static const double radius8 = 8.0;

  // Component sizes — fixed width/height units shared across pages so layout
  // dimensions have a single source of truth. The same unit may serve
  // different roles per page; comments list current uses, not a contract.
  static const double size18 = 18.0; // small inline spinner / action icon
  static const double size20 = 20.0; // cell / status spinner
  static const double size44 = 44.0; // chip rows, tab strips
  static const double size56 = 56.0; // method badge width
  static const double size72 = 72.0; // error summary banner height
  static const double size120 = 120.0; // detail-section label column
  static const double size140 = 140.0; // key-value key column, card width

  // Paddings — named <axis><value>: A=all, H=horizontal, V=vertical.
  static const EdgeInsets paddingAll8 = EdgeInsets.all(spacing8);
  static const EdgeInsets paddingAll12 = EdgeInsets.all(spacing12);
  static const EdgeInsets paddingAll16 = EdgeInsets.all(spacing16);
  static const EdgeInsets paddingH8 = EdgeInsets.symmetric(horizontal: spacing8);
  static const EdgeInsets paddingH16V8 = EdgeInsets.symmetric(
    horizontal: spacing16,
    vertical: spacing8,
  );

  // Colors — hex value in the name; role in the comment.
  static const Color color9E9E9E = Color(0xFF9E9E9E); // grey — muted text
  static const Color colorF44336 = Color(0xFFF44336); // red — error
  static const Color colorFF9800 = Color(0xFFFF9800); // orange — warning
  static const Color color2196F3 = Color(0xFF2196F3); // blue — info
  static const Color color4CAF50 = Color(0xFF4CAF50); // green — success

  // Status Colors (mapped from HTTP status codes)
  static Color statusColor(int? statusCode, {bool hasError = false}) {
    if (hasError && statusCode == null) return colorF44336;
    if (statusCode == null) return color9E9E9E;
    if (statusCode >= 500) return colorF44336;
    if (statusCode >= 400) return colorFF9800;
    if (statusCode >= 300) return color2196F3;
    if (statusCode >= 200) return color4CAF50;
    return color9E9E9E;
  }

  // Text Styles
  static const TextStyle monospaceStyle = TextStyle(
    fontFamily: 'monospace',
    fontSize: 12,
  );
  static const TextStyle boldStyle = TextStyle(fontWeight: FontWeight.bold);
  static const TextStyle mutedStyle = TextStyle(color: color9E9E9E);
  static const TextStyle mutedSmallStyle = TextStyle(
    color: color9E9E9E,
    fontSize: 12,
  );
}
