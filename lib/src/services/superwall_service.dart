import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:superwallkit_flutter/superwallkit_flutter.dart' as sw;
import 'package:purchases_flutter/purchases_flutter.dart';
import 'rc_purchase_controller.dart';
import 'debug_log_service.dart';

/// Thin wrapper around Superwall to manage configuration, identity, and paywall presentation.
class SuperwallService {
  SuperwallService._internal();
  static final SuperwallService _instance = SuperwallService._internal();
  factory SuperwallService() => _instance;

  static const String defaultPlacement = 'onboarding_paywall';

  sw.SubscriptionStatus _latestStatus = sw.SubscriptionStatus.unknown;
  StreamSubscription<sw.SubscriptionStatus>? _statusSub;
  bool _configured = false;
  bool _configRefreshed = false;
  bool _lastPresentationTimedOut = false;
  bool _isPresentingPaywall = false;
  Completer<void>? _pendingPlacementCompleter;
  final _debugLog = DebugLogService();
  late final _superwallDelegate = _SuperwallDebugDelegate(
    _log,
    onConfigRefreshed: () {
      _configRefreshed = true;
      _log('Observed config_refresh event from Superwall');
    },
    onPaywallDidPresent: () {
      _log('Delegate observed paywall presentation');
    },
    onPaywallDidDismiss: () {
      _resolvePendingPlacement('delegate.didDismissPaywall');
    },
  );

  void _log(String message, {DebugLogLevel level = DebugLogLevel.info}) {
    _debugLog.log(message, level: level, tag: 'Superwall');
    if (kDebugMode) {
      debugPrint('[Superwall] $message');
    }
  }

  void _resolvePendingPlacement(String source) {
    final completer = _pendingPlacementCompleter;
    if (completer != null && !completer.isCompleted) {
      _log('Resolving pending placement from $source');
      completer.complete();
    }
  }

  Future<void> _logRevenueCatOfferingsCheck() async {
    // Debug-only health probe. This should never block paywall flow.
    if (!kDebugMode) return;
    try {
      final offerings = await Purchases.getOfferings().timeout(
        const Duration(seconds: 8),
      );
      final currentOffering = offerings.current;
      _log(
        'RevenueCat offerings check: current=${currentOffering?.identifier ?? "null"} packages=${currentOffering?.availablePackages.length ?? 0}',
      );
    } on TimeoutException {
      _log(
        'RevenueCat offerings check: timeout',
        level: DebugLogLevel.warning,
      );
    } on PlatformException catch (e) {
      final code = PurchasesErrorHelper.getErrorCode(e);
      _log(
        'RevenueCat offerings check: platform_error code=$code message=${e.message}',
        level: DebugLogLevel.warning,
      );
    } catch (e) {
      _log(
        'RevenueCat offerings check: error ($e)',
        level: DebugLogLevel.warning,
      );
    }
  }

  /// Configure Superwall with the provided API key and optional user.
  Future<void> initialize({required String apiKey, String? userId}) async {
    if (_configured) {
      _log('Already configured, skipping...');
      return;
    }

    _log('Creating RevenueCat purchase controller...');

    try {
      // Create RevenueCat purchase controller
      final purchaseController = RCPurchaseController();

      _log('Configuring Superwall with API key: ${apiKey.substring(0, 5)}...');

      // Configure Superwall with RevenueCat purchase controller
      sw.Superwall.configure(
        apiKey,
        purchaseController: purchaseController,
        completion: () {
          _log('SDK configure completion callback received');
        },
      );
      _configured = true;
      sw.Superwall.shared.setDelegate(_superwallDelegate);
      await sw.Superwall.shared.setSubscriptionStatus(
        sw.SubscriptionStatusInactive(),
      );
      _latestStatus = sw.SubscriptionStatusInactive();
      _log(
        'Set initial subscription status to inactive to avoid unknown-status timeout',
      );

      _log('Configured with RevenueCat purchase controller');

      _statusSub = sw.Superwall.shared.subscriptionStatus.listen((status) {
        _latestStatus = status;
        _log('Subscription status changed: ${status.runtimeType}');
      });

      // Kick off immediate RC->Superwall status sync so active subscribers are
      // upgraded from initial "inactive" as soon as possible.
      unawaited(_syncSubscriptionStatus());

      if (userId != null && userId.isNotEmpty) {
        _log('Identifying user: $userId');
        await identify(userId);
      }

      _log('Initialization complete; user=${userId ?? 'anon'}');
    } catch (e, stackTrace) {
      _log(
        'ERROR during initialization: $e\nStack trace: $stackTrace',
        level: DebugLogLevel.error,
      );
      rethrow;
    }
  }

  Future<bool> _waitUntilConfigured({
    Duration timeout = const Duration(seconds: 15),
    Duration pollInterval = const Duration(milliseconds: 300),
  }) async {
    final started = DateTime.now();
    while (DateTime.now().difference(started) < timeout) {
      try {
        final isConfigured = await sw.Superwall.shared.getIsConfigured();
        final status = await sw.Superwall.shared.getConfigurationStatus();
        if (isConfigured ||
            status == sw.ConfigurationStatus.configured ||
            _configRefreshed) {
          _log(
            'SDK ready for placement: isConfigured=$isConfigured status=$status',
          );
          return true;
        }
      } catch (e) {
        _log('Config readiness poll failed: $e', level: DebugLogLevel.warning);
      }
      await Future.delayed(pollInterval);
    }
    _log(
      'Timed out waiting for Superwall configuration',
      level: DebugLogLevel.warning,
    );
    return false;
  }

  /// Identify the current user and sync subscription status from RevenueCat.
  Future<void> identify(String userId) async {
    if (!_configured) {
      _log(
        'identify called but not configured - skipping',
        level: DebugLogLevel.warning,
      );
      return;
    }
    _log('Identifying user: $userId');
    await sw.Superwall.shared.identify(userId);

    // Sync subscription status from RevenueCat to Superwall
    await _syncSubscriptionStatus();
  }

  /// Sync RevenueCat subscription status to Superwall
  /// This ensures Superwall knows about active subscriptions and trial eligibility
  Future<void> _syncSubscriptionStatus() async {
    if (!_configured) return;

    try {
      final customerInfo = await Purchases.getCustomerInfo();
      final hasActiveEntitlement = customerInfo.entitlements.active.isNotEmpty;

      if (hasActiveEntitlement) {
        // User has active subscription - tell Superwall
        // Convert RevenueCat entitlements to Superwall entitlements
        final entitlements = customerInfo.entitlements.active.keys.map((id) {
          return sw.Entitlement(id: id);
        }).toSet();

        await sw.Superwall.shared.setSubscriptionStatus(
          sw.SubscriptionStatusActive(entitlements: entitlements),
        );

        _log(
          'Synced subscription status: active with ${entitlements.length} entitlements',
        );
      } else {
        // User has no active subscription
        await sw.Superwall.shared.setSubscriptionStatus(
          sw.SubscriptionStatusInactive(),
        );

        _log('Synced subscription status: inactive');
      }
    } catch (e) {
      _log('Error syncing subscription status: $e', level: DebugLogLevel.error);
    }
  }

  /// Sync subscription status from RevenueCat to Superwall
  /// Call this after purchases or when subscription status changes
  Future<void> syncSubscriptionStatus() async {
    await _syncSubscriptionStatus();
  }

  /// Reset the current user/session.
  Future<void> reset() async {
    if (!_configured) {
      _log(
        'reset called but not configured - skipping',
        level: DebugLogLevel.warning,
      );
      return;
    }
    _log('Resetting Superwall identity');
    await sw.Superwall.shared.reset();
    _latestStatus = sw.SubscriptionStatus.unknown;
  }

  /// Present a paywall and return true if user purchased, false otherwise.
  Future<bool> presentPaywall({
    String placement = defaultPlacement,
    Map<String, Object>? params,
  }) async {
    _lastPresentationTimedOut = false;
    if (_isPresentingPaywall) {
      _log(
        'presentPaywall ignored because another presentation is already in progress',
        level: DebugLogLevel.warning,
      );
      return false;
    }

    _log('presentPaywall called with placement: $placement');
    if (params != null && params.isNotEmpty) {
      _log('presentPaywall params: $params');
    }
    _log('_configured = $_configured');

    if (!_configured) {
      _log(
        'ERROR - presentPaywall called but not configured - skipping',
        level: DebugLogLevel.error,
      );
      return false;
    }

    _isPresentingPaywall = true;

    try {
      try {
        final isConfigured = await sw.Superwall.shared.getIsConfigured();
        final configStatus = await sw.Superwall.shared.getConfigurationStatus();
        _log(
          'Config state before register: isConfigured=$isConfigured status=$configStatus',
        );
      } catch (e) {
        _log(
          'Unable to fetch config state before register: $e',
          level: DebugLogLevel.warning,
        );
      }

      final ready = await _waitUntilConfigured();
      if (!ready) {
        _lastPresentationTimedOut = true;
        _log(
          'Skipping placement registration because SDK is still not configured',
          level: DebugLogLevel.warning,
        );
        return false;
      }

      // Non-blocking RC health probe for debugging only.
      if (kDebugMode) {
        unawaited(_logRevenueCatOfferingsCheck());
      }

      // Preflight to get a concrete decision when possible.
      try {
        final presentationResult = await sw.Superwall.shared
            .getPresentationResult(placement, params: params)
            .timeout(const Duration(seconds: 6));
        final resultType = presentationResult.runtimeType.toString();
        _log('Presentation preflight result: $resultType');
        if (const {
          'PlacementNotFoundPresentationResult',
          'NoAudienceMatchPresentationResult',
          'PaywallNotAvailablePresentationResult',
          'HoldoutPresentationResult',
        }.contains(resultType)) {
          return false;
        }
      } on TimeoutException {
        _log(
          'Presentation preflight result: timeout',
          level: DebugLogLevel.warning,
        );
      } catch (e) {
        _log(
          'Presentation preflight result: error ($e)',
          level: DebugLogLevel.warning,
        );
      }

      final completer = Completer<void>();
      _pendingPlacementCompleter = completer;

      void resolve(String source) {
        if (!completer.isCompleted) {
          _log('Resolving placement callback from $source');
          completer.complete();
        }
      }

      final handler = sw.PaywallPresentationHandler()
        ..onPresent((info) {
          _log('Paywall presented: ${info.identifier}');
        })
        ..onDismiss((info, result) {
          _log('Paywall dismissed with result: ${result.runtimeType}');
          resolve('handler.onDismiss');
        })
        ..onSkip((reason) {
          _log('Paywall skipped: ${reason.runtimeType}');
          resolve('handler.onSkip');
        })
        ..onError((error) {
          _log('Paywall error: $error', level: DebugLogLevel.warning);
          resolve('handler.onError');
        });

      _log('Registering placement: $placement');
      await sw.Superwall.shared.registerPlacement(
        placement,
        params: params,
        handler: handler,
        feature: () {
          _log('Feature callback executed for "$placement"');
          resolve('feature');
        },
      ).timeout(const Duration(seconds: 20));
      _log(
        'Placement registered successfully, waiting for paywall/feature callback...',
      );

      try {
        final isPresented = await sw.Superwall.shared.getIsPaywallPresented();
        _log('Post-register state: isPaywallPresented=$isPresented');
      } catch (e) {
        _log(
          'Post-register paywall state check failed: $e',
          level: DebugLogLevel.warning,
        );
      }

      var callbackTimedOut = false;
      await completer.future.timeout(
        const Duration(seconds: 35),
        onTimeout: () {
          callbackTimedOut = true;
          _lastPresentationTimedOut = true;
          _log(
            'No callback received from registerPlacement - returning false to unblock UI',
            level: DebugLogLevel.warning,
          );
          return;
        },
      );

      if (callbackTimedOut) {
        try {
          final isPresented = await sw.Superwall.shared.getIsPaywallPresented();
          final latestPaywallInfo =
              await sw.Superwall.shared.getLatestPaywallInfo();
          _log(
            'No-callback diagnostics: isPaywallPresented=$isPresented latestPaywallId=${latestPaywallInfo?.identifier}',
            level: DebugLogLevel.warning,
          );
        } catch (e) {
          _log(
            'No-callback diagnostics failed: $e',
            level: DebugLogLevel.warning,
          );
        }
      }

      // Validate actual entitlement state so non-gated paywalls don't incorrectly
      // get treated as purchases.
      try {
        final customerInfo = await Purchases.getCustomerInfo();
        final hasActiveEntitlement =
            customerInfo.entitlements.active.isNotEmpty;
        _log(
          'Post-placement entitlement check: hasActiveEntitlement=$hasActiveEntitlement',
        );
        return hasActiveEntitlement;
      } catch (e) {
        _log(
          'Post-placement entitlement check failed: $e',
          level: DebugLogLevel.warning,
        );
        return false;
      }
    } catch (e, stackTrace) {
      _log(
        'presentPaywall error: $e\nStack trace: $stackTrace',
        level: DebugLogLevel.error,
      );
      return false;
    } finally {
      _pendingPlacementCompleter = null;
      _isPresentingPaywall = false;
    }
  }

  bool get lastPresentationTimedOut => _lastPresentationTimedOut;

  /// Current cached subscription status.
  SubscriptionStatusSnapshot getSubscriptionSnapshot() {
    if (!_configured) {
      _log(
        'getSubscriptionSnapshot called but not configured - returning inactive',
        level: DebugLogLevel.warning,
      );
      return SubscriptionStatusSnapshot.initial();
    }
    return SubscriptionStatusSnapshot.fromSuperwall(_latestStatus);
  }

  /// Dispose listeners (rarely needed in app lifecycle).
  void dispose() {
    _statusSub?.cancel();
    _statusSub = null;
  }
}

class _SuperwallDebugDelegate implements sw.SuperwallDelegate {
  _SuperwallDebugDelegate(
    this._log, {
    this.onConfigRefreshed,
    this.onPaywallDidPresent,
    this.onPaywallDidDismiss,
  });

  final void Function(String message, {DebugLogLevel level}) _log;
  final VoidCallback? onConfigRefreshed;
  final VoidCallback? onPaywallDidPresent;
  final VoidCallback? onPaywallDidDismiss;

  @override
  void handleSuperwallEvent(sw.SuperwallEventInfo eventInfo) {
    _log('[Delegate] event=${eventInfo.event} params=${eventInfo.params}');
    final eventName = eventInfo.params?['event_name']?.toString();
    final hasConfigRefreshShape = eventInfo.params != null &&
        eventInfo.params!.containsKey('config_build_id') &&
        eventInfo.params!.containsKey('cache_status');
    final statusReason = eventInfo.params?['status_reason']?.toString();
    if (statusReason != null && statusReason.isNotEmpty) {
      final status = eventInfo.params?['status']?.toString() ?? 'unknown';
      _log(
        '[Delegate] paywallPresentationRequest status=$status status_reason=$statusReason',
      );
    }
    if (eventName == 'config_refresh' || hasConfigRefreshShape) {
      onConfigRefreshed?.call();
    }
  }

  @override
  void handleLog(
    String level,
    String scope,
    String? message,
    Map<dynamic, dynamic>? info,
    String? error,
  ) {
    final shouldPrint = scope == 'placements' ||
        scope == 'paywallPresentation' ||
        scope == 'productsManager' ||
        scope == 'network' ||
        scope == 'paywallEvents' ||
        scope == 'superwallCore' ||
        level == 'error' ||
        level == 'warn';
    if (!shouldPrint) return;
    _log(
      '[DelegateLog] level=$level scope=$scope msg=$message info=$info error=$error',
    );
  }

  @override
  void didDismissPaywall(sw.PaywallInfo paywallInfo) {
    _log('[Delegate] didDismissPaywall id=${paywallInfo.identifier}');
    onPaywallDidDismiss?.call();
  }

  @override
  void didPresentPaywall(sw.PaywallInfo paywallInfo) {
    _log('[Delegate] didPresentPaywall id=${paywallInfo.identifier}');
    onPaywallDidPresent?.call();
  }

  @override
  void willDismissPaywall(sw.PaywallInfo paywallInfo) {
    _log('[Delegate] willDismissPaywall id=${paywallInfo.identifier}');
  }

  @override
  void willPresentPaywall(sw.PaywallInfo paywallInfo) {
    _log('[Delegate] willPresentPaywall id=${paywallInfo.identifier}');
  }

  @override
  void handleCustomPaywallAction(String name) {}

  @override
  void handleSuperwallDeepLink(
    Uri fullURL,
    List<String> pathComponents,
    Map<String, String> queryParameters,
  ) {}

  @override
  void paywallWillOpenDeepLink(Uri url) {}

  @override
  void paywallWillOpenURL(Uri url) {}

  @override
  void subscriptionStatusDidChange(sw.SubscriptionStatus newValue) {
    _log('[Delegate] subscriptionStatusDidChange=$newValue');
  }

  @override
  void customerInfoDidChange(sw.CustomerInfo from, sw.CustomerInfo to) {}

  @override
  void userAttributesDidChange(Map<String, Object> newAttributes) {}

  @override
  void didRedeemLink(sw.RedemptionResult result) {}

  @override
  void willRedeemLink() {}
}

/// Lightweight status DTO the app can use without importing Superwall enums everywhere.
class SubscriptionStatusSnapshot {
  final bool isActive;
  final bool isInTrialPeriod;
  final String? productIdentifier;
  final DateTime? expirationDate;

  const SubscriptionStatusSnapshot({
    required this.isActive,
    this.isInTrialPeriod = false,
    this.productIdentifier,
    this.expirationDate,
  });

  factory SubscriptionStatusSnapshot.fromSuperwall(
    sw.SubscriptionStatus status,
  ) {
    return SubscriptionStatusSnapshot(
      isActive: status is sw.SubscriptionStatusActive,
      isInTrialPeriod: false,
    );
  }

  factory SubscriptionStatusSnapshot.initial() {
    return const SubscriptionStatusSnapshot(isActive: false);
  }
}
