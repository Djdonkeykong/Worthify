import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:async';

class DebugLogService {
  static final DebugLogService _instance = DebugLogService._internal();
  factory DebugLogService() => _instance;
  DebugLogService._internal();

  final List<String> _logs = [];
  final int _maxLogs = 500;
  final StreamController<String> _logController = StreamController<String>.broadcast();

  Stream<String> get logStream => _logController.stream;
  List<String> get logs => List.unmodifiable(_logs);

  void initialize() {
    // Intercept debugPrint calls
    debugPrint = (String? message, {int? wrapWidth}) {
      if (message == null) return;

      final timestamp = DateTime.now().toIso8601String();
      final logEntry = '[$timestamp] $message';

      // Add to in-memory list
      _logs.add(logEntry);
      if (_logs.length > _maxLogs) {
        _logs.removeAt(0);
      }

      // Notify listeners
      _logController.add(logEntry);

      // Still print to console
      debugPrintSynchronously(message, wrapWidth: wrapWidth);
    };

    debugPrint('[DebugLogService] Initialized - logs will be captured');
  }

  void clear() {
    _logs.clear();
    debugPrint('[DebugLogService] Logs cleared');
  }

  String getAllLogsAsString() {
    return _logs.join('\n');
  }

  Future<void> saveToPreferences() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setStringList('debug_logs', _logs);
      debugPrint('[DebugLogService] Saved ${_logs.length} logs to preferences');
    } catch (e) {
      debugPrintSynchronously('[DebugLogService] Error saving logs: $e');
    }
  }

  Future<void> loadFromPreferences() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final savedLogs = prefs.getStringList('debug_logs');
      if (savedLogs != null) {
        _logs.clear();
        _logs.addAll(savedLogs);
        debugPrint('[DebugLogService] Loaded ${_logs.length} logs from preferences');
      }
    } catch (e) {
      debugPrintSynchronously('[DebugLogService] Error loading logs: $e');
    }
  }

  void dispose() {
    _logController.close();
  }
}
