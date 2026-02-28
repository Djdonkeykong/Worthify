import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'dart:io' show Platform;

class NotificationService {
  static final NotificationService _instance = NotificationService._internal();
  factory NotificationService() => _instance;
  NotificationService._internal();

  FirebaseMessaging? _messaging;
  String? _currentToken;
  static const _notificationChannel = MethodChannel('worthify/notifications');

  Future<void> initialize() async {
    try {
      debugPrint('[NotificationService] Initializing...');

      // Check if Firebase is initialized
      try {
        await Firebase.initializeApp();
      } catch (e) {
        // Already initialized or failed - check if we can access it
        try {
          Firebase.app();
        } catch (e) {
          debugPrint('[NotificationService] Firebase not initialized: $e');
          return;
        }
      }

      _messaging = FirebaseMessaging.instance;

      // Request permission
      final settings = await _messaging!.requestPermission(
        alert: true,
        badge: true,
        sound: true,
        provisional: false,
      );

      debugPrint('[NotificationService] Permission status: ${settings.authorizationStatus}');

      if (settings.authorizationStatus == AuthorizationStatus.authorized ||
          settings.authorizationStatus == AuthorizationStatus.provisional) {
        // Set up token refresh listener FIRST
        // This will save the token whenever it becomes available
        _messaging!.onTokenRefresh.listen(_onTokenRefresh);
        debugPrint('[NotificationService] Token refresh listener set up');

        // Try to get FCM token
        await _registerToken();

        debugPrint('[NotificationService] Initialized successfully');
      } else {
        debugPrint('[NotificationService] Permission denied');
      }
    } catch (e, stackTrace) {
      debugPrint('[NotificationService] Error initializing: $e');
      debugPrint('[NotificationService] Stack trace: $stackTrace');
    }
  }

  Future<void> _triggerApnsRegistration() async {
    if (!Platform.isIOS) return;

    try {
      debugPrint('[NotificationService] Triggering APNS registration on iOS...');
      await _notificationChannel.invokeMethod('registerForRemoteNotifications');
      debugPrint('[NotificationService] APNS registration triggered successfully');

      // Give iOS a moment to generate the APNS token
      await Future.delayed(const Duration(milliseconds: 1000));
    } catch (e) {
      debugPrint('[NotificationService] Error triggering APNS registration: $e');
      // Continue anyway - might already be registered
    }
  }

  Future<void> _registerToken() async {
    try {
      if (_messaging == null) return;

      // On iOS, we MUST trigger APNS registration first
      // This is critical when FirebaseAppDelegateProxyEnabled is false
      if (Platform.isIOS) {
        debugPrint('[NotificationService] iOS detected - triggering APNS registration...');
        await _triggerApnsRegistration();

        // Check if APNS token is now available
        String? apnsToken;
        try {
          apnsToken = await _messaging!.getAPNSToken();
          debugPrint('[NotificationService] APNS token available: ${apnsToken != null}');
        } catch (e) {
          debugPrint('[NotificationService] APNS token check error: $e');
        }

        // If still not available, wait a bit longer
        if (apnsToken == null) {
          debugPrint('[NotificationService] APNS token not ready, waiting longer...');
          await Future.delayed(const Duration(seconds: 2));

          try {
            apnsToken = await _messaging!.getAPNSToken();
            debugPrint('[NotificationService] APNS token after extended wait: ${apnsToken != null}');
          } catch (e) {
            debugPrint('[NotificationService] Still no APNS token: $e');
            // The token will be available via onTokenRefresh listener when ready
          }
        }
      }

      final token = await _messaging!.getToken();
      if (token != null) {
        _currentToken = token;
        debugPrint('[NotificationService] FCM Token: $token');
        await _saveTokenToDatabase(token);
      } else {
        debugPrint('[NotificationService] Failed to get FCM token - will retry when APNS token is available');
      }
    } catch (e) {
      debugPrint('[NotificationService] Error getting token: $e');
    }
  }

  Future<void> _onTokenRefresh(String token) async {
    debugPrint('[NotificationService] Token refreshed: $token');
    _currentToken = token;
    await _saveTokenToDatabase(token);
  }

  Future<void> _saveTokenToDatabase(String token) async {
    try {
      final userId = Supabase.instance.client.auth.currentUser?.id;
      debugPrint('');
      debugPrint('[NotificationService] ===== SAVING TOKEN TO DATABASE =====');
      debugPrint('[NotificationService] User ID: $userId');
      debugPrint('[NotificationService] Token: $token');
      debugPrint('[NotificationService] Platform: ${defaultTargetPlatform.name}');

      if (userId == null) {
        debugPrint('[NotificationService] ERROR: No authenticated user - token will be saved after login');
        debugPrint('[NotificationService] ======================================');
        return;
      }

      final data = {
        'user_id': userId,
        'token': token,
        'platform': defaultTargetPlatform.name,
        'updated_at': DateTime.now().toIso8601String(),
      };

      debugPrint('[NotificationService] Upserting data: $data');

      await Supabase.instance.client.from('fcm_tokens').upsert(
        data,
        onConflict: 'user_id,token',
      );

      debugPrint('[NotificationService] SUCCESS: Token saved to database');
      debugPrint('[NotificationService] ======================================');
    } catch (e, stackTrace) {
      debugPrint('[NotificationService] ERROR saving token: $e');
      debugPrint('[NotificationService] Stack trace: $stackTrace');
      debugPrint('[NotificationService] ======================================');
    }
  }

  Future<void> deleteToken() async {
    try {
      if (_messaging == null) return;

      final userId = Supabase.instance.client.auth.currentUser?.id;
      if (userId == null) return;

      debugPrint('[NotificationService] Deleting token for user: $userId');

      await Supabase.instance.client
          .from('fcm_tokens')
          .delete()
          .eq('user_id', userId)
          .eq('token', _currentToken ?? '');

      await _messaging!.deleteToken();
      _currentToken = null;

      debugPrint('[NotificationService] Token deleted successfully');
    } catch (e) {
      debugPrint('[NotificationService] Error deleting token: $e');
    }
  }

  Future<void> registerTokenForUser() async {
    debugPrint('');
    debugPrint('[NotificationService] ===== REGISTER TOKEN FOR USER =====');
    final userId = Supabase.instance.client.auth.currentUser?.id;
    debugPrint('[NotificationService] User ID: $userId');
    debugPrint('[NotificationService] Current token: $_currentToken');

    if (userId == null) {
      debugPrint('[NotificationService] ERROR: No user to register token for');
      debugPrint('[NotificationService] ====================================');
      return;
    }

    if (_currentToken != null) {
      debugPrint('[NotificationService] Using existing token: $_currentToken');
      await _saveTokenToDatabase(_currentToken!);
    } else {
      debugPrint('[NotificationService] No existing token, registering new one...');
      await _registerToken();
    }
    debugPrint('[NotificationService] ====================================');
  }

  String? get currentToken => _currentToken;
}
