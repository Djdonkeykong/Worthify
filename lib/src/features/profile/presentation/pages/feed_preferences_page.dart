import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../../../core/theme/app_colors.dart';
import '../../../../../core/theme/theme_extensions.dart';
import '../../../../shared/widgets/worthify_back_button.dart';
import '../../../auth/domain/providers/auth_provider.dart';
import '../../../../services/onboarding_state_service.dart';
import '../../domain/providers/feed_preference_provider.dart';

enum FeedPreference { men, women, both }

class FeedPreferencesPage extends ConsumerStatefulWidget {
  const FeedPreferencesPage({super.key});

  @override
  ConsumerState<FeedPreferencesPage> createState() =>
      _FeedPreferencesPageState();
}

class _FeedPreferencesPageState
    extends ConsumerState<FeedPreferencesPage> {
  FeedPreference? _selectedPreference;
  bool _isLoading = true;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _loadCurrentPreference();
  }

  Future<void> _loadCurrentPreference() async {
    try {
      final user = ref.read(authServiceProvider).currentUser;
      if (user == null) return;

      final supabase = Supabase.instance.client;
      final response = await supabase
          .from('users')
          .select('preferred_gender_filter')
          .eq('id', user.id)
          .maybeSingle();

      if (response != null && mounted) {
        final filter = response['preferred_gender_filter'] as String?;
        setState(() {
          _selectedPreference = _filterToPreference(filter);
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('[FeedPreferences] Error loading preference: $e');
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  FeedPreference _filterToPreference(String? filter) {
    switch (filter) {
      case 'men':
        return FeedPreference.men;
      case 'women':
        return FeedPreference.women;
      case 'all':
        return FeedPreference.both;
      default:
        return FeedPreference.both;
    }
  }

  String _preferenceToFilter(FeedPreference preference) {
    switch (preference) {
      case FeedPreference.men:
        return 'men';
      case FeedPreference.women:
        return 'women';
      case FeedPreference.both:
        return 'all';
    }
  }

  Future<void> _savePreference(FeedPreference preference) async {
    if (_isSaving) return;

    setState(() => _isSaving = true);

    try {
      final user = ref.read(authServiceProvider).currentUser;
      if (user == null) return;

      final filterValue = _preferenceToFilter(preference);

      await OnboardingStateService().saveUserPreferences(
        userId: user.id,
        preferredGenderFilter: filterValue,
      );

      if (mounted) {
        setState(() {
          _selectedPreference = preference;
          _isSaving = false;
        });

        // Notify home feed to refresh with new preference
        notifyFeedPreferenceChanged(ref);

        ScaffoldMessenger.of(context).clearSnackBars();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Feed preference updated',
              style: context.snackTextStyle(
                merge: const TextStyle(fontFamily: 'PlusJakartaSans'),
              ),
            ),
            duration: const Duration(milliseconds: 2000),
            backgroundColor: Colors.black87,
          ),
        );
      }
    } catch (e) {
      debugPrint('[FeedPreferences] Error saving preference: $e');
      if (mounted) {
        setState(() => _isSaving = false);

        ScaffoldMessenger.of(context).clearSnackBars();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Error updating preference',
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
          'Feed Preferences',
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
          ? const Center(
              child: CircularProgressIndicator(
                color: AppColors.secondary,
              ),
            )
          : SafeArea(
              child: Padding(
                padding: EdgeInsets.fromLTRB(spacing.l, spacing.l, spacing.l, spacing.xl),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SizedBox(height: 4),
                    Text(
                      'Choose what you want to see in your feed',
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
                          label: "Men's Clothing",
                          value: _selectedPreference == FeedPreference.men,
                          onChanged: (val) {
                            HapticFeedback.selectionClick();
                            if (val) _savePreference(FeedPreference.men);
                          },
                        ),
                        const SizedBox(height: 8),
                        _Divider(),
                        const SizedBox(height: 8),
                        _SettingsRow.toggle(
                          label: "Women's Clothing",
                          value: _selectedPreference == FeedPreference.women,
                          onChanged: (val) {
                            HapticFeedback.selectionClick();
                            if (val) _savePreference(FeedPreference.women);
                          },
                        ),
                        const SizedBox(height: 8),
                        _Divider(),
                        const SizedBox(height: 8),
                        _SettingsRow.toggle(
                          label: 'Both',
                          value: _selectedPreference == FeedPreference.both,
                          onChanged: (val) {
                            HapticFeedback.selectionClick();
                            if (val) _savePreference(FeedPreference.both);
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

  const _SettingsCard({required this.children});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
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
  final bool value;
  final ValueChanged<bool> onChanged;

  const _SettingsRow.toggle({
    required this.label,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final textColor = Colors.black;
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
            activeColor: const Color(0xFFF2003C),
            onChanged: onChanged,
          ),
        ],
      ),
    );
  }
}
