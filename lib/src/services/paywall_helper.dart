import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../features/onboarding/presentation/pages/welcome_free_analysis_page.dart';
import '../../shared/navigation/main_navigation.dart';
import 'superwall_service.dart';
import 'subscription_sync_service.dart';
import 'onboarding_state_service.dart';

/// Helper to present Superwall paywall and handle post-purchase navigation
class PaywallHelper {
  /// Present Superwall paywall and navigate appropriately
  /// Returns true if user subscribed successfully
  static Future<bool> presentPaywall({
    required BuildContext context,
    required String? userId,
    String placement = 'onboarding_paywall',
  }) async {
    try {
      debugPrint('[PaywallHelper] Presenting Superwall paywall...');

      // Present Superwall paywall
      final didPurchase = await SuperwallService().presentPaywall(
        placement: placement,
      );

      if (!context.mounted) return didPurchase;

      debugPrint('[PaywallHelper] Purchase result: $didPurchase');

      // If user purchased and has account, identify user and sync subscription to Supabase
      if (didPurchase && userId != null) {
        try {
          debugPrint('[PaywallHelper] Identifying user and syncing subscription...');
          // CRITICAL: Identify user with RevenueCat to link any anonymous purchases
          await SubscriptionSyncService().identify(userId);
          await OnboardingStateService().markPaymentComplete(userId);
          debugPrint('[PaywallHelper] User identified and subscription synced successfully');
        } catch (e) {
          debugPrint('[PaywallHelper] Error syncing subscription: $e');
        }
      }

      return didPurchase;
    } catch (e) {
      debugPrint('[PaywallHelper] Error during paywall presentation: $e');
      return false;
    }
  }

  /// Present paywall and navigate to next screen based on onboarding state
  /// Only navigates forward if user completed purchase
  ///
  /// [isReturningUser] - If true, skips onboarding check and goes directly to MainNavigation after purchase
  static Future<void> presentPaywallAndNavigate({
    required BuildContext context,
    required String? userId,
    String placement = 'onboarding_paywall',
    bool isReturningUser = false,
  }) async {
    if (!context.mounted) return;

    try {
      // Present paywall
      final didPurchase = await presentPaywall(
        context: context,
        userId: userId,
        placement: placement,
      );

      if (!context.mounted) return;

      // Only navigate forward if user purchased
      if (!didPurchase) {
        debugPrint('[PaywallHelper] User dismissed paywall without purchasing - staying on current page');
        return;
      }

      if (userId == null) {
        // Should never happen since auth is required before paywall
        debugPrint('[PaywallHelper] WARNING: No user found after paywall');
        return;
      }

      // Determine next page based on whether this is a returning user
      Widget nextPage;
      if (isReturningUser) {
        // Returning user (login flow) - go directly to main app
        debugPrint('[PaywallHelper] Returning user purchased - navigating to MainNavigation');
        nextPage = const MainNavigation();
      } else {
        // New user (onboarding flow) - check onboarding state
        final supabase = Supabase.instance.client;
        final userResponse = await supabase
            .from('users')
            .select('onboarding_state')
            .eq('id', userId)
            .maybeSingle();

        final hasCompletedOnboarding =
            userResponse?['onboarding_state'] == 'completed';

        debugPrint(
            '[PaywallHelper] New user purchased - hasCompletedOnboarding=$hasCompletedOnboarding');

        nextPage = hasCompletedOnboarding
            ? const MainNavigation()
            : const WelcomeFreeAnalysisPage();
      }

      if (context.mounted) {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (context) => nextPage),
        );
      }
    } catch (e) {
      debugPrint('[PaywallHelper] Error in navigation flow: $e');
      // Don't navigate on error - let user stay where they are
    }
  }
}
