/// Onboarding analytics constants for funnel tracking.
///
/// Each screen in the onboarding flow is assigned a step number
/// to enable proper funnel analysis and drop-off tracking in Amplitude.
class OnboardingAnalytics {
  OnboardingAnalytics._();

  /// Ordered list of onboarding screens with their step numbers.
  /// The order reflects the actual user flow through onboarding.
  ///
  /// Flow: How It Works -> Share Your Style -> Add First Style -> Discovery Source
  ///       -> Gender Selection -> Rating Social Proof -> Notification Permission
  ///       -> Create Account -> Trial Intro -> Paywall -> Welcome
  static const Map<String, OnboardingStep> screens = {
    // Main onboarding flow (7 steps with progress indicator)
    'onboarding_how_it_works': OnboardingStep(1, 'How It Works'),
    'onboarding_share_your_style': OnboardingStep(2, 'Share Your Style'),
    'onboarding_add_first_style': OnboardingStep(3, 'Add First Style'),
    'onboarding_tutorial_analysis': OnboardingStep(3, 'Tutorial Analysis'),
    'onboarding_discovery_source': OnboardingStep(4, 'Discovery Source'),
    'onboarding_gender_selection': OnboardingStep(5, 'Gender Selection'),
    'onboarding_rating_social_proof': OnboardingStep(6, 'Rating Social Proof'),
    'onboarding_notification_permission': OnboardingStep(7, 'Notification Permission'),
    // Post-progress-bar screens (account creation and monetization)
    'onboarding_save_progress': OnboardingStep(8, 'Create Account'),
    'onboarding_trial_intro': OnboardingStep(9, 'Trial Intro'),
    'onboarding_trial_reminder': OnboardingStep(10, 'Trial Reminder'),
    'onboarding_paywall': OnboardingStep(11, 'Paywall'),
    'onboarding_welcome': OnboardingStep(12, 'Welcome'),
  };

  /// Tutorial screens (optional branch from step 3)
  static const Map<String, OnboardingStep> tutorialScreens = {
    'onboarding_instagram_tutorial': OnboardingStep(3, 'Instagram Tutorial', isTutorial: true),
    'onboarding_pinterest_tutorial': OnboardingStep(3, 'Pinterest Tutorial', isTutorial: true),
    'onboarding_tiktok_tutorial': OnboardingStep(3, 'TikTok Tutorial', isTutorial: true),
    'onboarding_x_tutorial': OnboardingStep(3, 'X Tutorial', isTutorial: true),
    'onboarding_imdb_tutorial': OnboardingStep(3, 'IMDB Tutorial', isTutorial: true),
    'onboarding_safari_tutorial': OnboardingStep(3, 'Safari Tutorial', isTutorial: true),
    'onboarding_photos_tutorial': OnboardingStep(3, 'Photos Tutorial', isTutorial: true),
  };

  /// Get step info for a screen name, checking both main and tutorial screens.
  static OnboardingStep? getStep(String screenName) {
    return screens[screenName] ?? tutorialScreens[screenName];
  }

  /// Check if a screen name is an onboarding screen.
  static bool isOnboardingScreen(String screenName) {
    return screenName.startsWith('onboarding_');
  }

  /// Total number of main steps in the onboarding flow.
  static const int totalSteps = 12;

  /// Key conversion milestones for funnel analysis.
  static const List<String> conversionMilestones = [
    'onboarding_how_it_works',           // Step 1: Entry
    'onboarding_add_first_style',        // Step 3: Engaged with style upload
    'onboarding_gender_selection',       // Step 5: Selected catalog
    'onboarding_notification_permission', // Step 7: Completed main onboarding
    'onboarding_save_progress',          // Step 8: Created account
    'onboarding_paywall',                // Step 11: Reached paywall
    'onboarding_welcome',                // Step 12: Completed
  ];
}

/// Represents a step in the onboarding flow.
class OnboardingStep {
  final int stepNumber;
  final String displayName;
  final bool isTutorial;

  const OnboardingStep(
    this.stepNumber,
    this.displayName, {
    this.isTutorial = false,
  });
}
