import 'package:flutter/material.dart';

/// Worthify Design System Colors
/// Gallery minimal — off-white backgrounds, near-black text, no accent color yet
class AppColors {
  AppColors._();

  // Primary Colors (Off-white gallery scale)
  static const Color primary = Color(0xFFF9F8F7); // Gallery off-white
  static const Color primaryLight = Color(0xFFFFFFFF); // Pure white
  static const Color primaryDark = Color(0xFFEFEFED); // Light surface gray

  // Secondary Colors (Near-black — used for CTAs, active states)
  static const Color secondary = Color(0xFF1C1B1A); // Near-black CTA
  static const Color secondaryLight = Color(0xFF3A3936); // Lighter dark
  static const Color secondaryDark = Color(0xFF0D0D0C); // Deeper black

  // Black accent
  static const Color black = Color(0xFF1C1B1A); // Near black (not pure)
  static const Color blackLight = Color(0xFF3A3936); // Lighter black
  static const Color blackDark = Color(0xFF0D0D0C); // Deeper black

  // Tertiary Colors
  static const Color tertiary = Color(0xFF4A4845); // Mid charcoal
  static const Color tertiaryLight = Color(0xFF6B6966); // Lighter charcoal
  static const Color tertiaryDark = Color(0xFF2A2927); // Darker charcoal

  // Neutral Colors (Gallery surfaces)
  static const Color surface = Color(0xFFFFFFFF); // Pure white cards
  static const Color surfaceVariant = Color(0xFFEFEFED); // Light gray surface
  static const Color background = Color(0xFFF9F8F7); // Off-white background
  static const Color outline = Color(0xFFE2E0DD); // Warm light border
  static const Color outlineVariant = Color(0xFFEEECE9); // Even lighter border

  // Text Colors
  static const Color onSurface = Color(0xFF1C1B1A); // Primary text
  static const Color onSurfaceVariant = Color(0xFF6B6966); // Secondary text
  static const Color onBackground = Color(0xFF1C1B1A); // Background text
  static const Color textPrimary = onSurface;
  static const Color textSecondary = Color(0xFF6B6966); // Muted text
  static const Color textTertiary = Color(0xFF9C9A97); // Captions
  static const Color textDisabled = Color(0xFFCECCC9); // Disabled

  // Icon Colors
  static const Color iconPrimary = Color(0xFF1C1B1A);

  // State Colors
  static const Color error = Color(0xFFEF4444);
  static const Color errorContainer = Color(0xFFFEF2F2);
  static const Color onError = Color(0xFFFFFFFF);
  static const Color onErrorContainer = Color(0xFF991B1B);

  static const Color success = Color(0xFF22C55E);
  static const Color successContainer = Color(0xFFF0FDF4);
  static const Color warning = Color(0xFFF59E0B);
  static const Color warningContainer = Color(0xFFFFFBEB);

  // Overlay Colors
  static const Color scrim = Color(0x80000000);
  static const Color shadow = Color(0x1A000000);

  // Component-specific Colors
  static const Color cardBackground = surface;
  static const Color bottomSheetBackground = surface;
  static const Color appBarBackground = Color(0xFFF9F8F7);

  // Navigation Colors
  static const Color navigationBackground = Color(0xFFF9F8F7);
  static const Color navigationSelected = secondary; // Near-black for active
  static const Color navigationUnselected = Color(0xFF9C9A97); // Muted gray

  // Art category placeholder colors
  static const Color categoryPainting = Color(0xFFEDE8E3);
  static const Color categoryDrawing = Color(0xFFE8ECF0);
  static const Color categorySculpture = Color(0xFFECEBE8);
  static const Color categoryPhotography = Color(0xFFE8E8EC);
  static const Color categoryPrint = Color(0xFFECE8EC);
}
