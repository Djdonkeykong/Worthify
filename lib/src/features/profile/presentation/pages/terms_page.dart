import 'package:flutter/material.dart';
import '../../../../../core/theme/theme_extensions.dart';
import '../../../../shared/widgets/worthify_back_button.dart';

class TermsPage extends StatelessWidget {
  const TermsPage({super.key});

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
          'Terms and Conditions',
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
              _TermsSection(
                title: '1. Acceptance of Terms',
                content:
                    'By accessing and using Worthify, you accept and agree to be bound by the terms and conditions of this agreement.',
              ),
              SizedBox(height: spacing.l),
              _TermsSection(
                title: '2. Use License',
                content:
                    'Permission is granted to temporarily use Worthify for personal, non-commercial purposes. This is the grant of a license, not a transfer of title.',
              ),
              SizedBox(height: spacing.l),
              _TermsSection(
                title: '3. User Accounts',
                content:
                    'You are responsible for maintaining the confidentiality of your account and password. You agree to accept responsibility for all activities that occur under your account.',
              ),
              SizedBox(height: spacing.l),
              _TermsSection(
                title: '4. Content',
                content:
                    'Our service allows you to post, link, store, share and otherwise make available certain information. You are responsible for the content that you post on or through the service.',
              ),
              SizedBox(height: spacing.l),
              _TermsSection(
                title: '5. Prohibited Uses',
                content:
                    'You may not use our service for any illegal or unauthorized purpose, to violate any laws, or to harm others in any way.',
              ),
              SizedBox(height: spacing.l),
              _TermsSection(
                title: '6. Limitation of Liability',
                content:
                    'Worthify shall not be liable for any indirect, incidental, special, consequential or punitive damages resulting from your use of or inability to use the service.',
              ),
              SizedBox(height: spacing.xl),
            ],
          ),
        ),
      ),
    );
  }
}

class _TermsSection extends StatelessWidget {
  final String title;
  final String content;

  const _TermsSection({
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
