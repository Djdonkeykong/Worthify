import 'dart:io';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:crypto/crypto.dart';
import 'dart:convert';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Service for fraud prevention and trial tracking
/// Uses device fingerprinting to prevent trial abuse
class FraudPreventionService {
  static final DeviceInfoPlugin _deviceInfo = DeviceInfoPlugin();
  static final SupabaseClient _supabase = Supabase.instance.client;

  /// Generate stable device fingerprint
  /// This creates a unique identifier for the device without storing personal info
  static Future<String> getDeviceFingerprint() async {
    try {
      List<String> components = [];

      if (Platform.isIOS) {
        final iosInfo = await _deviceInfo.iosInfo;
        components = [
          iosInfo.identifierForVendor ?? 'unknown',
          iosInfo.systemVersion ?? 'unknown',
          iosInfo.model ?? 'unknown',
          iosInfo.name ?? 'unknown',
        ];
      } else if (Platform.isAndroid) {
        final androidInfo = await _deviceInfo.androidInfo;
        components = [
          androidInfo.id ?? 'unknown',
          androidInfo.model ?? 'unknown',
          androidInfo.brand ?? 'unknown',
          androidInfo.device ?? 'unknown',
        ];
      }

      return _hashFingerprint(components);
    } catch (e) {
      debugPrint('Error generating device fingerprint: $e');
      return 'unknown_${DateTime.now().millisecondsSinceEpoch}';
    }
  }

  /// Hash the fingerprint components for privacy
  static String _hashFingerprint(List<String> components) {
    final combined = components.join('_');
    final bytes = utf8.encode(combined);
    final digest = sha256.convert(bytes);
    return digest.toString();
  }

  /// Check if device is eligible for trial
  /// Returns true if device hasn't used a trial before
  static Future<bool> isDeviceEligibleForTrial() async {
    try {
      final fingerprint = await getDeviceFingerprint();

      final response = await _supabase
          .from('trial_history')
          .select('id')
          .eq('device_fingerprint', fingerprint)
          .maybeSingle();

      return response == null;
    } catch (e) {
      debugPrint('Error checking trial eligibility: $e');
      return true;
    }
  }

  /// Record trial start for a user
  static Future<void> recordTrialStart(String userId) async {
    try {
      final fingerprint = await getDeviceFingerprint();

      await _supabase.from('trial_history').insert({
        'user_id': userId,
        'device_fingerprint': fingerprint,
        'started_at': DateTime.now().toIso8601String(),
      });

      debugPrint('Trial start recorded for user: $userId');
    } catch (e) {
      debugPrint('Error recording trial start: $e');
    }
  }

  /// Update device fingerprint for existing user
  static Future<void> updateUserDeviceFingerprint(String userId) async {
    try {
      final fingerprint = await getDeviceFingerprint();

      await _supabase
          .from('users')
          .update({'device_fingerprint': fingerprint}).eq('id', userId);

      debugPrint('Device fingerprint updated for user: $userId');
    } catch (e) {
      debugPrint('Error updating device fingerprint: $e');
    }
  }

  /// Check account creation rate limit
  /// Returns true if within limits, false if rate limit exceeded
  static Future<bool> checkAccountCreationRateLimit(
      String deviceFingerprint) async {
    try {
      final oneWeekAgo =
          DateTime.now().subtract(const Duration(days: 7)).toIso8601String();

      final response = await _supabase
          .from('users')
          .select('id, created_at')
          .eq('device_fingerprint', deviceFingerprint)
          .gte('created_at', oneWeekAgo);

      if (response is List && response.length >= 3) {
        debugPrint(
            'Rate limit exceeded: ${response.length} accounts created from this device in the last week');
        return false;
      }

      return true;
    } catch (e) {
      debugPrint('Error checking rate limit: $e');
      return true;
    }
  }

  /// Detect disposable email addresses
  static bool isDisposableEmail(String email) {
    const disposableDomains = [
      'tempmail.com',
      'guerrillamail.com',
      '10minutemail.com',
      'throwaway.email',
      'mailinator.com',
      'temp-mail.org',
      'getnada.com',
      'maildrop.cc',
      'trashmail.com',
      'yopmail.com',
      'fakeinbox.com',
      'sharklasers.com',
      'guerrillamail.info',
      'grr.la',
      'spam4.me',
      'mintemail.com',
    ];

    final domain = email.split('@').last.toLowerCase();
    return disposableDomains.contains(domain);
  }

  /// Calculate fraud score based on various indicators
  static Future<int> calculateFraudScore(String userId,
      {String? email, String? deviceFingerprint}) async {
    int score = 0;
    List<String> flags = [];

    try {
      final fingerprint = deviceFingerprint ?? await getDeviceFingerprint();

      if (email != null && isDisposableEmail(email)) {
        score += 30;
        flags.add('disposable_email');
      }

      final trialCount = await _supabase
          .from('trial_history')
          .select('id')
          .eq('device_fingerprint', fingerprint);
      if (trialCount is List && trialCount.length > 1) {
        score += 40;
        flags.add('multiple_trials');
      }

      final accountCount = await _supabase
          .from('users')
          .select('id')
          .eq('device_fingerprint', fingerprint);
      if (accountCount is List && accountCount.length > 2) {
        score += 20;
        flags.add('multiple_accounts');
      }

      final recentAccounts = await _supabase
          .from('users')
          .select('id')
          .eq('device_fingerprint', fingerprint)
          .gte('created_at',
              DateTime.now().subtract(const Duration(hours: 24)).toIso8601String());
      if (recentAccounts is List && recentAccounts.length > 1) {
        score += 30;
        flags.add('rapid_account_creation');
      }

      await _supabase.from('users').update({
        'fraud_score': score,
        'fraud_flags': flags,
      }).eq('id', userId);

      debugPrint('Fraud score calculated: $score (flags: ${flags.join(", ")})');
      return score;
    } catch (e) {
      debugPrint('Error calculating fraud score: $e');
      return 0;
    }
  }

  /// Get fraud risk level as human-readable string
  static String getFraudRiskLevel(int score) {
    if (score >= 80) return 'High';
    if (score >= 50) return 'Medium';
    if (score >= 20) return 'Low';
    return 'Minimal';
  }

  /// Check if user should be blocked based on fraud score
  static bool shouldBlockUser(int fraudScore) {
    return fraudScore >= 80;
  }
}
