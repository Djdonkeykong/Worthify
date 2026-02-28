import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';
import '../services/debug_log_service.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/theme_extensions.dart';

class FlutterLogsPage extends StatefulWidget {
  const FlutterLogsPage({super.key});

  @override
  State<FlutterLogsPage> createState() => _FlutterLogsPageState();
}

class _FlutterLogsPageState extends State<FlutterLogsPage> {
  final ScrollController _scrollController = ScrollController();
  bool _autoScroll = true;

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _scrollToBottom() {
    if (_scrollController.hasClients && _autoScroll) {
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
      );
    }
  }

  Future<void> _shareLogs() async {
    final logsText = DebugLogService().getAllLogsAsString();
    if (logsText.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No logs to share')),
      );
      return;
    }

    final box = context.findRenderObject() as RenderBox?;

    try {
      await Share.share(
        logsText,
        subject: 'Flutter App Logs',
        sharePositionOrigin: box != null
            ? box.localToGlobal(Offset.zero) & box.size
            : const Rect.fromLTWH(0, 0, 1, 1),
      );
    } catch (e) {
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

  void _clearLogs() {
    DebugLogService().clear();
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final spacing = context.spacing;

    return Scaffold(
      backgroundColor: colorScheme.background,
      appBar: AppBar(
        backgroundColor: colorScheme.background,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: true,
        title: Text(
          'Flutter Logs',
          style: TextStyle(
            fontSize: 22,
            fontFamily: 'PlusJakartaSans',
            fontWeight: FontWeight.bold,
            color: colorScheme.onSurface,
            letterSpacing: -0.3,
          ),
        ),
        actions: [
          IconButton(
            icon: Icon(
              _autoScroll ? Icons.vertical_align_bottom : Icons.vertical_align_center,
              color: colorScheme.onSurface,
            ),
            onPressed: () {
              setState(() {
                _autoScroll = !_autoScroll;
                if (_autoScroll) {
                  _scrollToBottom();
                }
              });
            },
            tooltip: _autoScroll ? 'Disable auto-scroll' : 'Enable auto-scroll',
          ),
          IconButton(
            icon: Icon(Icons.share, color: colorScheme.onSurface),
            onPressed: _shareLogs,
            tooltip: 'Share logs',
          ),
          IconButton(
            icon: Icon(Icons.delete, color: colorScheme.onSurface),
            onPressed: _clearLogs,
            tooltip: 'Clear logs',
          ),
        ],
      ),
      body: StreamBuilder<String>(
        stream: DebugLogService().logStream,
        builder: (context, snapshot) {
          final logs = DebugLogService().logs;

          WidgetsBinding.instance.addPostFrameCallback((_) {
            _scrollToBottom();
          });

          if (logs.isEmpty) {
            return Center(
              child: Text(
                'No logs yet',
                style: TextStyle(
                  fontSize: 16,
                  fontFamily: 'PlusJakartaSans',
                  fontWeight: FontWeight.w500,
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
            );
          }

          return Container(
            color: colorScheme.surface,
            child: Column(
              children: [
                Padding(
                  padding: EdgeInsets.all(spacing.m),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Total: ${logs.length} logs',
                        style: TextStyle(
                          fontSize: 14,
                          fontFamily: 'PlusJakartaSans',
                          fontWeight: FontWeight.w600,
                          color: colorScheme.onSurfaceVariant,
                        ),
                      ),
                      Text(
                        _autoScroll ? 'Auto-scroll: ON' : 'Auto-scroll: OFF',
                        style: TextStyle(
                          fontSize: 14,
                          fontFamily: 'PlusJakartaSans',
                          fontWeight: FontWeight.w600,
                          color: _autoScroll ? AppColors.secondary : colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: ListView.separated(
                    controller: _scrollController,
                    padding: EdgeInsets.all(spacing.m),
                    itemCount: logs.length,
                    separatorBuilder: (context, index) => Divider(
                      height: 1,
                      color: colorScheme.outline.withOpacity(0.3),
                    ),
                    itemBuilder: (context, index) {
                      final log = logs[index];
                      return Padding(
                        padding: EdgeInsets.symmetric(vertical: spacing.sm),
                        child: SelectableText(
                          log,
                          style: TextStyle(
                            fontSize: 13,
                            fontFamily: 'SF Mono',
                            color: colorScheme.onSurface,
                            height: 1.4,
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}
