/// Subscription plan model for Superwall integration
class SubscriptionPlan {
  final String id;
  final String name;
  final String productId; // Store product identifier
  final double price;
  final String priceString;
  final int creditsPerMonth;
  final bool hasTrial;
  final int trialDays;
  final SubscriptionDuration duration;

  const SubscriptionPlan({
    required this.id,
    required this.name,
    required this.productId,
    required this.price,
    required this.priceString,
    required this.creditsPerMonth,
    this.hasTrial = false,
    this.trialDays = 0,
    required this.duration,
  });

  /// Monthly subscription plan
  static const monthly = SubscriptionPlan(
    id: 'monthly',
    name: 'Monthly',
    productId: 'worthify_premium_monthly',
    price: 7.99,
    priceString: '\$7.99/mo',
    creditsPerMonth: 100, // 100 scans per month
    hasTrial: false,
    trialDays: 0,
    duration: SubscriptionDuration.monthly,
  );

  /// Yearly subscription plan with 3-day free trial
  static const yearly = SubscriptionPlan(
    id: 'yearly',
    name: 'Yearly',
    productId: 'worthify_premium_yearly',
    price: 59.99,
    priceString: '\$4.99/mo',
    creditsPerMonth: 100, // 100 scans per month (refills monthly)
    hasTrial: true,
    trialDays: 3,
    duration: SubscriptionDuration.yearly,
  );

  /// Get all available subscription plans
  static List<SubscriptionPlan> get allPlans => [monthly, yearly];

  /// Get plan by ID
  static SubscriptionPlan? getPlanById(String id) {
    try {
      return allPlans.firstWhere((plan) => plan.id == id);
    } catch (e) {
      return null;
    }
  }

  /// Get plan by product ID
  static SubscriptionPlan? getPlanByProductId(String productId) {
    try {
      return allPlans.firstWhere((plan) => plan.productId == productId);
    } catch (e) {
      return null;
    }
  }
}

enum SubscriptionDuration {
  monthly,
  yearly,
}

extension SubscriptionDurationExtension on SubscriptionDuration {
  String get displayName {
    switch (this) {
      case SubscriptionDuration.monthly:
        return 'Monthly';
      case SubscriptionDuration.yearly:
        return 'Yearly';
    }
  }

  int get months {
    switch (this) {
      case SubscriptionDuration.monthly:
        return 1;
      case SubscriptionDuration.yearly:
        return 12;
    }
  }
}
