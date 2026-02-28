import 'package:freezed_annotation/freezed_annotation.dart';

part 'user_profile.freezed.dart';
part 'user_profile.g.dart';

/// User profile with location preferences for localized search results
@freezed
class UserProfile with _$UserProfile {
  const factory UserProfile({
    required String id,

    // Location data for localized search
    String? countryCode, // ISO 3166-1 alpha-2 (e.g., 'US', 'GB', 'CA')
    String? countryName, // Human-readable (e.g., 'United States')
    String? location, // SearchAPI location string
    String? detectedLocation, // Auto-detected from IP/GPS
    @Default(false) bool manualLocation, // User manually set vs auto

    // User preferences
    @Default('USD') String preferredCurrency,
    @Default('en') String preferredLanguage, // Language code for SearchAPI (e.g., 'en', 'nb', 'fr')

    // Privacy settings
    @Default(true) bool enableLocation,

    // Metadata
    DateTime? createdAt,
    DateTime? updatedAt,
  }) = _UserProfile;

  factory UserProfile.fromJson(Map<String, dynamic> json) =>
      _$UserProfileFromJson(json);
}

/// Common country mappings for SearchAPI
class SearchLocations {
  static const Map<String, String> countryToLocation = {
    'US': 'United States',
    'GB': 'United Kingdom',
    'CA': 'Canada',
    'AU': 'Australia',
    'FR': 'France',
    'DE': 'Germany',
    'IT': 'Italy',
    'ES': 'Spain',
    'JP': 'Japan',
    'KR': 'South Korea',
    'MX': 'Mexico',
    'BR': 'Brazil',
    'IN': 'India',
    'CN': 'China',
    'NL': 'Netherlands',
    'SE': 'Sweden',
    'NO': 'Norway',
    'DK': 'Denmark',
    'FI': 'Finland',
    'IE': 'Ireland',
    'NZ': 'New Zealand',
    'SG': 'Singapore',
    'HK': 'Hong Kong',
    'TW': 'Taiwan',
  };

  static const Map<String, String> countryToCurrency = {
    'US': 'USD',
    'GB': 'GBP',
    'CA': 'CAD',
    'AU': 'AUD',
    'FR': 'EUR',
    'DE': 'EUR',
    'IT': 'EUR',
    'ES': 'EUR',
    'JP': 'JPY',
    'KR': 'KRW',
    'MX': 'MXN',
    'BR': 'BRL',
    'IN': 'INR',
    'CN': 'CNY',
    'NL': 'EUR',
    'SE': 'SEK',
    'NO': 'NOK',
    'DK': 'DKK',
    'FI': 'EUR',
    'IE': 'EUR',
    'NZ': 'NZD',
    'SG': 'SGD',
    'HK': 'HKD',
    'TW': 'TWD',
  };

  /// Get SearchAPI location string from country code
  static String getLocation(String? countryCode) {
    if (countryCode == null || countryCode.isEmpty) {
      return 'United States'; // Default
    }
    return countryToLocation[countryCode.toUpperCase()] ?? 'United States';
  }

  /// Get currency from country code
  static String getCurrency(String? countryCode) {
    if (countryCode == null || countryCode.isEmpty) {
      return 'USD'; // Default
    }
    return countryToCurrency[countryCode.toUpperCase()] ?? 'USD';
  }
}
