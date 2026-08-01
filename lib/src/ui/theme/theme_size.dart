/// Core size tokens (spacing, radius, dimensions).
///
/// Naming convention: the numeric value goes straight into the name
/// (`space8`, `radius8`, `size44`).
abstract final class ThemeSize {
  // ────────────────────────────────────────────
  // 間距 (Spacing)
  // ────────────────────────────────────────────
  static const double zero = 0;
  static const double space2 = 2.0;
  static const double space4 = 4.0;
  static const double space8 = 8.0;
  static const double space12 = 12.0;
  static const double space16 = 16.0;

  // ────────────────────────────────────────────
  // 圓角 (Radius)
  // ────────────────────────────────────────────
  static const double radius4 = 4.0;
  static const double radius8 = 8.0;

  // ────────────────────────────────────────────
  // 尺寸 (Dimensions)
  // ────────────────────────────────────────────
  static const double size16 = 16.0; // inline action icon
  static const double size18 = 18.0; // small inline spinner / action icon
  static const double size20 = 20.0; // cell / status spinner
  static const double size44 = 44.0; // chip rows, tab strips
  static const double size48 = 48.0; // large status icon (error card)
  static const double size56 = 56.0; // method badge width
  static const double size72 = 72.0; // error summary banner height
  static const double size120 = 120.0; // detail-section label column
  static const double size140 = 140.0; // key-value key column, card width
}
