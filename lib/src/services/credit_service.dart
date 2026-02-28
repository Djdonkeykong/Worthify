import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../features/paywall/models/credit_balance.dart';
import '../features/paywall/models/subscription_plan.dart';
import 'superwall_service.dart';

/// Service for managing user credits
class CreditService {
  static final CreditService _instance = CreditService._internal();
  factory CreditService() => _instance;
  CreditService._internal();

  final SuperwallService _superwallService = SuperwallService();

  static const String _creditBalanceKey = 'credit_balance';
  static const String _lastRefillDateKey = 'last_refill_date';
  static const String _freeTrialUsedKey = 'free_trial_used';

  CreditBalance? _cachedBalance;

  /// Get current credit balance from Supabase
  Future<CreditBalance> getCreditBalance() async {
    // Return cached balance if available
    if (_cachedBalance != null) {
      debugPrint('[CreditService] Returning cached balance: ${_cachedBalance!.availableCredits} credits');
      return _cachedBalance!;
    }

    try {
      final userId = Supabase.instance.client.auth.currentUser?.id;

      if (userId == null) {
        debugPrint('[CreditService] No authenticated user');
        return CreditBalance.empty();
      }

      // Fetch credits from Supabase users table
      final userResponse = await Supabase.instance.client
          .from('users')
          .select(
              'paid_credits_remaining, subscription_status, is_trial, subscription_product_id, credits_reset_date')
          .eq('id', userId)
          .maybeSingle()
          .timeout(const Duration(seconds: 5));

      if (userResponse == null) {
        debugPrint('[CreditService] User not found in database');
        return CreditBalance.empty();
      }

      final paidCredits = userResponse['paid_credits_remaining'] ?? 0;
      final subscriptionStatus = userResponse['subscription_status'] ?? 'free';
      final isTrial = userResponse['is_trial'] == true;
      final subscriptionProductId =
          userResponse['subscription_product_id'] as String?;
      final creditsResetRaw = userResponse['credits_reset_date'] as String?;
      final creditsResetDate =
          creditsResetRaw != null ? DateTime.tryParse(creditsResetRaw) : null;
      final hasActiveSubscription = subscriptionStatus == 'active' || isTrial;

      // Get subscription status from Superwall for product ID
      final superwallStatus = _superwallService.getSubscriptionSnapshot();

      _cachedBalance = CreditBalance(
        availableCredits: paidCredits,
        totalCredits: paidCredits,
        hasActiveSubscription: hasActiveSubscription,
        hasUsedFreeTrial: true, // All users are now paid users
        isTrialSubscription: isTrial,
        nextRefillDate:
            creditsResetDate ?? _calculateNextRefillDate(),
        subscriptionPlanId:
            subscriptionProductId ?? superwallStatus.productIdentifier,
      );

      debugPrint('[CreditService] Loaded balance from Supabase: $paidCredits credits, active: $hasActiveSubscription');
      return _cachedBalance!;
    } catch (e) {
      debugPrint('[CreditService] Error getting credit balance: $e');
      return CreditBalance.empty();
    }
  }

  /// Consume one credit for an action
  Future<CreditBalance> consumeCredit() async {
    try {
      final balance = await getCreditBalance();

      if (!balance.canPerformAction) {
        throw Exception('No credits available');
      }

      // Mark free trial as used if this is the first credit consumption
      if (balance.isInFreeTrial) {
        await _markFreeTrialAsUsed();
      }

      _cachedBalance = balance.consumeCredit();
      await _saveCreditBalance(_cachedBalance!);

      debugPrint('Credit consumed. Remaining: ${_cachedBalance!.availableCredits}');
      return _cachedBalance!;
    } catch (e) {
      debugPrint('Error consuming credit: $e');
      rethrow;
    }
  }

  /// Refill credits (called when subscription is renewed monthly)
  Future<CreditBalance> refillCredits() async {
    try {
      final subscriptionStatus = _superwallService.getSubscriptionSnapshot();

      if (!subscriptionStatus.isActive) {
        throw Exception('No active subscription');
      }

      final plan = SubscriptionPlan.getPlanByProductId(
            subscriptionStatus.productIdentifier ?? SubscriptionPlan.yearly.productId) ??
          SubscriptionPlan.yearly;

      if (plan == null) {
        throw Exception('Unknown subscription plan');
      }

      _cachedBalance = (await getCreditBalance()).refillCredits(plan.creditsPerMonth);
      _cachedBalance = _cachedBalance!.copyWith(
        nextRefillDate: _calculateNextRefillDate(),
      );

      await _saveCreditBalance(_cachedBalance!);
      await _saveLastRefillDate(DateTime.now());

      debugPrint('Credits refilled. New balance: ${_cachedBalance!.availableCredits}');
      return _cachedBalance!;
    } catch (e) {
      debugPrint('Error refilling credits: $e');
      rethrow;
    }
  }

  /// Check if credits need to be refilled (monthly check)
  Future<CreditBalance> _checkAndRefillCredits(CreditBalance currentBalance) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final lastRefillDateString = prefs.getString(_lastRefillDateKey);

      if (lastRefillDateString == null) {
        // First time - refill now
        return await refillCredits();
      }

      final lastRefillDate = DateTime.parse(lastRefillDateString);
      final now = DateTime.now();

      // Check if a month has passed since last refill
      final monthsSinceRefill = _monthsBetween(lastRefillDate, now);

      if (monthsSinceRefill >= 1) {
        debugPrint('Monthly refill due. Last refill: $lastRefillDate');
        return await refillCredits();
      }

      return currentBalance;
    } catch (e) {
      debugPrint('Error checking refill: $e');
      return currentBalance;
    }
  }

  /// Calculate months between two dates
  int _monthsBetween(DateTime from, DateTime to) {
    return (to.year - from.year) * 12 + to.month - from.month;
  }

  /// Calculate next refill date (start of next month)
  DateTime _calculateNextRefillDate() {
    final now = DateTime.now();
    return DateTime(now.year, now.month + 1, 1);
  }

  /// Save credit balance to local storage
  Future<void> _saveCreditBalance(CreditBalance balance) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final jsonString = jsonEncode(balance.toJson());
      await prefs.setString(_creditBalanceKey, jsonString);
      debugPrint('Credit balance saved: $balance');
    } catch (e) {
      debugPrint('Error saving credit balance: $e');
    }
  }

  /// Save last refill date
  Future<void> _saveLastRefillDate(DateTime date) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_lastRefillDateKey, date.toIso8601String());
    } catch (e) {
      debugPrint('Error saving refill date: $e');
    }
  }

  /// Mark free trial as used
  Future<void> _markFreeTrialAsUsed() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_freeTrialUsedKey, true);
      debugPrint('Free trial marked as used');
    } catch (e) {
      debugPrint('Error marking free trial as used: $e');
    }
  }

  /// Sync credits with subscription status (call after purchase/restore)
  Future<CreditBalance> syncWithSubscription() async {
    try {
      // Always re-fetch from Supabase to avoid local drift.
      _cachedBalance = null;
      return await getCreditBalance();
    } catch (e) {
      debugPrint('Error syncing with subscription: $e');
      rethrow;
    }
  }

  /// Reset credit balance (for testing/debugging)
  Future<void> resetCredits() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_creditBalanceKey);
      await prefs.remove(_lastRefillDateKey);
      await prefs.remove(_freeTrialUsedKey);
      _cachedBalance = null;
      debugPrint('Credits reset');
    } catch (e) {
      debugPrint('Error resetting credits: $e');
    }
  }

  /// Clear cached balance (force reload on next access)
  void clearCache() {
    _cachedBalance = null;
    debugPrint('[CreditService] Cache cleared');
  }

  /// SECURITY: Clear all sensitive credit data on logout
  Future<void> clearOnLogout() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_creditBalanceKey);
    await prefs.remove(_lastRefillDateKey);
    await prefs.remove(_freeTrialUsedKey);
    _cachedBalance = null;
    debugPrint('[Security] Credit data cleared on logout');
  }
}
