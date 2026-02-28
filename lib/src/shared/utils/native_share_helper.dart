import 'dart:io';
import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';

/// Provides an iOS-specific share path that always places the image item first
/// in the activity controller. Falls back to share_plus when not handled.
class NativeShareHelper {
  static const _channel = MethodChannel('worthify/native_share');

  /// Returns true if the native iOS share was invoked, false otherwise.
  static Future<bool> shareImageFirst({
    required XFile file,
    required String text,
    String? subject,
    Rect? origin,
    String? thumbnailPath,
  }) async {
    if (!Platform.isIOS) return false;

    try {
      await _channel.invokeMethod('shareImageWithText', {
        'path': file.path,
        'text': text,
        'subject': subject ?? '',
        'thumbnailPath': thumbnailPath,
        'origin': origin != null
            ? {
                'x': origin.left,
                'y': origin.top,
                'w': origin.width,
                'h': origin.height,
              }
            : null,
      });
      return true;
    } catch (e, st) {
      debugPrint('[NativeShare] Falling back to share_plus: $e\n$st');
      return false;
    }
  }
}
