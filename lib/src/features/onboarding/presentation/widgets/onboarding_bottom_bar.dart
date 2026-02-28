import 'package:flutter/material.dart';
import '../../../../../core/theme/theme_extensions.dart';

/// A fixed bottom bar for onboarding pages with subtle shadow separation
class OnboardingBottomBar extends StatelessWidget {
  final Widget? primaryButton;
  final Widget? secondaryButton;

  const OnboardingBottomBar({
    super.key,
    this.primaryButton,
    this.secondaryButton,
  });

  @override
  Widget build(BuildContext context) {
    final spacing = context.spacing;

    return Container(
      color: Colors.transparent,
      child: SafeArea(
        top: false,
        minimum: EdgeInsets.only(
          left: spacing.l,
          right: spacing.l,
          bottom: spacing.m,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(height: spacing.m),
            if (primaryButton != null) ...[
              primaryButton!,
              if (secondaryButton != null) SizedBox(height: spacing.m),
            ],
            if (secondaryButton != null) secondaryButton!,
            SizedBox(height: spacing.m),
          ],
        ),
      ),
    );
  }
}
