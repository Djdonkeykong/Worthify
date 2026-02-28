import 'package:flutter/material.dart';

const lightColorScheme = ColorScheme(
  brightness: Brightness.light,
  primary: Color(0xFFF9F8F7), // Gallery off-white
  onPrimary: Color(0xFF1C1B1A), // Near-black text on white
  primaryContainer: Color(0xFFEFEFED), // Light surface gray
  onPrimaryContainer: Color(0xFF1C1B1A),
  secondary: Color(0xFF1C1B1A), // Near-black CTA
  onSecondary: Color(0xFFF9F8F7), // Off-white text on dark
  secondaryContainer: Color(0xFF3A3936), // Lighter dark container
  onSecondaryContainer: Color(0xFFF9F8F7),
  tertiary: Color(0xFF4A4845), // Mid charcoal
  onTertiary: Color(0xFFFFFFFF),
  tertiaryContainer: Color(0xFFEFEFED),
  onTertiaryContainer: Color(0xFF1C1B1A),
  error: Color(0xFFEF4444),
  onError: Color(0xFFFFFFFF),
  errorContainer: Color(0xFFFEF2F2),
  onErrorContainer: Color(0xFF7F1D1D),
  surface: Color(0xFFFFFFFF), // Pure white surface
  onSurface: Color(0xFF1C1B1A), // Near-black text
  surfaceContainerHighest: Color(0xFFEFEFED),
  onSurfaceVariant: Color(0xFF6B6966),
  outline: Color(0xFFE2E0DD),
  outlineVariant: Color(0xFFEEECE9),
  shadow: Color(0xFF000000),
  scrim: Color(0xFF000000),
  inverseSurface: Color(0xFF1C1B1A),
  onInverseSurface: Color(0xFFF9F8F7),
  inversePrimary: Color(0xFF3A3936),
  surfaceVariant: Color(0xFFEFEFED),
);

const darkColorScheme = ColorScheme(
  brightness: Brightness.dark,
  primary: Color(0xFF0F0E0D), // Near-black background
  onPrimary: Color(0xFFF5F3F0), // Warm off-white text
  primaryContainer: Color(0xFF1A1917), // Dark surface
  onPrimaryContainer: Color(0xFFF5F3F0),
  secondary: Color(0xFFEFEDEA), // Light CTA on dark
  onSecondary: Color(0xFF1C1B1A),
  secondaryContainer: Color(0xFF2A2927),
  onSecondaryContainer: Color(0xFFF5F3F0),
  tertiary: Color(0xFF2A2927),
  onTertiary: Color(0xFFF5F3F0),
  tertiaryContainer: Color(0xFF1A1917),
  onTertiaryContainer: Color(0xFFF5F3F0),
  error: Color(0xFFEF4444),
  onError: Color(0xFFFFFFFF),
  errorContainer: Color(0xFF3A0B12),
  onErrorContainer: Color(0xFFF5D7DB),
  surface: Color(0xFF1A1917),
  onSurface: Color(0xFFF5F3F0),
  surfaceContainerHighest: Color(0xFF2A2927),
  onSurfaceVariant: Color(0xFFB8B5B1),
  outline: Color(0xFF3A3936),
  outlineVariant: Color(0xFF2A2927),
  shadow: Color(0xFF000000),
  scrim: Color(0xFF000000),
  inverseSurface: Color(0xFFF5F3F0),
  onInverseSurface: Color(0xFF0F0E0D),
  inversePrimary: Color(0xFFEFEDEA),
  surfaceVariant: Color(0xFF2A2927),
);
