import 'package:flutter/material.dart';

/// Design System Border Radius
/// Following the established radius system: small: 8, medium: 12, large: 16
class AppRadius {
  AppRadius._();

  // Radius values
  static const double small = 8.0;   // Small components, buttons
  static const double medium = 12.0; // Cards, containers
  static const double large = 16.0;  // Modals, sheets, large cards
  static const double xlarge = 24.0; // Bottom sheets, dialogs

  // Radius objects for convenience
  static const BorderRadius smallRadius = BorderRadius.all(Radius.circular(small));
  static const BorderRadius mediumRadius = BorderRadius.all(Radius.circular(medium));
  static const BorderRadius largeRadius = BorderRadius.all(Radius.circular(large));
  static const BorderRadius xlargeRadius = BorderRadius.all(Radius.circular(xlarge));

  // Component-specific radius
  static const BorderRadius buttonRadius = smallRadius;
  static const BorderRadius cardRadius = mediumRadius;
  static const BorderRadius modalRadius = largeRadius;
  static const BorderRadius bottomSheetRadius = BorderRadius.only(
    topLeft: Radius.circular(xlarge),
    topRight: Radius.circular(xlarge),
  );

  // Image radius
  static const BorderRadius imageRadius = mediumRadius;
  static const BorderRadius avatarRadius = BorderRadius.all(Radius.circular(32.0));

  // Input field radius
  static const BorderRadius inputRadius = smallRadius;

  // Chip radius
  static const BorderRadius chipRadius = BorderRadius.all(Radius.circular(20.0));
}