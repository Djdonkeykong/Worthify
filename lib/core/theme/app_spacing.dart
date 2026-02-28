/// Design System Spacing
/// Following the established spacing system: [4, 8, 16, 24, 32, 48]
class AppSpacing {
  AppSpacing._();

  // Base spacing unit
  static const double xs = 4.0;   // Extra small
  static const double sm = 8.0;   // Small
  static const double md = 16.0;  // Medium (default)
  static const double lg = 24.0;  // Large
  static const double xl = 32.0;  // Extra large
  static const double xxl = 48.0; // Extra extra large

  // Semantic spacing
  static const double padding = md;      // Default padding (16)
  static const double margin = md;       // Default margin (16)
  static const double listPadding = md;  // List padding (16)
  static const double cardPadding = md;  // Card internal padding (16)
  static const double sectionSpacing = lg; // Between sections (24)
  static const double pageMargin = lg;   // Page margins (24)

  // Component-specific spacing
  static const double buttonPadding = md;
  static const double iconSpacing = sm;
  static const double textSpacing = xs;
  static const double elementSpacing = sm;
  static const double groupSpacing = lg;

  // Layout spacing
  static const double safeAreaPadding = md;
  static const double bottomSheetPadding = lg;
  static const double modalPadding = lg;
  static const double dialogPadding = lg;
}