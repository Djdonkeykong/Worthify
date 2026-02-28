import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:purchases_flutter/purchases_flutter.dart';
import 'package:superwallkit_flutter/superwallkit_flutter.dart' as sw;

/// RevenueCat purchase controller for Superwall
/// This allows Superwall to use RevenueCat for purchases and access trial eligibility
class RCPurchaseController extends sw.PurchaseController {
  @override
  Future<sw.PurchaseResult> purchaseFromAppStore(String productId) async {
    try {
      if (kDebugMode) {
        debugPrint('[RCPurchaseController] Purchasing iOS product: $productId');
      }

      // Find the RevenueCat package that matches this product
      final offerings = await Purchases.getOfferings();
      final currentOffering = offerings.current;

      if (currentOffering == null) {
        if (kDebugMode) {
          debugPrint('[RCPurchaseController] No current offering found');
        }
        return sw.PurchaseResult.failed('No offerings available');
      }

      // Find the package with this product identifier
      Package? matchingPackage;
      for (final package in currentOffering.availablePackages) {
        if (kDebugMode) {
          debugPrint('[RCPurchaseController] Checking package: ${package.identifier} with product: ${package.storeProduct.identifier}');
        }
        if (package.storeProduct.identifier == productId) {
          matchingPackage = package;
          if (kDebugMode) {
            debugPrint('[RCPurchaseController] ✓ Found matching package: ${package.identifier}');
          }
          break;
        }
      }

      if (matchingPackage == null) {
        if (kDebugMode) {
          debugPrint('[RCPurchaseController] No matching package found for $productId');
        }
        return sw.PurchaseResult.failed('Product not found in offerings');
      }

      if (kDebugMode) {
        debugPrint('[RCPurchaseController] Purchasing package: ${matchingPackage.identifier}');
        debugPrint('[RCPurchaseController] Product ID: ${matchingPackage.storeProduct.identifier}');
      }

      // Purchase through RevenueCat
      final customerInfo = await Purchases.purchasePackage(matchingPackage);

      if (kDebugMode) {
        debugPrint('[RCPurchaseController] Purchase completed');
        debugPrint('[RCPurchaseController] All purchased product IDs: ${customerInfo.allPurchasedProductIdentifiers}');
      }

      if (kDebugMode) {
        debugPrint('[RCPurchaseController] Purchase successful');
        debugPrint('[RCPurchaseController] Active entitlements: ${customerInfo.entitlements.active.keys}');
      }

      return sw.PurchaseResult.purchased;
    } on PlatformException catch (e) {
      if (kDebugMode) {
        debugPrint('[RCPurchaseController] Purchase error: ${e.message}');
      }

      final errorCode = PurchasesErrorHelper.getErrorCode(e);
      if (errorCode == PurchasesErrorCode.purchaseCancelledError) {
        return sw.PurchaseResult.cancelled;
      }

      return sw.PurchaseResult.failed(e.message ?? 'Purchase failed');
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[RCPurchaseController] Purchase error: $e');
      }

      // Check if user cancelled
      if (e.toString().contains('purchaseCancelledError') ||
          e.toString().contains('cancelled')) {
        return sw.PurchaseResult.cancelled;
      }

      return sw.PurchaseResult.failed(e.toString());
    }
  }

  @override
  Future<sw.PurchaseResult> purchaseFromGooglePlay(
    String productId,
    String? basePlanId,
    String? offerId,
  ) async {
    try {
      if (kDebugMode) {
        debugPrint('[RCPurchaseController] Purchasing Android product: $productId');
        debugPrint('[RCPurchaseController]   basePlanId: $basePlanId');
        debugPrint('[RCPurchaseController]   offerId: $offerId');
      }

      // Attempt 1: direct product purchase.
      // This avoids an extra product-fetch round-trip and is often more
      // resilient when purchase is initiated from an in-app paywall webview.
      try {
        if (kDebugMode) {
          debugPrint(
              '[RCPurchaseController] Attempting direct purchaseProduct path');
        }
        // ignore: deprecated_member_use
        final customerInfo = await Purchases.purchaseProduct(
          productId,
        ).timeout(const Duration(seconds: 20));

        if (kDebugMode) {
          debugPrint(
              '[RCPurchaseController] Purchase successful (direct product)');
          debugPrint(
              '[RCPurchaseController] Active entitlements: ${customerInfo.entitlements.active.keys}');
        }
        return sw.PurchaseResult.purchased;
      } on PlatformException catch (e) {
        final errorCode = PurchasesErrorHelper.getErrorCode(e);
        if (errorCode == PurchasesErrorCode.purchaseCancelledError) {
          return sw.PurchaseResult.cancelled;
        }
        if (kDebugMode) {
          debugPrint(
              '[RCPurchaseController] Direct purchaseProduct failed: ${e.message}');
        }
      } on TimeoutException {
        if (kDebugMode) {
          debugPrint(
              '[RCPurchaseController] Direct purchaseProduct timed out, trying option path');
        }
      } catch (e) {
        if (kDebugMode) {
          debugPrint(
              '[RCPurchaseController] Direct purchaseProduct error, trying option path: $e');
        }
      }

      // Avoid depending on getOfferings() during purchase because that can
      // time out even when Play product data is available.
      final products = await Purchases.getProducts(
        [productId],
        productCategory: ProductCategory.subscription,
      ).timeout(const Duration(seconds: 8));

      if (products.isEmpty) {
        if (kDebugMode) {
          debugPrint(
              '[RCPurchaseController] No StoreProduct found for $productId');
        }
        return sw.PurchaseResult.failed('Store product not found');
      }

      final storeProduct = products.first;
      final options = storeProduct.subscriptionOptions ?? const [];

      if (kDebugMode) {
        debugPrint(
            '[RCPurchaseController] StoreProduct resolved: ${storeProduct.identifier}');
        final optionIds = options.map((o) => o.id).toList(growable: false);
        debugPrint('[RCPurchaseController] Subscription options: $optionIds');
      }

      SubscriptionOption? selectedOption;
      final hasBasePlan = basePlanId != null && basePlanId.isNotEmpty;
      final hasOffer = offerId != null && offerId.isNotEmpty;

      if (hasBasePlan && hasOffer) {
        final exactId = '$basePlanId:$offerId';
        selectedOption = options.where((o) => o.id == exactId).firstOrNull;
      }

      if (selectedOption == null && hasBasePlan) {
        selectedOption = options
            .where((o) =>
                o.id == basePlanId ||
                o.storeProductId == '$productId:$basePlanId' ||
                (o.productId == productId && o.isBasePlan))
            .firstOrNull;
      }

      selectedOption ??= storeProduct.defaultOption;
      selectedOption ??= options.isNotEmpty ? options.first : null;

      if (selectedOption == null) {
        if (kDebugMode) {
          debugPrint(
              '[RCPurchaseController] No subscription option found; falling back to purchaseStoreProduct');
        }
        final customerInfo = await Purchases.purchaseStoreProduct(storeProduct);
        if (kDebugMode) {
          debugPrint('[RCPurchaseController] Purchase successful (storeProduct)');
          debugPrint(
              '[RCPurchaseController] Active entitlements: ${customerInfo.entitlements.active.keys}');
        }
        return sw.PurchaseResult.purchased;
      }

      if (kDebugMode) {
        debugPrint(
            '[RCPurchaseController] Purchasing option id=${selectedOption.id} storeProductId=${selectedOption.storeProductId}');
      }

      final customerInfo =
          await Purchases.purchaseSubscriptionOption(selectedOption);

      if (kDebugMode) {
        debugPrint('[RCPurchaseController] Purchase successful');
        debugPrint('[RCPurchaseController] Active entitlements: ${customerInfo.entitlements.active.keys}');
      }

      return sw.PurchaseResult.purchased;
    } on PlatformException catch (e) {
      if (kDebugMode) {
        debugPrint('[RCPurchaseController] Purchase error: ${e.message}');
      }

      final errorCode = PurchasesErrorHelper.getErrorCode(e);
      if (errorCode == PurchasesErrorCode.purchaseCancelledError) {
        return sw.PurchaseResult.cancelled;
      }

      return sw.PurchaseResult.failed(e.message ?? 'Purchase failed');
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[RCPurchaseController] Purchase error: $e');
      }

      // Check if user cancelled
      if (e.toString().contains('purchaseCancelledError') ||
          e.toString().contains('cancelled')) {
        return sw.PurchaseResult.cancelled;
      }

      return sw.PurchaseResult.failed(e.toString());
    }
  }

  @override
  Future<sw.RestorationResult> restorePurchases() async {
    try {
      if (kDebugMode) {
        debugPrint('[RCPurchaseController] Restoring purchases...');
      }

      final customerInfo = await Purchases.restorePurchases();

      if (kDebugMode) {
        debugPrint('[RCPurchaseController] Restore complete');
        debugPrint('[RCPurchaseController] Active entitlements: ${customerInfo.entitlements.active.keys}');
      }

      return sw.RestorationResult.restored;
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[RCPurchaseController] Restore error: $e');
      }

      return sw.RestorationResult.failed(e.toString());
    }
  }
}
