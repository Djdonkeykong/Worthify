import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lottie/lottie.dart';
import '../../../../../core/theme/app_colors.dart';
import '../../../../../core/theme/theme_extensions.dart';
import '../../../../services/analytics_service.dart';
import '../../../../../shared/navigation/main_navigation.dart';
import '../../../auth/domain/providers/auth_provider.dart';
import '../../../home/domain/providers/inspiration_provider.dart';
import '../../../paywall/providers/credit_provider.dart';
import '../../../user/repositories/user_profile_repository.dart';
import 'notification_permission_page.dart';
import '../../../../services/onboarding_state_service.dart';
import '../../../../services/notification_service.dart';
import '../../../../shared/services/image_preloader.dart';
import '../widgets/onboarding_bottom_bar.dart';
import '../../domain/providers/onboarding_preferences_provider.dart';
import 'discovery_source_page.dart';

class WelcomeFreeAnalysisPage extends ConsumerStatefulWidget {
  const WelcomeFreeAnalysisPage({super.key});

  @override
  ConsumerState<WelcomeFreeAnalysisPage> createState() =>
      _WelcomeFreeAnalysisPageState();
}

class _WelcomeFreeAnalysisPageState
    extends ConsumerState<WelcomeFreeAnalysisPage>
    with SingleTickerProviderStateMixin {
  Future<void>? _initializationFuture;
  bool _isInitialized = false;
  bool _animationLoaded = false;
  bool _isNavigating = false;
  late AnimationController _textAnimationController;
  late Animation<double> _textFadeAnimation;

  @override
  void initState() {
    super.initState();
    AnalyticsService().trackOnboardingScreen('onboarding_welcome');

    // Precache Lottie animation to prevent jitter
    _precacheLottieAnimation();

    // Initialize user's free analysis
    _initializationFuture = _initializeFreeAnalysis();

    // Setup text fade animation
    _textAnimationController = AnimationController(
      duration: const Duration(milliseconds: 600),
      vsync: this,
    );

    _textFadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _textAnimationController, curve: Curves.easeIn),
    );

    // Start text fade-in after 0.5 seconds
    Future.delayed(const Duration(milliseconds: 500), () {
      if (mounted) {
        _textAnimationController.forward();
      }
    });
  }

  Future<void> _precacheLottieAnimation() async {
    try {
      // Load the Lottie animation into cache
      await rootBundle.load('assets/animations/congratulations.json');
      if (mounted) {
        setState(() {
          _animationLoaded = true;
        });
      }
    } catch (e) {
      print('[WelcomePage] Error precaching animation: $e');
      // Still show the page even if animation fails to load
      if (mounted) {
        setState(() {
          _animationLoaded = true;
        });
      }
    }
  }

  @override
  void dispose() {
    _textAnimationController.dispose();
    super.dispose();
  }

  Future<void> _initializeFreeAnalysis() async {
    try {
      final userId = ref.read(authServiceProvider).currentUser?.id;
      debugPrint('');
      debugPrint('=====================================================');
      debugPrint('[WelcomePage] ==> Starting initialization');
      debugPrint('[WelcomePage] User ID: $userId');
      debugPrint('=====================================================');

      if (userId == null) {
        debugPrint('[WelcomePage] ERROR: No user ID found!');
        if (mounted) setState(() => _isInitialized = true);
        return;
      }

      // Update checkpoint to 'welcome' to mark this stage of onboarding
      debugPrint('[WelcomePage] Updating checkpoint to welcome...');
      try {
        unawaited(OnboardingStateService().updateCheckpoint(
          userId,
          OnboardingCheckpoint.welcome,
        ));
        debugPrint('[WelcomePage] Checkpoint update dispatched');
      } catch (checkpointError) {
        debugPrint('[WelcomePage] Error updating checkpoint: $checkpointError');
        // Non-critical - continue
      }

      // IMPORTANT: If user went through onboarding BEFORE account creation,
      // preferences are stored in providers but NOT saved to database yet.
      // We need to save them now that we have a user ID.

      // Read ALL preferences from providers
      final notificationGranted =
          ref.read(notificationPermissionGrantedProvider);
      final styleDirection = ref.read(styleDirectionProvider);
      final whatYouWant = ref.read(whatYouWantProvider);
      final budget = ref.read(budgetProvider);
      final discoverySource = ref.read(selectedDiscoverySourceProvider);

      // Map DiscoverySource enum to string
      String? discoverySourceString;
      if (discoverySource != null) {
        discoverySourceString = discoverySource.name;
      }

      // Save ALL preferences to database
      debugPrint('');
      debugPrint(
          '[WelcomePage] ===== SAVING ALL PREFERENCES TO DATABASE =====');
      debugPrint('[WelcomePage] User ID: $userId');
      try {
        await OnboardingStateService().saveUserPreferences(
          userId: userId,
          preferredGenderFilter: null,
          notificationEnabled: notificationGranted,
          styleDirection: styleDirection.isNotEmpty ? styleDirection : null,
          whatYouWant: whatYouWant.isNotEmpty ? whatYouWant : null,
          budget: budget,
          discoverySource: discoverySourceString,
        );
        debugPrint('[WelcomePage] SUCCESS: All preferences saved to database');
        debugPrint('[WelcomePage] ==========================================');
      } catch (saveError, stackTrace) {
        debugPrint('[WelcomePage] ERROR saving preferences: $saveError');
        debugPrint('[WelcomePage] Stack trace: $stackTrace');
        debugPrint('[WelcomePage] ==========================================');
        // Non-critical - allow user to continue
      }

      // If notification permission was granted, initialize FCM and register token
      // This needs to happen AFTER account creation so we have a user ID
      if (notificationGranted == true) {
        debugPrint('');
        debugPrint('[WelcomePage] ===== INITIALIZING FCM =====');
        debugPrint(
            '[WelcomePage] Notification permission was granted, initializing FCM...');
        try {
          await NotificationService().initialize();
          debugPrint(
              '[WelcomePage] FCM initialized, now registering token for user...');
          // Also explicitly register token for the new user
          await NotificationService().registerTokenForUser();
          debugPrint(
              '[WelcomePage] SUCCESS: FCM initialized and token registered');
          debugPrint('[WelcomePage] ==============================');
        } catch (fcmError, stackTrace) {
          debugPrint('[WelcomePage] ERROR initializing FCM: $fcmError');
          debugPrint('[WelcomePage] Stack trace: $stackTrace');
          debugPrint('[WelcomePage] ==============================');
          // Non-critical - allow user to continue
        }
      } else {
        debugPrint(
            '[WelcomePage] Skipping FCM initialization (notification permission not granted or null)');
      }

      // Mark onboarding as completed
      print('[WelcomePage] Marking onboarding as completed...');
      try {
        await OnboardingStateService().completeOnboarding(userId);
        print('[WelcomePage] SUCCESS: Onboarding marked as completed');
      } catch (completeError) {
        print('[WelcomePage] ERROR completing onboarding: $completeError');
        // Non-critical - allow user to continue
      }

      // NOTE: Device locale/location tracking disabled
      // The user_profiles table doesn't exist in database
      // Location detection can be added later if needed
      debugPrint(
          '[WelcomePage] Skipping device locale setup (user_profiles table not configured)');

      // Initialize credits (auto-initialized when first accessed)
      print('[WelcomePage] Initializing credits...');
      final creditService = ref.read(creditServiceProvider);
      await creditService.getCreditBalance();
      print('[WelcomePage] Credits initialized');

      // Invalidate credit status to refresh UI
      ref.invalidate(creditBalanceProvider);

      if (mounted) {
        setState(() {
          _isInitialized = true;
        });
      }
      print('[WelcomePage] ==> Initialization complete successfully');
    } catch (e, stackTrace) {
      print('[WelcomePage] CRITICAL ERROR during initialization: $e');
      print('[WelcomePage] Stack trace: $stackTrace');

      if (mounted) {
        // Show error to user
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error saving preferences: ${e.toString()}'),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 5),
          ),
        );

        setState(() {
          _isInitialized = true; // Allow navigation even if there's an error
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final spacing = context.spacing;
    final colorScheme = Theme.of(context).colorScheme;

    return Stack(
      children: [
        Scaffold(
          backgroundColor: Theme.of(context).scaffoldBackgroundColor,
          body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            return SingleChildScrollView(
              child: ConstrainedBox(
                constraints: BoxConstraints(minHeight: constraints.maxHeight),
                child: Padding(
                  padding: EdgeInsets.symmetric(horizontal: spacing.l),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const SizedBox(height: 24),

                      // Only show content after animation is loaded to prevent jitter
                      if (_animationLoaded) ...[
                        _CompletionBadge(),
                      ] else ...[
                        SizedBox(
                          width: 600,
                          height: 600,
                        ),
                      ],

                      FadeTransition(
                        opacity: _textFadeAnimation,
                        child: Transform.translate(
                          offset: const Offset(0, -154),
                          child: Text(
                            'Your fashion search\nstarts now!',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 32,
                              fontWeight: FontWeight.bold,
                              color: colorScheme.onSurface,
                              fontFamily: 'PlusJakartaSans',
                              letterSpacing: -0.5,
                              height: 1.2,
                            ),
                          ),
                        ),
                      ),

                      const SizedBox(height: 24),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      ),
      bottomNavigationBar: OnboardingBottomBar(
        primaryButton: SizedBox(
          width: double.infinity,
          height: 56,
          child: ElevatedButton(
            onPressed: _isNavigating ? null : () async {
              HapticFeedback.mediumImpact();

              setState(() {
                _isNavigating = true;
              });

              // Wait for initialization to complete before navigating
              if (_initializationFuture != null) {
                print(
                    '[WelcomePage] Waiting for initialization to complete...');
                await _initializationFuture;
                print(
                    '[WelcomePage] Initialization finished, navigating to app');
              }

              // CRITICAL: Ensure onboarding is marked as completed before navigating
              // This is a failsafe in case initialization didn't complete properly
              final userId = ref.read(authServiceProvider).currentUser?.id;
              if (userId != null) {
                try {
                  print('[WelcomePage] FAILSAFE: Ensuring onboarding is marked as completed...');
                  await OnboardingStateService().completeOnboarding(userId);
                  print('[WelcomePage] FAILSAFE: Onboarding completion ensured');
                } catch (e) {
                  print('[WelcomePage] FAILSAFE: Error completing onboarding: $e');
                  // Continue anyway - non-critical
                }
              }

              if (mounted) {
                try {
                  await ImagePreloader.instance.preloadHomeAssets(context);
                } catch (e) {
                  debugPrint('[WelcomePage] Failed to preload home assets: $e');
                }

                // Reset to home tab and navigate to main app
                ref.read(selectedIndexProvider.notifier).state = 0;
                ref.invalidate(inspirationProvider);
                Navigator.of(context).pushAndRemoveUntil(
                  MaterialPageRoute(
                    builder: (context) => const MainNavigation(),
                  ),
                  (route) => false,
                );
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFf2003c),
              foregroundColor: Colors.white,
              elevation: 0,
              disabledBackgroundColor: const Color(0xFFf2003c),
              disabledForegroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(28),
              ),
            ),
            child: _isNavigating
                ? const SizedBox(
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                    ),
                  )
                : const Text(
                    'Start Exploring',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      fontFamily: 'PlusJakartaSans',
                      letterSpacing: -0.2,
                    ),
                  ),
          ),
        ),
      ),
        ),
      ],
    );
  }
}

class _CompletionBadge extends StatefulWidget {
  const _CompletionBadge();

  @override
  State<_CompletionBadge> createState() => _CompletionBadgeState();
}

class _CompletionBadgeState extends State<_CompletionBadge> {
  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 600,
      height: 600,
      child: Lottie.asset(
        'assets/animations/congratulations.json',
        repeat: false,
        fit: BoxFit.contain,
        frameRate: FrameRate.max, // Ensure smooth animation
      ),
    );
  }
}
