import 'package:flutter/services.dart';

class ShareExtensionLogsService {
  ShareExtensionLogsService._();

  static const MethodChannel _channel = MethodChannel('worthify/share_extension_logs');

  static Future<List<String>> fetchLogs() async {
    final result = await _channel.invokeMethod<List<dynamic>>('getLogs');
    if (result == null) {
      return const [];
    }
    return result.map((e) => e.toString()).toList();
  }

  static Future<void> clearLogs() {
    return _channel.invokeMethod('clearLogs');
  }
}
