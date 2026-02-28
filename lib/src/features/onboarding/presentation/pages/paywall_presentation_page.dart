import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../../../core/theme/app_colors.dart';
import '../../../../services/analytics_service.dart';
import 'welcome_free_analysis_page.dart';
import '../../../../../shared/navigation/main_navigation.dart';
import '../../../../services/superwall_service.dart';
import '../../../../services/subscription_sync_service.dart';
import '../../../../services/onboarding_state_service.dart';

/// A dedicated page that presents the paywall and handles navigation
/// This prevents the previous page from being visible when the paywall closes
class PaywallPresentationPage extends StatefulWidget {
  const PaywallPresentationPage({
    super.key,
    required this.userId,
    this.placement = 'onboarding_paywall',
  });

  final String? userId;
  final String placement;

  @override
  State<PaywallPresentationPage> createState() =>
      _PaywallPresentationPageState();
}

class _PaywallPresentationPageState extends State<PaywallPresentationPage> {
  bool _isLoading = true;
  bool _hasPresented = false;

  @override
  void initState() {
    super.initState();
    AnalyticsService().trackOnboardingScreen('onboarding_paywall');
    // Present paywall after build is complete
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _presentPaywall();
    });
  }

  Future<void> _presentPaywall() async {
    if (_hasPresented) return;
    _hasPresented = true;

    try {
      debugPrint('[PaywallPresentationPage] Presenting Superwall paywall...');

      // Keep loading overlay visible while Superwall initializes
      await Future.delayed(const Duration(milliseconds: 500));

      // Present Superwall paywall (this will show Superwall's UI over our page)
      final didPurchase = await SuperwallService().presentPaywall(
        placement: widget.placement,
      );

      // Paywall has been dismissed - hide loading overlay
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }

      if (!mounted) return;

      debugPrint('[PaywallPresentationPage] Purchase result: $didPurchase');

      // If user purchased and has account, sync subscription to Supabase
      if (didPurchase && widget.userId != null) {
        // Show loading overlay while syncing
        if (mounted) {
          setState(() {
            _isLoading = true;
          });
        }

        try {
          debugPrint(
              '[PaywallPresentationPage] Purchase completed - waiting for RevenueCat to process...');

          // Wait briefly for RevenueCat to process the purchase and update entitlements
          await Future.delayed(const Duration(milliseconds: 500));

          debugPrint(
              '[PaywallPresentationPage] Syncing subscription to Supabase...');
          await SubscriptionSyncService().syncSubscriptionToSupabase();
          await OnboardingStateService().markPaymentComplete(widget.userId!);
          debugPrint(
              '[PaywallPresentationPage] Subscription synced successfully');
        } catch (e) {
          debugPrint(
              '[PaywallPresentationPage] Error syncing subscription: $e');
        }
      }

      if (!mounted) return;

      // Only navigate forward if user purchased
      if (!didPurchase) {
        debugPrint(
            '[PaywallPresentationPage] User dismissed paywall without purchasing - going back');
        Navigator.of(context).pop();
        return;
      }

      if (widget.userId == null) {
        debugPrint('[PaywallPresentationPage] WARNING: No user found after paywall');
        Navigator.of(context).pop();
        return;
      }

      // Check if user has completed onboarding before
      final supabase = Supabase.instance.client;
      final userResponse = await supabase
          .from('users')
          .select('onboarding_state')
          .eq('id', widget.userId!)
          .maybeSingle();

      final hasCompletedOnboarding =
          userResponse?['onboarding_state'] == 'completed';

      debugPrint(
          '[PaywallPresentationPage] User purchased - navigating: hasCompletedOnboarding=$hasCompletedOnboarding');

      final nextPage = hasCompletedOnboarding
          ? const MainNavigation()
          : const WelcomeFreeAnalysisPage();

      if (mounted) {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (context) => nextPage),
        );
      }
    } catch (e) {
      debugPrint('[PaywallPresentationPage] Error during paywall: $e');
      // Go back on error
      if (mounted) {
        Navigator.of(context).pop();
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: _isLoading
          ? Center(
              child: CircularProgressIndicator(
                valueColor: const AlwaysStoppedAnimation<Color>(
                  AppColors.secondary,
                ),
                backgroundColor: colorScheme.outlineVariant,
                strokeWidth: 3,
              ),
            )
          : const SizedBox.shrink(),
    );
  }
}
