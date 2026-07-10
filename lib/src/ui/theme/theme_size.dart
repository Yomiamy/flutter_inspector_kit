/// Component-size tokens — fixed width/height units shared across pages so
/// layout dimensions have a single source of truth.
///
/// Naming convention: the numeric value goes straight into the name
/// (`size44`). The same unit may serve different roles per page; comments
/// list current uses, not a contract.
class ThemeSize {
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
