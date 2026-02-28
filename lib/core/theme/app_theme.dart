// lib/core/theme/app_theme.dart
import 'package:flutter/material.dart';
import 'color_schemes.dart';
import 'text_themes.dart';
import 'theme_extensions.dart';
import 'app_colors.dart';

class AppTheme {
  static ThemeData get lightTheme {
    const colorScheme = lightColorScheme;
    final interTextTheme = AppTextThemes.textTheme;
    final baseSnackTextStyle =
        (interTextTheme.bodyMedium ?? const TextStyle());

    return ThemeData(
      useMaterial3: true,
      colorScheme: colorScheme,
      scaffoldBackgroundColor: AppColors.background,
      canvasColor: colorScheme.surface,
      textTheme: interTextTheme,
      appBarTheme: AppBarTheme(
        backgroundColor: AppColors.appBarBackground,
        foregroundColor: colorScheme.onSurface,
        elevation: 0,
        centerTitle: true,
        iconTheme: IconThemeData(color: colorScheme.onSurface),
        titleTextStyle: interTextTheme.titleMedium?.copyWith(
          color: colorScheme.onSurface,
          fontWeight: FontWeight.w600,
        ),
      ),
      bottomNavigationBarTheme: BottomNavigationBarThemeData(
        backgroundColor: AppColors.navigationBackground,
        selectedItemColor: AppColors.navigationSelected,
        unselectedItemColor: AppColors.navigationUnselected,
        showSelectedLabels: false,
        showUnselectedLabels: false,
        elevation: 0,
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: AppColors.black,
        contentTextStyle: baseSnackTextStyle.copyWith(
          color: Colors.white,
          fontWeight: FontWeight.w500,
        ),
        actionTextColor: AppColors.secondary,
        behavior: SnackBarBehavior.fixed,
        elevation: 0,
      ),
      extensions: const [
        AppSpacingExtension.standard,
        AppRadiusExtension.standard,
        AppNavigationExtension.light,
      ],
    );
  }

  static ThemeData get darkTheme {
    const colorScheme = darkColorScheme;
    final interTextTheme = AppTextThemes.textTheme;
    final baseSnackTextStyle =
        (interTextTheme.bodyMedium ?? const TextStyle());

    return ThemeData(
      useMaterial3: true,
      colorScheme: colorScheme,
      scaffoldBackgroundColor: colorScheme.primary,
      canvasColor: colorScheme.surface,
      textTheme: interTextTheme,
      appBarTheme: AppBarTheme(
        backgroundColor: colorScheme.primary,
        foregroundColor: colorScheme.onSurface,
        elevation: 0,
        centerTitle: true,
        iconTheme: IconThemeData(color: colorScheme.onSurface),
        titleTextStyle: interTextTheme.titleMedium?.copyWith(
          color: colorScheme.onSurface,
          fontWeight: FontWeight.w600,
        ),
      ),
      bottomNavigationBarTheme: BottomNavigationBarThemeData(
        backgroundColor: colorScheme.surface,
        selectedItemColor: colorScheme.secondary,
        unselectedItemColor: colorScheme.onSurfaceVariant,
        showSelectedLabels: false,
        showUnselectedLabels: false,
        elevation: 0,
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: colorScheme.surface,
        contentTextStyle: baseSnackTextStyle.copyWith(
          color: colorScheme.onSurface,
          fontWeight: FontWeight.w500,
        ),
        actionTextColor: AppColors.secondary,
        behavior: SnackBarBehavior.fixed,
        elevation: 0,
      ),
      extensions: const [
        AppSpacingExtension.standard,
        AppRadiusExtension.standard,
        AppNavigationExtension.dark,
      ],
    );
  }
}
