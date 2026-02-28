import 'package:flutter/foundation.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import '../../../services/superwall_service.dart';
import '../../../services/credit_service.dart';

/// Initialize Superwall and credit system
/// Call this in main.dart before runApp()
Future<void> initializePaywallSystem({String? userId}) async {
  try {
    debugPrint('Initializing paywall system...');

    // SECURITY: Get API key from environment variables
    final apiKey = dotenv.env['SUPERWALL_API_KEY'];
    if (apiKey == null || apiKey.isEmpty) {
      throw Exception(
        'SUPERWALL_API_KEY not found in environment variables. '
        'Please ensure .env file is properly configured.',
      );
    }

    // Initialize Superwall
    await SuperwallService().initialize(
      apiKey: apiKey,
      userId: userId,
    );

    // Initialize credit service (will load initial balance)
    await CreditService().getCreditBalance();

    debugPrint('Paywall system initialized successfully');
  } catch (e) {
    debugPrint('Error initializing paywall system: $e');
    // Don't throw - allow app to continue even if initialization fails
    // Users can still use the app, purchases just won't work until they restart
  }
}

/// Initialize paywall system with user authentication
/// Call this after user logs in/signs up
Future<void> initializePaywallWithUser(String userId) async {
  try {
    debugPrint('Initializing paywall for user: $userId');

    // Identify user in Superwall
    await SuperwallService().identify(userId);

    // Refresh credit balance for this user
    CreditService().clearCache();
    await CreditService().getCreditBalance();

    debugPrint('Paywall initialized for user successfully');
  } catch (e) {
    debugPrint('Error initializing paywall for user: $e');
  }
}

/// Clean up paywall system on logout
Future<void> cleanupPaywallOnLogout() async {
  try {
    debugPrint('Cleaning up paywall on logout...');

    // Reset Superwall identity
    await SuperwallService().reset();

    // Clear credit cache
    CreditService().clearCache();

    debugPrint('Paywall cleanup completed');
  } catch (e) {
    debugPrint('Error cleaning up paywall: $e');
  }
}
