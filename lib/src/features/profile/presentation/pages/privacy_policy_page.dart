import 'package:flutter/material.dart';
import '../../../../../core/theme/theme_extensions.dart';
import '../../../../shared/widgets/worthify_back_button.dart';

class PrivacyPolicyPage extends StatelessWidget {
  const PrivacyPolicyPage({super.key});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final spacing = context.spacing;

    return Scaffold(
      backgroundColor: colorScheme.background,
      appBar: AppBar(
        backgroundColor: colorScheme.background,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: true,
        title: Text(
          'Privacy Policy',
          style: TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.bold,
            fontFamily: 'PlusJakartaSans',
            color: colorScheme.onSurface,
            letterSpacing: -0.3,
          ),
        ),
        leadingWidth: 56,
        leading: WorthifyBackButton(
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: EdgeInsets.all(spacing.l),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(height: spacing.m),
              Text(
                'Last updated: ${DateTime.now().year}',
                style: TextStyle(
                  fontSize: 14,
                  color: colorScheme.onSurfaceVariant,
                  fontFamily: 'PlusJakartaSans',
                ),
              ),
              SizedBox(height: spacing.xl),
              _PolicySection(
                title: '1. Information We Collect',
                content:
                    'We collect information you provide directly to us, including when you create an account, use our services, or communicate with us. This may include your name, email address, and preferences.',
              ),
              SizedBox(height: spacing.l),
              _PolicySection(
                title: '2. How We Use Your Information',
                content:
                    'We use the information we collect to provide, maintain, and improve our services, to process your transactions, and to communicate with you.',
              ),
              SizedBox(height: spacing.l),
              _PolicySection(
                title: '3. Information Sharing',
                content:
                    'We do not sell, trade, or otherwise transfer your personal information to third parties without your consent, except as described in this policy.',
              ),
              SizedBox(height: spacing.l),
              _PolicySection(
                title: '4. Data Security',
                content:
                    'We implement appropriate security measures to protect your personal information against unauthorized access, alteration, disclosure, or destruction.',
              ),
              SizedBox(height: spacing.l),
              _PolicySection(
                title: '5. Your Rights',
                content:
                    'You have the right to access, update, or delete your personal information at any time. You can also opt-out of certain data collection practices.',
              ),
              SizedBox(height: spacing.xl),
            ],
          ),
        ),
      ),
    );
  }
}

class _PolicySection extends StatelessWidget {
  final String title;
  final String content;

  const _PolicySection({
    required this.title,
    required this.content,
  });

  @override
  Widget build(BuildContext context) {
    final spacing = context.spacing;
    final colorScheme = Theme.of(context).colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w600,
            fontFamily: 'PlusJakartaSans',
            color: colorScheme.onSurface,
          ),
        ),
        SizedBox(height: spacing.sm),
        Text(
          content,
          style: TextStyle(
            fontSize: 15,
            color: colorScheme.onSurfaceVariant,
            fontFamily: 'PlusJakartaSans',
            height: 1.6,
          ),
        ),
      ],
    );
  }
}
