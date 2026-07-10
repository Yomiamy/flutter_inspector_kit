import 'package:flutter/widgets.dart';

import 'theme_spacing.dart';

/// Padding tokens — named `padding<axis><value>`: All, H(orizontal), V(ertical).
class ThemePadding {
  static const EdgeInsets paddingAll8 = EdgeInsets.all(ThemeSpacing.spacing8);
  static const EdgeInsets paddingAll12 = EdgeInsets.all(ThemeSpacing.spacing12);
  static const EdgeInsets paddingAll16 = EdgeInsets.all(ThemeSpacing.spacing16);
  static const EdgeInsets paddingH8 =
      EdgeInsets.symmetric(horizontal: ThemeSpacing.spacing8);
  static const EdgeInsets paddingH16V8 = EdgeInsets.symmetric(
    horizontal: ThemeSpacing.spacing16,
    vertical: ThemeSpacing.spacing8,
  );
}
