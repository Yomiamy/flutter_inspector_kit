import 'package:flutter/widgets.dart';

import 'theme_size.dart';

/// Padding tokens — named `padding<axis><value>`: All, H(orizontal), V(ertical).
class ThemePadding {
  static const EdgeInsets paddingAll8 = EdgeInsets.all(ThemeSize.space8);
  static const EdgeInsets paddingAll12 = EdgeInsets.all(ThemeSize.space12);
  static const EdgeInsets paddingAll16 = EdgeInsets.all(ThemeSize.space16);
  static const EdgeInsets paddingH8 = EdgeInsets.symmetric(
    horizontal: ThemeSize.space8,
  );
  static const EdgeInsets paddingH16V8 = EdgeInsets.symmetric(
    horizontal: ThemeSize.space16,
    vertical: ThemeSize.space8,
  );
}
