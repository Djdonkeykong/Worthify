import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../../../core/theme/app_colors.dart';
import '../../../../../core/theme/theme_extensions.dart';
import '../../../../shared/widgets/worthify_back_button.dart';

class NotificationSettingsPage extends ConsumerStatefulWidget {
  const NotificationSettingsPage({super.key});

  @override
  ConsumerState<NotificationSettingsPage> createState() =>
      _NotificationSettingsPageState();
}

class _NotificationSettingsPageState
    extends ConsumerState<NotificationSettingsPage> {
  bool _isLoading = true;
  bool _pushEnabled = true;
  bool _uploadReminders = false;
  bool _promotions = false;

  @override
  void initState() {
    super.initState();
    _loadPreferences();
  }

  Future<void> _loadPreferences() async {
    try {
      final userId = Supabase.instance.client.auth.currentUser?.id;
      if (userId == null) {
        debugPrint('[NotificationSettings] No authenticated user');
        setState(() => _isLoading = false);
        return;
      }

      final response = await Supabase.instance.client
          .from('users')
          .select('notification_enabled, upload_reminders_enabled, promotions_enabled')
          .eq('id', userId)
          .maybeSingle();

      if (response != null && mounted) {
        setState(() {
          _pushEnabled = response['notification_enabled'] as bool? ?? true;
          _uploadReminders = response['upload_reminders_enabled'] as bool? ?? false;
          _promotions = response['promotions_enabled'] as bool? ?? false;
          _isLoading = false;
        });
        debugPrint('[NotificationSettings] Loaded preferences: push=$_pushEnabled, reminders=$_uploadReminders, promos=$_promotions');
      } else {
        setState(() => _isLoading = false);
      }
    } catch (e) {
      debugPrint('[NotificationSettings] Error loading preferences: $e');
      setState(() => _isLoading = false);
    }
  }

  Future<void> _updatePreference(String column, bool value) async {
    try {
      final userId = Supabase.instance.client.auth.currentUser?.id;
      if (userId == null) {
        debugPrint('[NotificationSettings] No authenticated user');
        return;
      }

      debugPrint('[NotificationSettings] Updating $column to $value');

      await Supabase.instance.client.from('users').update({
        column: value,
        'updated_at': DateTime.now().toIso8601String(),
      }).eq('id', userId);

      debugPrint('[NotificationSettings] Successfully updated $column');
    } catch (e) {
      debugPrint('[NotificationSettings] Error updating $column: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to update notification settings'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  void _togglePush(bool value) {
    HapticFeedback.selectionClick();
    setState(() => _pushEnabled = value);
    _updatePreference('notification_enabled', value);
  }

  void _toggleUploadReminders(bool value) {
    HapticFeedback.selectionClick();
    setState(() => _uploadReminders = value);
    _updatePreference('upload_reminders_enabled', value);
  }

  void _togglePromotions(bool value) {
    HapticFeedback.selectionClick();
    setState(() => _promotions = value);
    _updatePreference('promotions_enabled', value);
  }

  @override
  Widget build(BuildContext context) {
    final spacing = context.spacing;

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        elevation: 0,
        scrolledUnderElevation: 0,
        leading: const WorthifyBackButton(),
        centerTitle: true,
        title: const Text(
          'Notifications',
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.bold,
            color: Colors.black,
            fontFamily: 'PlusJakartaSans',
            letterSpacing: -0.3,
          ),
        ),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: Color(0xFFF2003C)))
          : SafeArea(
              child: Padding(
                padding: EdgeInsets.fromLTRB(spacing.l, spacing.l, spacing.l, spacing.xl),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SizedBox(height: 4),
                    Text(
                      'Choose the updates you want to receive',
                      style: TextStyle(
                        fontSize: 16,
                        color: Colors.black.withOpacity(0.6),
                        fontFamily: 'PlusJakartaSans',
                        height: 1.5,
                      ),
                    ),
                    SizedBox(height: spacing.l),
                    _SettingsCard(
                      children: [
                        const SizedBox(height: 8),
                        _SettingsRow.toggle(
                          label: 'Push Notifications',
                          value: _pushEnabled,
                          onChanged: _togglePush,
                        ),
                        const SizedBox(height: 8),
                        _Divider(),
                        const SizedBox(height: 8),
                        _SettingsRow.toggle(
                          label: 'Upload Reminders',
                          helper: 'A nudge if you haven\'t shared in a while',
                          value: _uploadReminders,
                          onChanged: _toggleUploadReminders,
                        ),
                        const SizedBox(height: 8),
                        _Divider(),
                        const SizedBox(height: 8),
                        _SettingsRow.toggle(
                          label: 'Promotions',
                          value: _promotions,
                          onChanged: _togglePromotions,
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
  const _SettingsCard({required this.children});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(children: children),
    );
  }
}

class _Divider extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return const Divider(
      height: 1,
      thickness: 1,
      color: Color(0xFFECECEC),
      indent: 16,
      endIndent: 16,
    );
  }
}

class _SettingsRow extends StatelessWidget {
  final String label;
  final String? helper;
  final bool value;
  final ValueChanged<bool> onChanged;

  const _SettingsRow.toggle({
    required this.label,
    required this.value,
    required this.onChanged,
    this.helper,
  });

  @override
  Widget build(BuildContext context) {
    final textStyle = const TextStyle(
      fontSize: 16,
      fontWeight: FontWeight.w600,
      fontFamily: 'PlusJakartaSans',
      color: Colors.black,
    );
    final helperStyle = TextStyle(
      fontSize: 13,
      fontWeight: FontWeight.w500,
      fontFamily: 'PlusJakartaSans',
      color: Colors.black.withOpacity(0.55),
      height: 1.35,
    );

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: Row(
        crossAxisAlignment:
            helper == null ? CrossAxisAlignment.center : CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: textStyle),
                if (helper != null) ...[
                  const SizedBox(height: 4),
                  Text(helper!, style: helperStyle),
                ],
              ],
            ),
          ),
          CupertinoSwitch(
            value: value,
            activeColor: const Color(0xFFF2003C),
            onChanged: onChanged,
          ),
        ],
      ),
    );
  }
}
