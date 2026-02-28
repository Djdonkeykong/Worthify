import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:video_player/video_player.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../../../core/theme/app_colors.dart';
import '../../../../../core/theme/theme_extensions.dart';
import '../../../../services/analytics_service.dart';
import '../../../../shared/widgets/worthify_back_button.dart';
import '../../../../../src/shared/services/video_preloader.dart';
import '../widgets/onboarding_bottom_bar.dart';
import 'trial_reminder_page.dart';
import 'save_progress_page.dart';
import '../../../../../shared/navigation/main_navigation.dart';
import '../../../../services/revenuecat_service.dart';
import '../../../../services/onboarding_state_service.dart';
import '../../../../services/superwall_service.dart';
import '../../../../services/subscription_sync_service.dart';

class TrialIntroPage extends ConsumerStatefulWidget {
  const TrialIntroPage({super.key});

  @override
  ConsumerState<TrialIntroPage> createState() => _TrialIntroPageState();
}

class _TrialIntroPageState extends ConsumerState<TrialIntroPage>
    with WidgetsBindingObserver {
  VideoPlayerController? get _controller =>
      VideoPreloader.instance.trialVideoController;
  bool _isEligibleForTrial = true;
  bool _isCheckingEligibility = true;

  @override
  void initState() {
    super.initState();
    AnalyticsService().trackOnboardingScreen('onboarding_trial_intro');
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      // Update checkpoint for authenticated users
      final userId = Supabase.instance.client.auth.currentUser?.id;
      if (userId != null) {
        try {
          await OnboardingStateService().updateCheckpoint(
            userId,
            OnboardingCheckpoint.trial,
          );
        } catch (e) {
          debugPrint('[TrialIntro] Error updating checkpoint: $e');
        }
      }

      // Check trial eligibility first
      await _checkTrialEligibility();

      await VideoPreloader.instance.preloadTrialVideo();
      // Preload bell video for next page
      VideoPreloader.instance.preloadBellVideo();
      if (mounted) {
        setState(() {});
        // Ensure video plays when returning to this page
        VideoPreloader.instance.playTrialVideo();
      }
    });
  }

  Future<void> _checkTrialEligibility() async {
    try {
      final isEligible = await RevenueCatService().isEligibleForTrial().timeout(
        const Duration(seconds: 10),
        onTimeout: () {
          debugPrint(
              '[TrialIntro] Trial eligibility check timed out - defaulting to eligible');
          return true;
        },
      );
      if (mounted) {
        setState(() {
          _isEligibleForTrial = isEligible;
          _isCheckingEligibility = false;
        });

        // If not eligible, present paywall directly
        if (!isEligible && mounted) {
          final userId = Supabase.instance.client.auth.currentUser?.id;
          final didPurchase = await SuperwallService().presentPaywall(
            placement: 'onboarding_paywall',
          );

          if (!mounted) return;

          if (didPurchase && userId != null) {
            // User purchased - sync subscription and navigate
            debugPrint('[TrialIntro] Purchase completed - syncing subscription');

            try {
              await Future.delayed(const Duration(milliseconds: 500));
              await SubscriptionSyncService().syncSubscriptionToSupabase();
              await OnboardingStateService().markPaymentComplete(userId);
            } catch (e) {
              debugPrint('[TrialIntro] Error syncing subscription: $e');
            }

            if (mounted) {
              // Check if user has completed onboarding before
              final userResponse = await Supabase.instance.client
                  .from('users')
                  .select('onboarding_state')
                  .eq('id', userId)
                  .maybeSingle();

              final hasCompletedOnboarding =
                  userResponse?['onboarding_state'] == 'completed';

              debugPrint('[TrialIntro] Has completed onboarding: $hasCompletedOnboarding');

              if (hasCompletedOnboarding) {
                // Returning user - go directly to home
                Navigator.of(context).pushAndRemoveUntil(
                  MaterialPageRoute(
                    builder: (context) => const MainNavigation(
                      key: ValueKey('fresh-main-nav'),
                    ),
                  ),
                  (route) => false,
                );
              } else {
                // New user - create account first
                Navigator.of(context).pushReplacement(
                  MaterialPageRoute(
                    builder: (context) => const SaveProgressPage(),
                  ),
                );
              }
            }
          } else {
            // User dismissed paywall - show trial eligibility again
            if (mounted) {
              setState(() {
                _isEligibleForTrial = true;
              });
            }
          }
        }
      }
    } catch (e) {
      debugPrint('[TrialIntro] Error checking trial eligibility: $e');
      if (mounted) {
        setState(() {
          _isEligibleForTrial = true; // Default to showing trial on error
          _isCheckingEligibility = false;
        });
      }
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    VideoPreloader.instance.pauseTrialVideo();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    if (state == AppLifecycleState.resumed) {
      // Resume video when app comes back to foreground
      VideoPreloader.instance.playTrialVideo();
    } else if (state == AppLifecycleState.paused) {
      // Pause video when app goes to background
      VideoPreloader.instance.pauseTrialVideo();
    }
  }

  @override
  Widget build(BuildContext context) {
    final spacing = context.spacing;
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        elevation: 0,
        scrolledUnderElevation: 0,
        leading: WorthifyBackButton(
          enableHaptics: true,
          backgroundColor: colorScheme.surface,
          iconColor: colorScheme.onSurface,
        ),
        centerTitle: true,
        title: const SizedBox.shrink(),
      ),
      body: Padding(
        padding: EdgeInsets.symmetric(horizontal: spacing.l),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(height: spacing.l),

            // Main heading
            Text(
              'We want you to\ntry Worthify for free',
              textAlign: TextAlign.start,
              style: TextStyle(
                fontSize: 34,
                fontFamily: 'PlusJakartaSans',
                letterSpacing: -1.0,
                fontWeight: FontWeight.bold,
                color: colorScheme.onSurface,
                height: 1.3,
              ),
            ),

            SizedBox(height: spacing.xl),

            // Video player with slight seek to avoid initial flash
            Expanded(
              child: Align(
                alignment: Alignment.bottomCenter,
                child: FractionallySizedBox(
                  widthFactor: 0.92,
                  child: _controller != null &&
                          VideoPreloader.instance.isTrialVideoInitialized
                      ? Container(
                          decoration: BoxDecoration(
                            color: colorScheme.surface,
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(16),
                            child: Center(
                              child: AspectRatio(
                                aspectRatio: _controller!.value.aspectRatio,
                                child: VideoPlayer(_controller!),
                              ),
                            ),
                          ),
                        )
                      : Container(
                          decoration: BoxDecoration(
                            color: colorScheme.surface,
                            borderRadius: BorderRadius.circular(16),
                          ),
                        ),
                ),
              ),
            ),
          ],
        ),
      ),
      bottomNavigationBar: OnboardingBottomBar(
        primaryButton: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Price prominently displayed
            Text(
              '\$41.99/year after 3-day free trial',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.bold,
                fontFamily: 'PlusJakartaSans',
                color: colorScheme.onSurface,
                letterSpacing: -0.2,
              ),
            ),
            const SizedBox(height: 16),
            // Start free trial button
            SizedBox(
              width: double.infinity,
              height: 56,
              child: ElevatedButton(
                onPressed: () {
                  HapticFeedback.mediumImpact();
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (context) => const TrialReminderPage(),
                    ),
                  );
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.secondary,
                  foregroundColor: Colors.white,
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(28),
                  ),
                ),
                child: const Text(
                  'Start free trial',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    fontFamily: 'PlusJakartaSans',
                    letterSpacing: -0.2,
                  ),
                ),
              ),
            ),
          ],
        ),
        secondaryButton: Align(
          alignment: Alignment.center,
          child: Text(
            'Cancel anytime during trial. \$3.49/mo.',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 14,
              color: colorScheme.onSurfaceVariant,
              fontFamily: 'PlusJakartaSans',
              fontWeight: FontWeight.w500,
              height: 1.5,
            ),
          ),
        ),
      ),
    );
  }
}
