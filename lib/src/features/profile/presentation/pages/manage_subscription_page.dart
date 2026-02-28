import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'dart:io';
import '../../../../../core/theme/app_colors.dart';
import '../../../../../core/theme/theme_extensions.dart';
import '../../../../shared/widgets/worthify_back_button.dart';

// Provider to fetch user subscription info from Supabase
final userSubscriptionProvider = FutureProvider.autoDispose<Map<String, dynamic>?>((ref) async {
  final userId = Supabase.instance.client.auth.currentUser?.id;
  if (userId == null) return null;

  try {
    final response = await Supabase.instance.client
        .from('users')
        .select('subscription_status, is_trial, paid_credits_remaining')
        .eq('id', userId)
        .maybeSingle();

    return response;
  } catch (e) {
    print('[ManageSubscription] Error fetching subscription: $e');
    return null;
  }
});

class ManageSubscriptionPage extends ConsumerWidget {
  const ManageSubscriptionPage({super.key});

  Future<void> _openSubscriptionManagement(BuildContext context) async {
    try {
      Uri? uri;

      if (Platform.isIOS) {
        // iOS subscription management
        uri = Uri.parse('https://apps.apple.com/account/subscriptions');
      } else if (Platform.isAndroid) {
        // Android subscription management
        uri = Uri.parse('https://play.google.com/store/account/subscriptions');
      }

      if (uri != null) {
        await launchUrl(uri, mode: LaunchMode.inAppBrowserView);
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Could not open subscription management',
              style: context.snackTextStyle(
                merge: const TextStyle(fontFamily: 'PlusJakartaSans'),
              ),
            ),
            duration: const Duration(milliseconds: 2000),
          ),
        );
      }
    }
  }

  Future<void> _restorePurchases(BuildContext context) async {
    // TODO: Implement Superwall restore purchases
    // This will call Superwall's restore purchases method
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          'Restoring purchases...',
          style: context.snackTextStyle(
            merge: const TextStyle(fontFamily: 'PlusJakartaSans'),
          ),
        ),
        duration: const Duration(milliseconds: 2000),
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colorScheme = Theme.of(context).colorScheme;
    final spacing = context.spacing;
    final subscriptionAsync = ref.watch(userSubscriptionProvider);

    return Scaffold(
      backgroundColor: colorScheme.background,
      appBar: AppBar(
        backgroundColor: colorScheme.background,
        elevation: 0,
        scrolledUnderElevation: 0,
        automaticallyImplyLeading: false,
        centerTitle: true,
        leadingWidth: 56,
        leading: WorthifyBackButton(
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Text(
          'Manage Subscription',
          style: TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.bold,
            fontFamily: 'PlusJakartaSans',
            color: colorScheme.onSurface,
            letterSpacing: -0.3,
          ),
        ),
      ),
      body: SafeArea(
        child: subscriptionAsync.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (error, stack) => Center(
            child: Text(
              'Error loading subscription',
              style: TextStyle(
                color: colorScheme.onSurfaceVariant,
                fontFamily: 'PlusJakartaSans',
              ),
            ),
          ),
          data: (subscriptionData) {
            // Extract subscription info from Supabase users table
            final subscriptionStatus = subscriptionData?['subscription_status'] as String? ?? 'free';
            final isTrial = subscriptionData?['is_trial'] as bool? ?? false;
            final credits = subscriptionData?['paid_credits_remaining'] as int? ?? 0;

            // Determine display values
            final isSubscribed = subscriptionStatus == 'active';
            final displayStatus = _formatSubscriptionStatus(subscriptionStatus, isTrial);

            return SingleChildScrollView(
              padding: EdgeInsets.symmetric(horizontal: spacing.l),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(height: spacing.l),

                  _SettingsCard(
                    showShadow: true,
                    children: [
                      const SizedBox(height: 8),
                      _SettingsRow.value(
                        label: 'Current Plan',
                        value: displayStatus,
                        valueColor:
                            isSubscribed ? AppColors.secondary : colorScheme.onSurface,
                      ),
                      const SizedBox(height: 8),
                    ],
                  ),

                  SizedBox(height: spacing.l),

                  _SettingsCard(
                    children: [
                      const SizedBox(height: 8),
                      _SettingsRow.disclosure(
                        label: Platform.isIOS
                            ? 'Manage in App Store'
                            : 'Manage in Google Play',
                        onTap: () => _openSubscriptionManagement(context),
                      ),
                      const SizedBox(height: 8),
                      _Divider(),
                      const SizedBox(height: 8),
                      _SettingsRow.disclosure(
                        label: 'Restore Purchases',
                        onTap: () => _restorePurchases(context),
                      ),
                      const SizedBox(height: 8),
                    ],
                  ),

                  SizedBox(height: spacing.l),

                  _SettingsCard(
                    children: [
                      Padding(
                        padding:
                            const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                        child: Text(
                          'To cancel or modify your subscription, use the ${Platform.isIOS ? 'App Store' : 'Google Play'} subscription management. Changes take effect at the end of your billing period.',
                          style: TextStyle(
                            fontSize: 14,
                            height: 1.45,
                            color: colorScheme.onSurfaceVariant,
                            fontFamily: 'PlusJakartaSans',
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  String _formatSubscriptionStatus(String status, bool isTrial) {
    if (status == 'active') {
      return isTrial ? 'Premium (Trial)' : 'Premium';
    } else if (status == 'cancelled' || status == 'expired') {
      return 'Expired';
    } else {
      return 'Free';
    }
  }

  String _formatMembership(String raw) {
    final cleaned = raw.trim();
    final normalized = cleaned.replaceAll(RegExp(r'[_-]+'), ' ').trim();
    final segments =
        normalized.split(RegExp(r'\s+')).where((segment) => segment.isNotEmpty);
    if (segments.isEmpty) {
      return 'Free';
    }
    return segments
        .map(
          (segment) =>
              segment[0].toUpperCase() + segment.substring(1).toLowerCase(),
        )
        .join(' ');
  }
}

class _SettingsCard extends StatelessWidget {
  final List<Widget> children;
  final bool showShadow;

  const _SettingsCard({
    required this.children,
    this.showShadow = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        boxShadow: showShadow ? [
          BoxShadow(
            color: Colors.black.withOpacity(0.03),
            blurRadius: 12,
            offset: const Offset(0, 6),
          ),
        ] : null,
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
  final String? value;
  final Color? valueColor;
  final VoidCallback? onTap;
  final _RowType type;

  const _SettingsRow.value({
    required this.label,
    this.value,
    this.valueColor,
  })  : onTap = null,
        type = _RowType.value;

  const _SettingsRow.disclosure({
    required this.label,
    required this.onTap,
    this.value,
    this.valueColor,
  }) : type = _RowType.disclosure;

  @override
  Widget build(BuildContext context) {
    final textStyle = TextStyle(
      fontSize: 16,
      fontWeight: FontWeight.w600,
      fontFamily: 'PlusJakartaSans',
      color: Colors.black,
    );
    final valueStyle = TextStyle(
      fontSize: 15,
      fontWeight: FontWeight.w600,
      fontFamily: 'PlusJakartaSans',
      color: valueColor ?? Colors.black.withOpacity(0.6),
    );

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(
          children: [
            Expanded(
              child: Text(
                label,
                style: textStyle,
              ),
            ),
            if (value != null)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                margin: const EdgeInsets.only(right: 8),
                decoration: BoxDecoration(
                  color: AppColors.outlineVariant,
                  borderRadius: BorderRadius.circular(12),
                ),
                alignment: Alignment.center,
                child: Text(
                  value!,
                  style: valueStyle.copyWith(height: 1.0),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                ),
              ),
            if (type == _RowType.disclosure)
              const Icon(
                Icons.chevron_right,
                size: 20,
                color: Color(0xFF8E8E93),
              ),
          ],
        ),
      ),
    );
  }
}

enum _RowType { value, disclosure }
