import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../../core/theme/theme_extensions.dart';
import '../widgets/progress_indicator.dart';
import '../widgets/onboarding_bottom_bar.dart';
import '../../../../shared/widgets/worthify_back_button.dart';
import '../../../../services/analytics_service.dart';
import '../../../../services/onboarding_state_service.dart';
import '../../../auth/domain/providers/auth_provider.dart';

class AwesomeIntroPage extends ConsumerStatefulWidget {
  const AwesomeIntroPage({super.key});

  @override
  ConsumerState<AwesomeIntroPage> createState() => _AwesomeIntroPageState();
}

class _AwesomeIntroPageState extends ConsumerState<AwesomeIntroPage> {
  @override
  void initState() {
    super.initState();
    AnalyticsService().trackOnboardingScreen('onboarding_share_your_style');
  }

  @override
  Widget build(BuildContext context) {
    final spacing = context.spacing;
    final colorScheme = Theme.of(context).colorScheme;
    const double shareImageAspectRatio = 939 / 1110;

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
          currentStep: 2,
          totalSteps: 4,
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
              'Share your style,\nfind the look',
              textAlign: TextAlign.start,
              style: TextStyle(
                fontSize: 34,
                fontFamily: 'PlusJakartaSans',
                letterSpacing: -1.0,
                fontWeight: FontWeight.bold,
                color: colorScheme.onSurface,
                height: 1.3,
              ),
            ),

            SizedBox(height: spacing.xl * 2),

            // Phone illustration
            Expanded(
              flex: 3,
              child: _ShareImageFrame(
                assetPath: 'assets/images/social_media_share_mobile_screen.png',
                maxWidth: 420,
                aspectRatio: shareImageAspectRatio,
              ),
            ),

            SizedBox(height: spacing.xl),

            // Description text
            Center(
              child: Text(
                'Share fashion images from Instagram, Pinterest,\nor any app to find similar styles and products!',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 16,
                  color: colorScheme.onSurfaceVariant,
                  fontWeight: FontWeight.w500,
                  fontFamily: 'PlusJakartaSans',
                  letterSpacing: -0.3,
                ),
              ),
            ),

            SizedBox(height: spacing.l),
          ],
        ),
      ),
      bottomNavigationBar: OnboardingBottomBar(
        primaryButton: SizedBox(
          width: double.infinity,
          height: 56,
          child: ElevatedButton(
            onPressed: () async {
              HapticFeedback.mediumImpact();

              final user = ref.read(authServiceProvider).currentUser;
              if (user != null) {
                unawaited(OnboardingStateService().updateCheckpoint(
                  user.id,
                  OnboardingCheckpoint.tutorial,
                ));
              }

              if (!context.mounted) return;
              Navigator.of(context).pop();
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFf2003c),
              foregroundColor: Colors.white,
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(28),
              ),
            ),
            child: const Text(
              'Show me how',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                fontFamily: 'PlusJakartaSans',
                letterSpacing: -0.2,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ShareImageFrame extends StatelessWidget {
  const _ShareImageFrame({
    required this.assetPath,
    required this.maxWidth,
    required this.aspectRatio,
  });

  final String assetPath;
  final double maxWidth;
  final double aspectRatio;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final double availableWidth = constraints.maxWidth * 0.97;
        final double width = math.min(maxWidth, availableWidth);
        final double height = width / aspectRatio;
        final double cappedHeight = math.min(height, constraints.maxHeight);
        final double cappedWidth = cappedHeight * aspectRatio;

        return Center(
          child: SizedBox(
            width: cappedWidth,
            height: cappedHeight,
            child: Image.asset(
              assetPath,
              fit: BoxFit.contain,
              gaplessPlayback: true,
            ),
          ),
        );
      },
    );
  }
}
