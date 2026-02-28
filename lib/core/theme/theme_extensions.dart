// lib/core/theme/theme_extensions.dart
import 'package:flutter/material.dart';
import 'app_colors.dart';

@immutable
class AppSpacingExtension extends ThemeExtension<AppSpacingExtension> {
  const AppSpacingExtension({
    required this.xs,
    required this.s,
    required this.m,
    required this.l,
    required this.xl,
    required this.xxl,
  });

  final double xs;
  final double s;
  final double m;
  final double l;
  final double xl;
  final double xxl;

  double get sm => s;

  static const AppSpacingExtension standard = AppSpacingExtension(
    xs: 4.0,
    s: 8.0,
    m: 16.0,
    l: 24.0,
    xl: 32.0,
    xxl: 48.0,
  );

  @override
  AppSpacingExtension copyWith({
    double? xs,
    double? s,
    double? m,
    double? l,
    double? xl,
    double? xxl,
  }) {
    return AppSpacingExtension(
      xs: xs ?? this.xs,
      s: s ?? this.s,
      m: m ?? this.m,
      l: l ?? this.l,
      xl: xl ?? this.xl,
      xxl: xxl ?? this.xxl,
    );
  }

  @override
  AppSpacingExtension lerp(AppSpacingExtension? other, double t) {
    if (other is! AppSpacingExtension) return this;
    return AppSpacingExtension(
      xs: xs + (other.xs - xs) * t,
      s: s + (other.s - s) * t,
      m: m + (other.m - m) * t,
      l: l + (other.l - l) * t,
      xl: xl + (other.xl - xl) * t,
      xxl: xxl + (other.xxl - xxl) * t,
    );
  }
}

@immutable
class AppRadiusExtension extends ThemeExtension<AppRadiusExtension> {
  const AppRadiusExtension({
    required this.small,
    required this.medium,
    required this.large,
    required this.full,
  });

  final double small;
  final double medium;
  final double large;
  final double full;

  static const AppRadiusExtension standard = AppRadiusExtension(
    small: 8.0,
    medium: 12.0,
    large: 16.0,
    full: 999.0,   // <--- already set to 999.0
  );

  @override
  AppRadiusExtension copyWith({
    double? small,
    double? medium,
    double? large,
    double? full,
  }) {
    return AppRadiusExtension(
      small: small ?? this.small,
      medium: medium ?? this.medium,
      large: large ?? this.large,
      full: full ?? this.full,
    );
  }

  @override
  AppRadiusExtension lerp(AppRadiusExtension? other, double t) {
    if (other is! AppRadiusExtension) return this;
    return AppRadiusExtension(
      small: small + (other.small - small) * t,
      medium: medium + (other.medium - medium) * t,
      large: large + (other.large - large) * t,
      full: full + (other.full - full) * t,
    );
  }
}

extension ThemeExtensions on BuildContext {
  AppSpacingExtension get spacing => Theme.of(this).extension<AppSpacingExtension>()!;
  AppRadiusExtension get radius => Theme.of(this).extension<AppRadiusExtension>()!;
  TextStyle snackTextStyle({TextStyle? merge}) {
    final theme = Theme.of(this);
    final base = theme.snackBarTheme.contentTextStyle ??
        theme.textTheme.bodyMedium ??
        const TextStyle();
    return merge != null ? base.merge(merge) : base;
  }
}

@immutable
class AppNavigationExtension extends ThemeExtension<AppNavigationExtension> {
  const AppNavigationExtension({
    required this.navBarBackground,
    required this.navBarActiveIcon,
    required this.navBarInactiveIcon,
    required this.navBarBadgeBackground,
    required this.navBarBadgeBorder,
    required this.actionBarBackground,
    required this.actionBarIcon,
    required this.actionBarLabel,
  });

  final Color navBarBackground;
  final Color navBarActiveIcon;
  final Color navBarInactiveIcon;
  final Color navBarBadgeBackground;
  final Color navBarBadgeBorder;
  final Color actionBarBackground;
  final Color actionBarIcon;
  final Color actionBarLabel;

  static const AppNavigationExtension light = AppNavigationExtension(
    navBarBackground: Colors.white,
    navBarActiveIcon: AppColors.secondary,
    navBarInactiveIcon: Colors.black,
    navBarBadgeBackground: Colors.black,
    navBarBadgeBorder: Colors.white,
    actionBarBackground: AppColors.secondary,
    actionBarIcon: Colors.white,
    actionBarLabel: Colors.white,
  );

  static const AppNavigationExtension dark = AppNavigationExtension(
    navBarBackground: Color(0xFF0B0B0D),
    navBarActiveIcon: Color(0xFFF5F7FA),
    navBarInactiveIcon: Color(0xFFC1C6CF),
    navBarBadgeBackground: AppColors.secondary,
    navBarBadgeBorder: Colors.white,
    actionBarBackground: AppColors.secondary,
    actionBarIcon: Colors.white,
    actionBarLabel: Colors.white,
  );

  @override
  AppNavigationExtension copyWith({
    Color? navBarBackground,
    Color? navBarActiveIcon,
    Color? navBarInactiveIcon,
    Color? navBarBadgeBackground,
    Color? navBarBadgeBorder,
    Color? actionBarBackground,
    Color? actionBarIcon,
    Color? actionBarLabel,
  }) {
    return AppNavigationExtension(
      navBarBackground: navBarBackground ?? this.navBarBackground,
      navBarActiveIcon: navBarActiveIcon ?? this.navBarActiveIcon,
      navBarInactiveIcon: navBarInactiveIcon ?? this.navBarInactiveIcon,
      navBarBadgeBackground: navBarBadgeBackground ?? this.navBarBadgeBackground,
      navBarBadgeBorder: navBarBadgeBorder ?? this.navBarBadgeBorder,
      actionBarBackground: actionBarBackground ?? this.actionBarBackground,
      actionBarIcon: actionBarIcon ?? this.actionBarIcon,
      actionBarLabel: actionBarLabel ?? this.actionBarLabel,
    );
  }

  @override
  AppNavigationExtension lerp(AppNavigationExtension? other, double t) {
    if (other is! AppNavigationExtension) return this;
    return AppNavigationExtension(
      navBarBackground: Color.lerp(navBarBackground, other.navBarBackground, t)!,
      navBarActiveIcon: Color.lerp(navBarActiveIcon, other.navBarActiveIcon, t)!,
      navBarInactiveIcon: Color.lerp(navBarInactiveIcon, other.navBarInactiveIcon, t)!,
      navBarBadgeBackground: Color.lerp(navBarBadgeBackground, other.navBarBadgeBackground, t)!,
      navBarBadgeBorder: Color.lerp(navBarBadgeBorder, other.navBarBadgeBorder, t)!,
      actionBarBackground: Color.lerp(actionBarBackground, other.actionBarBackground, t)!,
      actionBarIcon: Color.lerp(actionBarIcon, other.actionBarIcon, t)!,
      actionBarLabel: Color.lerp(actionBarLabel, other.actionBarLabel, t)!,
    );
  }
}

extension NavigationExtensionGetter on BuildContext {
  AppNavigationExtension get navigation =>
      Theme.of(this).extension<AppNavigationExtension>() ?? AppNavigationExtension.light;
}
