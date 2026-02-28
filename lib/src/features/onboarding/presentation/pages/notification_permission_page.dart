import 'dart:async';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:purchases_flutter/purchases_flutter.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'dart:io' show Platform;
import '../../../../../core/theme/app_colors.dart';
import '../../../../../core/theme/theme_extensions.dart';
import '../../../../services/analytics_service.dart';
import '../../../../shared/widgets/worthify_back_button.dart';
import '../widgets/progress_indicator.dart';
import 'save_progress_page.dart';
import 'trial_intro_page.dart';
import '../../../../../shared/navigation/main_navigation.dart';
import '../../../auth/domain/providers/auth_provider.dart';
import '../../../../services/onboarding_state_service.dart';
import '../../../../services/notification_service.dart';
import '../../../../services/revenuecat_service.dart';
import '../../../../services/paywall_helper.dart';
import '../../../../services/subscription_sync_service.dart';

// Provider to store notification permission choice
final notificationPermissionGrantedProvider =
    StateProvider<bool?>((ref) => null);

class NotificationPermissionPage extends ConsumerStatefulWidget {
  const NotificationPermissionPage({
    super.key,
    this.continueToTrialFlow = false,
  });

  final bool continueToTrialFlow;

  @override
  ConsumerState<NotificationPermissionPage> createState() =>
      _NotificationPermissionPageState();
}

class _NotificationPermissionPageState
    extends ConsumerState<NotificationPermissionPage> {
  bool _isRequesting = false;
  bool _isRouting = false;

  @override
  void initState() {
    super.initState();
    AnalyticsService().trackOnboardingScreen('onboarding_notification_permission');
  }

  /// Save notification preference to database if user is authenticated
  Future<void> _saveNotificationPreference(bool granted) async {
    try {
      final user = ref.read(authServiceProvider).currentUser;
      if (user == null) {
        debugPrint(
            '[NotificationPermission] No authenticated user - preference will be saved later');
        return;
      }

      debugPrint(
          '[NotificationPermission] Saving notification preference: $granted');

      // Save notification preference to database
      await OnboardingStateService().saveUserPreferences(
        userId: user.id,
        notificationEnabled: granted,
      );

      debugPrint(
          '[NotificationPermission] Notification preference saved successfully');
    } catch (e) {
      debugPrint(
          '[NotificationPermission] Error saving notification preference: $e');
      // Non-critical error - allow user to continue
    }
  }

  Future<void> _handleAllow() async {
    if (_isRequesting) return;

    setState(() {
      _isRequesting = true;
    });

    HapticFeedback.mediumImpact();

    try {
      // Check if Firebase is initialized
      bool firebaseReady = false;
      try {
        Firebase.app();
        firebaseReady = true;
      } catch (e) {
        debugPrint('[NotificationPermission] Firebase not initialized: $e');
      }

      bool granted = false;

      if (firebaseReady) {
        // Request notification permission using Firebase Messaging (shows native iOS dialog)
        final settings = await FirebaseMessaging.instance.requestPermission(
          alert: true,
          badge: true,
          sound: true,
          provisional: false,
        );

        granted =
            settings.authorizationStatus == AuthorizationStatus.authorized ||
                settings.authorizationStatus == AuthorizationStatus.provisional;

        debugPrint(
            '[NotificationPermission] Permission requested, granted: $granted');
        debugPrint(
            '[NotificationPermission] Authorization status: ${settings.authorizationStatus}');

        // CRITICAL: Explicitly register for remote notifications with iOS
        // When FirebaseAppDelegateProxyEnabled is false, we must manually trigger this
        if (granted && Platform.isIOS) {
          debugPrint(
              '[NotificationPermission] Explicitly registering for remote notifications on iOS...');
          try {
            const platform = MethodChannel('worthify/notifications');
            await platform.invokeMethod('registerForRemoteNotifications');
            debugPrint(
                '[NotificationPermission] Remote notification registration triggered');

            // Give iOS a moment to generate APNS token, then try to get FCM token
            await Future.delayed(const Duration(milliseconds: 500));

            final token = await FirebaseMessaging.instance.getToken();
            if (token != null) {
              debugPrint('[NotificationPermission] Got FCM token: $token');
            } else {
              debugPrint(
                  '[NotificationPermission] FCM token is null - APNS token may not be available yet');
            }
          } catch (e) {
            debugPrint(
                '[NotificationPermission] Error during notification registration: $e');
            // Token will be registered later when APNS token becomes available
          }
        }
      } else {
        debugPrint(
            '[NotificationPermission] Skipping permission request - Firebase not ready');
      }

      // Store permission result in provider
      ref.read(notificationPermissionGrantedProvider.notifier).state = granted;

      // Non-critical work: run in background so routing is not delayed.
      unawaited(_saveNotificationPreference(granted));
      if (granted && firebaseReady) {
        unawaited(_initializeFcmInBackground());
      }

      _navigateToNextStep();
    } catch (e, stackTrace) {
      debugPrint('[NotificationPermission] Error requesting permission: $e');
      debugPrint('[NotificationPermission] Stack trace: $stackTrace');
      // Default to false on error
      ref.read(notificationPermissionGrantedProvider.notifier).state = false;

      _navigateToNextStep();
    } finally {
      if (mounted) {
        setState(() {
          _isRequesting = false;
        });
      }
    }
  }

  Future<void> _handleDontAllow() async {
    HapticFeedback.mediumImpact();

    debugPrint('[NotificationPermission] User declined permission');

    // Store that permission was denied
    ref.read(notificationPermissionGrantedProvider.notifier).state = false;

    // Non-critical write: do not block navigation.
    unawaited(_saveNotificationPreference(false));

    _navigateToNextStep();
  }

  Future<void> _initializeFcmInBackground() async {
    try {
      await NotificationService().initialize();
      debugPrint('[NotificationPermission] FCM initialized and token registered');
    } catch (e) {
      debugPrint('[NotificationPermission] Error initializing FCM: $e');
    }
  }

  Future<void> _navigateToNextStep() async {
    if (!mounted) return;
    setState(() => _isRouting = true);

    try {
      // Check if user is already authenticated (works for Apple, Google, and Email)
      final user = ref.read(authServiceProvider).currentUser;

      if (user != null) {
        // User is authenticated - skip SaveProgressPage and route based on subscription
        debugPrint(
            '[NotificationPermission] User authenticated - skipping SaveProgressPage');

        // Ensure RevenueCat is identified to this user before checking status/eligibility.
        try {
          await SubscriptionSyncService()
              .identify(user.id)
              .timeout(const Duration(seconds: 4));
        } catch (e) {
          debugPrint('[NotificationPermission] RevenueCat identify error: $e');
        }

        // Update checkpoint
        unawaited(OnboardingStateService().updateCheckpoint(
          user.id,
          OnboardingCheckpoint.notification,
        ));

        // Check subscription status from RevenueCat
        CustomerInfo? customerInfo;
        try {
          customerInfo = await Purchases.getCustomerInfo()
              .timeout(const Duration(seconds: 5));
        } catch (e) {
          debugPrint(
              '[NotificationPermission] Error fetching customer info: $e');
        }

        final activeEntitlements = customerInfo?.entitlements.active.values;
        final hasActiveSubscription =
            activeEntitlements != null && activeEntitlements.isNotEmpty;

        debugPrint(
            '[NotificationPermission] Has active subscription: $hasActiveSubscription');

        if (hasActiveSubscription) {
          // User has subscription - go to home
          debugPrint('[NotificationPermission] Navigating to home');
          if (mounted) {
            Navigator.of(context).pushAndRemoveUntil(
              MaterialPageRoute(
                builder: (context) => const MainNavigation(
                  key: ValueKey('fresh-main-nav'),
                ),
              ),
              (route) => false,
            );
          }
        } else {
          // No subscription:
          // - If user has used trial before, skip TrialIntroPage and go directly to paywall.
          // - Otherwise route to TrialIntroPage.
          bool hasUsedTrialBefore = false;
          try {
            hasUsedTrialBefore = await RevenueCatService()
                .hasUsedFreeTrialBefore()
                .timeout(
                  const Duration(seconds: 5),
                  onTimeout: () {
                    debugPrint(
                        '[NotificationPermission] Trial history check timed out - defaulting to prior-trial path');
                    return true;
                  },
                );
            debugPrint(
                '[NotificationPermission] Has used free trial before: $hasUsedTrialBefore');
          } catch (e) {
            debugPrint(
                '[NotificationPermission] Error checking trial history: $e');
            hasUsedTrialBefore = true;
          }

          if (hasUsedTrialBefore) {
            debugPrint(
                '[NotificationPermission] Prior trial detected - presenting Superwall paywall');

            // Determine whether this is a returning user who already completed onboarding.
            bool isReturningUser = false;
            try {
              final userResponse = await Supabase.instance.client
                  .from('users')
                  .select('onboarding_state')
                  .eq('id', user.id)
                  .maybeSingle();
              isReturningUser = userResponse?['onboarding_state'] == 'completed';
            } catch (_) {}

            if (mounted) {
              await PaywallHelper.presentPaywallAndNavigate(
                context: context,
                userId: user.id,
                placement: 'onboarding_paywall',
                isReturningUser: isReturningUser,
              );
            }
          } else {
            debugPrint(
                '[NotificationPermission] No prior trial - navigating to trial intro');
            if (mounted) {
              Navigator.of(context).pushReplacement(
                MaterialPageRoute(builder: (context) => const TrialIntroPage()),
              );
            }
          }
        }
      } else {
        // User NOT authenticated - show SaveProgressPage to create account
        debugPrint(
            '[NotificationPermission] User not authenticated - showing SaveProgressPage');
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (context) => const SaveProgressPage(),
          ),
        );
      }
    } catch (e) {
      debugPrint('[NotificationPermission] Error in routing: $e');
      // On error, default to trial flow
      if (mounted) {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (context) => const TrialIntroPage()),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isRouting = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final spacing = context.spacing;
    final colorScheme = Theme.of(context).colorScheme;
    final hasAuthenticatedUser =
        ref.read(authServiceProvider).currentUser != null;
    final progressStep = hasAuthenticatedUser ? 6 : 5;

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
            title: OnboardingProgressIndicator(
              currentStep: progressStep,
              totalSteps: 6,
            ),
          ),
          body: SafeArea(
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: spacing.l),
              child: Column(
                children: [
                  SizedBox(height: spacing.l),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      'Get reminders to find\nyour next look',
                      textAlign: TextAlign.left,
                      style: TextStyle(
                        fontSize: 34,
                        fontWeight: FontWeight.bold,
                        color: colorScheme.onSurface,
                        fontFamily: 'PlusJakartaSans',
                        letterSpacing: -1.0,
                        height: 1.3,
                      ),
                    ),
                  ),
                  SizedBox(height: spacing.l),
                  const Spacer(flex: 2),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(horizontal: 24),
                    child: Container(
                      decoration: BoxDecoration(
                        color: const Color(0xFFD1D1D6),
                        borderRadius: BorderRadius.circular(16),
                      ),
                      clipBehavior: Clip.antiAlias,
                      child: Column(
                        children: [
                          Padding(
                            padding: EdgeInsets.symmetric(
                                vertical: 32, horizontal: 24),
                            child: Text(
                              'Worthify Would Like To\nSend You Notifications',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.w700,
                                color: colorScheme.onSurface,
                                fontFamily: 'SF Pro Display',
                                height: 1.3,
                              ),
                            ),
                          ),
                          Container(
                            width: double.infinity,
                            height: 1,
                            color: const Color(0xFFB5B5B5),
                          ),
                          Row(
                            children: [
                              Expanded(
                                child: _DialogButton(
                                  text: "Don't Allow",
                                  isPrimary: false,
                                  onTap: _handleDontAllow,
                                ),
                              ),
                              Expanded(
                                child: _DialogButton(
                                  text: 'Allow',
                                  isPrimary: true,
                                  onTap: _handleAllow,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                  const Spacer(flex: 3),
                ],
              ),
            ),
          ),
        ),
        if (_isRequesting || _isRouting)
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

class _DialogButton extends StatelessWidget {
  final String text;
  final bool isPrimary;
  final VoidCallback onTap;

  const _DialogButton({
    required this.text,
    required this.isPrimary,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 60,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color:
              isPrimary ? AppColors.secondary : const Color(0xFFD1D1D6),
        ),
        child: Text(
          text,
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.w500,
            color: isPrimary ? Colors.white : colorScheme.onSurface,
            fontFamily: 'SF Pro Text',
          ),
        ),
      ),
    );
  }
}
