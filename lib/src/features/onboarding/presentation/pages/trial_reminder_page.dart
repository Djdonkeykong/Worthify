import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lottie/lottie.dart';
import '../../../../../core/theme/app_colors.dart';
import '../../../../../core/theme/theme_extensions.dart';
import '../../../../services/analytics_service.dart';
import '../../../../shared/widgets/worthify_back_button.dart';
import '../widgets/onboarding_bottom_bar.dart';
import '../../../../../shared/navigation/main_navigation.dart';
import '../../../../services/revenuecat_service.dart';
import '../../../../services/superwall_service.dart';
import '../../../../services/subscription_sync_service.dart';
import '../../../../services/onboarding_state_service.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'save_progress_page.dart';

class TrialReminderPage extends ConsumerStatefulWidget {
  const TrialReminderPage({super.key});

  @override
  ConsumerState<TrialReminderPage> createState() => _TrialReminderPageState();
}

class _TrialReminderPageState extends ConsumerState<TrialReminderPage> {
  bool _isEligibleForTrial = true;
  bool _isCheckingEligibility = true;
  bool _isPresenting = false;

  @override
  void initState() {
    super.initState();
    AnalyticsService().trackOnboardingScreen('onboarding_trial_reminder');
    WidgetsBinding.instance.addPostFrameCallback((_) {
      // Update checkpoint
      final userId = Supabase.instance.client.auth.currentUser?.id;
      if (userId != null) {
        OnboardingStateService().updateCheckpoint(
          userId,
          OnboardingCheckpoint.trialReminder,
        );
      }
      // Check trial eligibility
      _checkTrialEligibility();
    });
  }

  Future<void> _checkTrialEligibility() async {
    try {
      final isEligible = await RevenueCatService().isEligibleForTrial();
      if (mounted) {
        setState(() {
          _isEligibleForTrial = isEligible;
          _isCheckingEligibility = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isEligibleForTrial = true;
          _isCheckingEligibility = false;
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
            actions: [
              TextButton(
                onPressed: () async {
                  try {
                    await RevenueCatService().restorePurchases();
                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Purchases restored successfully'),
                          duration: Duration(seconds: 2),
                        ),
                      );
                    }
                  } catch (e) {
                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('No purchases to restore'),
                          duration: Duration(seconds: 2),
                        ),
                      );
                    }
                  }
                },
                child: Text(
                  'Restore',
                  style: TextStyle(
                    color: colorScheme.onSurfaceVariant,
                    fontSize: 14,
                    fontFamily: 'PlusJakartaSans',
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ],
          ),
          body: Padding(
            padding: EdgeInsets.symmetric(horizontal: spacing.l),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(height: spacing.l),

                // Main heading - conditional based on trial eligibility
                Text(
                  _isEligibleForTrial
                      ? 'We\'ll send you a reminder before your free trial ends'
                      : 'Get notified about new styles and deals',
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

                // Spacer to push bell icon to center
                const Spacer(flex: 2),

                // Bell animation
                Center(
                  child: SizedBox(
                    width: 180,
                    height: 180,
                    child: Lottie.asset(
                      'assets/animations/bell.json',
                      fit: BoxFit.contain,
                      repeat: true,
                    ),
                  ),
                ),

                const Spacer(flex: 2),

                SizedBox(height: spacing.l),
              ],
            ),
          ),
          bottomNavigationBar: OnboardingBottomBar(
            primaryButton: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // No Payment Due Now - only show for new users eligible for trial
                if (_isEligibleForTrial) ...[
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.check,
                        color: Colors.green,
                        size: 16,
                      ),
                      SizedBox(width: 8),
                      Text(
                        'No Payment Due Now',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                          fontFamily: 'PlusJakartaSans',
                          color: colorScheme.onSurface,
                          letterSpacing: -0.2,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                ],
                // Button with conditional text
                SizedBox(
                  width: double.infinity,
                  height: 56,
                  child: ElevatedButton(
                    onPressed: () async {
                      HapticFeedback.mediumImpact();

                      setState(() {
                        _isPresenting = true;
                      });

                      try {
                        final userId =
                            Supabase.instance.client.auth.currentUser?.id;
                        final didPurchase =
                            await SuperwallService().presentPaywall(
                          placement: 'onboarding_paywall',
                          params: const {
                            'occurrence': 1,
                            'source': 'trial_reminder',
                          },
                        );

                        if (!mounted) return;

                        setState(() {
                          _isPresenting = false;
                        });

                        if (didPurchase && userId != null) {
                          // User purchased - sync subscription and navigate to welcome or home
                          debugPrint(
                              '[TrialReminder] Purchase completed - syncing subscription');

                          try {
                            await Future.delayed(
                                const Duration(milliseconds: 500));
                            await SubscriptionSyncService()
                                .syncSubscriptionToSupabase();
                            await OnboardingStateService()
                                .markPaymentComplete(userId);
                          } catch (e) {
                            debugPrint(
                                '[TrialReminder] Error syncing subscription: $e');
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

                            debugPrint(
                                '[TrialReminder] Has completed onboarding: $hasCompletedOnboarding');

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
                                  builder: (context) =>
                                      const SaveProgressPage(),
                                ),
                              );
                            }
                          }
                        }
                        // If user dismissed without purchasing, stay on this page.
                      } catch (e) {
                        debugPrint(
                            '[TrialReminder] Error presenting paywall: $e');
                        if (mounted) {
                          setState(() {
                            _isPresenting = false;
                          });
                        }
                      }
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.secondary,
                      foregroundColor: Colors.white,
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(28),
                      ),
                    ),
                    child: Text(
                      _isEligibleForTrial ? 'Continue for FREE' : 'See plans',
                      style: const TextStyle(
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
          ),
        ),
        if (_isPresenting)
          Container(
            color: colorScheme.scrim.withOpacity(0.3),
            child: Center(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(20),
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 20.0, sigmaY: 20.0),
                  child: Container(
                    width: 80,
                    height: 80,
                    decoration: BoxDecoration(
                      color: colorScheme.surface.withOpacity(0.9),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Center(
                      child: const SizedBox(
                        width: 32,
                        height: 32,
                        child: CircularProgressIndicator(
                          color: AppColors.secondary,
                          strokeWidth: 2,
                        ),
                      ),
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
