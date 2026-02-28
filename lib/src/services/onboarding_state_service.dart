import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:purchases_flutter/purchases_flutter.dart';
import 'superwall_service.dart';
import 'revenuecat_service.dart';
import 'fraud_prevention_service.dart';
import 'analytics_service.dart';

/// States of the onboarding process
enum OnboardingState {
  notStarted('not_started'),
  inProgress('in_progress'),
  paymentComplete('payment_complete'),
  completed('completed');

  final String value;
  const OnboardingState(this.value);

  static OnboardingState fromString(String value) {
    return OnboardingState.values.firstWhere(
      (e) => e.value == value,
      orElse: () => OnboardingState.notStarted,
    );
  }
}

/// Checkpoints in the onboarding flow
enum OnboardingCheckpoint {
  gender('gender'),
  discovery('discovery'),
  tutorial('tutorial'),
  notification('notification'),
  trial('trial'),
  trialReminder('trial_reminder'),
  saveProgress('save_progress'),
  paywall('paywall'),
  account('account'),
  welcome('welcome');

  final String value;
  const OnboardingCheckpoint(this.value);

  static OnboardingCheckpoint? fromString(String? value) {
    if (value == null) return null;
    return OnboardingCheckpoint.values.firstWhere(
      (e) => e.value == value,
      orElse: () => OnboardingCheckpoint.discovery,
    );
  }
}

/// Service for managing onboarding state
class OnboardingStateService {
  static final OnboardingStateService _instance = OnboardingStateService._internal();
  factory OnboardingStateService() => _instance;
  OnboardingStateService._internal();

  final _supabase = Supabase.instance.client;
  final _superwall = SuperwallService();
  final _revenueCat = RevenueCatService();

  /// Start onboarding process
  Future<void> startOnboarding(String userId) async {
    try {
      await _supabase.from('users').update({
        'onboarding_state': OnboardingState.inProgress.value,
        'onboarding_started_at': DateTime.now().toIso8601String(),
        'onboarding_checkpoint': OnboardingCheckpoint.discovery.value,
        'updated_at': DateTime.now().toIso8601String(),
      }).eq('id', userId);

      debugPrint('[OnboardingState] Started onboarding for user $userId');
      unawaited(AnalyticsService().track('onboarding_started', properties: {
        'checkpoint': OnboardingCheckpoint.discovery.value,
      }));
    } catch (e) {
      debugPrint('[OnboardingState] Error starting onboarding: $e');
      rethrow;
    }
  }

  /// Update onboarding checkpoint
  Future<void> updateCheckpoint(String userId, OnboardingCheckpoint checkpoint) async {
    try {
      final existing = await _supabase
          .from('users')
          .select('onboarding_state, onboarding_started_at')
          .eq('id', userId)
          .maybeSingle();

      final existingState = OnboardingState.fromString(
        existing?['onboarding_state'] ?? OnboardingState.notStarted.value,
      );
      final hasStartedAt = existing?['onboarding_started_at'] != null;

      final updates = <String, dynamic>{
        'onboarding_checkpoint': checkpoint.value,
        'updated_at': DateTime.now().toIso8601String(),
      };

      // If checkpoint advances while onboarding is not_started, promote to in_progress.
      if (existingState == OnboardingState.notStarted) {
        updates['onboarding_state'] = OnboardingState.inProgress.value;
        if (!hasStartedAt) {
          updates['onboarding_started_at'] = DateTime.now().toIso8601String();
        }
      }

      await _supabase.from('users').update(updates).eq('id', userId);

      debugPrint('[OnboardingState] Updated checkpoint to ${checkpoint.value} for user $userId');
      unawaited(AnalyticsService().track('onboarding_checkpoint_updated', properties: {
        'checkpoint': checkpoint.value,
      }));
    } catch (e) {
      debugPrint('[OnboardingState] Error updating checkpoint: $e');
    }
  }

  /// Mark payment as complete during onboarding
  Future<void> markPaymentComplete(String userId) async {
    try {
      final existing = await _supabase
          .from('users')
          .select('onboarding_state')
          .eq('id', userId)
          .maybeSingle();

      final existingState = existing?['onboarding_state'] as String?;
      final alreadyCompleted =
          existingState == OnboardingState.completed.value;

      if (alreadyCompleted) {
        await _supabase.from('users').update({
          'payment_completed_at': DateTime.now().toIso8601String(),
          'updated_at': DateTime.now().toIso8601String(),
        }).eq('id', userId);
        debugPrint(
            '[OnboardingState] Payment complete for $userId - preserving completed onboarding state');
      } else {
        await _supabase.from('users').update({
          'onboarding_state': OnboardingState.paymentComplete.value,
          'payment_completed_at': DateTime.now().toIso8601String(),
          'onboarding_checkpoint': OnboardingCheckpoint.account.value,
          'updated_at': DateTime.now().toIso8601String(),
        }).eq('id', userId);
      }

      // Record trial start if applicable (check RevenueCat)
      bool isInTrial = false;
      try {
        if (!_revenueCat.isConfigured) {
          debugPrint(
              '[OnboardingState] RevenueCat not configured - skipping trial status check');
        } else {
          final customerInfo = _revenueCat.currentCustomerInfo ??
              await Purchases.getCustomerInfo();
          final activeEntitlements = customerInfo.entitlements.active.values;
          final entitlement =
              (activeEntitlements.isNotEmpty) ? activeEntitlements.first : null;
          isInTrial = entitlement?.periodType == PeriodType.trial ||
              entitlement?.periodType == PeriodType.intro;
        }
      } catch (e) {
        debugPrint('[OnboardingState] Error checking trial status: $e');
      }

      if (isInTrial) {
        await FraudPreventionService.recordTrialStart(userId);
      }

      debugPrint('[OnboardingState] Marked payment complete for user $userId (trial: $isInTrial)');
      unawaited(AnalyticsService().track('onboarding_payment_complete', properties: {
        'is_trial': isInTrial,
      }));
    } catch (e) {
      debugPrint('[OnboardingState] Error marking payment complete: $e');
      rethrow;
    }
  }

  /// Mark onboarding as complete
  Future<void> completeOnboarding(String userId) async {
    try {
      await _supabase.from('users').update({
        'onboarding_state': OnboardingState.completed.value,
        'onboarding_completed_at': DateTime.now().toIso8601String(),
        'onboarding_checkpoint': OnboardingCheckpoint.welcome.value,
        'updated_at': DateTime.now().toIso8601String(),
      }).eq('id', userId);

      debugPrint('[OnboardingState] Completed onboarding for user $userId');
      unawaited(AnalyticsService().track('onboarding_completed', properties: {
        'checkpoint': OnboardingCheckpoint.welcome.value,
      }));
    } catch (e) {
      debugPrint('[OnboardingState] Error completing onboarding: $e');
      rethrow;
    }
  }

  /// Reset onboarding to start (used when user abandons and restarts)
  Future<void> resetOnboarding(String userId) async {
    try {
      await _supabase.from('users').update({
        'onboarding_state': OnboardingState.notStarted.value,
        'onboarding_checkpoint': null,
        'onboarding_started_at': null,
        'payment_completed_at': null,
        'updated_at': DateTime.now().toIso8601String(),
      }).eq('id', userId);

      debugPrint('[OnboardingState] Reset onboarding for user $userId');
      unawaited(AnalyticsService().track('onboarding_reset'));
    } catch (e) {
      debugPrint('[OnboardingState] Error resetting onboarding: $e');
    }
  }

  /// Save user preferences during onboarding
  Future<void> saveUserPreferences({
    required String userId,
    String? preferredGenderFilter,
    bool? notificationEnabled,
    List<String>? styleDirection,
    List<String>? whatYouWant,
    String? budget,
    String? discoverySource,
  }) async {
    try {
      debugPrint('');
      debugPrint('[OnboardingState] ===== SAVING USER PREFERENCES =====');
      debugPrint('[OnboardingState] User ID: $userId');
      debugPrint('[OnboardingState] Gender filter: $preferredGenderFilter');
      debugPrint('[OnboardingState] Notification enabled: $notificationEnabled');
      debugPrint('[OnboardingState] Style direction: $styleDirection');
      debugPrint('[OnboardingState] What you want: $whatYouWant');
      debugPrint('[OnboardingState] Budget: $budget');
      debugPrint('[OnboardingState] Discovery source: $discoverySource');

      final updates = <String, dynamic>{
        'updated_at': DateTime.now().toIso8601String(),
      };

      if (preferredGenderFilter != null) {
        updates['preferred_gender_filter'] = preferredGenderFilter;
        debugPrint('[OnboardingState] Adding preferred_gender_filter to updates');
      }
      if (notificationEnabled != null) {
        updates['notification_enabled'] = notificationEnabled;
        debugPrint('[OnboardingState] Adding notification_enabled to updates');
      }
      if (styleDirection != null && styleDirection.isNotEmpty) {
        updates['style_direction'] = styleDirection;
        debugPrint('[OnboardingState] Adding style_direction to updates');
      }
      if (whatYouWant != null && whatYouWant.isNotEmpty) {
        updates['what_you_want'] = whatYouWant;
        debugPrint('[OnboardingState] Adding what_you_want to updates');
      }
      if (budget != null) {
        updates['budget'] = budget;
        debugPrint('[OnboardingState] Adding budget to updates');
      }
      if (discoverySource != null) {
        updates['discovery_source'] = discoverySource;
        debugPrint('[OnboardingState] Adding discovery_source to updates');
      }

      debugPrint('[OnboardingState] Final updates object: $updates');
      debugPrint('[OnboardingState] Executing update query...');

      await _supabase.from('users').update(updates).eq('id', userId);

      debugPrint('[OnboardingState] SUCCESS: Saved preferences for user $userId');
      debugPrint('[OnboardingState] =======================================');

      final analyticsProperties = <String, dynamic>{};
      if (preferredGenderFilter != null) {
        analyticsProperties['preferred_gender_filter'] = preferredGenderFilter;
      }
      if (notificationEnabled != null) {
        analyticsProperties['notification_enabled'] = notificationEnabled;
      }
      if (styleDirection != null && styleDirection.isNotEmpty) {
        analyticsProperties['style_direction'] = styleDirection;
      }
      if (whatYouWant != null && whatYouWant.isNotEmpty) {
        analyticsProperties['what_you_want'] = whatYouWant;
      }
      if (budget != null) {
        analyticsProperties['budget'] = budget;
      }
      if (discoverySource != null) {
        analyticsProperties['discovery_source'] = discoverySource;
      }

      if (analyticsProperties.isNotEmpty) {
        unawaited(AnalyticsService().track(
          'user_preferences_saved',
          properties: analyticsProperties,
        ));
        unawaited(AnalyticsService().setUserProperties(analyticsProperties));
      }
    } catch (e, stackTrace) {
      debugPrint('[OnboardingState] ERROR saving preferences: $e');
      debugPrint('[OnboardingState] Stack trace: $stackTrace');
      debugPrint('[OnboardingState] =======================================');
      rethrow;
    }
  }

  /// Get current onboarding state for a user
  Future<Map<String, dynamic>?> getOnboardingState(String userId) async {
    try {
      final response = await _supabase
          .from('users')
          .select('onboarding_state, onboarding_checkpoint, '
              'payment_completed_at, subscription_status, is_trial, '
              'onboarding_started_at, preferred_gender_filter')
          .eq('id', userId)
          .maybeSingle();

      return response;
    } catch (e) {
      debugPrint('[OnboardingState] Error getting onboarding state: $e');
      return null;
    }
  }

  /// Determine where user should be routed based on onboarding state
  /// Returns the route name or null if home screen
  Future<String?> determineOnboardingRoute(String userId) async {
    try {
      final state = await getOnboardingState(userId);

      debugPrint('[OnboardingState] determineOnboardingRoute for $userId:');
      debugPrint('[OnboardingState]   - Raw state object: $state');

      if (state == null) {
        debugPrint('[OnboardingState]   - State is null -> routing to discovery');
        return 'discovery';
      }

      final onboardingStateRaw = state['onboarding_state'];
      final onboardingState = OnboardingState.fromString(onboardingStateRaw ?? 'not_started');
      final subscriptionStatusRaw = state['subscription_status'];
      final subscriptionStatus = subscriptionStatusRaw ?? 'free';
      final isTrial = state['is_trial'] == true;
      final checkpoint = state['onboarding_checkpoint'];

      debugPrint('[OnboardingState]   - onboarding_state (raw): $onboardingStateRaw');
      debugPrint('[OnboardingState]   - onboarding_state (parsed): $onboardingState');
      debugPrint('[OnboardingState]   - onboarding_state (enum comparison): ${onboardingState == OnboardingState.completed}');
      debugPrint('[OnboardingState]   - onboarding_checkpoint: $checkpoint');
      debugPrint('[OnboardingState]   - subscription_status (raw): $subscriptionStatusRaw');
      debugPrint('[OnboardingState]   - subscription_status (processed): $subscriptionStatus');
      debugPrint('[OnboardingState]   - subscription_status == "active": ${subscriptionStatus == 'active'}');
      debugPrint('[OnboardingState]   - is_trial: $isTrial');

      // Check if user has completed onboarding
      if (onboardingState == OnboardingState.completed) {
        debugPrint('[OnboardingState]   - Onboarding IS completed');
        // Check if subscription is active or in trial
        final hasActiveSubscription = subscriptionStatus == 'active';
        final hasAccess = hasActiveSubscription || isTrial;
        debugPrint('[OnboardingState]   - hasActiveSubscription: $hasActiveSubscription');
        debugPrint('[OnboardingState]   - hasAccess (active || trial): $hasAccess');

        if (hasAccess) {
          debugPrint('[OnboardingState]   - Has active subscription/trial → routing to home (return null)');
          return null; // Go to home screen
        } else {
          debugPrint('[OnboardingState]   - No active subscription/trial → routing to resubscribe paywall');
          debugPrint('[OnboardingState]   - (subscription_status="$subscriptionStatus", is_trial=$isTrial)');
          // Subscription expired - show paywall
          return 'resubscribe_paywall';
        }
      }

      // Check if payment completed but onboarding not finished
      if (onboardingState == OnboardingState.paymentComplete) {
        debugPrint('[OnboardingState]   - Onboarding state is paymentComplete');

        // BUGFIX: If user has active subscription and payment was completed a while ago,
        // they likely completed onboarding but it wasn't persisted. Auto-complete and send to home.
        final hasActiveSubscription = subscriptionStatus == 'active';
        final hasAccess = hasActiveSubscription || isTrial;
        final paymentCompletedAtStr = state['payment_completed_at'];

        if (hasAccess && paymentCompletedAtStr != null) {
          try {
            final paymentCompletedAt = DateTime.parse(paymentCompletedAtStr);
            final now = DateTime.now();
            final minutesSincePayment = now.difference(paymentCompletedAt).inMinutes;

            // If payment was more than 5 minutes ago and they have subscription, auto-complete
            if (minutesSincePayment > 5) {
              debugPrint('[OnboardingState]   - Payment completed $minutesSincePayment minutes ago with active subscription');
              debugPrint('[OnboardingState]   - Auto-completing onboarding and routing to home');

              // Auto-complete the onboarding silently
              await completeOnboarding(userId);

              return null; // Go to home screen
            }
          } catch (e) {
            debugPrint('[OnboardingState]   - Error parsing payment_completed_at: $e');
            // Continue with normal flow
          }
        }

        debugPrint('[OnboardingState]   - Routing to welcome to complete onboarding');
        return 'welcome';
      }

      // Check if onboarding in progress
      if (onboardingState == OnboardingState.inProgress) {
        debugPrint('[OnboardingState]   - Onboarding state is inProgress');
        final checkpoint = OnboardingCheckpoint.fromString(state['onboarding_checkpoint']);

        // If user reached save_progress or paywall checkpoint, they likely created an account
        // Send them back to paywall instead of resetting
        if (checkpoint == OnboardingCheckpoint.saveProgress ||
            checkpoint == OnboardingCheckpoint.paywall) {
          debugPrint('[OnboardingState] User abandoned at paywall - sending back to paywall');
          return 'paywall';
        }

        // Otherwise, reset onboarding if they closed app before creating account
        await resetOnboarding(userId);
        return 'discovery';
      }

      // Onboarding not started
      return 'discovery';
    } catch (e) {
      debugPrint('[OnboardingState] Error determining route: $e');
      return 'discovery'; // Default to start of onboarding
    }
  }

  /// Check if user can access home screen
  Future<bool> canAccessHome(String userId) async {
    try {
      final state = await getOnboardingState(userId);
      if (state == null) return false;

      final onboardingState = OnboardingState.fromString(state['onboarding_state'] ?? 'not_started');
      final subscriptionStatus = state['subscription_status'] ?? 'free';
      final isTrial = state['is_trial'] == true;

      // User must complete onboarding AND have active subscription or trial
      return onboardingState == OnboardingState.completed && (subscriptionStatus == 'active' || isTrial);
    } catch (e) {
      debugPrint('[OnboardingState] Error checking home access: $e');
      return false;
    }
  }

  /// Update device fingerprint for user
  Future<void> updateDeviceFingerprint(String userId) async {
    try {
      await FraudPreventionService.updateUserDeviceFingerprint(userId);
    } catch (e) {
      debugPrint('[OnboardingState] Error updating device fingerprint: $e');
    }
  }

  /// Check if user is eligible for trial
  Future<bool> isEligibleForTrial() async {
    try {
      return await FraudPreventionService.isDeviceEligibleForTrial();
    } catch (e) {
      debugPrint('[OnboardingState] Error checking trial eligibility: $e');
      return true; // Default to eligible if check fails
    }
  }
}
