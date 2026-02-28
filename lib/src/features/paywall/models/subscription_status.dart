import 'package:equatable/equatable.dart';
import '../../../services/superwall_service.dart';

/// Represents the user's subscription status (Superwall-backed).
class SubscriptionStatus extends Equatable {
  final bool isActive;
  final bool isInTrialPeriod;
  final String? productIdentifier;
  final DateTime? expirationDate;
  final DateTime? purchaseDate;

  const SubscriptionStatus({
    required this.isActive,
    this.isInTrialPeriod = false,
    this.productIdentifier,
    this.expirationDate,
    this.purchaseDate,
  });

  factory SubscriptionStatus.fromSnapshot(SubscriptionStatusSnapshot snapshot) {
    return SubscriptionStatus(
      isActive: snapshot.isActive,
      isInTrialPeriod: snapshot.isInTrialPeriod,
      productIdentifier: snapshot.productIdentifier,
      expirationDate: snapshot.expirationDate,
    );
  }

  factory SubscriptionStatus.initial() {
    return const SubscriptionStatus(
      isActive: false,
      isInTrialPeriod: false,
    );
  }

  bool get isExpired {
    if (expirationDate == null) return false;
    return DateTime.now().isAfter(expirationDate!);
  }

  int? get daysRemainingInTrial {
    if (!isInTrialPeriod || expirationDate == null) return null;
    final daysRemaining = expirationDate!.difference(DateTime.now()).inDays;
    return daysRemaining > 0 ? daysRemaining : 0;
  }

  int? get daysUntilExpiration {
    if (expirationDate == null) return null;
    final daysRemaining = expirationDate!.difference(DateTime.now()).inDays;
    return daysRemaining > 0 ? daysRemaining : 0;
  }

  bool get shouldShowRenewalReminder {
    final daysRemaining = daysUntilExpiration;
    if (daysRemaining == null) return false;
    return daysRemaining <= 3 && daysRemaining > 0;
  }

  @override
  List<Object?> get props => [
        isActive,
        isInTrialPeriod,
        productIdentifier,
        expirationDate,
        purchaseDate,
      ];

  @override
  String toString() {
    return 'SubscriptionStatus(isActive: $isActive, isInTrialPeriod: $isInTrialPeriod, productIdentifier: $productIdentifier, expirationDate: $expirationDate)';
  }
}
