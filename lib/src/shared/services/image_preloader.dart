import 'package:flutter/material.dart';

class ImagePreloader {
  static ImagePreloader? _instance;
  static ImagePreloader get instance => _instance ??= ImagePreloader._();

  ImagePreloader._();

  bool _isSocialMediaShareImageLoaded = false;
  bool _isHomeAssetsLoaded = false;

  bool get isSocialMediaShareImageLoaded => _isSocialMediaShareImageLoaded;
  bool get isHomeAssetsLoaded => _isHomeAssetsLoaded;

  Future<void> preloadSocialMediaShareImage(BuildContext context) async {
    if (_isSocialMediaShareImageLoaded) return;

    try {
      await precacheImage(
        const AssetImage('assets/images/social_media_share_mobile_screen.png'),
        context,
      );
      _isSocialMediaShareImageLoaded = true;
      debugPrint('[ImagePreloader] Social media share image preloaded successfully');
    } catch (e) {
      debugPrint('[ImagePreloader] Error preloading social media share image: $e');
    }
  }

  Future<void> preloadHomeAssets(BuildContext context) async {
    if (_isHomeAssetsLoaded) return;

    try {
      await precacheImage(
        const AssetImage('assets/images/home-polaroids.png'),
        context,
      );
      await precacheImage(
        const AssetImage('assets/images/logo.png'),
        context,
      );
      _isHomeAssetsLoaded = true;
      debugPrint('[ImagePreloader] Home assets preloaded successfully');
    } catch (e) {
      debugPrint('[ImagePreloader] Error preloading home assets: $e');
    }
  }

  void reset() {
    _isSocialMediaShareImageLoaded = false;
    _isHomeAssetsLoaded = false;
  }
}
