import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import '../../core/constants/app_constants.dart';

class ShareExtensionConfigService {
  static const String _appGroupId = 'group.com.worthify.worthify';
  static const MethodChannel _channel = MethodChannel('worthify/share_config');

  static Future<void> initializeSharedConfig() async {
    if (!Platform.isIOS) {
      debugPrint('ShareExtensionConfig: Skipping (not iOS)');
      return;
    }

    try {
      // Use method channel to write to app group UserDefaults (iOS native)
      final serpKey = AppConstants.serpApiKey;
      final endpoint = AppConstants.serpDetectAndSearchEndpoint;
      final apifyToken = AppConstants.apifyApiToken;
      final supabaseUrl = AppConstants.supabaseUrl;
      final supabaseAnonKey = AppConstants.supabaseAnonKey;

      await _channel.invokeMethod('saveSharedConfig', {
        'appGroupId': _appGroupId,
        'serpApiKey': serpKey,
        'detectorEndpoint': endpoint,
        'apifyApiToken': apifyToken,
        'supabaseUrl': supabaseUrl,
        'supabaseAnonKey': supabaseAnonKey,
      });

      debugPrint('ShareExtensionConfig: ✅ Saved SerpApiKey to app group');
      debugPrint('ShareExtensionConfig: ✅ Saved DetectorEndpoint: $endpoint');
      debugPrint('ShareExtensionConfig: ✅ Saved ApifyApiToken to app group');
      debugPrint('ShareExtensionConfig: ✅ Saved Supabase URL to app group');
      debugPrint('ShareExtensionConfig: ✅ Saved Supabase Anon Key to app group');
      debugPrint('ShareExtensionConfig: Configuration saved successfully');
    } catch (e) {
      debugPrint('ShareExtensionConfig: ❌ Failed to save config: $e');
    }
  }
}
