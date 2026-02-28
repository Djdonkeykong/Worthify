import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/rendering.dart' show ScrollDirection;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:purchases_flutter/purchases_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../../../core/theme/app_colors.dart';
import '../../../../services/analytics_service.dart';
import '../../../../../core/theme/theme_extensions.dart';
import '../../../auth/domain/providers/auth_provider.dart';
import '../../../auth/domain/services/auth_service.dart';
import '../../../auth/presentation/pages/email_sign_in_page.dart';
import '../widgets/progress_indicator.dart';
import 'welcome_free_analysis_page.dart';
import '../../../../../shared/navigation/main_navigation.dart';
import '../../../../services/subscription_sync_service.dart';
import '../../../../services/fraud_prevention_service.dart';
import '../../../../services/onboarding_state_service.dart';
import '../../../../services/revenuecat_service.dart';
import '../../../../services/superwall_service.dart';
import '../../domain/providers/onboarding_preferences_provider.dart';
import 'notification_permission_page.dart';
import 'discovery_source_page.dart';

class SaveProgressPage extends ConsumerStatefulWidget {
  const SaveProgressPage({super.key});

  @override
  ConsumerState<SaveProgressPage> createState() => _SaveProgressPageState();
}

class _SaveProgressPageState extends ConsumerState<SaveProgressPage> {
  final ScrollController _scrollController = ScrollController();
  double _anchorOffset = 0.0;
  bool _isSnapping = false;

  void _resetMainNavigationState() {
    ref.read(selectedIndexProvider.notifier).state = 0;
    ref.invalidate(selectedIndexProvider);
    ref.invalidate(scrollToTopTriggerProvider);
    ref.invalidate(isAtHomeRootProvider);
  }

  Future<void> _openLegalLink({
    required String url,
    required String fallbackLabel,
  }) async {
    final uri = Uri.parse(url);
    final opened = await launchUrl(uri, mode: LaunchMode.inAppBrowserView);
    if (!opened) {
      debugPrint('[SaveProgress] Failed to open $fallbackLabel link');
    }
  }

  @override
  void initState() {
    super.initState();
    AnalyticsService().trackOnboardingScreen('onboarding_save_progress');
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (_scrollController.hasClients) {
        _anchorOffset = _scrollController.offset;
      }
    });
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _snapBackToAnchor() {
    if (!_scrollController.hasClients || _isSnapping) return;

    final double currentOffset = _scrollController.offset;
    if ((currentOffset - _anchorOffset).abs() < 0.5) return;

    _isSnapping = true;
    _scrollController
        .animateTo(
      _anchorOffset,
      duration: const Duration(milliseconds: 200),
      curve: Curves.easeOut,
    )
        .whenComplete(() {
      _isSnapping = false;
    });
  }

  Future<void> _navigateBasedOnSubscriptionStatus() async {
    if (!mounted) return;

    final authService = ref.read(authServiceProvider);
    final userId = authService.currentUser?.id;

    if (userId == null) {
      debugPrint('[SaveProgress] ERROR: No user found after auth');
      return;
    }

    try {
      debugPrint(
          '[SaveProgress] Checking onboarding and subscription status for user $userId');

      // Check if user has completed onboarding
      final supabase = Supabase.instance.client;
      final userResponse = await supabase
          .from('users')
          .select('onboarding_state')
          .eq('id', userId)
          .maybeSingle();

      final hasCompletedOnboarding = userResponse != null &&
          userResponse['onboarding_state'] == 'completed';

      debugPrint(
          '[SaveProgress] Has completed onboarding: $hasCompletedOnboarding');

      if (hasCompletedOnboarding) {
        // Existing user who completed onboarding - check subscription
        debugPrint(
            '[SaveProgress] User completed onboarding, checking subscription status');

        // Get subscription status from RevenueCat with retry logic
        CustomerInfo? customerInfo;
        int retryCount = 0;
        const maxRetries = 3;

        while (retryCount < maxRetries) {
          try {
            customerInfo = RevenueCatService().currentCustomerInfo ??
                await Purchases.getCustomerInfo()
                    .timeout(const Duration(seconds: 10));
            break;
          } catch (e) {
            retryCount++;
            debugPrint(
                '[SaveProgress] Error fetching customer info (attempt $retryCount/$maxRetries): $e');

            if (retryCount >= maxRetries) {
              debugPrint(
                  '[SaveProgress] Max retries reached, defaulting to paywall');
              break;
            }

            await Future.delayed(Duration(seconds: retryCount));
          }
        }

        final activeEntitlements = customerInfo?.entitlements.active.values;
        final hasActiveSubscription =
            activeEntitlements != null && activeEntitlements.isNotEmpty;

        debugPrint(
            '[SaveProgress] Has active subscription: $hasActiveSubscription');

        if (hasActiveSubscription) {
          // Completed onboarding + subscription → Home
          debugPrint('[SaveProgress] User has subscription - going to home');

          // Sync subscription to Supabase
          try {
            await SubscriptionSyncService()
                .syncSubscriptionToSupabase()
                .timeout(const Duration(seconds: 10));
          } catch (e) {
            debugPrint('[SaveProgress] Error syncing subscription: $e');
          }

          if (mounted) {
            _resetMainNavigationState();
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
          // Completed onboarding + NO subscription → Present paywall
          debugPrint('[SaveProgress] User has no subscription - presenting paywall');
          if (mounted) {
            final didPurchase = await SuperwallService().presentPaywall(
              placement: 'onboarding_paywall',
            );

            if (!mounted) return;

            if (didPurchase) {
              // User purchased - sync subscription and navigate to home
              debugPrint('[SaveProgress] Purchase completed - syncing subscription');

              try {
                await Future.delayed(const Duration(milliseconds: 500));
                await SubscriptionSyncService().syncSubscriptionToSupabase();
                await OnboardingStateService().markPaymentComplete(userId);
              } catch (e) {
                debugPrint('[SaveProgress] Error syncing subscription: $e');
              }

              if (mounted) {
                _resetMainNavigationState();
                Navigator.of(context).pushAndRemoveUntil(
                  MaterialPageRoute(
                    builder: (context) => const MainNavigation(
                      key: ValueKey('fresh-main-nav'),
                    ),
                  ),
                  (route) => false,
                );
              }
            }
            // If user dismissed without purchasing, stay on this page
          }
        }
      } else {
        // New user (hasn't completed onboarding) → WelcomeFreeAnalysisPage
        debugPrint('[SaveProgress] New user - navigating to welcome');
        if (mounted) {
          Navigator.of(context).pushReplacement(
            MaterialPageRoute(builder: (context) => const WelcomeFreeAnalysisPage()),
          );
        }
      }
    } catch (e, stackTrace) {
      debugPrint('[SaveProgress] Error checking status: $e');
      debugPrint('[SaveProgress] Stack trace: $stackTrace');

      if (mounted) {
        // On error, default to welcome flow
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (context) => const WelcomeFreeAnalysisPage()),
        );
      }
    }
  }

  Future<void> _persistOnboardingSelections(String userId) async {
    try {
      final notificationGranted =
          ref.read(notificationPermissionGrantedProvider);
      final styleDirection = ref.read(styleDirectionProvider);
      final whatYouWant = ref.read(whatYouWantProvider);
      final budget = ref.read(budgetProvider);
      final discoverySource = ref.read(selectedDiscoverySourceProvider);

      String? discoverySourceString;
      if (discoverySource != null) {
        discoverySourceString = discoverySource.name;
      }

      await OnboardingStateService().saveUserPreferences(
        userId: userId,
        preferredGenderFilter: null,
        notificationEnabled: notificationGranted,
        styleDirection: styleDirection.isNotEmpty ? styleDirection : null,
        whatYouWant: whatYouWant.isNotEmpty ? whatYouWant : null,
        budget: budget,
        discoverySource: discoverySourceString,
      );

      debugPrint(
          '[SaveProgress] All onboarding selections persisted successfully');
    } catch (e) {
      debugPrint('[SaveProgress] Error persisting onboarding selections: $e');
    }
  }

  Future<void> _handleAuthSuccess(BuildContext context) async {
    final authService = ref.read(authServiceProvider);
    final userId = authService.currentUser?.id;

    if (userId == null) {
      debugPrint('[SaveProgress] No user ID after auth');
      return;
    }

    debugPrint('[SaveProgress] Auth successful for user $userId');

    try {
      unawaited(OnboardingStateService().updateCheckpoint(
        userId,
        OnboardingCheckpoint.saveProgress,
      ));
    } catch (e) {
      debugPrint('[SaveProgress] Error updating checkpoint: $e');
    }

    try {
      await SubscriptionSyncService().identify(userId);
      await FraudPreventionService.updateUserDeviceFingerprint(userId);

      final email = authService.currentUser?.email;
      if (email != null) {
        await FraudPreventionService.calculateFraudScore(
          userId,
          email: email,
        );
      }
    } catch (e) {
      debugPrint('[SaveProgress] Error syncing subscription data: $e');
    }

    await _persistOnboardingSelections(userId);

    await _navigateBasedOnSubscriptionStatus();
  }

  @override
  Widget build(BuildContext context) {
    final spacing = context.spacing;
    final targetPlatform = Theme.of(context).platform;
    final isAppleSignInAvailable = targetPlatform == TargetPlatform.iOS ||
        targetPlatform == TargetPlatform.macOS;
    final colorScheme = Theme.of(context).colorScheme;
    final bottomPadding = kBottomNavigationBarHeight +
        spacing.xl +
        MediaQuery.of(context).padding.bottom;

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        elevation: 0,
        scrolledUnderElevation: 0,
        automaticallyImplyLeading: false,
        centerTitle: true,
        title: const OnboardingProgressIndicator(
          currentStep: 4,
          totalSteps: 4,
        ),
      ),
      body: SafeArea(
        child: NotificationListener<ScrollNotification>(
          onNotification: (n) {
            if (n is ScrollEndNotification ||
                (n is UserScrollNotification &&
                    n.direction == ScrollDirection.idle)) {
              _snapBackToAnchor();
            }
            return false;
          },
          child: SingleChildScrollView(
            controller: _scrollController,
            physics: const BouncingScrollPhysics(),
            padding: EdgeInsets.fromLTRB(
              spacing.l,
              0,
              spacing.l,
              bottomPadding,
            ),
            child: ConstrainedBox(
              constraints: BoxConstraints(
                minHeight: MediaQuery.of(context).size.height -
                    MediaQuery.of(context).padding.top -
                    MediaQuery.of(context).padding.bottom -
                    kToolbarHeight,
              ),
              child: IntrinsicHeight(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(height: spacing.l),
                    Text(
                      'Create your account',
                      style: TextStyle(
                        fontSize: 34,
                        fontFamily: 'PlusJakartaSans',
                        letterSpacing: -1.0,
                        fontWeight: FontWeight.bold,
                        color: colorScheme.onSurface,
                        height: 1.3,
                      ),
                    ),
                    SizedBox(height: spacing.xs),
                    Text(
                      'Sign in to continue',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w500,
                        color: colorScheme.onSurfaceVariant,
                        fontFamily: 'PlusJakartaSans',
                        height: 1.4,
                      ),
                    ),
                    SizedBox(height: spacing.xxl * 4),
                    Center(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 400),
                        child: Column(
                          children: [
                            if (isAppleSignInAvailable) ...[
                              _AuthButton(
                                icon: Icons.apple,
                                iconSize: 32,
                                label: 'Continue with Apple',
                                backgroundColor: Colors.black,
                                textColor: Colors.white,
                                onPressed: () async {
                                  final authService =
                                      ref.read(authServiceProvider);

                                  try {
                                    await authService.signInWithApple();
                                  } catch (e) {
                                    debugPrint(
                                        '[SaveProgress] Apple sign in error: $e');

                                    if (e ==
                                        AuthService.authCancelledException) {
                                      // User cancelled - do nothing
                                      return;
                                    }

                                    if (context.mounted) {
                                      ScaffoldMessenger.of(context)
                                          .clearSnackBars();
                                      ScaffoldMessenger.of(context)
                                          .showSnackBar(
                                        SnackBar(
                                          content: Text(
                                            'Error signing in with Apple: ${e.toString()}',
                                            style: context.snackTextStyle(
                                              merge: const TextStyle(
                                                  fontFamily:
                                                      'PlusJakartaSans'),
                                            ),
                                          ),
                                          duration: const Duration(
                                              milliseconds: 2500),
                                        ),
                                      );
                                      return;
                                    }
                                  }

                                  await Future.delayed(
                                      const Duration(milliseconds: 500));

                                  if (context.mounted) {
                                    await _handleAuthSuccess(context);
                                  }
                                },
                              ),
                              SizedBox(height: spacing.m),
                            ],
                            _AuthButtonWithSvg(
                              svgAsset: 'assets/icons/google_logo.svg',
                              iconSize: 22,
                              label: 'Continue with Google',
                              backgroundColor: Colors.white,
                              textColor: Colors.black,
                              borderColor: colorScheme.outline,
                              onPressed: () async {
                                final authService =
                                    ref.read(authServiceProvider);

                                try {
                                  await authService.signInWithGoogle();

                                  await Future.delayed(
                                      const Duration(milliseconds: 500));

                                  if (context.mounted) {
                                    await _handleAuthSuccess(context);
                                  }
                                } catch (e) {
                                  debugPrint(
                                      '[SaveProgress] Sign in error: $e');

                                  if (e == AuthService.authCancelledException) {
                                    // User cancelled - do nothing
                                    return;
                                  }

                                  if (context.mounted) {
                                    ScaffoldMessenger.of(context)
                                        .clearSnackBars();
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(
                                        content: Text(
                                          'Error signing in with Google: ${e.toString()}',
                                          style: context.snackTextStyle(
                                            merge: const TextStyle(
                                                fontFamily: 'PlusJakartaSans'),
                                          ),
                                        ),
                                        duration:
                                            const Duration(milliseconds: 2500),
                                      ),
                                    );
                                  }
                                }
                              },
                            ),
                            SizedBox(height: spacing.m),
                            _AuthButton(
                              icon: Icons.email_outlined,
                              iconSize: 26,
                              label: 'Continue with Email',
                              backgroundColor: Colors.white,
                              textColor: Colors.black,
                              borderColor: colorScheme.outline,
                              onPressed: () async {
                                final result = await Navigator.of(context).push(
                                  MaterialPageRoute(
                                    builder: (context) =>
                                        const EmailSignInPage(),
                                  ),
                                );

                                if (result == true && context.mounted) {
                                  await Future.delayed(
                                      const Duration(milliseconds: 500));
                                  if (!context.mounted) return;
                                  await _handleAuthSuccess(context);
                                }
                              },
                            ),
                            SizedBox(height: spacing.l),
                            Padding(
                              padding:
                                  EdgeInsets.symmetric(horizontal: spacing.m),
                              child: RichText(
                                textAlign: TextAlign.center,
                                text: TextSpan(
                                  text:
                                      "By continuing you agree to Worthify's ",
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: colorScheme.onSurfaceVariant,
                                    fontFamily: 'PlusJakartaSans',
                                    height: 1.5,
                                  ),
                                  children: [
                                    TextSpan(
                                      text: 'Terms of Conditions',
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: colorScheme.onSurface,
                                        fontFamily: 'PlusJakartaSans',
                                        fontWeight: FontWeight.bold,
                                        decoration: TextDecoration.underline,
                                        height: 1.5,
                                      ),
                                      recognizer: TapGestureRecognizer()
                                        ..onTap = () {
                                          HapticFeedback.selectionClick();
                                          _openLegalLink(
                                            url:
                                                'https://worthify.app/terms-of-service/',
                                            fallbackLabel: 'Terms of Service',
                                          );
                                        },
                                    ),
                                    const TextSpan(
                                      text: ' and ',
                                      style: TextStyle(fontSize: 12),
                                    ),
                                    TextSpan(
                                      text: 'Privacy Policy',
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: colorScheme.onSurface,
                                        fontFamily: 'PlusJakartaSans',
                                        fontWeight: FontWeight.bold,
                                        decoration: TextDecoration.underline,
                                        height: 1.5,
                                      ),
                                      recognizer: TapGestureRecognizer()
                                        ..onTap = () {
                                          HapticFeedback.selectionClick();
                                          _openLegalLink(
                                            url:
                                                'https://worthify.app/privacy-policy/',
                                            fallbackLabel: 'Privacy Policy',
                                          );
                                        },
                                    ),
                                  ],
                                ),
                              ),
                            ),
                            SizedBox(height: spacing.l),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _AuthButton extends StatefulWidget {
  final IconData icon;
  final double iconSize;
  final String label;
  final Color backgroundColor;
  final Color textColor;
  final Color? borderColor;
  final Future<void> Function() onPressed;

  const _AuthButton({
    required this.icon,
    this.iconSize = 24,
    required this.label,
    required this.backgroundColor,
    required this.textColor,
    this.borderColor,
    required this.onPressed,
  });

  @override
  State<_AuthButton> createState() => _AuthButtonState();
}

class _AuthButtonState extends State<_AuthButton> {
  bool _isLoading = false;

  Future<void> _handlePress() async {
    if (_isLoading) return;

    setState(() => _isLoading = true);
    HapticFeedback.mediumImpact();

    try {
      await widget.onPressed();
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      height: 56,
      decoration: BoxDecoration(
        color: widget.backgroundColor,
        borderRadius: BorderRadius.circular(28),
        border: widget.borderColor != null
            ? Border.all(color: widget.borderColor!, width: 1.5)
            : null,
      ),
      child: ElevatedButton(
        onPressed: _isLoading ? null : _handlePress,
        style: ElevatedButton.styleFrom(
          backgroundColor: widget.backgroundColor,
          foregroundColor: widget.textColor,
          elevation: 0,
          shadowColor: Colors.transparent,
          disabledBackgroundColor: widget.backgroundColor,
          disabledForegroundColor: widget.textColor,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(28),
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (_isLoading)
              SizedBox(
                width: widget.iconSize,
                height: widget.iconSize,
                child: Center(
                  child: SizedBox(
                    width: widget.icon == Icons.apple ? 22 : widget.iconSize,
                    height: widget.icon == Icons.apple ? 22 : widget.iconSize,
                    child: const CircularProgressIndicator(
                      strokeWidth: 2,
                      valueColor:
                          AlwaysStoppedAnimation<Color>(AppColors.secondary),
                    ),
                  ),
                ),
              )
            else
              Transform.translate(
                offset: widget.icon == Icons.apple
                    ? const Offset(0, -2)
                    : Offset.zero,
                child: Icon(widget.icon, size: widget.iconSize),
              ),
            const SizedBox(width: 12),
            Text(
              widget.label,
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                fontFamily: 'PlusJakartaSans',
                letterSpacing: -0.2,
                color: widget.textColor,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AuthButtonWithSvg extends StatefulWidget {
  final String svgAsset;
  final double iconSize;
  final String label;
  final Color backgroundColor;
  final Color textColor;
  final Color? borderColor;
  final Future<void> Function() onPressed;

  const _AuthButtonWithSvg({
    required this.svgAsset,
    this.iconSize = 24,
    required this.label,
    required this.backgroundColor,
    required this.textColor,
    this.borderColor,
    required this.onPressed,
  });

  @override
  State<_AuthButtonWithSvg> createState() => _AuthButtonWithSvgState();
}

class _AuthButtonWithSvgState extends State<_AuthButtonWithSvg> {
  bool _isLoading = false;

  Future<void> _handlePress() async {
    if (_isLoading) return;

    setState(() => _isLoading = true);
    HapticFeedback.mediumImpact();

    try {
      await widget.onPressed();
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      height: 56,
      decoration: BoxDecoration(
        color: widget.backgroundColor,
        borderRadius: BorderRadius.circular(28),
        border: widget.borderColor != null
            ? Border.all(color: widget.borderColor!, width: 1.5)
            : null,
      ),
      child: ElevatedButton(
        onPressed: _isLoading ? null : _handlePress,
        style: ElevatedButton.styleFrom(
          backgroundColor: widget.backgroundColor,
          foregroundColor: widget.textColor,
          elevation: 0,
          shadowColor: Colors.transparent,
          disabledBackgroundColor: widget.backgroundColor,
          disabledForegroundColor: widget.textColor,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(28),
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (_isLoading)
              SizedBox(
                width: widget.iconSize,
                height: widget.iconSize,
                child: const CircularProgressIndicator(
                  strokeWidth: 2,
                  valueColor:
                      AlwaysStoppedAnimation<Color>(AppColors.secondary),
                ),
              )
            else
              SvgPicture.asset(
                widget.svgAsset,
                width: widget.iconSize,
                height: widget.iconSize,
              ),
            const SizedBox(width: 12),
            Text(
              widget.label,
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                fontFamily: 'PlusJakartaSans',
                letterSpacing: -0.2,
                color: widget.textColor,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
