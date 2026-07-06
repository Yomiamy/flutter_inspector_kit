import 'package:flutter/material.dart';
import '../models/log_level.dart';

extension LogLevelColor on LogLevel {
  Color get color {
    switch (this) {
      case LogLevel.verbose:
      case LogLevel.debug:
        return Colors.blueGrey;
      case LogLevel.info:
        return Colors.blue;
      case LogLevel.warning:
        return Colors.orange;
      case LogLevel.error:
        return Colors.red;
    }
  }
}
