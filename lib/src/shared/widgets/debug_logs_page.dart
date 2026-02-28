import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/theme_extensions.dart';
import '../services/debug_log_service.dart';

class DebugLogsPage extends StatefulWidget {
  const DebugLogsPage({super.key});

  @override
  State<DebugLogsPage> createState() => _DebugLogsPageState();
}

class _DebugLogsPageState extends State<DebugLogsPage> {
  final _debugLogService = DebugLogService();
  final ScrollController _scrollController = ScrollController();
  bool _autoScroll = true;

  @override
  void initState() {
    super.initState();
    // Scroll to bottom when new logs arrive
    _debugLogService.logStream.listen((_) {
      if (_autoScroll && _scrollController.hasClients) {
        Future.delayed(const Duration(milliseconds: 100), () {
          if (_scrollController.hasClients) {
            _scrollController.animateTo(
              _scrollController.position.maxScrollExtent,
              duration: const Duration(milliseconds: 200),
              curve: Curves.easeOut,
            );
          }
        });
      }
    });
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _shareAllLogs() async {
    final logs = _debugLogService.getAllLogsAsString();
    if (logs.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'No logs to share',
            style: context.snackTextStyle(
              merge: const TextStyle(fontFamily: 'PlusJakartaSans'),
            ),
          ),
        ),
      );
      return;
    }

    final renderBox = context.findRenderObject() as RenderBox?;
    final origin = (renderBox != null && renderBox.hasSize)
        ? renderBox.localToGlobal(Offset.zero) & renderBox.size
        : const Rect.fromLTWH(0, 0, 1, 1);

    await Share.share(
      logs,
      subject: 'Worthify Debug Logs',
      sharePositionOrigin: origin,
    );
  }

  void _copyAllLogs() async {
    final logs = _debugLogService.getAllLogsAsString();
    if (logs.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'No logs to copy',
            style: context.snackTextStyle(
              merge: const TextStyle(fontFamily: 'PlusJakartaSans'),
            ),
          ),
        ),
      );
      return;
    }

    await Clipboard.setData(ClipboardData(text: logs));
    if (mounted) {
      ScaffoldMessenger.of(context).clearSnackBars();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Logs copied to clipboard',
            style: context.snackTextStyle(
              merge: const TextStyle(fontFamily: 'PlusJakartaSans'),
            ),
          ),
          duration: const Duration(milliseconds: 2000),
        ),
      );
    }
  }

  void _clearLogs() {
    _debugLogService.clear();
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final spacing = context.spacing;
    final logs = _debugLogService.logs;

    return Scaffold(
      backgroundColor: Theme.of(context).colorScheme.background,
      appBar: AppBar(
        backgroundColor: Theme.of(context).colorScheme.background,
        elevation: 0,
        scrolledUnderElevation: 0,
        title: const Text(
          'Debug Logs',
          style: TextStyle(
            fontSize: 22,
            fontFamily: 'PlusJakartaSans',
            fontWeight: FontWeight.bold,
            letterSpacing: -0.3,
          ),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () {
              setState(() {});
            },
            tooltip: 'Refresh',
          ),
          IconButton(
            icon: const Icon(Icons.delete_outline),
            onPressed: _clearLogs,
            tooltip: 'Clear logs',
          ),
        ],
      ),
      body: Column(
        children: [
          // Auto-scroll toggle
          Container(
            padding: EdgeInsets.symmetric(horizontal: spacing.l, vertical: spacing.sm),
            color: Theme.of(context).colorScheme.surface,
            child: Row(
              children: [
                Icon(
                  _autoScroll ? Icons.arrow_downward : Icons.pause,
                  size: 16,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
                SizedBox(width: spacing.sm),
                Text(
                  'Auto-scroll',
                  style: TextStyle(
                    fontSize: 14,
                    fontFamily: 'PlusJakartaSans',
                    fontWeight: FontWeight.w500,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
                const Spacer(),
                Switch(
                  value: _autoScroll,
                  onChanged: (value) {
                    setState(() {
                      _autoScroll = value;
                    });
                  },
                  activeColor: AppColors.secondary,
                ),
              ],
            ),
          ),

          // Log count
          Container(
            width: double.infinity,
            padding: EdgeInsets.all(spacing.m),
            color: Theme.of(context).colorScheme.surface.withOpacity(0.5),
            child: Text(
              '${logs.length} log entries',
              style: TextStyle(
                fontSize: 12,
                fontFamily: 'PlusJakartaSans',
                fontWeight: FontWeight.w500,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ),

          // Logs list
          Expanded(
            child: logs.isEmpty
                ? Center(
                    child: Text(
                      'No logs yet',
                      style: TextStyle(
                        fontSize: 14,
                        fontFamily: 'PlusJakartaSans',
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                  )
                : ListView.builder(
                    controller: _scrollController,
                    padding: EdgeInsets.all(spacing.m),
                    itemCount: logs.length,
                    itemBuilder: (context, index) {
                      final log = logs[index];
                      return Padding(
                        padding: EdgeInsets.only(bottom: spacing.xs),
                        child: SelectableText(
                          log,
                          style: TextStyle(
                            fontSize: 11,
                            fontFamily: 'Courier',
                            color: _getLogColor(log),
                            height: 1.4,
                          ),
                        ),
                      );
                    },
                  ),
          ),

          // Action buttons
          Container(
            decoration: BoxDecoration(
              color: Colors.white,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.06),
                  blurRadius: 18,
                  offset: const Offset(0, -6),
                  spreadRadius: 1,
                ),
              ],
            ),
            child: SafeArea(
              top: false,
              minimum: EdgeInsets.only(
                left: spacing.l,
                right: spacing.l,
                bottom: spacing.m,
                top: spacing.m,
              ),
              child: Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _copyAllLogs,
                      icon: const Icon(Icons.copy, size: 18),
                      label: const Text('Copy'),
                      style: OutlinedButton.styleFrom(
                        padding: EdgeInsets.symmetric(vertical: spacing.m),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(28),
                        ),
                        side: BorderSide(
                          color: Theme.of(context).colorScheme.outline,
                        ),
                        foregroundColor: Theme.of(context).colorScheme.onSurface,
                        textStyle: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          fontFamily: 'PlusJakartaSans',
                        ),
                      ),
                    ),
                  ),
                  SizedBox(width: spacing.m),
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: _shareAllLogs,
                      icon: const Icon(Icons.share, size: 18),
                      label: const Text('Share'),
                      style: ElevatedButton.styleFrom(
                        padding: EdgeInsets.symmetric(vertical: spacing.m),
                        backgroundColor: AppColors.secondary,
                        foregroundColor: Colors.white,
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(28),
                        ),
                        textStyle: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          fontFamily: 'PlusJakartaSans',
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Color _getLogColor(String log) {
    if (log.contains('ERROR') || log.contains('Error') || log.contains('FAILED')) {
      return Colors.red.shade700;
    } else if (log.contains('WARNING') || log.contains('Warning')) {
      return Colors.orange.shade700;
    } else if (log.contains('SUCCESS') || log.contains('Success')) {
      return Colors.green.shade700;
    } else if (log.contains('[APNS]') || log.contains('[NotificationService]')) {
      return Colors.blue.shade700;
    } else if (log.contains('[WelcomePage]') || log.contains('[OnboardingState]')) {
      return Colors.purple.shade700;
    }
    return Colors.black87;
  }
}
