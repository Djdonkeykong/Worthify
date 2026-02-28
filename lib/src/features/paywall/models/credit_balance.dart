import 'package:equatable/equatable.dart';

/// Represents the user's credit balance and subscription status
class CreditBalance extends Equatable {
  final int availableCredits;
  final int totalCredits;
  final bool hasActiveSubscription;
  final bool hasUsedFreeTrial;
  final bool isTrialSubscription;
  final DateTime? nextRefillDate;
  final String? subscriptionPlanId;

  const CreditBalance({
    required this.availableCredits,
    required this.totalCredits,
    this.hasActiveSubscription = false,
    this.hasUsedFreeTrial = false,
    this.isTrialSubscription = false,
    this.nextRefillDate,
    this.subscriptionPlanId,
  });

  /// Initial state for new users (1 free credit)
  factory CreditBalance.initial() {
    return const CreditBalance(
      availableCredits: 1,
      totalCredits: 1,
      hasActiveSubscription: false,
      hasUsedFreeTrial: false,
    );
  }

  /// State when user has no credits and no subscription
  factory CreditBalance.empty() {
    return const CreditBalance(
      availableCredits: 0,
      totalCredits: 0,
      hasActiveSubscription: false,
      hasUsedFreeTrial: true,
    );
  }

  /// Check if user can perform an action
  bool get canPerformAction => availableCredits > 0;

  /// Check if user needs to see paywall
  bool get needsPaywall => !hasActiveSubscription && availableCredits == 0;

  /// Check if user is in free trial period
  bool get isInFreeTrial => !hasUsedFreeTrial && availableCredits == 1;

  /// Copy with method for state updates
  CreditBalance copyWith({
    int? availableCredits,
    int? totalCredits,
    bool? hasActiveSubscription,
    bool? hasUsedFreeTrial,
    bool? isTrialSubscription,
    DateTime? nextRefillDate,
    String? subscriptionPlanId,
  }) {
    return CreditBalance(
      availableCredits: availableCredits ?? this.availableCredits,
      totalCredits: totalCredits ?? this.totalCredits,
      hasActiveSubscription: hasActiveSubscription ?? this.hasActiveSubscription,
      hasUsedFreeTrial: hasUsedFreeTrial ?? this.hasUsedFreeTrial,
      isTrialSubscription: isTrialSubscription ?? this.isTrialSubscription,
      nextRefillDate: nextRefillDate ?? this.nextRefillDate,
      subscriptionPlanId: subscriptionPlanId ?? this.subscriptionPlanId,
    );
  }

  /// Consume one credit
  CreditBalance consumeCredit() {
    if (availableCredits <= 0) {
      throw Exception('No credits available to consume');
    }
    return copyWith(availableCredits: availableCredits - 1);
  }

  /// Refill credits (monthly refill for subscribers)
  CreditBalance refillCredits(int amount) {
    return copyWith(
      availableCredits: amount,
      totalCredits: amount,
    );
  }

  /// Convert to JSON for storage
  Map<String, dynamic> toJson() {
    return {
      'availableCredits': availableCredits,
      'totalCredits': totalCredits,
      'hasActiveSubscription': hasActiveSubscription,
      'hasUsedFreeTrial': hasUsedFreeTrial,
      'isTrialSubscription': isTrialSubscription,
      'nextRefillDate': nextRefillDate?.toIso8601String(),
      'subscriptionPlanId': subscriptionPlanId,
    };
  }

  /// Create from JSON
  factory CreditBalance.fromJson(Map<String, dynamic> json) {
    return CreditBalance(
      availableCredits: json['availableCredits'] as int? ?? 0,
      totalCredits: json['totalCredits'] as int? ?? 0,
      hasActiveSubscription: json['hasActiveSubscription'] as bool? ?? false,
      hasUsedFreeTrial: json['hasUsedFreeTrial'] as bool? ?? false,
      isTrialSubscription: json['isTrialSubscription'] as bool? ?? false,
      nextRefillDate: json['nextRefillDate'] != null
          ? DateTime.parse(json['nextRefillDate'] as String)
          : null,
      subscriptionPlanId: json['subscriptionPlanId'] as String?,
    );
  }

  @override
  List<Object?> get props => [
        availableCredits,
        totalCredits,
        hasActiveSubscription,
        hasUsedFreeTrial,
        isTrialSubscription,
        nextRefillDate,
        subscriptionPlanId,
      ];

  @override
  String toString() {
    return 'CreditBalance(availableCredits: $availableCredits, totalCredits: $totalCredits, hasActiveSubscription: $hasActiveSubscription, hasUsedFreeTrial: $hasUsedFreeTrial, isTrialSubscription: $isTrialSubscription)';
  }
}
