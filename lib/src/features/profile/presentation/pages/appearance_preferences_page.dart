import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../../core/theme/theme_extensions.dart';
import '../../../../../core/theme/theme_mode_provider.dart';
import '../../../../shared/widgets/worthify_back_button.dart';
import '../../../../../core/theme/app_colors.dart';

class AppearancePreferencesPage extends ConsumerWidget {
  const AppearancePreferencesPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final spacing = context.spacing;
    final themeMode = ref.watch(themeModeProvider);
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: colorScheme.background,
      appBar: AppBar(
        backgroundColor: colorScheme.background,
        elevation: 0,
        scrolledUnderElevation: 0,
        leading: const WorthifyBackButton(),
        centerTitle: true,
        title: Text(
          'Appearance',
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.bold,
            color: colorScheme.onSurface,
            fontFamily: 'PlusJakartaSans',
            letterSpacing: -0.3,
          ),
        ),
      ),
      body: SafeArea(
        child: Padding(
          padding: EdgeInsets.fromLTRB(
            spacing.l,
            spacing.l,
            spacing.l,
            spacing.xl,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 4),
              Text(
                'Choose your preferred appearance',
                style: TextStyle(
                  fontSize: 16,
                  color: colorScheme.onSurfaceVariant,
                  fontFamily: 'PlusJakartaSans',
                  height: 1.5,
                ),
              ),
              SizedBox(height: spacing.l),
              _SettingsCard(
                backgroundColor: colorScheme.surface,
                children: [
                  const SizedBox(height: 8),
                  _SettingsRow.toggle(
                    label: 'System',
                    value: themeMode == ThemeMode.system,
                    onChanged: (val) async {
                      if (!val) return;
                      HapticFeedback.selectionClick();
                      await ref
                          .read(themeModeProvider.notifier)
                          .setMode(ThemeMode.system);
                    },
                  ),
                  const SizedBox(height: 8),
                  _Divider(color: colorScheme.outlineVariant),
                  const SizedBox(height: 8),
                  _SettingsRow.toggle(
                    label: 'Light',
                    value: themeMode == ThemeMode.light,
                    onChanged: (val) async {
                      if (!val) return;
                      HapticFeedback.selectionClick();
                      await ref
                          .read(themeModeProvider.notifier)
                          .setMode(ThemeMode.light);
                    },
                  ),
                  const SizedBox(height: 8),
                  _Divider(color: colorScheme.outlineVariant),
                  const SizedBox(height: 8),
                  _SettingsRow.toggle(
                    label: 'Dark',
                    value: themeMode == ThemeMode.dark,
                    onChanged: (val) async {
                      if (!val) return;
                      HapticFeedback.selectionClick();
                      await ref
                          .read(themeModeProvider.notifier)
                          .setMode(ThemeMode.dark);
                    },
                  ),
                  const SizedBox(height: 8),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SettingsCard extends StatelessWidget {
  final List<Widget> children;
  final Color backgroundColor;

  const _SettingsCard({
    required this.children,
    required this.backgroundColor,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(children: children),
    );
  }
}

class _Divider extends StatelessWidget {
  final Color color;

  const _Divider({required this.color});

  @override
  Widget build(BuildContext context) {
    return Divider(
      height: 1,
      thickness: 1,
      color: color,
      indent: 16,
      endIndent: 16,
    );
  }
}

class _SettingsRow extends StatelessWidget {
  final String label;
  final bool value;
  final ValueChanged<bool> onChanged;

  const _SettingsRow.toggle({
    required this.label,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final textColor = Theme.of(context).colorScheme.onSurface;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                fontFamily: 'PlusJakartaSans',
                color: textColor,
              ),
            ),
          ),
          CupertinoSwitch(
            value: value,
            activeColor: AppColors.secondary,
            onChanged: onChanged,
          ),
        ],
      ),
    );
  }
}
