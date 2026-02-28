import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:purchases_flutter/purchases_flutter.dart';

/// Service to manage RevenueCat SDK configuration and purchases
class RevenueCatService {
  RevenueCatService._internal();
  static final RevenueCatService _instance = RevenueCatService._internal();
  factory RevenueCatService() => _instance;

  bool _configured = false;
  bool _logHandlerInstalled = false;
  CustomerInfo? _customerInfo;
  Offerings? _cachedOfferings;

  /// Initialize RevenueCat with API key
  Future<void> initialize({required String apiKey, String? userId}) async {
    if (_configured) return;

    try {
      if (kDebugMode) {
        await Purchases.setLogLevel(LogLevel.debug);
        if (!_logHandlerInstalled) {
          await Purchases.setLogHandler((level, message) {
            debugPrint('[RevenueCatSDK][${level.name}] $message');
          });
          _logHandlerInstalled = true;
        }
      }

      // Configure RevenueCat SDK
      await Purchases.configure(
        PurchasesConfiguration(apiKey)..appUserID = userId,
      );

      _configured = true;

      if (kDebugMode) {
        debugPrint('[RevenueCat] Configured successfully');
        debugPrint('[RevenueCat] User: ${userId ?? 'anonymous'}');
      }

      // Don't fetch customer info immediately to avoid "Sign in to Apple Account" popup
      // Customer info will be fetched lazily when needed (during paywall display, restore, etc.)

      // Preload offerings for faster paywall display
      preloadOfferings();
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[RevenueCat] Configuration failed: $e');
      }
      rethrow;
    }
  }

  /// Preload offerings in the background
  void preloadOfferings() {
    if (!_configured) return;

    getOfferings().then((offerings) {
      if (kDebugMode && offerings != null) {
        debugPrint('[RevenueCat] Offerings preloaded successfully');
      }
    }).catchError((e) {
      if (kDebugMode) {
        debugPrint('[RevenueCat] Preload offerings error: $e');
      }
    });
  }

  /// Identify a user
  Future<void> identify(String userId) async {
    if (!_configured) {
      if (kDebugMode) {
        debugPrint(
            '[RevenueCat] identify called but not configured - skipping');
      }
      return;
    }

    try {
      await Purchases.logIn(userId);
      _customerInfo = await Purchases.getCustomerInfo();

      if (kDebugMode) {
        debugPrint('[RevenueCat] User identified: $userId');
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[RevenueCat] Error identifying user: $e');
      }
    }
  }

  /// Log out current user
  Future<void> logOut() async {
    if (!_configured) {
      if (kDebugMode) {
        debugPrint('[RevenueCat] logOut called but not configured - skipping');
      }
      return;
    }

    try {
      _customerInfo = await Purchases.logOut();

      if (kDebugMode) {
        debugPrint('[RevenueCat] User logged out');
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[RevenueCat] Error logging out: $e');
      }
    }
  }

  /// Get available offerings (uses cache if available)
  Future<Offerings?> getOfferings() async {
    if (!_configured) {
      if (kDebugMode) {
        debugPrint('[RevenueCat] getOfferings called but not configured');
      }
      return null;
    }

    // Return cached offerings if available
    if (_cachedOfferings != null) {
      if (kDebugMode) {
        debugPrint(
            '[RevenueCat] Returning cached offerings: ${_cachedOfferings!.current?.identifier}');
      }
      return _cachedOfferings;
    }

    try {
      final offerings = await Purchases.getOfferings();
      _cachedOfferings = offerings;

      if (kDebugMode) {
        final current = offerings.current;
        final allKeys = offerings.all.keys.toList(growable: false);
        debugPrint(
          '[RevenueCat] Fetched offerings: current=${current?.identifier ?? "null"} all=$allKeys',
        );
        if (current != null) {
          for (final pkg in current.availablePackages) {
            debugPrint(
              '[RevenueCat] Package ${pkg.identifier} product=${pkg.storeProduct.identifier} price=${pkg.storeProduct.priceString}',
            );
          }
        }
      }

      return offerings;
    } on PlatformException catch (e) {
      final errorCode = PurchasesErrorHelper.getErrorCode(e);
      if (kDebugMode) {
        debugPrint(
          '[RevenueCat] Error fetching offerings: code=$errorCode message=${e.message}',
        );
      }
      return null;
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[RevenueCat] Error fetching offerings: $e');
      }
      return null;
    }
  }

  /// Purchase a package
  Future<bool> purchasePackage(Package package) async {
    if (!_configured) {
      if (kDebugMode) {
        debugPrint('[RevenueCat] purchasePackage called but not configured');
      }
      return false;
    }

    try {
      if (kDebugMode) {
        debugPrint('[RevenueCat] Purchasing package: ${package.identifier}');
      }

      final customerInfo = await Purchases.purchasePackage(package);
      _customerInfo = customerInfo;

      final hasActiveEntitlement =
          _customerInfo?.entitlements.active.isNotEmpty ?? false;

      if (kDebugMode) {
        debugPrint(
            '[RevenueCat] Purchase completed - Has active entitlement: $hasActiveEntitlement');
      }

      return hasActiveEntitlement;
    } on PlatformException catch (e) {
      final errorCode = PurchasesErrorHelper.getErrorCode(e);
      if (errorCode == PurchasesErrorCode.purchaseCancelledError) {
        if (kDebugMode) {
          debugPrint('[RevenueCat] Purchase cancelled by user');
        }
        return false;
      }
      if (kDebugMode) {
        debugPrint('[RevenueCat] Purchase error: ${e.message}');
      }
      return false;
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[RevenueCat] Purchase error: $e');
      }
      return false;
    }
  }

  /// Restore purchases
  Future<bool> restorePurchases() async {
    if (!_configured) {
      if (kDebugMode) {
        debugPrint('[RevenueCat] restorePurchases called but not configured');
      }
      return false;
    }

    try {
      if (kDebugMode) {
        debugPrint('[RevenueCat] Restoring purchases...');
      }

      _customerInfo = await Purchases.restorePurchases();
      final hasActiveEntitlement =
          _customerInfo?.entitlements.active.isNotEmpty ?? false;

      if (kDebugMode) {
        debugPrint(
            '[RevenueCat] Restore completed - Has active entitlement: $hasActiveEntitlement');
      }

      return hasActiveEntitlement;
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[RevenueCat] Restore error: $e');
      }
      return false;
    }
  }

  /// Check if user has active subscription
  Future<bool> hasActiveSubscription() async {
    if (!_configured) return false;

    try {
      final customerInfo = await Purchases.getCustomerInfo();
      _customerInfo = customerInfo;

      return customerInfo.entitlements.active.containsKey('premium');
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[RevenueCat] Error checking subscription: $e');
      }
      return false;
    }
  }

  /// Check if user is eligible for intro offer (free trial)
  /// Returns true if user has never used a trial before
  Future<bool> isEligibleForTrial() async {
    if (!_configured) return true; // Default to eligible if not configured

    try {
      final offerings = await getOfferings();
      if (offerings?.current?.annual == null) return true;

      final yearlyPackage = offerings!.current!.annual!;

      // Check if product has an intro offer and user is eligible
      final product = yearlyPackage.storeProduct;

      // If there's an introductory price and the product has eligibility info
      if (product.introductoryPrice != null) {
        // Check customer info for past subscriptions
        final customerInfo = _customerInfo ?? await Purchases.getCustomerInfo();

        // User is NOT eligible if they have any non-subscription purchases for this product
        // or if they've already subscribed to this product in the past
        final allPurchasedProductIds =
            customerInfo.allPurchasedProductIdentifiers;

        // If user has purchased the yearly product before, they're not eligible for trial
        if (allPurchasedProductIds.contains(product.identifier)) {
          if (kDebugMode) {
            debugPrint(
                '[RevenueCat] User NOT eligible for trial - already purchased ${product.identifier}');
          }
          return false;
        }
      }

      if (kDebugMode) {
        debugPrint('[RevenueCat] User IS eligible for trial');
      }
      return true;
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[RevenueCat] Error checking trial eligibility: $e');
      }
      return true; // Default to eligible on error
    }
  }

  /// Returns true if the user appears to have consumed a trial/intro previously.
  /// Used to avoid routing known ineligible users through trial-intro UI.
  Future<bool> hasUsedFreeTrialBefore() async {
    if (!_configured) return false;

    try {
      final customerInfo = _customerInfo ?? await Purchases.getCustomerInfo();
      _customerInfo = customerInfo;

      final hadIntroPeriod = customerInfo.entitlements.all.values.any((ent) =>
          ent.periodType == PeriodType.trial ||
          ent.periodType == PeriodType.intro);
      if (hadIntroPeriod) {
        if (kDebugMode) {
          debugPrint(
              '[RevenueCat] Trial history detected via entitlement periodType');
        }
        return true;
      }

      final purchasedIds = customerInfo.allPurchasedProductIdentifiers
          .map((id) => id.toLowerCase())
          .toSet();
      final hasYearlyHistory = purchasedIds.any((id) =>
          id == 'com.worthify.worthify.yearly' ||
          id.startsWith('com.worthify.worthify.yearly:'));

      if (kDebugMode) {
        debugPrint(
            '[RevenueCat] Trial history fallback check (yearly purchase): $hasYearlyHistory');
      }
      return hasYearlyHistory;
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[RevenueCat] Error checking trial history: $e');
      }
      return false;
    }
  }

  /// Get current customer info
  CustomerInfo? get currentCustomerInfo => _customerInfo;

  /// Check if configured
  bool get isConfigured => _configured;
}
