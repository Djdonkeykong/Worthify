import 'package:shared_preferences/shared_preferences.dart';

/// Lightweight logger for app review prompt attempts and outcomes.
class ReviewPromptLogsService {
  ReviewPromptLogsService._();

  static const _storageKey = 'review_prompt_logs';

  static Future<List<String>> fetchLogs() async {
    final prefs = await SharedPreferences.getInstance();
    final list = prefs.getStringList(_storageKey);
    if (list == null) return const [];
    return List<String>.from(list);
  }

  static Future<void> addLog(String entry) async {
    final prefs = await SharedPreferences.getInstance();
    final list = prefs.getStringList(_storageKey) ?? <String>[];
    list.add(entry);
    await prefs.setStringList(_storageKey, list);
  }

  static Future<void> clearLogs() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_storageKey);
  }
}
