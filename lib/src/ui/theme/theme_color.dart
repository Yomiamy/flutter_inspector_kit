import 'package:flutter/material.dart';

/// Color tokens — hex value in the name; role in the comment.
class ThemeColor {
  static const Color color9E9E9E = Color(0xFF9E9E9E); // grey — muted text
  static const Color colorF44336 = Color(0xFFF44336); // red — error
  static const Color colorFF9800 = Color(0xFFFF9800); // orange — warning
  static const Color color2196F3 = Color(0xFF2196F3); // blue — info
  static const Color color4CAF50 = Color(0xFF4CAF50); // green — success

  /// Maps an HTTP status code to its display color. [hasError] distinguishes
  /// a transport failure (no status code) from a plain pending/unknown request.
  static Color statusColor(int? statusCode, {bool hasError = false}) {
    if (hasError && statusCode == null) return colorF44336;
    if (statusCode == null) return color9E9E9E;
    if (statusCode >= 500) return colorF44336;
    if (statusCode >= 400) return colorFF9800;
    if (statusCode >= 300) return color2196F3;
    if (statusCode >= 200) return color4CAF50;
    return color9E9E9E;
  }
}
