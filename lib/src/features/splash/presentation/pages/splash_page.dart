import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:purchases_flutter/purchases_flutter.dart';
import '../../../../../shared/navigation/main_navigation.dart';
import '../../../auth/presentation/pages/login_page.dart';
import '../../../auth/domain/providers/auth_provider.dart';
import '../../../../shared/services/image_preloader.dart';
import '../../../../services/onboarding_state_service.dart';
import '../../../../services/paywall_helper.dart';
import '../../../onboarding/presentation/pages/welcome_free_analysis_page.dart';
import '../../../onboarding/presentation/pages/paywall_presentation_page.dart';
import '../../../home/domain/providers/history_bootstrap_provider.dart';
import '../../../wardrobe/domain/providers/history_provider.dart';

class SplashPage extends ConsumerStatefulWidget {
  const SplashPage({super.key});

  @override
  ConsumerState<SplashPage> createState() => _SplashPageState();
}

class _SplashPageState extends ConsumerState<SplashPage> {
  static const _assetPath = 'assets/images/worthify-logo-splash.png';
  // Keep launch and splash logos in sync: fixed width so it doesn't vary by device size.
  static const double _logoWidth = 93.027; // about +8% from original (~+1% from prior)
  bool _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    _precacheAndNavigate();
  }

  Future<void> _precacheAndNavigate() async {
    try {
      await precacheImage(const AssetImage(_assetPath), context);
    } catch (e) {
      debugPrint('[Splash] Failed to precache splash logo: $e');
    }

    // Preload onboarding images to prevent white flash
    try {
      await ImagePreloader.instance.preloadSocialMediaShareImage(context);
    } catch (e) {
      debugPrint('[Splash] Failed to preload onboarding images: $e');
    }

    // Preload home CTA assets so first Home paint is immediate.
    try {
      await ImagePreloader.instance.preloadHomeAssets(context);
    } catch (e) {
      debugPrint('[Splash] Failed to preload home assets: $e');
    }

    // Wait for auth state to be ready (with minimum 0.5s splash time)
    // CRITICAL: Wait for actual auth state data, not just the provider to be available
    // This ensures Supabase session restoration from SharedPreferences completes
    try {
      await ref
          .read(authStateProvider.future)
          .timeout(const Duration(seconds: 3));
    } catch (e) {
      debugPrint('[Splash] Auth state wait failed: $e');
    }

    // Keep a minimum splash duration for smoother transition.
    await Future.delayed(const Duration(milliseconds: 500));

    if (!mounted) return;

    // Check if user is authenticated
    // By this point, the auth state stream has emitted and session restoration is complete
    final isAuthenticated = ref.read(isAuthenticatedProvider);

    // Ensure share extension receives the latest auth state via AuthService.
    // This avoids racing MethodChannel calls that might send a null userId.
    if (mounted) {
      final authService = ref.read(authServiceProvider);
      await authService.syncAuthState();
    }

    // Check if user came from share extension needing credits
    final needsCreditsFromShareExtension = await _checkNeedsCreditsFlag();

    // Determine the next page based on auth status and subscription status
    Widget nextPage;

    if (isAuthenticated) {
      final user = ref.read(authServiceProvider).currentUser;

      if (user == null) {
        // No user - go to login
        nextPage = const LoginPage();
      } else {
        // User is authenticated - check onboarding state
        final onboardingService = OnboardingStateService();

        try {
          if (PaywallHelper.shouldBypassPaywall) {
            debugPrint(
                '[Splash] Paywall bypass enabled - routing authenticated user directly to home');
            await _bootstrapHistoryUiState();
            nextPage = const MainNavigation();
          } else {
          // Determine where user should go based on onboarding completion
          final onboardingRoute =
              await onboardingService.determineOnboardingRoute(user.id);

          if (onboardingRoute == null) {
            // Onboarding complete - go to home
            debugPrint('[Splash] User has completed onboarding - routing to home');
            await _bootstrapHistoryUiState();
            nextPage = const MainNavigation();
          } else if (onboardingRoute == 'welcome') {
            // Payment complete but need to finish onboarding
            debugPrint('[Splash] User paid but needs to complete onboarding - routing to welcome');
            nextPage = const WelcomeFreeAnalysisPage();
          } else if (onboardingRoute == 'paywall') {
            // User abandoned at paywall - send them back to complete payment
            debugPrint('[Splash] User abandoned at paywall - routing back to paywall');
            nextPage = PaywallPresentationPage(userId: user.id);
          } else {
            // Onboarding not started or abandoned before account creation - send to login
            debugPrint('[Splash] User onboarding not started or incomplete - routing to login');
            nextPage = const LoginPage();
          }
          }
        } catch (e) {
          debugPrint('[Splash] Error determining onboarding route: $e');
          // On error, check if they can access home as fallback
          try {
            final canAccess = await onboardingService.canAccessHome(user.id);
            if (canAccess) {
              await _bootstrapHistoryUiState();
              nextPage = const MainNavigation();
            } else {
              // Default to login
              nextPage = const LoginPage();
            }
          } catch (e2) {
            debugPrint('[Splash] Error checking home access: $e2');
            // Last resort - go to login
            nextPage = const LoginPage();
          }
        }
      }
    } else {
      // Not authenticated - go to login
      nextPage = const LoginPage();
    }

    if (!mounted) return;

    Navigator.of(context).pushReplacement(
      PageRouteBuilder(
        pageBuilder: (context, animation, secondaryAnimation) => nextPage,
        transitionDuration: const Duration(milliseconds: 300),
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          return FadeTransition(
            opacity: animation,
            child: child,
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        // iOS: dark background = light (white) icons
        statusBarBrightness: Brightness.dark,
        // Android: light icons directly
        statusBarIconBrightness: Brightness.light,
      ),
    child: Scaffold(
        backgroundColor: const Color(0xFFF2003C),
        body: Center(
          child: SizedBox(
            width: _logoWidth,
            child: Image.asset(
              _assetPath,
              fit: BoxFit.contain,
            ),
          ),
        ),
      ),
    );
  }

  Future<bool> _checkNeedsCreditsFlag() async {
    try {
      const platform = MethodChannel('worthify/auth');
      final result = await platform.invokeMethod('getNeedsCreditsFlag');
      debugPrint('[Splash] Needs credits from share extension: $result');
      return result == true;
    } catch (e) {
      debugPrint('[Splash] Error checking needs credits flag: $e');
      return false;
    }
  }

  Future<void> _bootstrapHistoryUiState() async {
    try {
      final history = await ref
          .read(historyProvider.future)
          .timeout(const Duration(seconds: 4));
      ref.read(historyBootstrapProvider.notifier).state = history.isNotEmpty
          ? HistoryBootstrapState.hasHistory
          : HistoryBootstrapState.noHistory;
    } catch (e) {
      debugPrint('[Splash] Failed to bootstrap history UI state: $e');
      ref.read(historyBootstrapProvider.notifier).state =
          HistoryBootstrapState.unknown;
    }
  }
}
