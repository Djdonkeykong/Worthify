import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/flutter_svg.dart';
import '../../../../services/analytics_service.dart';
import '../mixins/screen_tracking_mixin.dart';
import '../../../../../core/theme/app_colors.dart';
import '../../../../../core/theme/theme_extensions.dart';
import '../../../../../core/constants/worthify-more-and-family_icons.dart';
import '../../../../../core/constants/worthify-people_icons.dart';
import '../../../../../shared/navigation/route_observer.dart';
import '../../../../shared/widgets/worthify_back_button.dart';
import '../widgets/progress_indicator.dart';
import '../widgets/onboarding_bottom_bar.dart';
import 'notification_permission_page.dart';
import '../../../../services/onboarding_state_service.dart';
import '../../../auth/domain/providers/auth_provider.dart';

enum DiscoverySource {
  instagram,
  tiktok,
  facebook,
  youtube,
  google,
  friendOrFamily,
  other
}

final selectedDiscoverySourceProvider =
    StateProvider<DiscoverySource?>((ref) => null);

class DiscoverySourcePage extends ConsumerStatefulWidget {
  const DiscoverySourcePage({super.key});

  @override
  ConsumerState<DiscoverySourcePage> createState() =>
      _DiscoverySourcePageState();
}

class _DiscoverySourcePageState extends ConsumerState<DiscoverySourcePage>
    with TickerProviderStateMixin, RouteAware, ScreenTrackingMixin {
  @override
  String get screenName => 'onboarding_discovery_source';
  late List<AnimationController> _animationControllers;
  late List<Animation<double>> _fadeAnimations;
  late List<Animation<double>> _scaleAnimations;

  bool _isRouteAware = false;

  @override
  void initState() {
    super.initState();
    AnalyticsService().trackOnboardingScreen('onboarding_discovery_source');

    _animationControllers = List.generate(7, (index) {
      return AnimationController(
        duration: const Duration(milliseconds: 400),
        vsync: this,
      );
    });

    _fadeAnimations = _animationControllers.map((controller) {
      return Tween<double>(begin: 0.0, end: 1.0).animate(
        CurvedAnimation(parent: controller, curve: Curves.easeOut),
      );
    }).toList();

    _scaleAnimations = _animationControllers.map((controller) {
      return Tween<double>(begin: 0.8, end: 1.0).animate(
        CurvedAnimation(parent: controller, curve: Curves.easeOutBack),
      );
    }).toList();
  }

  void _startStaggeredAnimation() {
    // Reset all controllers first
    for (var controller in _animationControllers) {
      controller.reset();
    }

    // Then start staggered animation
    for (int i = 0; i < _animationControllers.length; i++) {
      final controller = _animationControllers[i];
      Future.delayed(Duration(milliseconds: i * 100), () {
        if (mounted) {
          controller.forward();
        }
      });
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final route = ModalRoute.of(context);
    if (!_isRouteAware && route is PageRoute) {
      routeObserver.subscribe(this, route);
      _isRouteAware = true;
      if (route.isCurrent) {
        _startStaggeredAnimation();
      }
    }
  }

  @override
  void dispose() {
    if (_isRouteAware) {
      routeObserver.unsubscribe(this);
    }
    for (var controller in _animationControllers) {
      controller.dispose();
    }
    super.dispose();
  }

  @override
  void didPush() {
    _startStaggeredAnimation();
  }

  @override
  void didPopNext() {
    _startStaggeredAnimation();
  }

  @override
  Widget build(BuildContext context) {
    final selectedSource = ref.watch(selectedDiscoverySourceProvider);
    final spacing = context.spacing;
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        elevation: 0,
        scrolledUnderElevation: 0,
        leading: WorthifyBackButton(
          enableHaptics: true,
          backgroundColor: colorScheme.surface,
          iconColor: colorScheme.onSurface,
        ),
        centerTitle: true,
        title: const OnboardingProgressIndicator(
          currentStep: 4,
          totalSteps: 6,
        ),
      ),
      body: Padding(
        padding: EdgeInsets.symmetric(horizontal: spacing.l),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(height: spacing.l),

            // Title
            Text(
              'Where did you hear\nabout us?',
              style: TextStyle(
                fontSize: 34,
                fontFamily: 'PlusJakartaSans',
                letterSpacing: -1.0,
                fontWeight: FontWeight.bold,
                color: colorScheme.onSurface,
                height: 1.3,
              ),
            ),

            SizedBox(height: spacing.l),

            // Discovery Source Options
            Expanded(
              child: ListView.separated(
                padding: EdgeInsets.only(bottom: spacing.l),
                physics: const BouncingScrollPhysics(),
                itemCount: 7,
                separatorBuilder: (_, __) => SizedBox(height: spacing.l),
                itemBuilder: (context, index) {
                  switch (index) {
                    case 0:
                      return AnimatedBuilder(
                        animation: _animationControllers[0],
                        builder: (context, child) {
                          return FadeTransition(
                            opacity: _fadeAnimations[0],
                            child: ScaleTransition(
                              scale: _scaleAnimations[0],
                              child: _DiscoverySourceOption(
                                source: DiscoverySource.instagram,
                                label: 'Instagram',
                                icon: Image.asset('assets/icons/insta.png',
                                    width: 24, height: 24),
                                isSelected:
                                    selectedSource == DiscoverySource.instagram,
                                onTap: () => ref
                                    .read(selectedDiscoverySourceProvider
                                        .notifier)
                                    .state = DiscoverySource.instagram,
                              ),
                            ),
                          );
                        },
                      );
                    case 1:
                      return AnimatedBuilder(
                        animation: _animationControllers[1],
                        builder: (context, child) {
                          return FadeTransition(
                            opacity: _fadeAnimations[1],
                            child: ScaleTransition(
                              scale: _scaleAnimations[1],
                              child: _DiscoverySourceOption(
                                source: DiscoverySource.tiktok,
                                label: 'TikTok',
                                icon: SvgPicture.asset(
                                    'assets/icons/4362958_tiktok_logo_social media_icon.svg',
                                    width: 24,
                                    height: 24),
                                isSelected:
                                    selectedSource == DiscoverySource.tiktok,
                                onTap: () => ref
                                    .read(selectedDiscoverySourceProvider
                                        .notifier)
                                    .state = DiscoverySource.tiktok,
                              ),
                            ),
                          );
                        },
                      );
                    case 2:
                      return AnimatedBuilder(
                        animation: _animationControllers[2],
                        builder: (context, child) {
                          return FadeTransition(
                            opacity: _fadeAnimations[2],
                            child: ScaleTransition(
                              scale: _scaleAnimations[2],
                              child: _DiscoverySourceOption(
                                source: DiscoverySource.facebook,
                                label: 'Facebook',
                                icon: SvgPicture.asset(
                                    'assets/icons/5296499_fb_facebook_facebook logo_icon.svg',
                                    width: 24,
                                    height: 24),
                                isSelected:
                                    selectedSource == DiscoverySource.facebook,
                                onTap: () => ref
                                    .read(selectedDiscoverySourceProvider
                                        .notifier)
                                    .state = DiscoverySource.facebook,
                              ),
                            ),
                          );
                        },
                      );
                    case 3:
                      return AnimatedBuilder(
                        animation: _animationControllers[3],
                        builder: (context, child) {
                          return FadeTransition(
                            opacity: _fadeAnimations[3],
                            child: ScaleTransition(
                              scale: _scaleAnimations[3],
                              child: _DiscoverySourceOption(
                                source: DiscoverySource.youtube,
                                label: 'YouTube',
                                icon: SvgPicture.asset(
                                    'assets/icons/5296521_play_video_vlog_youtube_youtube logo_icon.svg',
                                    width: 24,
                                    height: 24),
                                isSelected:
                                    selectedSource == DiscoverySource.youtube,
                                onTap: () => ref
                                    .read(selectedDiscoverySourceProvider
                                        .notifier)
                                    .state = DiscoverySource.youtube,
                              ),
                            ),
                          );
                        },
                      );
                    case 4:
                      return AnimatedBuilder(
                        animation: _animationControllers[4],
                        builder: (context, child) {
                          return FadeTransition(
                            opacity: _fadeAnimations[4],
                            child: ScaleTransition(
                              scale: _scaleAnimations[4],
                              child: _DiscoverySourceOption(
                                source: DiscoverySource.google,
                                label: 'Google',
                                icon: SvgPicture.asset(
                                    'assets/icons/4975303_search_web_internet_google search_search engine_icon.svg',
                                    width: 24,
                                    height: 24),
                                isSelected:
                                    selectedSource == DiscoverySource.google,
                                onTap: () => ref
                                    .read(selectedDiscoverySourceProvider
                                        .notifier)
                                    .state = DiscoverySource.google,
                              ),
                            ),
                          );
                        },
                      );
                    case 5:
                      return AnimatedBuilder(
                        animation: _animationControllers[5],
                        builder: (context, child) {
                          return FadeTransition(
                            opacity: _fadeAnimations[5],
                            child: ScaleTransition(
                              scale: _scaleAnimations[5],
                              child: _DiscoverySourceOption(
                                source: DiscoverySource.friendOrFamily,
                                label: 'Friend or family',
                                icon: Icon(Worthify_people.biPeopleFill,
                                    size: 24,
                                    color: colorScheme.onSurface),
                                isSelected: selectedSource ==
                                    DiscoverySource.friendOrFamily,
                                onTap: () => ref
                                    .read(selectedDiscoverySourceProvider
                                        .notifier)
                                    .state = DiscoverySource.friendOrFamily,
                              ),
                            ),
                          );
                        },
                      );
                    case 6:
                    default:
                      return AnimatedBuilder(
                        animation: _animationControllers[6],
                        builder: (context, child) {
                          return FadeTransition(
                            opacity: _fadeAnimations[6],
                            child: ScaleTransition(
                              scale: _scaleAnimations[6],
                              child: _DiscoverySourceOption(
                                source: DiscoverySource.other,
                                label: 'Other',
                                icon: Transform.translate(
                                  offset: const Offset(-2, -1),
                                  child: Icon(
                                      Worthify_more_and_family.icRoundLayers,
                                      size: 28,
                                      color: colorScheme.onSurface),
                                ),
                                isSelected:
                                    selectedSource == DiscoverySource.other,
                                onTap: () => ref
                                    .read(selectedDiscoverySourceProvider
                                        .notifier)
                                    .state = DiscoverySource.other,
                              ),
                            ),
                          );
                        },
                      );
                  }
                },
              ),
            ),
          ],
        ),
      ),
      bottomNavigationBar: OnboardingBottomBar(
        primaryButton: SizedBox(
          width: double.infinity,
          height: 56,
          child: ElevatedButton(
            onPressed: selectedSource != null
                ? () async {
                    HapticFeedback.mediumImpact();

                    final user = ref.read(authServiceProvider).currentUser;
                    if (user != null) {
                      unawaited(OnboardingStateService().updateCheckpoint(
                        user.id,
                        OnboardingCheckpoint.discovery,
                      ));
                    }

                    if (!context.mounted) return;
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (context) =>
                            const NotificationPermissionPage(),
                      ),
                    );
                  }
                : null,
            style: ElevatedButton.styleFrom(
              backgroundColor: selectedSource != null
                  ? AppColors.secondary
                  : colorScheme.outlineVariant,
              foregroundColor: Colors.white,
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(28),
              ),
            ),
            child: Text(
              'Continue',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                fontFamily: 'PlusJakartaSans',
                letterSpacing: -0.2,
                color: selectedSource != null
                    ? Colors.white
                    : colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _DiscoverySourceOption extends StatelessWidget {
  final DiscoverySource source;
  final String label;
  final Widget icon;
  final bool isSelected;
  final VoidCallback onTap;

  const _DiscoverySourceOption({
    required this.source,
    required this.label,
    required this.icon,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return GestureDetector(
      onTap: () {
        HapticFeedback.mediumImpact();
        onTap();
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        width: double.infinity,
        height: 56,
        decoration: BoxDecoration(
          color: isSelected
              ? AppColors.secondary
              : colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: colorScheme.surface,
                  shape: BoxShape.circle,
                ),
                child: Center(
                  child: SizedBox(
                    width: 24,
                    height: 24,
                    child: icon,
                  ),
                ),
              ),
              const SizedBox(width: 16),
              Text(
                label,
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: isSelected
                      ? Colors.white
                      : colorScheme.onSurface,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// Custom brand icons
class _InstagramIcon extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      width: 24,
      height: 24,
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFFE1306C), Color(0xFFFD1D1D), Color(0xFFF77737)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(6),
      ),
      child: const Icon(Icons.camera_alt, color: Colors.white, size: 14),
    );
  }
}

class _FacebookIcon extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      width: 24,
      height: 24,
      decoration: BoxDecoration(
        color: const Color(0xFF1877F2),
        borderRadius: BorderRadius.circular(6),
      ),
      child: const Center(
        child: Text(
          'f',
          style: TextStyle(
            color: Colors.white,
            fontSize: 16,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
    );
  }
}

class _TikTokIcon extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      width: 24,
      height: 24,
      decoration: BoxDecoration(
        color: Colors.black,
        borderRadius: BorderRadius.circular(6),
      ),
      child: const Center(
        child: Text(
          '♪',
          style: TextStyle(
            color: Colors.white,
            fontSize: 14,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
    );
  }
}

class _YouTubeIcon extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      width: 24,
      height: 24,
      decoration: BoxDecoration(
        color: const Color(0xFFFF0000),
        borderRadius: BorderRadius.circular(6),
      ),
      child: const Icon(Icons.play_arrow, color: Colors.white, size: 16),
    );
  }
}

class _GoogleIcon extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      width: 24,
      height: 24,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: Colors.grey.shade300),
      ),
      child: const Center(
        child: Text(
          'G',
          style: TextStyle(
            color: Color(0xFF4285F4),
            fontSize: 14,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
    );
  }
}
