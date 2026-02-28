import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../../../core/theme/app_colors.dart';
import '../../../../../core/theme/theme_extensions.dart';
import '../../../../shared/widgets/worthify_back_button.dart';

class ContactSupportPage extends StatelessWidget {
  const ContactSupportPage({super.key});

  Future<void> _sendEmail() async {
    final Uri emailUri = Uri(
      scheme: 'mailto',
      path: 'support@worthify.com',
      query: 'subject=Worthify Support Request',
    );

    if (await canLaunchUrl(emailUri)) {
      await launchUrl(emailUri);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final spacing = context.spacing;

    return Scaffold(
      backgroundColor: colorScheme.background,
      appBar: AppBar(
        backgroundColor: colorScheme.surface,
        elevation: 0,
        leadingWidth: 56,
        leading: WorthifyBackButton(
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Text(
          'Contact Support',
          style: TextStyle(
            color: colorScheme.onSurface,
            fontFamily: 'PlusJakartaSans',
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
      body: Padding(
        padding: EdgeInsets.all(spacing.l),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Get in Touch',
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
                fontFamily: 'PlusJakartaSans',
                color: colorScheme.onSurface,
              ),
            ),
            SizedBox(height: spacing.m),
            Text(
              'Have a question or need assistance? We\'re here to help!',
              style: TextStyle(
                fontSize: 16,
                color: colorScheme.onSurfaceVariant,
                fontFamily: 'PlusJakartaSans',
                height: 1.5,
              ),
            ),
            SizedBox(height: spacing.xl),
            Container(
              padding: EdgeInsets.all(spacing.l),
              decoration: BoxDecoration(
                color: colorScheme.surface,
                borderRadius: BorderRadius.circular(context.radius.medium),
                border: Border.all(color: colorScheme.outlineVariant),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(
                        Icons.email_outlined,
                        color: AppColors.secondary,
                        size: 24,
                      ),
                      SizedBox(width: spacing.m),
                      Text(
                        'Email Support',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w600,
                          fontFamily: 'PlusJakartaSans',
                          color: colorScheme.onSurface,
                        ),
                      ),
                    ],
                  ),
                  SizedBox(height: spacing.m),
                  Text(
                    'support@worthify.com',
                    style: TextStyle(
                      fontSize: 16,
                      fontFamily: 'PlusJakartaSans',
                      color: colorScheme.onSurface,
                    ),
                  ),
                  SizedBox(height: spacing.sm),
                  Text(
                  'We typically respond within 24 hours',
                  style: TextStyle(
                    fontSize: 14,
                    color: colorScheme.onSurfaceVariant,
                    fontFamily: 'PlusJakartaSans',
                  ),
                ),
                ],
              ),
            ),
            SizedBox(height: spacing.l),
            GestureDetector(
              onTap: _sendEmail,
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 16),
                decoration: BoxDecoration(
                  color: AppColors.secondary,
                  borderRadius: BorderRadius.circular(28),
                ),
                child: const Center(
                  child: Text(
                    'Send Email',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      fontFamily: 'PlusJakartaSans',
                      color: Colors.white,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
