import 'package:flutter/widgets.dart';
import '../models/log_level.dart';
import '../ui/theme/theme.dart';

extension LogLevelColor on LogLevel {
  Color get color {
    switch (this) {
      case LogLevel.verbose:
      case LogLevel.debug:
        return ThemeColor.color9E9E9E;
      case LogLevel.info:
        return ThemeColor.color2196F3;
      case LogLevel.warning:
        return ThemeColor.colorFF9800;
      case LogLevel.error:
        return ThemeColor.colorF44336;
    }
  }
}
