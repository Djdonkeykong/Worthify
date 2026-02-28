import 'dart:convert';
import 'dart:io';
import 'package:path_provider/path_provider.dart';

class DebugLogger {
  static DebugLogger? _instance;
  static DebugLogger get instance => _instance ??= DebugLogger._();

  DebugLogger._();

  /// Log a complete detection session with all details
  Future<void> logDetectionSession({
    required String sessionId,
    required String imagePath,
    required Map<String, dynamic> detectionResults,
    required List<Map<String, dynamic>> searchResults,
    required Map<String, dynamic> searchMetadata,
  }) async {
    try {
      final timestamp = DateTime.now().toIso8601String();

      final sessionData = {
        'session_id': sessionId,
        'timestamp': timestamp,
        'image_info': {
          'path': imagePath,
          'file_size': await _getFileSize(imagePath),
        },
        'detection_results': detectionResults,
        'search_metadata': searchMetadata,
        'search_results': searchResults,
        'analysis': {
          'total_items_detected': detectionResults['total_items_detected'] ?? 0,
          'total_results_found': searchResults.length,
          'detection_summary': detectionResults['detection_summary'] ?? '',
        }
      };

      await _writeToLogFile(sessionData);
      await _writeToCSV(sessionData);

      print('📝 Debug session logged: $sessionId');

      // Print detailed session info to console for immediate debugging
      print('=== DEBUG SESSION DETAILS ===');
      print('Session ID: $sessionId');
      print('Items detected: ${detectionResults['total_items_detected'] ?? 0}');
      print('Total results: ${searchResults.length}');

      final items = detectionResults['items'] as List? ?? [];
      for (int i = 0; i < items.length; i++) {
        final item = items[i];
        print('Item ${i + 1}: ${item['category']} (${item['color_primary']}) - confidence: ${item['confidence']}');
      }

      print('Top search results:');
      for (int i = 0; i < searchResults.length && i < 5; i++) {
        final result = searchResults[i];
        print('  ${i + 1}. ${result['title'] ?? result['product_name'] ?? 'Unknown'} - ${result['color_primary'] ?? 'no-color'}/${result['color_secondary'] ?? 'no-color'} (${result['confidence']})');
      }
      print('=== END DEBUG SESSION ===');

    } catch (e) {
      print('❌ Failed to log debug session: $e');
    }
  }

  /// Log detailed search process for a specific item
  Future<void> logSearchProcess({
    required String sessionId,
    required String itemType,
    required String primaryColor,
    required List<String> colorVariations,
    required Map<String, dynamic> searchLevels,
    required List<Map<String, dynamic>> finalResults,
    required Map<String, dynamic> styleFilters,
  }) async {
    try {
      final searchLog = {
        'session_id': sessionId,
        'timestamp': DateTime.now().toIso8601String(),
        'item_type': itemType,
        'color_analysis': {
          'primary_color': primaryColor,
          'color_variations': colorVariations,
          'variation_count': colorVariations.length,
        },
        'search_levels': searchLevels,
        'style_filters': styleFilters,
        'results': {
          'final_count': finalResults.length,
          'top_3_ids': finalResults.take(3).map((r) => r['id']).toList(),
          'products': finalResults,
        }
      };

      await _writeSearchLogFile(searchLog);

    } catch (e) {
      print('❌ Failed to log search process: $e');
    }
  }

  /// Log color matching analysis
  Future<void> logColorMatching({
    required String sessionId,
    required String requestedColor,
    required List<String> variations,
    required Map<String, int> levelResults,
    required List<Map<String, dynamic>> matchedProducts,
  }) async {
    try {
      final colorLog = {
        'session_id': sessionId,
        'timestamp': DateTime.now().toIso8601String(),
        'color_matching': {
          'requested_color': requestedColor,
          'variations_generated': variations,
          'level_results': levelResults,
          'total_matches_before_filter': matchedProducts.length,
          'color_distribution': _analyzeColorDistribution(matchedProducts),
        },
        'matched_products': matchedProducts.map((p) => {
          'id': p['id'],
          'title': p['title'],
          'color_primary': p['color_primary'],
          'color_secondary': p['color_secondary'],
          'category': p['category'],
          'subcategory': p['subcategory'],
        }).toList(),
      };

      await _writeColorLogFile(colorLog);

    } catch (e) {
      print('❌ Failed to log color matching: $e');
    }
  }

  /// Get debug statistics
  Future<Map<String, dynamic>> getDebugStats() async {
    try {
      final logsDir = await _getLogsDirectory();
      final sessionsFile = File('${logsDir.path}/detection_sessions.jsonl');

      if (!await sessionsFile.exists()) {
        return {'total_sessions': 0, 'recent_sessions': []};
      }

      final lines = await sessionsFile.readAsLines();
      final sessions = lines.map((line) => json.decode(line)).toList();

      // Get stats from last 10 sessions
      final recentSessions = sessions.reversed.take(10).map((s) => s as Map<String, dynamic>).toList();

      final stats = {
        'total_sessions': sessions.length,
        'recent_sessions': recentSessions.length,
        'color_accuracy': _calculateColorAccuracy(recentSessions),
        'avg_results_per_session': _calculateAvgResults(recentSessions),
        'most_searched_colors': _getMostSearchedColors(recentSessions),
        'most_searched_categories': _getMostSearchedCategories(recentSessions),
      };

      return stats;

    } catch (e) {
      print('❌ Failed to get debug stats: $e');
      return {};
    }
  }

  /// Export all logs as a report
  Future<String?> exportDebugReport() async {
    try {
      final logsDir = await _getLogsDirectory();
      final timestamp = DateTime.now().toIso8601String().replaceAll(':', '-');
      final reportFile = File('${logsDir.path}/debug_report_$timestamp.json');

      final stats = await getDebugStats();
      final sessionsFile = File('${logsDir.path}/detection_sessions.jsonl');
      final colorFile = File('${logsDir.path}/color_matching.jsonl');
      final searchFile = File('${logsDir.path}/search_process.jsonl');

      final report = {
        'generated_at': DateTime.now().toIso8601String(),
        'statistics': stats,
        'recent_sessions': [],
        'color_matching_logs': [],
        'search_process_logs': [],
      };

      // Add recent session data
      if (await sessionsFile.exists()) {
        final sessionLines = await sessionsFile.readAsLines();
        report['recent_sessions'] = sessionLines.reversed
            .take(20)
            .map((line) => json.decode(line))
            .toList();
      }

      // Add color matching data
      if (await colorFile.exists()) {
        final colorLines = await colorFile.readAsLines();
        report['color_matching_logs'] = colorLines.reversed
            .take(50)
            .map((line) => json.decode(line))
            .toList();
      }

      // Add search process data
      if (await searchFile.exists()) {
        final searchLines = await searchFile.readAsLines();
        report['search_process_logs'] = searchLines.reversed
            .take(50)
            .map((line) => json.decode(line))
            .toList();
      }

      await reportFile.writeAsString(json.encode(report));

      print('📊 Debug report exported: ${reportFile.path}');
      return reportFile.path;

    } catch (e) {
      print('❌ Failed to export debug report: $e');
      return null;
    }
  }

  // Private helper methods
  Future<Directory> _getLogsDirectory() async {
    // Use app's cache directory for Android compatibility
    final appDir = await getApplicationDocumentsDirectory();
    final logsDir = Directory('${appDir.path}/debug_logs');
    if (!await logsDir.exists()) {
      await logsDir.create(recursive: true);
    }

    // Also try to write to external storage if available
    try {
      final externalDir = Directory('/storage/emulated/0/Download/worthify_debug');
      if (!await externalDir.exists()) {
        await externalDir.create(recursive: true);
      }
      print('Debug logs will also be saved to: ${externalDir.path}');
    } catch (e) {
      print('Could not create external debug directory: $e');
    }

    return logsDir;
  }

  Future<int> _getFileSize(String path) async {
    try {
      final file = File(path);
      return await file.length();
    } catch (e) {
      return 0;
    }
  }

  Future<void> _writeToLogFile(Map<String, dynamic> data) async {
    final logsDir = await _getLogsDirectory();
    final file = File('${logsDir.path}/detection_sessions.jsonl');
    final jsonLine = json.encode(data) + '\n';
    await file.writeAsString(jsonLine, mode: FileMode.append);

    // Also write to Downloads folder for easy access
    await _writeToExternalStorage('detection_sessions.jsonl', jsonLine);
  }

  Future<void> _writeSearchLogFile(Map<String, dynamic> data) async {
    final logsDir = await _getLogsDirectory();
    final file = File('${logsDir.path}/search_process.jsonl');
    final jsonLine = json.encode(data) + '\n';
    await file.writeAsString(jsonLine, mode: FileMode.append);

    // Also write to Downloads folder for easy access
    await _writeToExternalStorage('search_process.jsonl', jsonLine);
  }

  Future<void> _writeColorLogFile(Map<String, dynamic> data) async {
    final logsDir = await _getLogsDirectory();
    final file = File('${logsDir.path}/color_matching.jsonl');
    final jsonLine = json.encode(data) + '\n';
    await file.writeAsString(jsonLine, mode: FileMode.append);

    // Also write to Downloads folder for easy access
    await _writeToExternalStorage('color_matching.jsonl', jsonLine);
  }

  Future<void> _writeToCSV(Map<String, dynamic> data) async {
    final logsDir = await _getLogsDirectory();
    final file = File('${logsDir.path}/sessions_summary.csv');

    // Check if file exists to write header
    final exists = await file.exists();

    if (!exists) {
      const header = 'session_id,timestamp,items_detected,results_found,primary_colors,categories\n';
      await file.writeAsString(header);
    }

    final detectionResults = data['detection_results'] as Map<String, dynamic>? ?? {};
    final items = detectionResults['items'] as List? ?? [];

    final primaryColors = items
        .map((item) => item['color_primary'] ?? 'unknown')
        .join('|');

    final categories = items
        .map((item) => item['category'] ?? 'unknown')
        .join('|');

    final csvLine = '${data['session_id']},${data['timestamp']},'
        '${data['analysis']['total_items_detected']},'
        '${data['analysis']['total_results_found']},'
        '"$primaryColors","$categories"\n';

    await file.writeAsString(csvLine, mode: FileMode.append);
  }

  Map<String, int> _analyzeColorDistribution(List<Map<String, dynamic>> products) {
    final colorCounts = <String, int>{};

    for (final product in products) {
      final primaryColor = product['color_primary'] as String?;
      if (primaryColor != null) {
        colorCounts[primaryColor] = (colorCounts[primaryColor] ?? 0) + 1;
      }
    }

    return colorCounts;
  }

  double _calculateColorAccuracy(List<Map<String, dynamic>> sessions) {
    if (sessions.isEmpty) return 0.0;

    int accurateMatches = 0;
    int totalItems = 0;

    for (final session in sessions) {
      final detectionResults = session['detection_results'] as Map<String, dynamic>? ?? {};
      final items = detectionResults['items'] as List? ?? [];

      for (final item in items) {
        totalItems++;
        // This is a simplified accuracy check - you might want to implement more sophisticated logic
        final searchResults = session['search_results'] as List? ?? [];
        if (searchResults.isNotEmpty) {
          accurateMatches++;
        }
      }
    }

    return totalItems > 0 ? (accurateMatches / totalItems) * 100 : 0.0;
  }

  double _calculateAvgResults(List<Map<String, dynamic>> sessions) {
    if (sessions.isEmpty) return 0.0;

    final totalResults = sessions
        .map((s) => s['analysis']['total_results_found'] as int? ?? 0)
        .reduce((a, b) => a + b);

    return totalResults / sessions.length;
  }

  Map<String, int> _getMostSearchedColors(List<Map<String, dynamic>> sessions) {
    final colorCounts = <String, int>{};

    for (final session in sessions) {
      final detectionResults = session['detection_results'] as Map<String, dynamic>? ?? {};
      final items = detectionResults['items'] as List? ?? [];

      for (final item in items) {
        final color = item['color_primary'] as String?;
        if (color != null) {
          colorCounts[color] = (colorCounts[color] ?? 0) + 1;
        }
      }
    }

    return colorCounts;
  }

  Map<String, int> _getMostSearchedCategories(List<Map<String, dynamic>> sessions) {
    final categoryCounts = <String, int>{};

    for (final session in sessions) {
      final detectionResults = session['detection_results'] as Map<String, dynamic>? ?? {};
      final items = detectionResults['items'] as List? ?? [];

      for (final item in items) {
        final category = item['category'] as String?;
        if (category != null) {
          categoryCounts[category] = (categoryCounts[category] ?? 0) + 1;
        }
      }
    }

    return categoryCounts;
  }

  /// Helper method to write logs to external storage (Downloads folder)
  Future<void> _writeToExternalStorage(String filename, String content) async {
    try {
      final externalFile = File('/storage/emulated/0/Download/worthify_debug/$filename');
      await externalFile.writeAsString(content, mode: FileMode.append);
    } catch (e) {
      // Silently fail - external storage is just a convenience
      print('Could not write to external storage: $e');
    }
  }
}