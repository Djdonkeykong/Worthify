import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:purchases_flutter/purchases_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:video_player/video_player.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../../../core/theme/app_colors.dart';
import '../../../../../core/theme/theme_extensions.dart';
import '../../../../../shared/navigation/main_navigation.dart';
import '../../../../../src/shared/services/video_preloader.dart';
import '../../../../shared/widgets/bottom_sheet_handle.dart';
import '../../../../shared/widgets/worthify_circular_icon_button.dart';
import '../../../onboarding/presentation/pages/how_it_works_page.dart';
import '../../../onboarding/presentation/pages/discovery_source_page.dart';
import '../../../onboarding/presentation/pages/trial_intro_page.dart';
import '../../../onboarding/presentation/pages/save_progress_page.dart';
import '../../../onboarding/presentation/pages/welcome_free_analysis_page.dart';
import '../../../../services/paywall_helper.dart';
import '../../domain/providers/auth_provider.dart';
import '../../../user/repositories/user_profile_repository.dart';
import 'email_sign_in_page.dart';
import '../../../home/domain/providers/inspiration_provider.dart';
import '../../domain/services/auth_service.dart';
import '../../../../services/subscription_sync_service.dart';
import '../../../../services/revenuecat_service.dart';

class LoginPage extends ConsumerStatefulWidget {
  const LoginPage({super.key});

  @override
  ConsumerState<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends ConsumerState<LoginPage>
    with WidgetsBindingObserver {
  VideoPlayerController? get _controller =>
      VideoPreloader.instance.loginVideoController;

  Future<void> _openLegalLink({
    required String url,
    required String fallbackLabel,
  }) async {
    final uri = Uri.parse(url);

    // Only use in-app browser; no fallbacks
    await launchUrl(uri, mode: LaunchMode.inAppBrowserView);
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await VideoPreloader.instance.preloadLoginVideo();
      if (mounted) {
        setState(() {});
        // Ensure video plays when returning to this page
        VideoPreloader.instance.playLoginVideo();
      }
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    VideoPreloader.instance.pauseLoginVideo();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    if (state == AppLifecycleState.resumed) {
      // Resume video when app comes back to foreground
      VideoPreloader.instance.playLoginVideo();
    } else if (state == AppLifecycleState.paused) {
      // Pause video when app goes to background
      VideoPreloader.instance.pauseLoginVideo();
    }
  }

  @override
  Widget build(BuildContext context) {
    final spacing = context.spacing;
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;
    final screenHeight = MediaQuery.of(context).size.height;
    final screenWidth = MediaQuery.of(context).size.width;

    // Calculate video height based on available space
    // Reserve space for: text (90px), button (56px), sign-in (50px), spacings (100px)
    final reservedBottomSpace = 360.0; // Space needed for bottom content
    final topSpacing = 24.0; // spacing.l
    final spacingBelowVideo = 16.0; // spacing.m
    final availableVideoSpace =
        screenHeight - reservedBottomSpace - topSpacing - spacingBelowVideo;
    final videoHeight = availableVideoSpace.clamp(280.0, availableVideoSpace);

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness:
            isDark ? Brightness.light : Brightness.dark, // Android
        statusBarBrightness: isDark ? Brightness.dark : Brightness.light, // iOS
        systemNavigationBarColor: theme.scaffoldBackgroundColor,
        systemNavigationBarIconBrightness:
            isDark ? Brightness.light : Brightness.dark,
      ),
      child: Scaffold(
        backgroundColor: theme.scaffoldBackgroundColor,
        body: SafeArea(
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: spacing.l),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                SizedBox(height: spacing.l),
                if (_controller != null &&
                    VideoPreloader.instance.isLoginVideoInitialized)
                  Container(
                    height: videoHeight,
                    width: double.infinity,
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
                else
                  Container(
                    height: videoHeight,
                    width: double.infinity,
                    decoration: BoxDecoration(
                      color: colorScheme.surfaceVariant,
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                SizedBox(height: spacing.xl),
                Text(
                  'Snap the look\nin seconds.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 34,
                    fontWeight: FontWeight.bold,
                    color: colorScheme.onSurface,
                    fontFamily: 'PlusJakartaSans',
                    letterSpacing: -1.0,
                    height: 1.3,
                  ),
                ),
                const Spacer(),
                SizedBox(height: spacing.m),
                Container(
                  width: double.infinity,
                  height: 56,
                  decoration: BoxDecoration(
                    color: AppColors.secondary,
                    borderRadius: BorderRadius.circular(28),
                  ),
                  child: ElevatedButton(
                    onPressed: () {
                      HapticFeedback.mediumImpact();
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (context) => const HowItWorksPage(),
                        ),
                      );
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFFf2003c),
                      foregroundColor: Colors.white,
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(28),
                      ),
                    ),
                    child: const Text(
                      'Get Started',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        fontFamily: 'PlusJakartaSans',
                        letterSpacing: -0.2,
                      ),
                    ),
                  ),
                ),
                SizedBox(height: spacing.m),
                TextButton(
                  onPressed: () {
                    HapticFeedback.mediumImpact();
                    _showSignInBottomSheet(context);
                  },
                  child: RichText(
                    textAlign: TextAlign.center,
                    text: TextSpan(
                      text: 'Already have an account? ',
                      style: TextStyle(
                        color: colorScheme.onSurfaceVariant,
                        fontSize: 14,
                        fontFamily: 'PlusJakartaSans',
                        fontWeight: FontWeight.w400,
                        height: 1.5,
                      ),
                      children: [
                        TextSpan(
                          text: 'Sign In',
                          style: TextStyle(
                            color: colorScheme.onSurface,
                            fontWeight: FontWeight.bold,
                            fontFamily: 'PlusJakartaSans',
                            letterSpacing: -0.2,
                          ),
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
      ),
    );
  }

  void _showSignInBottomSheet(BuildContext context) {
    final spacing = context.spacing;
    final navigator = Navigator.of(context);
    final platform = Theme.of(context).platform;
    final colorScheme = Theme.of(context).colorScheme;
    final isAppleSignInAvailable =
        platform == TargetPlatform.iOS || platform == TargetPlatform.macOS;

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) => Container(
        decoration: BoxDecoration(
          color: colorScheme.surface,
          borderRadius: BorderRadius.vertical(
            top: Radius.circular(20),
          ),
        ),
        child: SafeArea(
          top: false,
          child: Stack(
            children: [
              Padding(
                padding: EdgeInsets.all(spacing.l),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    BottomSheetHandle(
                      margin: EdgeInsets.only(bottom: spacing.m),
                    ),
                    Center(
                      child: Text(
                        'Sign In',
                        style: TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                          color: colorScheme.onSurface,
                          fontFamily: 'PlusJakartaSans',
                          letterSpacing: -0.5,
                        ),
                      ),
                    ),
                    SizedBox(height: spacing.xxl),
                    if (isAppleSignInAvailable) ...[
                      _AuthButton(
                        icon: Icons.apple,
                        iconSize: 32,
                        label: 'Continue with Apple',
                        backgroundColor: Colors.black,
                        textColor: Colors.white,
                        onPressed: () async {
                          try {
                            print('[LoginPage] Apple sign-in button clicked');
                            final authService = ref.read(authServiceProvider);
                            await authService.signInWithApple();
                            print('[LoginPage] Apple sign-in completed');

                            if (context.mounted) {
                              print(
                                  '[LoginPage] Context is mounted, closing bottom sheet');
                              Navigator.pop(context);

                              final supabase = Supabase.instance.client;
                              final userId = supabase.auth.currentUser?.id;
                              print('[LoginPage] Current user ID: $userId');

                              if (userId != null) {
                                // CRITICAL: Identify user with RevenueCat to link any anonymous purchases
                                print(
                                    '[LoginPage] Linking RevenueCat subscription to Apple account...');
                                try {
                                  await SubscriptionSyncService()
                                      .identify(userId);
                                  print(
                                      '[LoginPage] RevenueCat subscription linked and synced');
                                } catch (linkError) {
                                  print(
                                      '[LoginPage] Error linking RevenueCat subscription: $linkError');
                                }

                                // Check onboarding status from database
                                final userResponse = await supabase
                                    .from('users')
                                    .select(
                                        'onboarding_state, onboarding_checkpoint')
                                    .eq('id', userId)
                                    .maybeSingle();

                                print(
                                    '[LoginPage] Apple sign-in - user ID: $userId');
                                print(
                                    '[LoginPage] Database response: $userResponse');
                                print(
                                    '[LoginPage] Onboarding state from DB: ${userResponse?['onboarding_state']}');
                                print(
                                    '[LoginPage] Onboarding checkpoint from DB: ${userResponse?['onboarding_checkpoint']}');

                                final hasCompletedOnboarding =
                                    userResponse != null &&
                                        userResponse['onboarding_state'] ==
                                            'completed';

                                print(
                                    '[LoginPage] Has completed onboarding: $hasCompletedOnboarding');

                                // Check subscription status from RevenueCat (source of truth)
                                CustomerInfo? customerInfo;
                                try {
                                  customerInfo =
                                      await Purchases.getCustomerInfo();
                                  print(
                                      '[LoginPage] RevenueCat customer info fetched successfully');
                                  print(
                                      '[LoginPage] All entitlements: ${customerInfo.entitlements.all.keys.toList()}');
                                  print(
                                      '[LoginPage] Active entitlements: ${customerInfo.entitlements.active.keys.toList()}');
                                } catch (e) {
                                  debugPrint(
                                      '[LoginPage] Error fetching RevenueCat customer info: $e');
                                }

                                final activeEntitlements =
                                    customerInfo?.entitlements.active.values;
                                final hasActiveSubscription =
                                    activeEntitlements != null &&
                                        activeEntitlements.isNotEmpty;

                                print(
                                    '[LoginPage] Has active subscription (RevenueCat): $hasActiveSubscription');

                                // Check if user has credits (even without subscription)
                                final userCreditsResponse = await supabase
                                    .from('users')
                                    .select('paid_credits_remaining')
                                    .eq('id', userId)
                                    .maybeSingle();

                                final hasCredits =
                                    (userCreditsResponse?['paid_credits_remaining'] ?? 0) > 0;

                                print(
                                    '[LoginPage] User has credits: $hasCredits (${userCreditsResponse?['paid_credits_remaining']} remaining)');

                                if (hasCompletedOnboarding &&
                                    (hasActiveSubscription || hasCredits)) {
                                  // User completed onboarding and has active subscription OR credits - go to home
                                  debugPrint(
                                      '[LoginPage] User has completed onboarding and has access (subscription: $hasActiveSubscription, credits: $hasCredits) - going to home');
                                  debugPrint(
                                      '[LoginPage] Skipping device locale setup (user_profiles table not configured)');

                                  ref
                                      .read(selectedIndexProvider.notifier)
                                      .state = 0;
                                  ref.invalidate(inspirationProvider);
                                  navigator.pushAndRemoveUntil(
                                    MaterialPageRoute(
                                      builder: (context) =>
                                          const MainNavigation(
                                        key: ValueKey('fresh-main-nav'),
                                      ),
                                    ),
                                    (route) => false,
                                  );
                                } else if (hasCompletedOnboarding &&
                                    !hasActiveSubscription && !hasCredits) {
                                  // User completed onboarding but NO subscription and NO credits - present Superwall paywall
                                  debugPrint(
                                      '[LoginPage] User completed onboarding but no subscription or credits - presenting Superwall paywall');
                                  await PaywallHelper.presentPaywallAndNavigate(
                                    context: navigator.context,
                                    userId: userId,
                                    isReturningUser: true,  // Skip onboarding check - we know they completed it
                                  );
                                } else {
                                  // User hasn't completed onboarding - resume where they left off
                                  final checkpoint =
                                      userResponse?['onboarding_checkpoint'];
                                  debugPrint(
                                      '[LoginPage] User hasn\'t completed onboarding - checkpoint: $checkpoint');

                                  // Check trial eligibility for trial/paywall checkpoints
                                  bool isEligibleForTrial = true;
                                  if (checkpoint == 'trial' ||
                                      checkpoint == 'paywall' ||
                                      checkpoint == 'save_progress' ||
                                      checkpoint == 'account' ||
                                      checkpoint == 'welcome') {
                                    try {
                                      isEligibleForTrial =
                                          await RevenueCatService()
                                              .isEligibleForTrial();
                                      debugPrint(
                                          '[LoginPage] Trial eligibility check: $isEligibleForTrial');
                                    } catch (e) {
                                      debugPrint(
                                          '[LoginPage] Error checking trial eligibility: $e');
                                    }
                                  }

                                  // Route to the appropriate page based on checkpoint
                                  Widget nextPage;
                                  switch (checkpoint) {
                                    case 'gender':
                                      debugPrint(
                                          '[LoginPage] Resuming from legacy gender checkpoint to discovery source');
                                      nextPage = const DiscoverySourcePage();
                                      break;
                                    case 'discovery':
                                      debugPrint(
                                          '[LoginPage] Resuming at discovery source');
                                      nextPage = const DiscoverySourcePage();
                                      break;
                                    case 'tutorial':
                                      debugPrint(
                                          '[LoginPage] Resuming at tutorial');
                                      nextPage =
                                          const MainNavigation(key: ValueKey('fresh-main-nav'));
                                      break;
                                    case 'notification':
                                      debugPrint(
                                          '[LoginPage] Resuming at notification - showing paywall flow');
                                      nextPage = const MainNavigation(key: ValueKey('fresh-main-nav'));
                                      break;
                                    case 'trial':
                                    case 'trial_reminder':
                                      debugPrint(
                                          '[LoginPage] Resuming at trial/trial_reminder');
                                      nextPage = const TrialIntroPage();
                                      break;
                                    case 'save_progress':
                                      debugPrint(
                                          '[LoginPage] Already authenticated - checking subscription');
                                      nextPage = hasActiveSubscription
                                          ? const MainNavigation(
                                              key: ValueKey('fresh-main-nav'))
                                          : const MainNavigation(key: ValueKey('fresh-main-nav'));
                                      break;
                                    case 'paywall':
                                    case 'account':
                                      debugPrint(
                                          '[LoginPage] Resuming at paywall/account - has subscription: $hasActiveSubscription');
                                      nextPage = hasActiveSubscription
                                          ? const MainNavigation(
                                              key: ValueKey('fresh-main-nav'))
                                          : const MainNavigation(key: ValueKey('fresh-main-nav'));
                                      break;
                                    case 'welcome':
                                      debugPrint(
                                          '[LoginPage] Resuming at welcome');
                                      nextPage =
                                          const WelcomeFreeAnalysisPage();
                                      break;
                                    default:
                                      debugPrint(
                                          '[LoginPage] No checkpoint or unknown - starting from beginning');
                                      nextPage = const HowItWorksPage();
                                  }

                                  if (nextPage is MainNavigation) {
                                    ref
                                        .read(selectedIndexProvider.notifier)
                                        .state = 0;
                                    ref.invalidate(inspirationProvider);
                                    navigator.pushAndRemoveUntil(
                                      MaterialPageRoute(
                                          builder: (context) => nextPage),
                                      (route) => false,
                                    );
                                  } else {
                                    navigator.push(
                                      MaterialPageRoute(
                                          builder: (context) => nextPage),
                                    );
                                  }
                                }
                              }
                            }
                          } catch (e) {
                            print('[LoginPage] Apple sign-in error caught: $e');
                            if (context.mounted) {
                              print(
                                  '[LoginPage] Context mounted in catch block, closing sheet');
                              Navigator.pop(context);
                              if (e != AuthService.authCancelledException) {
                                ScaffoldMessenger.of(context).clearSnackBars();
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text(
                                      e.toString(),
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
                        try {
                          print('[LoginPage] Google sign-in button clicked');
                          final authService = ref.read(authServiceProvider);
                          await authService.signInWithGoogle();
                          print('[LoginPage] Google sign-in completed');

                          if (context.mounted) {
                            print(
                                '[LoginPage] Context is mounted, closing bottom sheet');
                            Navigator.pop(context);

                            final supabase = Supabase.instance.client;
                            final userId = supabase.auth.currentUser?.id;
                            print('[LoginPage] Current user ID: $userId');

                            if (userId != null) {
                              // CRITICAL: Identify user with RevenueCat to link any anonymous purchases
                              print(
                                  '[LoginPage] Linking RevenueCat subscription to Google account...');
                              try {
                                await SubscriptionSyncService()
                                    .identify(userId);
                                print(
                                    '[LoginPage] RevenueCat subscription linked and synced');
                              } catch (linkError) {
                                print(
                                    '[LoginPage] Error linking RevenueCat subscription: $linkError');
                              }

                              // Check onboarding status from database
                              final userResponse = await supabase
                                  .from('users')
                                  .select(
                                      'onboarding_state, onboarding_checkpoint')
                                  .eq('id', userId)
                                  .maybeSingle();

                              print(
                                  '[LoginPage] Google sign-in - user ID: $userId');
                              print(
                                  '[LoginPage] Database response: $userResponse');
                              print(
                                  '[LoginPage] Onboarding state from DB: ${userResponse?['onboarding_state']}');
                              print(
                                  '[LoginPage] Onboarding checkpoint from DB: ${userResponse?['onboarding_checkpoint']}');

                              final hasCompletedOnboarding =
                                  userResponse != null &&
                                      userResponse['onboarding_state'] ==
                                          'completed';

                              print(
                                  '[LoginPage] Has completed onboarding: $hasCompletedOnboarding');

                              // Check subscription status from RevenueCat (source of truth)
                              CustomerInfo? customerInfo;
                              try {
                                customerInfo =
                                    await Purchases.getCustomerInfo();
                                print(
                                    '[LoginPage] RevenueCat customer info fetched successfully');
                                print(
                                    '[LoginPage] All entitlements: ${customerInfo.entitlements.all.keys.toList()}');
                                print(
                                    '[LoginPage] Active entitlements: ${customerInfo.entitlements.active.keys.toList()}');
                              } catch (e) {
                                debugPrint(
                                    '[LoginPage] Error fetching RevenueCat customer info: $e');
                              }

                              final activeEntitlements =
                                  customerInfo?.entitlements.active.values;
                              final hasActiveSubscription =
                                  activeEntitlements != null &&
                                      activeEntitlements.isNotEmpty;

                              print(
                                  '[LoginPage] Has active subscription (RevenueCat): $hasActiveSubscription');

                              // Check if user has credits (even without subscription)
                              final userCreditsResponse = await supabase
                                  .from('users')
                                  .select('paid_credits_remaining')
                                  .eq('id', userId)
                                  .maybeSingle();

                              final hasCredits =
                                  (userCreditsResponse?['paid_credits_remaining'] ?? 0) > 0;

                              print(
                                  '[LoginPage] User has credits: $hasCredits (${userCreditsResponse?['paid_credits_remaining']} remaining)');

                              if (hasCompletedOnboarding &&
                                  (hasActiveSubscription || hasCredits)) {
                                // User completed onboarding and has active subscription OR credits - go to home
                                debugPrint(
                                    '[LoginPage] User has completed onboarding and has access (subscription: $hasActiveSubscription, credits: $hasCredits) - going to home');
                                debugPrint(
                                    '[LoginPage] Skipping device locale setup (user_profiles table not configured)');

                                ref.read(selectedIndexProvider.notifier).state =
                                    0;
                                ref.invalidate(inspirationProvider);
                                navigator.pushAndRemoveUntil(
                                  MaterialPageRoute(
                                    builder: (context) => const MainNavigation(
                                      key: ValueKey('fresh-main-nav'),
                                    ),
                                  ),
                                  (route) => false,
                                );
                              } else if (hasCompletedOnboarding &&
                                  !hasActiveSubscription && !hasCredits) {
                                // User completed onboarding but NO subscription and NO credits - present Superwall paywall
                                debugPrint(
                                    '[LoginPage] User completed onboarding but no subscription or credits - presenting Superwall paywall');
                                await PaywallHelper.presentPaywallAndNavigate(
                                  context: navigator.context,
                                  userId: userId,
                                  isReturningUser: true,  // Skip onboarding check - we know they completed it
                                );
                              } else {
                                // User hasn't completed onboarding - resume where they left off
                                final checkpoint =
                                    userResponse?['onboarding_checkpoint'];
                                debugPrint(
                                    '[LoginPage] User hasn\'t completed onboarding - checkpoint: $checkpoint');

                                // Check trial eligibility for trial/paywall checkpoints
                                bool isEligibleForTrial = true;
                                if (checkpoint == 'trial' ||
                                    checkpoint == 'paywall' ||
                                    checkpoint == 'save_progress' ||
                                    checkpoint == 'account' ||
                                    checkpoint == 'welcome') {
                                  try {
                                    isEligibleForTrial =
                                        await RevenueCatService()
                                            .isEligibleForTrial();
                                    debugPrint(
                                        '[LoginPage] Trial eligibility check: $isEligibleForTrial');
                                  } catch (e) {
                                    debugPrint(
                                        '[LoginPage] Error checking trial eligibility: $e');
                                  }
                                }

                                // Route to the appropriate page based on checkpoint
                                Widget nextPage;
                                switch (checkpoint) {
                                  case 'gender':
                                    debugPrint(
                                        '[LoginPage] Resuming from legacy gender checkpoint to discovery source');
                                    nextPage = const DiscoverySourcePage();
                                    break;
                                  case 'discovery':
                                    debugPrint(
                                        '[LoginPage] Resuming at discovery source');
                                    nextPage = const DiscoverySourcePage();
                                    break;
                                  case 'tutorial':
                                    debugPrint(
                                        '[LoginPage] Resuming at tutorial');
                                    nextPage =
                                        const MainNavigation(key: ValueKey('fresh-main-nav'));
                                    break;
                                  case 'notification':
                                    debugPrint(
                                        '[LoginPage] Resuming at notification - showing paywall flow');
                                    nextPage = const MainNavigation(key: ValueKey('fresh-main-nav'));
                                    break;
                                  case 'trial':
                                  case 'trial_reminder':
                                    debugPrint(
                                        '[LoginPage] Resuming at trial/trial_reminder');
                                    nextPage = const TrialIntroPage();
                                    break;
                                  case 'save_progress':
                                    debugPrint(
                                        '[LoginPage] Already authenticated - checking subscription');
                                    nextPage = hasActiveSubscription
                                        ? const MainNavigation(
                                            key: ValueKey('fresh-main-nav'))
                                        : const MainNavigation(key: ValueKey('fresh-main-nav'));
                                    break;
                                  case 'paywall':
                                  case 'account':
                                    debugPrint(
                                        '[LoginPage] Resuming at paywall/account - has subscription: $hasActiveSubscription');
                                    nextPage = hasActiveSubscription
                                        ? const MainNavigation(
                                            key: ValueKey('fresh-main-nav'))
                                        : const MainNavigation(key: ValueKey('fresh-main-nav'));
                                    break;
                                  case 'welcome':
                                    debugPrint(
                                        '[LoginPage] Resuming at welcome');
                                    nextPage = const WelcomeFreeAnalysisPage();
                                    break;
                                  default:
                                    debugPrint(
                                        '[LoginPage] No checkpoint or unknown - starting from beginning');
                                    nextPage = const HowItWorksPage();
                                }

                                if (nextPage is MainNavigation) {
                                  ref
                                      .read(selectedIndexProvider.notifier)
                                      .state = 0;
                                  ref.invalidate(inspirationProvider);
                                  navigator.pushAndRemoveUntil(
                                    MaterialPageRoute(
                                        builder: (context) => nextPage),
                                    (route) => false,
                                  );
                                } else {
                                  navigator.push(
                                    MaterialPageRoute(
                                        builder: (context) => nextPage),
                                  );
                                }
                              }
                            }
                          }
                        } catch (e) {
                          print('[LoginPage] Google sign-in error caught: $e');
                          if (context.mounted) {
                            print(
                                '[LoginPage] Context mounted in catch block, closing sheet');
                            Navigator.pop(context);
                            if (e != AuthService.authCancelledException) {
                              ScaffoldMessenger.of(context).clearSnackBars();
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text(
                                    e.toString(),
                                    style: context.snackTextStyle(
                                      merge: const TextStyle(
                                          fontFamily: 'PlusJakartaSans'),
                                    ),
                                  ),
                                  duration: const Duration(milliseconds: 2500),
                                ),
                              );
                            }
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
                        Navigator.pop(context);
                        // Give the sheet a moment to finish closing for smoother transition
                        await Future.delayed(const Duration(milliseconds: 150));
                        if (!context.mounted) return;

                        navigator.push(
                          MaterialPageRoute(
                            builder: (context) => const EmailSignInPage(),
                          ),
                        );
                      },
                    ),
                    SizedBox(height: spacing.l),
                    Padding(
                      padding: EdgeInsets.symmetric(horizontal: spacing.m),
                      child: RichText(
                        textAlign: TextAlign.center,
                        text: TextSpan(
                          text: "By continuing you agree to Worthify's ",
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
                            TextSpan(
                              text: ' and ',
                              style: TextStyle(
                                fontSize: 12,
                                color: colorScheme.onSurfaceVariant,
                                fontFamily: 'PlusJakartaSans',
                                height: 1.5,
                              ),
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
              Positioned(
                top: spacing.l,
                right: spacing.l,
                child: WorthifyCircularIconButton(
                  icon: Icons.close,
                  iconSize: 18,
                  backgroundColor: colorScheme.surfaceContainerHighest,
                  iconColor: colorScheme.onSurface,
                  onPressed: () => Navigator.pop(context),
                  tooltip: 'Close',
                  semanticLabel: 'Close',
                ),
              ),
            ],
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
