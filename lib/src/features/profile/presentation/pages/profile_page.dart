import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../../../core/theme/app_colors.dart';
import '../../../../../core/theme/theme_extensions.dart';
import '../../../../../shared/navigation/main_navigation.dart';
import '../../../auth/domain/providers/auth_provider.dart';
import '../../../auth/presentation/pages/login_page.dart';
import '../../../paywall/providers/credit_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'edit_profile_page.dart';
import 'appearance_preferences_page.dart';
import 'manage_subscription_page.dart';
import 'notification_settings_page.dart';
import '../widgets/profile_webview_bottom_sheet.dart';
import '../../../../shared/widgets/worthify_circular_icon_button.dart';

class ProfilePage extends ConsumerStatefulWidget {
  const ProfilePage({super.key});

  @override
  ConsumerState<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends ConsumerState<ProfilePage> {
  final ScrollController _scrollController = ScrollController();
  String _versionString = '';

  @override
  void initState() {
    super.initState();
    _loadVersion();
  }

  Future<void> _loadVersion() async {
    final info = await PackageInfo.fromPlatform();
    if (mounted) {
      setState(() {
        _versionString = 'Version ${info.version} (${info.buildNumber})';
      });
    }
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _shareApp(BuildContext context) {
    const message =
        'Check out Worthify – identify artwork and get AI value estimates. Download now: https://worthify.app';
    final renderBox = context.findRenderObject() as RenderBox?;
    final origin = (renderBox != null && renderBox.hasSize)
        ? renderBox.localToGlobal(Offset.zero) & renderBox.size
        : const Rect.fromLTWH(0, 0, 1, 1);

    Share.share(
      message,
      subject: 'Worthify',
      sharePositionOrigin: origin,
    );
  }

  Future<bool?> _showActionDialog({
    required String title,
    required String message,
    required String confirmLabel,
    required String cancelLabel,
  }) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final spacing = context.spacing;
    final outlineColor = colorScheme.outline;

    return showDialog<bool>(
      context: context,
      barrierDismissible: true,
      barrierColor: Colors.black.withOpacity(0.45),
      builder: (dialogContext) {
        return Dialog(
          clipBehavior: Clip.antiAlias,
          backgroundColor: colorScheme.surface,
          insetPadding:
              const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(22),
          ),
          child: Padding(
            padding:
                EdgeInsets.fromLTRB(spacing.l, spacing.l, spacing.l, spacing.l),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Expanded(
                      child: Text(
                        title,
                        style: TextStyle(
                          fontFamily: 'PlusJakartaSans',
                          fontSize: 20,
                          fontWeight: FontWeight.w700,
                          color: colorScheme.onSurface,
                        ),
                      ),
                    ),
                    WorthifyCircularIconButton(
                      icon: Icons.close,
                      size: 40,
                      iconSize: 18,
                      onPressed: () => Navigator.of(dialogContext).pop(false),
                      semanticLabel: 'Close',
                    ),
                  ],
                ),
                SizedBox(height: spacing.sm),
                Text(
                  message,
                  style: TextStyle(
                    fontFamily: 'PlusJakartaSans',
                    fontSize: 16,
                    fontWeight: FontWeight.w500,
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
                SizedBox(height: spacing.l),
                Row(
                  children: [
                    Expanded(
                      child: SizedBox(
                        height: 56,
                        child: OutlinedButton(
                          onPressed: () =>
                              Navigator.of(dialogContext).pop(false),
                          style: OutlinedButton.styleFrom(
                            minimumSize: const Size.fromHeight(56),
                            side: BorderSide(color: outlineColor, width: 1.4),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(30),
                            ),
                            foregroundColor: colorScheme.onSurface,
                            textStyle: const TextStyle(
                              fontFamily: 'PlusJakartaSans',
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          child: Text(cancelLabel, textAlign: TextAlign.center),
                        ),
                      ),
                    ),
                    SizedBox(width: spacing.sm),
                    Expanded(
                      child: SizedBox(
                        height: 56,
                        child: ElevatedButton(
                          onPressed: () =>
                              Navigator.of(dialogContext).pop(true),
                          style: ElevatedButton.styleFrom(
                            elevation: 0,
                            minimumSize: const Size.fromHeight(56),
                            backgroundColor: AppColors.secondary,
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(30),
                            ),
                            textStyle: const TextStyle(
                              fontFamily: 'PlusJakartaSans',
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          child:
                              Text(confirmLabel, textAlign: TextAlign.center),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _handleLogout() async {
    final confirmed = await _showActionDialog(
      title: 'Log out?',
      message: 'Are you sure you want to log out?',
      confirmLabel: 'Log out',
      cancelLabel: 'Cancel',
    );

    if (confirmed == true && mounted) {
      try {
        // Navigate immediately to prevent UI flash of default user
        Navigator.of(context, rootNavigator: true).pushAndRemoveUntil(
          MaterialPageRoute(builder: (context) => const LoginPage()),
          (route) => false,
        );

        // Sign out after navigation
        final authService = ref.read(authServiceProvider);
        await authService.signOut();

        // Invalidate credit balance provider to force refresh on next login
        ref.invalidate(creditBalanceProvider);
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).clearSnackBars();
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                'Error logging out: ${e.toString()}',
                style: context.snackTextStyle(
                  merge: const TextStyle(fontFamily: 'PlusJakartaSans'),
                ),
              ),
              duration: const Duration(milliseconds: 2500),
            ),
          );
        }
      }
    }
  }

  Future<void> _handleDeleteAccount() async {
    final confirmed = await _showActionDialog(
      title: 'Delete Account?',
      message:
          'Are you sure you want to permanently delete your account? This action cannot be undone.',
      confirmLabel: 'Delete',
      cancelLabel: 'Cancel',
    );

    if (confirmed == true && mounted) {
      try {
        // Show loading indicator
        if (mounted) {
          ScaffoldMessenger.of(context).clearSnackBars();
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                'Deleting account...',
                style: context.snackTextStyle(
                  merge: const TextStyle(fontFamily: 'PlusJakartaSans'),
                ),
              ),
              duration: const Duration(seconds: 10),
            ),
          );
        }

        final authService = ref.read(authServiceProvider);
        final user = authService.currentUser;

        if (user == null) {
          throw Exception('No user found');
        }

        // Delete user from Supabase (cascade will delete related data)
        await authService.deleteAccount();

        if (mounted) {
          ScaffoldMessenger.of(context).clearSnackBars();
        }

        // Navigate to login page
        if (mounted) {
          Navigator.of(context, rootNavigator: true).pushAndRemoveUntil(
            MaterialPageRoute(builder: (context) => const LoginPage()),
            (route) => false,
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).clearSnackBars();
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                'Error deleting account: ${e.toString()}',
                style: context.snackTextStyle(
                  merge: const TextStyle(fontFamily: 'PlusJakartaSans'),
                ),
              ),
              duration: const Duration(milliseconds: 3000),
            ),
          );
        }
      }
    }
  }

  Future<void> _openHelpLink(BuildContext context) async {
    final uri = Uri.parse('https://worthify.app/help-center/');

    // Use in-app browser only; no fallbacks
    await launchUrl(uri, mode: LaunchMode.inAppBrowserView);
  }

  Future<void> _openDocumentSheet({
    required String title,
    required String url,
  }) async {
    final uri = Uri.parse(url);
    await launchUrl(uri, mode: LaunchMode.inAppBrowserView);
  }

  void _handleManageSubscription() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => const ManageSubscriptionPage(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // Listen to scroll to top trigger for profile tab (index 2)
    ref.listen(scrollToTopTriggerProvider, (previous, next) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          0,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });

    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final spacing = context.spacing;
    // Watch so profile updates (name/initial) reflect after edits.
    final user = ref.watch(currentUserProvider);
    final userEmail = user?.email ?? 'user@example.com';
    final metadata = user?.userMetadata ?? <String, dynamic>{};
    final fullName = (metadata['full_name'] as String? ?? '').trim();
    final username = (metadata['username'] as String? ?? '').trim();
    final fallbackName = userEmail.split('@').first;
    final displayName = username.isNotEmpty
        ? username
        : (fullName.isNotEmpty ? fullName : fallbackName);
    final profileInitial =
        displayName.isNotEmpty ? displayName[0].toUpperCase() : 'U';

    return Scaffold(
      backgroundColor: colorScheme.background,
      appBar: AppBar(
        backgroundColor: colorScheme.background,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: true,
        automaticallyImplyLeading: false,
        title: Text(
          'Settings',
          style: TextStyle(
            fontSize: 22,
            fontFamily: 'PlusJakartaSans',
            fontWeight: FontWeight.bold,
            color: colorScheme.onSurface,
            letterSpacing: -0.3,
          ),
        ),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          controller: _scrollController,
          padding: EdgeInsets.only(top: spacing.m),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Profile Section
              Material(
                color: colorScheme.surface,
                child: InkWell(
                  onTap: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                          builder: (_) => const EditProfilePage()),
                    );
                  },
                  child: Padding(
                    padding: EdgeInsets.all(spacing.l),
                    child: Row(
                      children: [
                        // Circular Avatar
                        Container(
                          width: 64,
                          height: 64,
                          decoration: const BoxDecoration(
                            color: Color(0xFFF2003C),
                            shape: BoxShape.circle,
                          ),
                          alignment: Alignment.center,
                          child: Text(
                            profileInitial,
                            style: const TextStyle(
                              fontSize: 34,
                              fontWeight: FontWeight.bold,
                              fontFamily: 'PlusJakartaSans',
                              color: Colors.white,
                            ),
                          ),
                        ),
                        SizedBox(width: spacing.m),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                displayName,
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w600,
                                  fontFamily: 'PlusJakartaSans',
                                  color: colorScheme.onSurface,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                'View profile',
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                  fontFamily: 'PlusJakartaSans',
                                  color: AppColors.secondary,
                                ),
                              ),
                            ],
                          ),
                        ),
                        Icon(Icons.chevron_right,
                            color: colorScheme.onSurfaceVariant),
                      ],
                    ),
                  ),
                ),
              ),
              SizedBox(height: spacing.m),

              // Account
              _SectionHeader(title: 'Account'),
              _SimpleSettingItem(
                title: 'Manage Subscription',
                onTap: _handleManageSubscription,
              ),

              SizedBox(height: spacing.l),

              // Settings
              _SectionHeader(title: 'Settings'),
              // Disabled until dark mode is fully implemented
              // _SimpleSettingItem(
              //   title: 'Appearance',
              //   onTap: () {
              //     Navigator.of(context).push(
              //       MaterialPageRoute(
              //         builder: (_) => const AppearancePreferencesPage(),
              //       ),
              //     );
              //   },
              // ),
              _SimpleSettingItem(
                title: 'Notifications',
                onTap: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => const NotificationSettingsPage(),
                    ),
                  );
                },
              ),

              SizedBox(height: spacing.l),

              // Support & Sharing Section
              _SectionHeader(title: 'Support & Sharing'),
              _SimpleSettingItem(
                title: 'Help',
                onTap: () => _openHelpLink(context),
              ),
              _SimpleSettingItem(
                title: 'Give Feedback',
                onTap: () => _openDocumentSheet(
                  title: 'Give Feedback',
                  url: 'https://worthify.userjot.com/',
                ),
              ),
              _SimpleSettingItem(
                title: 'Invite Friends',
                onTap: () => _shareApp(context),
              ),
              SizedBox(height: spacing.l),

              // Legal Section
              _SectionHeader(title: 'Legal'),
              _SimpleSettingItem(
                title: 'Privacy Policy',
                onTap: () => _openDocumentSheet(
                  title: 'Privacy Policy',
                  url: 'https://worthify.app/privacy-policy/',
                ),
              ),
              _SimpleSettingItem(
                title: 'Terms of Service',
                onTap: () => _openDocumentSheet(
                  title: 'Terms of Service',
                  url: 'https://worthify.app/terms-of-service/',
                ),
              ),

              SizedBox(height: spacing.l),

              // Safety Section
              _SectionHeader(title: 'Control Panel'),
              _SimpleSettingItem(
                title: 'Logout',
                textColor: AppColors.secondary,
                onTap: _handleLogout,
              ),
              _SimpleSettingItem(
                title: 'Delete Account',
                textColor: AppColors.secondary,
                onTap: _handleDeleteAccount,
              ),

              SizedBox(height: spacing.xl),

              // Version info
              Center(
                child: Text(
                  _versionString,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    color: colorScheme.onSurfaceVariant,
                    fontFamily: 'PlusJakartaSans',
                  ),
                  textAlign: TextAlign.center,
                ),
              ),

              SizedBox(height: spacing.xl),
            ],
          ),
        ),
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String title;

  const _SectionHeader({required this.title});

  @override
  Widget build(BuildContext context) {
    final spacing = context.spacing;
    return Padding(
      padding: EdgeInsets.only(
        left: spacing.l,
        right: spacing.l,
        bottom: spacing.sm,
      ),
      child: Align(
        alignment: Alignment.centerLeft,
        child: Text(
          title,
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
            fontFamily: 'PlusJakartaSans',
          ),
        ),
      ),
    );
  }
}

class _SimpleSettingItem extends StatelessWidget {
  final String title;
  final VoidCallback? onTap;
  final Color? textColor;
  final String? trailingText;

  const _SimpleSettingItem({
    required this.title,
    this.onTap,
    this.textColor,
    this.trailingText,
  });

  @override
  Widget build(BuildContext context) {
    final spacing = context.spacing;
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Material(
      color: colorScheme.surface,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: EdgeInsets.symmetric(
            horizontal: spacing.l,
            vertical: spacing.sm + 4,
          ),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  title,
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w500,
                    color: textColor ?? colorScheme.onSurface,
                    fontFamily: 'PlusJakartaSans',
                  ),
                ),
              ),
              if (trailingText != null)
                Padding(
                  padding: EdgeInsets.only(right: spacing.xs),
                  child: Text(
                    trailingText!,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                      color: colorScheme.onSurfaceVariant,
                      fontFamily: 'PlusJakartaSans',
                    ),
                  ),
                ),
              Icon(
                Icons.chevron_right,
                color: colorScheme.onSurfaceVariant,
                size: 20,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
