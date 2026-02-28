/// User profile with location preferences for localized search results
class UserProfile {
  const UserProfile({
    required this.id,
    this.countryCode,
    this.countryName,
    this.location,
    this.detectedLocation,
    this.manualLocation = false,
    this.preferredCurrency = 'USD',
    this.preferredLanguage = 'en',
    this.enableLocation = true,
    this.createdAt,
    this.updatedAt,
  });

  final String id;
  final String? countryCode;
  final String? countryName;
  final String? location;
  final String? detectedLocation;
  final bool manualLocation;
  final String preferredCurrency;
  final String preferredLanguage;
  final bool enableLocation;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  factory UserProfile.fromJson(Map<String, dynamic> json) {
    DateTime? parseDate(dynamic value) {
      if (value is String && value.isNotEmpty) return DateTime.tryParse(value);
      return null;
    }

    return UserProfile(
      id: (json['id'] ?? '') as String,
      countryCode: json['country_code'] as String?,
      countryName: json['country_name'] as String?,
      location: json['location'] as String?,
      detectedLocation: json['detected_location'] as String?,
      manualLocation: (json['manual_location'] as bool?) ?? false,
      preferredCurrency: (json['preferred_currency'] as String?) ?? 'USD',
      preferredLanguage: (json['preferred_language'] as String?) ?? 'en',
      enableLocation: (json['enable_location'] as bool?) ?? true,
      createdAt: parseDate(json['created_at']),
      updatedAt: parseDate(json['updated_at']),
    );
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'id': id,
      'country_code': countryCode,
      'country_name': countryName,
      'location': location,
      'detected_location': detectedLocation,
      'manual_location': manualLocation,
      'preferred_currency': preferredCurrency,
      'preferred_language': preferredLanguage,
      'enable_location': enableLocation,
      'created_at': createdAt?.toIso8601String(),
      'updated_at': updatedAt?.toIso8601String(),
    };
  }
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
