import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:purchases_flutter/purchases_flutter.dart';
import 'superwall_service.dart';
import 'revenuecat_service.dart';

/// Service for syncing subscription data between RevenueCat and Supabase.
class SubscriptionSyncService {
  static final SubscriptionSyncService _instance =
      SubscriptionSyncService._internal();
  factory SubscriptionSyncService() => _instance;
  SubscriptionSyncService._internal();

  final _supabase = Supabase.instance.client;
  final _superwall = SuperwallService();
  final _revenueCat = RevenueCatService();
  static const MethodChannel _authChannel = MethodChannel('worthify/auth');

  /// Sync subscription data from RevenueCat to Supabase.
  /// Call this after:
  /// - Successful paywall flow
  /// - User login
  /// - App startup (if authenticated)
  Future<void> syncSubscriptionToSupabase() async {
    try {
      final user = _supabase.auth.currentUser;
      if (user == null) {
        debugPrint('[SubscriptionSync] No authenticated user - skipping sync');
        return;
      }

      debugPrint(
          '[SubscriptionSync] Starting RevenueCat sync for user ${user.id}');

      // Get FRESH RevenueCat customer info (don't use cache after purchase)
      CustomerInfo? customerInfo;
      try {
        if (!_revenueCat.isConfigured) {
          debugPrint(
              '[SubscriptionSync] RevenueCat not configured - skipping customer info fetch');
          await _syncShareExtensionAuthSnapshot(userId: user.id);
          return;
        }
        customerInfo = await Purchases.getCustomerInfo();
        debugPrint(
            '[SubscriptionSync] Fetched fresh customer info from RevenueCat');
      } catch (e) {
        debugPrint(
            '[SubscriptionSync] Error fetching RevenueCat customer info: $e');
        await _syncShareExtensionAuthSnapshot(userId: user.id);
        return;
      }

      // Parse RevenueCat subscription data
      final activeEntitlements = customerInfo.entitlements.active.values;
      final entitlement =
          (activeEntitlements.isNotEmpty) ? activeEntitlements.first : null;
      final hasActiveRevenueCat = entitlement != null;
      final isTrial = entitlement?.periodType == PeriodType.trial ||
          entitlement?.periodType == PeriodType.intro;
      final expirationDateIso = entitlement?.expirationDate != null
          ? DateTime.tryParse(entitlement!.expirationDate!)?.toIso8601String()
          : null;
      final productId = entitlement?.productIdentifier;
      final revenueCatUserId = customerInfo.originalAppUserId;

      debugPrint('[SubscriptionSync] RevenueCat data:');
      debugPrint('  - originalAppUserId: $revenueCatUserId');
      debugPrint('  - hasActiveSubscription: $hasActiveRevenueCat');
      debugPrint('  - isTrial: $isTrial');
      debugPrint('  - productId: $productId');
      debugPrint('  - expiresAt: $expirationDateIso');

      // Check if user has credits (users with credits should not have their status overwritten to 'free')
      final userResponse = await _supabase
          .from('users')
          .select(
              'paid_credits_remaining, subscription_status, subscription_expires_at, subscription_product_id, is_trial')
          .eq('id', user.id)
          .maybeSingle();

      final hasCredits = (userResponse?['paid_credits_remaining'] ?? 0) > 0;
      final currentStatus = userResponse?['subscription_status'] ?? 'free';

      // Determine what to sync
      if (hasActiveRevenueCat) {
        // RevenueCat says active - sync all data from RevenueCat
        const subscriptionStatus = 'active';

        await _supabase.from('users').upsert({
          'id': user.id,
          'revenue_cat_user_id': revenueCatUserId,
          'subscription_status': subscriptionStatus,
          'subscription_expires_at': expirationDateIso,
          'subscription_product_id': productId,
          'is_trial': isTrial,
          'subscription_last_synced_at': DateTime.now().toIso8601String(),
          'updated_at': DateTime.now().toIso8601String(),
        }, onConflict: 'id');

        debugPrint(
            '[SubscriptionSync] Sync complete - Status: $subscriptionStatus, Trial: $isTrial, Expires: $expirationDateIso');

        // Also sync status to Superwall so it knows about the subscription
        await _superwall.syncSubscriptionStatus();
      } else if (hasCredits &&
          (currentStatus == 'active' || currentStatus == 'expired')) {
        // User has credits but no active RevenueCat subscription
        // Preserve their existing subscription data entirely (don't overwrite with nulls)
        // Only update the sync timestamp
        await _supabase.from('users').update({
          'subscription_last_synced_at': DateTime.now().toIso8601String(),
          'updated_at': DateTime.now().toIso8601String(),
        }).eq('id', user.id);

        debugPrint(
            '[SubscriptionSync] User has credits - preserving existing subscription data. Status: $currentStatus');

        // Sync status to Superwall
        await _superwall.syncSubscriptionStatus();
      } else {
        // No RevenueCat subscription and no credits - set to free or expired
        String subscriptionStatus = 'free';
        if (expirationDateIso != null) {
          final expirationDate = DateTime.parse(expirationDateIso);
          if (expirationDate.isBefore(DateTime.now())) {
            subscriptionStatus = 'expired';
          }
        }

        await _supabase.from('users').upsert({
          'id': user.id,
          'revenue_cat_user_id': revenueCatUserId,
          'subscription_status': subscriptionStatus,
          'subscription_expires_at': expirationDateIso,
          'subscription_product_id': productId,
          'is_trial': isTrial,
          'subscription_last_synced_at': DateTime.now().toIso8601String(),
          'updated_at': DateTime.now().toIso8601String(),
        }, onConflict: 'id');

        // Sync status to Superwall
        await _superwall.syncSubscriptionStatus();
      }

      await _syncShareExtensionAuthSnapshot(userId: user.id);
    } catch (e, stackTrace) {
      debugPrint('[SubscriptionSync] Error syncing subscription: $e');
      debugPrint('[SubscriptionSync] Stack trace: $stackTrace');
    }
  }

  Future<void> _syncShareExtensionAuthSnapshot({required String userId}) async {
    try {
      final userResponse = await _supabase
          .from('users')
          .select('subscription_status, is_trial, paid_credits_remaining')
          .eq('id', userId)
          .maybeSingle();

      final subscriptionStatus = userResponse?['subscription_status'] ?? 'free';
      final isTrial = userResponse?['is_trial'] == true;
      final hasActiveSubscription = subscriptionStatus == 'active' || isTrial;
      final creditsRaw = userResponse?['paid_credits_remaining'];
      final availableCredits =
          creditsRaw is int ? creditsRaw : (creditsRaw as num?)?.toInt() ?? 0;
      final accessToken = _supabase.auth.currentSession?.accessToken;

      await _authChannel.invokeMethod('setAuthFlag', {
        'isAuthenticated': true,
        'userId': userId,
        'hasActiveSubscription': hasActiveSubscription,
        'availableCredits': availableCredits,
        'accessToken': accessToken,
      });

      debugPrint(
        '[SubscriptionSync] Synced share extension auth snapshot: '
        'subscription=$hasActiveSubscription, credits=$availableCredits',
      );
    } catch (e) {
      debugPrint(
          '[SubscriptionSync] Failed to sync share extension auth snapshot: $e');
    }
  }

  /// Get cached subscription status from Supabase
  /// This is fast but may be slightly out of date.
  Future<Map<String, dynamic>?> getCachedSubscriptionStatus() async {
    try {
      final user = _supabase.auth.currentUser;
      if (user == null) return null;

      final response = await _supabase
          .from('users')
          .select(
              'subscription_status, subscription_expires_at, is_trial, subscription_last_synced_at')
          .eq('id', user.id)
          .single();

      return response;
    } catch (e) {
      debugPrint('[SubscriptionSync] Error getting cached status: $e');
      return null;
    }
  }

  /// Check if cached subscription data is stale (older than 1 hour).
  Future<bool> isCacheStale() async {
    try {
      final cached = await getCachedSubscriptionStatus();
      if (cached == null) return true;

      final lastSynced = cached['subscription_last_synced_at'] as String?;
      if (lastSynced == null) return true;

      final lastSyncedDate = DateTime.parse(lastSynced);
      final hoursSinceSync = DateTime.now().difference(lastSyncedDate).inHours;

      return hoursSinceSync > 1;
    } catch (e) {
      debugPrint('[SubscriptionSync] Error checking cache staleness: $e');
      return true; // If error, assume stale
    }
  }

  /// Identify user with RevenueCat and Superwall.
  /// This links any anonymous purchases to the identified user.
  Future<void> identify(String userId) async {
    debugPrint('[SubscriptionSync] Identifying user $userId with RevenueCat');

    // Identify with RevenueCat - this merges anonymous purchases with the user account
    await _revenueCat.identify(userId);

    // Also identify with Superwall (for backwards compatibility)
    await _superwall.identify(userId);

    // Sync subscription data to Supabase
    await syncSubscriptionToSupabase();
  }

  /// Identify user with Superwall (deprecated - use identify() instead).
  @deprecated
  Future<void> identifyWithSuperwall(String userId) async {
    await identify(userId);
  }

  /// Reset RevenueCat and Superwall identity on logout.
  Future<void> resetOnLogout() async {
    await _revenueCat.logOut();
    await _superwall.reset();
  }
}
