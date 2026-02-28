import 'dart:ui' as ui;
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/user_profile.dart';

/// Repository for managing user profiles with location preferences
class UserProfileRepository {
  UserProfileRepository({SupabaseClient? client})
      : _client = client ?? Supabase.instance.client;

  final SupabaseClient _client;

  /// Get current user's profile
  Future<UserProfile?> getCurrentUserProfile() async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) {
      debugPrint('[UserProfile] No authenticated user');
      return null;
    }

    try {
      final response = await _client
          .from('user_profiles')
          .select()
          .eq('id', userId)
          .maybeSingle();

      if (response == null) {
        debugPrint('[UserProfile] No profile found for user $userId');
        return null;
      }

      return UserProfile.fromJson(response as Map<String, dynamic>);
    } catch (error, stackTrace) {
      debugPrint('[UserProfile] Error fetching profile: $error');
      debugPrint('[UserProfile] Stack trace: $stackTrace');
      return null;
    }
  }

  /// Update user's location preferences
  Future<bool> updateLocation({
    required String countryCode,
    required String countryName,
    required String location,
    bool isManual = false,
  }) async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) {
      debugPrint('[UserProfile] No authenticated user');
      return false;
    }

    try {
      final currency = SearchLocations.getCurrency(countryCode);

      await _client.from('user_profiles').upsert({
        'id': userId,
        'country_code': countryCode,
        'country_name': countryName,
        'location': location,
        'detected_location': isManual ? null : location,
        'manual_location': isManual,
        'preferred_currency': currency,
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      });

      debugPrint(
        '[UserProfile] Updated location: $location (${isManual ? 'manual' : 'auto'})',
      );
      return true;
    } catch (error, stackTrace) {
      debugPrint('[UserProfile] Error updating location: $error');
      debugPrint('[UserProfile] Stack trace: $stackTrace');
      return false;
    }
  }

  /// Auto-detect and save user's location from IP address
  Future<bool> autoDetectLocation() async {
    try {
      // Use ipapi.co for free IP geolocation (no API key needed for basic usage)
      // Alternative: Use platform-specific location services
      final response = await _client.functions.invoke(
        'detect-location',
        body: {},
      );

      if (response.data != null && response.data is Map) {
        final data = response.data as Map<String, dynamic>;
        final countryCode = data['country_code'] as String?;
        final countryName = data['country_name'] as String?;

        if (countryCode != null && countryName != null) {
          final location = SearchLocations.getLocation(countryCode);
          return await updateLocation(
            countryCode: countryCode,
            countryName: countryName,
            location: location,
            isManual: false,
          );
        }
      }

      debugPrint('[UserProfile] Auto-detection failed, using default (US)');
      return await updateLocation(
        countryCode: 'US',
        countryName: 'United States',
        location: 'United States',
        isManual: false,
      );
    } catch (error) {
      debugPrint('[UserProfile] Auto-detection error: $error');
      // Fallback to US
      return await updateLocation(
        countryCode: 'US',
        countryName: 'United States',
        location: 'United States',
        isManual: false,
      );
    }
  }

  /// Detect and save user's location from device locale settings
  /// This is the RECOMMENDED method - uses device's system locale (Settings > General > Language & Region)
  Future<bool> setDeviceLocale() async {
    try {
      // Get device locale from platform
      final locale = ui.PlatformDispatcher.instance.locale;

      // Extract country code (e.g., 'US', 'NO', 'GB')
      final countryCode = locale.countryCode?.toUpperCase() ?? 'US';

      // Extract language code (e.g., 'en', 'nb', 'fr')
      final languageCode = locale.languageCode.toLowerCase();

      debugPrint('[UserProfile] Device locale detected: $countryCode ($languageCode)');

      // Map to full country name
      final countryName = SearchLocations.countryToLocation[countryCode] ?? 'United States';
      final location = SearchLocations.getLocation(countryCode);

      // Update profile with device locale
      final userId = _client.auth.currentUser?.id;
      if (userId == null) {
        debugPrint('[UserProfile] No authenticated user');
        return false;
      }

      final currency = SearchLocations.getCurrency(countryCode);

      await _client.from('user_profiles').upsert({
        'id': userId,
        'country_code': countryCode,
        'country_name': countryName,
        'location': location,
        'detected_location': location,
        'manual_location': false,
        'preferred_currency': currency,
        'preferred_language': languageCode, // Store language code
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      });

      debugPrint('[UserProfile] Device locale saved: $location ($countryCode) - Language: $languageCode');
      return true;
    } catch (error, stackTrace) {
      debugPrint('[UserProfile] Error setting device locale: $error');
      debugPrint('[UserProfile] Stack trace: $stackTrace');

      // Fallback to US
      try {
        return await updateLocation(
          countryCode: 'US',
          countryName: 'United States',
          location: 'United States',
          isManual: false,
        );
      } catch (e) {
        return false;
      }
    }
  }

  /// Get user's search location (respects privacy settings)
  Future<String> getUserSearchLocation() async {
    final profile = await getCurrentUserProfile();

    if (profile == null || !profile.enableLocation) {
      return 'United States'; // Privacy fallback
    }

    return profile.location ?? 'United States';
  }

  /// Toggle location-based search on/off
  Future<bool> setLocationEnabled(bool enabled) async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) return false;

    try {
      await _client.from('user_profiles').upsert({
        'id': userId,
        'enable_location': enabled,
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      });

      debugPrint('[UserProfile] Location-based search: $enabled');
      return true;
    } catch (error) {
      debugPrint('[UserProfile] Error toggling location: $error');
      return false;
    }
  }

  /// Manual country selection by user
  Future<bool> setCountryManually(String countryCode) async {
    final countryName = SearchLocations.countryToLocation[countryCode];
    if (countryName == null) {
      debugPrint('[UserProfile] Invalid country code: $countryCode');
      return false;
    }

    final location = SearchLocations.getLocation(countryCode);
    return await updateLocation(
      countryCode: countryCode,
      countryName: countryName,
      location: location,
      isManual: true,
    );
  }
}
