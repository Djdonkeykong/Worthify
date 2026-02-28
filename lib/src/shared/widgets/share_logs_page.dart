import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';
import 'package:flutter/services.dart';

import '../services/share_extension_logs_service.dart';
import '../services/review_prompt_logs_service.dart';

class ShareLogsPage extends StatefulWidget {
  const ShareLogsPage({super.key});

  @override
  State<ShareLogsPage> createState() => _ShareLogsPageState();
}

class _ShareLogsPageState extends State<ShareLogsPage> {
  List<String> _logs = const [];
  List<String> _reviewLogs = const [];
  bool _loading = true;
  DateTime? _lastLoadedAt;

  @override
  void initState() {
    super.initState();
    _loadLogs();
  }

  Future<void> _loadLogs() async {
    debugPrint('[ShareLogs] Loading logs...');
    setState(() => _loading = true);
    final entries = await ShareExtensionLogsService.fetchLogs();
    final reviewEntries = await ReviewPromptLogsService.fetchLogs();
    setState(() {
      _logs = entries.reversed.toList();
      _reviewLogs = reviewEntries.reversed.toList();
      _loading = false;
      _lastLoadedAt = DateTime.now();
    });
    debugPrint(
      '[ShareLogs] Loaded share=${_logs.length} review=${_reviewLogs.length} at $_lastLoadedAt',
    );
  }

  Future<void> _clearLogs() async {
    debugPrint('[ShareLogs] Clearing logs...');
    await ShareExtensionLogsService.clearLogs();
    await ReviewPromptLogsService.clearLogs();
    await _loadLogs();
  }

  Future<void> _shareLogs() async {
    if (_logs.isEmpty && _reviewLogs.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No logs to share')),
      );
      return;
    }

    debugPrint(
      '[ShareLogs] Sharing logs share=${_logs.length} review=${_reviewLogs.length}',
    );

    final logsText = [
      if (_logs.isNotEmpty)
        '--- Share Extension Logs ---\n${_logs.join('\n\n')}',
      if (_reviewLogs.isNotEmpty)
        '--- Review Prompt Logs ---\n${_reviewLogs.join('\n\n')}',
    ].where((s) => s.isNotEmpty).join('\n\n');

    final box = context.findRenderObject() as RenderBox?;
    try {
      await Share.share(
        logsText,
        subject: 'Share Extension Logs',
        sharePositionOrigin: box != null
            ? box.localToGlobal(Offset.zero) & box.size
            : const Rect.fromLTWH(0, 0, 1, 1),
      );
    } catch (e) {
      // Fallback: copy to clipboard and notify user
      Clipboard.setData(ClipboardData(text: logsText));
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Share unavailable; logs copied to clipboard.'),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Share Extension Logs'),
        actions: [
          IconButton(
            icon: const Icon(Icons.share),
            onPressed: _shareLogs,
            tooltip: 'Share logs',
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadLogs,
            tooltip: 'Refresh',
          ),
          IconButton(
            icon: const Icon(Icons.delete),
            onPressed: _clearLogs,
            tooltip: 'Clear logs',
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : (_logs.isEmpty && _reviewLogs.isEmpty)
              ? const Center(child: Text('No logs recorded yet.'))
              : ListView(
                  children: [
                    if (_lastLoadedAt != null)
                      Padding(
                        padding: const EdgeInsets.all(12),
                        child: Text(
                          'Last refreshed: ${_lastLoadedAt!.toLocal()}  |  Share: ${_logs.length}, Review: ${_reviewLogs.length}',
                          style: Theme.of(context)
                              .textTheme
                              .bodySmall
                              ?.copyWith(color: Colors.grey[700]),
                        ),
                      ),
                    _LogSection(
                      title: 'Share Extension Logs',
                      logs: _logs,
                    ),
                    const Divider(height: 1),
                    _LogSection(
                      title: 'Review Prompt Logs',
                      logs: _reviewLogs,
                    ),
                  ],
                ),
    );
  }
}

class _LogSection extends StatelessWidget {
  final String title;
  final List<String> logs;

  const _LogSection({
    required this.title,
    required this.logs,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ExpansionTile(
      title: Text(title, style: theme.textTheme.titleMedium),
      initiallyExpanded: true,
      children: logs.isEmpty
          ? [
              const Padding(
                padding: EdgeInsets.all(12),
                child: Text('No entries'),
              )
            ]
          : List.generate(logs.length, (index) {
              final entry = logs[index];
              return Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.all(12),
                    child: Text(
                      entry,
                      style: theme.textTheme.bodyMedium,
                    ),
                  ),
                  if (index != logs.length - 1)
                    const Divider(height: 1, thickness: 0.5),
                ],
              );
            }),
    );
  }
}
