import 'package:flutter/material.dart';
import '../../../../services/analytics_service.dart';
import '../../../../../core/constants/onboarding_analytics.dart';

mixin ScreenTrackingMixin<T extends StatefulWidget> on State<T>, RouteAware {
  String get screenName;

  void _trackScreenView() {
    // Use enhanced tracking for onboarding screens
    if (OnboardingAnalytics.isOnboardingScreen(screenName)) {
      AnalyticsService().trackOnboardingScreen(screenName);
      final step = OnboardingAnalytics.getStep(screenName);
      debugPrint('[ScreenTracking] Onboarding step ${step?.stepNumber ?? '?'}: $screenName');
    } else {
      AnalyticsService().trackScreenView(screenName);
      debugPrint('[ScreenTracking] Screen viewed: $screenName');
    }
  }

  @override
  void didPush() {
    super.didPush();
    _trackScreenView();
  }

  @override
  void didPopNext() {
    super.didPopNext();
    _trackScreenView();
  }
}
