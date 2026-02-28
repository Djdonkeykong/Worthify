import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';
import '../../../../../core/theme/app_colors.dart';
import '../../../../../core/theme/theme_extensions.dart';
import '../../../../services/debug_log_service.dart';
import '../../../../shared/widgets/worthify_circular_icon_button.dart';

class DebugLogsPage extends ConsumerWidget {
  const DebugLogsPage({super.key});

  Color _getColorForLevel(DebugLogLevel level) {
    switch (level) {
      case DebugLogLevel.debug:
        return Colors.grey;
      case DebugLogLevel.info:
        return Colors.blue;
      case DebugLogLevel.warning:
        return Colors.orange;
      case DebugLogLevel.error:
        return Colors.red;
    }
  }

  void _shareLogs(BuildContext context) {
    final logs = DebugLogService().getLogsAsText();
    final renderBox = context.findRenderObject() as RenderBox?;
    final origin = (renderBox != null && renderBox.hasSize)
        ? renderBox.localToGlobal(Offset.zero) & renderBox.size
        : const Rect.fromLTWH(0, 0, 1, 1);

    Share.share(
      logs,
      subject: 'Worthify Debug Logs',
      sharePositionOrigin: origin,
    );
  }

  void _clearLogs() {
    DebugLogService().clear();
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
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
        leading: WorthifyCircularIconButton(
          icon: Icons.arrow_back,
          size: 40,
          iconSize: 20,
          onPressed: () => Navigator.of(context).pop(),
          semanticLabel: 'Back',
        ),
        title: Text(
          'Debug Logs',
          style: TextStyle(
            fontSize: 22,
            fontFamily: 'PlusJakartaSans',
            fontWeight: FontWeight.bold,
            color: colorScheme.onSurface,
            letterSpacing: -0.3,
          ),
        ),
        actions: [
          WorthifyCircularIconButton(
            icon: Icons.share,
            size: 40,
            iconSize: 20,
            onPressed: () => _shareLogs(context),
            semanticLabel: 'Share logs',
          ),
          SizedBox(width: spacing.xs),
          WorthifyCircularIconButton(
            icon: Icons.delete_outline,
            size: 40,
            iconSize: 20,
            onPressed: _clearLogs,
            semanticLabel: 'Clear logs',
          ),
          SizedBox(width: spacing.sm),
        ],
      ),
      body: SafeArea(
        child: StreamBuilder<List<LogEntry>>(
          stream: DebugLogService().logsStream,
          initialData: DebugLogService().logs,
          builder: (context, snapshot) {
            final logs = snapshot.data ?? [];

            if (logs.isEmpty) {
              return Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.description_outlined,
                      size: 64,
                      color: colorScheme.onSurfaceVariant.withOpacity(0.5),
                    ),
                    SizedBox(height: spacing.m),
                    Text(
                      'No logs yet',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                        fontFamily: 'PlusJakartaSans',
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                    SizedBox(height: spacing.xs),
                    Text(
                      'Logs will appear here when you interact with the app',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                        fontFamily: 'PlusJakartaSans',
                        color: colorScheme.onSurfaceVariant.withOpacity(0.7),
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              );
            }

            return ListView.builder(
              itemCount: logs.length,
              reverse: true, // Show newest logs at the top
              padding: EdgeInsets.all(spacing.sm),
              itemBuilder: (context, index) {
                final log = logs[logs.length - 1 - index]; // Reverse order
                final levelColor = _getColorForLevel(log.level);

                return Container(
                  margin: EdgeInsets.only(bottom: spacing.xs),
                  padding: EdgeInsets.all(spacing.sm),
                  decoration: BoxDecoration(
                    color: colorScheme.surface,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: levelColor.withOpacity(0.3),
                      width: 1,
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Header with time, tag, and level
                      Row(
                        children: [
                          // Time
                          Text(
                            log.formattedTime,
                            style: TextStyle(
                              fontSize: 11,
                              fontFamily: 'Courier',
                              color: colorScheme.onSurfaceVariant,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          SizedBox(width: spacing.xs),
                          // Tag (if present)
                          if (log.tag != null) ...[
                            Container(
                              padding: EdgeInsets.symmetric(
                                horizontal: spacing.xs,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: AppColors.secondary.withOpacity(0.1),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                log.tag!,
                                style: TextStyle(
                                  fontSize: 10,
                                  fontFamily: 'PlusJakartaSans',
                                  color: AppColors.secondary,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                            SizedBox(width: spacing.xs),
                          ],
                          // Level badge
                          Container(
                            padding: EdgeInsets.symmetric(
                              horizontal: spacing.xs,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: levelColor.withOpacity(0.15),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              log.level.name.toUpperCase(),
                              style: TextStyle(
                                fontSize: 10,
                                fontFamily: 'PlusJakartaSans',
                                color: levelColor,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ],
                      ),
                      SizedBox(height: spacing.xs),
                      // Message
                      Text(
                        log.message,
                        style: TextStyle(
                          fontSize: 12,
                          fontFamily: 'Courier',
                          color: colorScheme.onSurface,
                          height: 1.4,
                        ),
                      ),
                    ],
                  ),
                );
              },
            );
          },
        ),
      ),
    );
  }
}
