import 'dart:async';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:sign_in_with_apple/sign_in_with_apple.dart';
import 'package:flutter/services.dart';
import '../../../../services/subscription_sync_service.dart';
import '../../../../services/credit_service.dart';
import '../../../../services/analytics_service.dart';

class AuthService {
  final _supabase = Supabase.instance.client;
  static const _authChannel = MethodChannel('worthify/auth');
  StreamSubscription<AuthState>? _authSubscription;
  static const _friendlyGenericError =
      'Could not complete sign in. Please try again.';
  static const List<String> reviewerEmails = <String>[
    'appstore@worthify.app',
    'googleplay@worthify.app',
  ];
  static const Map<String, List<String>> _reviewerPasswordCandidates =
      <String, List<String>>{
    'appstore@worthify.app': <String>[
      'WorthifyReview2026!',
      '123456',
    ],
    'googleplay@worthify.app': <String>[
      '123456',
      'WorthifyReview2026!',
    ],
  };
  static final Exception authCancelledException =
      Exception('__auth_cancelled__');

  User? get currentUser => _supabase.auth.currentUser;
  bool get isAuthenticated => currentUser != null;

  Stream<AuthState> get authStateChanges => _supabase.auth.onAuthStateChange;

  // Initialize and sync current auth state to share extension
  Future<void> syncAuthState() async {
    print('[AuthService] syncAuthState called');
    print('[AuthService] isAuthenticated: $isAuthenticated');
    print('[AuthService] currentUser: ${currentUser?.id ?? "null"}');

    User? initialUser;
    if (isAuthenticated) {
      initialUser = await _waitForAuthenticatedUser(
        context: 'initial sync',
        timeout: const Duration(seconds: 2),
      );

      if (initialUser == null) {
        print(
            '[Auth] WARNING: Unable to resolve user for initial sync - deferring until auth events fire');
      }
    }

    await _updateAuthFlag(
      isAuthenticated,
      userId: initialUser?.id,
    );

    // Also listen for auth state changes and sync automatically
    _authSubscription?.cancel();
    _authSubscription = _supabase.auth.onAuthStateChange.listen(
      (authState) {
        print('[Auth] Auth state changed: ${authState.event}');
        print(
            '[Auth] Event session: ${authState.session != null ? "exists" : "null"}');
        print('[Auth] Event user: ${authState.session?.user.id ?? "null"}');
        print(
            '[Auth] Current user (at event time): ${currentUser?.id ?? "null"}');

        // IMPORTANT: Only sync if we have a valid user, or if we're explicitly signing out
        // This prevents race conditions where session exists but user is momentarily null
        final hasSession = authState.session != null;
        final hasUser = authState.session?.user != null;

        if (hasSession && hasUser) {
          // Valid authenticated state - sync it
          final userId = authState.session!.user.id;
          print('[Auth] Valid auth state - syncing userId: $userId');
          _updateAuthFlag(true, userId: userId);
        } else if (!hasSession) {
          // Explicitly signed out - clear auth
          print('[Auth] No session - clearing auth state');
          _updateAuthFlag(false);
        } else {
          // Session exists but no user - this is a race condition, skip sync
          print(
              '[Auth] WARNING: Session exists but no user - skipping sync to prevent clearing userId');
        }
      },
      onError: (error) {
        print('[Auth] Auth state listener error: $error');
        // Handle refresh token errors gracefully
        if (error.toString().contains('refresh_token_not_found') ||
            error.toString().contains('Invalid Refresh Token')) {
          print('[Auth] Refresh token error detected - clearing auth state');
          _updateAuthFlag(false);
        }
      },
    );

    print('[AuthService] Auth listener set up');
  }

  void dispose() {
    _authSubscription?.cancel();
  }

  // Track if this is the first call (to add delay for Flutter engine init)
  static bool _firstAuthFlagCall = true;

  // Update the authentication flag and user ID for share extension via method channel
  Future<void> _updateAuthFlag(
    bool isAuthenticated, {
    String? userId,
  }) async {
    try {
      // On first call, add small delay to ensure Flutter engine is ready
      if (_firstAuthFlagCall) {
        await Future.delayed(const Duration(milliseconds: 500));
        _firstAuthFlagCall = false;
      }

      String? effectiveUserId = userId;
      bool hasActiveSubscription = false;
      int availableCredits = 0;

      if (isAuthenticated) {
        effectiveUserId ??= currentUser?.id;

        if (effectiveUserId == null) {
          print(
              '[Auth] INFO: Authenticated but userId not yet available - waiting briefly before syncing');
          final resolvedUser = await _waitForAuthenticatedUser(
            context: 'authenticated sync',
            timeout: const Duration(seconds: 2),
          );
          effectiveUserId = resolvedUser?.id;
        }

        if (effectiveUserId == null) {
          print(
              '[Auth] WARNING: Skipping auth sync - userId still null after waiting');
          return;
        }

        // Fetch subscription status and credit balance from database
        try {
          final userResponse = await _supabase
              .from('users')
              .select('subscription_status, is_trial, paid_credits_remaining')
              .eq('id', effectiveUserId)
              .maybeSingle()
              .timeout(const Duration(seconds: 5));

          final subscriptionStatus =
              userResponse?['subscription_status'] ?? 'free';
          final isTrial = userResponse?['is_trial'] == true;
          hasActiveSubscription = subscriptionStatus == 'active' || isTrial;

          // Get available credits
          final paidCredits = userResponse?['paid_credits_remaining'] ?? 0;
          availableCredits = paidCredits;

          print('[Auth]   - subscription_status: $subscriptionStatus');
          print('[Auth]   - is_trial: $isTrial');
          print('[Auth]   - hasActiveSubscription: $hasActiveSubscription');
          print('[Auth]   - paid_credits_remaining: $paidCredits');
          print('[Auth]   - availableCredits: $availableCredits');
        } catch (e) {
          print(
              '[Auth] WARNING: Failed to fetch subscription and credit status: $e');
          // Continue with hasActiveSubscription = false and availableCredits = 0
        }
      }

      print('[Auth] Calling setAuthFlag method channel...');
      print('[Auth]   - isAuthenticated: $isAuthenticated');
      print('[Auth]   - userId: $effectiveUserId');
      print('[Auth]   - hasActiveSubscription: $hasActiveSubscription');
      print('[Auth]   - availableCredits: $availableCredits');
      final accessToken = _supabase.auth.currentSession?.accessToken;
      print('[Auth]   - hasAccessToken: ${accessToken != null && accessToken.isNotEmpty}');

      // IMPORTANT: Always send the current state, even if null
      // This ensures old user_id values are cleared from UserDefaults
      final result = await _authChannel.invokeMethod('setAuthFlag', {
        'isAuthenticated': isAuthenticated,
        'userId':
            effectiveUserId, // Will be null if not authenticated, clearing old values
        'hasActiveSubscription': hasActiveSubscription,
        'availableCredits': availableCredits,
        'accessToken': accessToken,
      });

      print('[Auth] Method channel call completed, result: $result');

      if (isAuthenticated && effectiveUserId != null) {
        unawaited(AnalyticsService().identifyUser(
          userId: effectiveUserId,
          userProperties: {
            'has_active_subscription': hasActiveSubscription,
            'available_credits': availableCredits,
          },
        ));
      } else if (!isAuthenticated) {
        unawaited(AnalyticsService().reset());
      }

      if (isAuthenticated && effectiveUserId != null) {
        print(
            '[Auth] Synced to share extension - authenticated with userId: $effectiveUserId, subscription: $hasActiveSubscription, credits: $availableCredits');
      } else {
        print(
            '[Auth] Synced to share extension - NOT authenticated, cleared user_id, subscription, and credits');
      }
    } catch (e) {
      print('[Auth] ERROR calling method channel: $e');
      print('[Auth] Stack trace: ${StackTrace.current}');
    }
  }

  Future<AuthResponse> signInWithGoogle() async {
    try {
      final googleSignIn = GoogleSignIn.instance;

      // Initialize with server client ID
      await googleSignIn.initialize(
        clientId:
            '134752292541-4289b71rova6eldn9f67qom4u2qc5onp.apps.googleusercontent.com',
        serverClientId:
            '134752292541-hekkkdi2mbl0jrdsct0l2n3hjm2sckmh.apps.googleusercontent.com',
      );

      // Authenticate
      final account = await googleSignIn.authenticate();
      if (account == null) {
        throw authCancelledException;
      }

      // Get ID token
      final auth = await account.authentication;
      final idToken = auth.idToken;

      if (idToken == null) {
        throw Exception(_friendlyGenericError);
      }

      final response = await _supabase.auth.signInWithIdToken(
        provider: OAuthProvider.google,
        idToken: idToken,
      );

      // Update auth flag for share extension
      await _updateAuthFlag(
        true,
        userId: response.user?.id,
      );

      return response;
    } catch (e) {
      print('Google sign in error: $e');
      if (e == authCancelledException) rethrow;

      // Check if user cancelled the sign-in
      final errorString = e.toString().toLowerCase();
      if (errorString.contains('cancel') ||
          errorString
              .contains('12501') || // Google's user cancellation error code
          errorString.contains('user_cancelled') ||
          errorString.contains('sign_in_cancelled')) {
        throw authCancelledException;
      }

      throw Exception(_friendlyGenericError);
    }
  }

  Future<AuthResponse> signInWithApple() async {
    try {
      final credential = await SignInWithApple.getAppleIDCredential(
        scopes: [
          AppleIDAuthorizationScopes.email,
          AppleIDAuthorizationScopes.fullName,
        ],
      );

      final idToken = credential.identityToken;
      if (idToken == null) {
        throw Exception(_friendlyGenericError);
      }

      final response = await _supabase.auth.signInWithIdToken(
        provider: OAuthProvider.apple,
        idToken: idToken,
        nonce: credential.state,
      );

      // Update auth flag for share extension
      await _updateAuthFlag(
        true,
        userId: response.user?.id,
      );

      return response;
    } catch (e) {
      print('Apple sign in error: $e');
      if (e == authCancelledException) rethrow;

      // Check if user cancelled the sign-in
      if (e is SignInWithAppleAuthorizationException) {
        // User cancelled or authorization failed
        throw authCancelledException;
      }

      final errorString = e.toString().toLowerCase();
      if (errorString.contains('cancel') ||
          errorString.contains('1001') || // Apple's cancellation error code
          errorString.contains('user_cancelled')) {
        throw authCancelledException;
      }

      throw Exception(_friendlyGenericError);
    }
  }

  Future<AuthResponse> signInAnonymously() async {
    try {
      final response = await _supabase.auth.signInAnonymously();

      // Update auth flag for share extension
      await _updateAuthFlag(
        true,
        userId: response.user?.id,
      );

      return response;
    } catch (e) {
      print('Anonymous sign in error: $e');
      rethrow;
    }
  }

  Future<void> signOut() async {
    try {
      await _supabase.auth.signOut();

      // Clear auth flag for share extension
      await _updateAuthFlag(false);

      // SECURITY: Clear sensitive credit data on logout
      await CreditService().clearOnLogout();
    } catch (e) {
      print('Sign out error: $e');
      rethrow;
    }
  }

  Future<void> deleteAccount() async {
    try {
      final user = currentUser;
      if (user == null) {
        throw Exception('No user found to delete');
      }

      print('[Auth] Deleting account for user: ${user.id}');

      // Reset RevenueCat and Superwall identities
      try {
        await SubscriptionSyncService().resetOnLogout();
        print('[Auth] RevenueCat and Superwall identities reset');
      } catch (e) {
        print('[Auth] Error resetting RevenueCat/Superwall: $e');
        // Continue with deletion even if this fails
      }

      // Delete user from auth.users (using database function with admin privileges)
      // This will cascade delete from public.users and all related tables
      await _supabase.rpc('delete_user_account');
      print('[Auth] User deleted from database');

      // Sign out to clear session and auth state
      await signOut();
      print('[Auth] Account deletion complete');
    } catch (e) {
      print('[Auth] Delete account error: $e');
      rethrow;
    }
  }

  Future<UserResponse> updateUserMetadata(Map<String, dynamic> metadata) async {
    try {
      final response = await _supabase.auth.updateUser(
        UserAttributes(
          data: metadata,
        ),
      );

      // Also update the dedicated username column in the users table if username is being updated
      if (metadata.containsKey('username') && currentUser != null) {
        final username = metadata['username'] as String?;
        try {
          await _supabase
              .from('users')
              .update({'username': username}).eq('id', currentUser!.id);
          print('[Auth] Updated username column in users table: $username');
        } catch (e) {
          print('[Auth] Error updating username column: $e');
          // Don't rethrow - metadata update succeeded, this is supplementary
        }
      }

      return response;
    } catch (e) {
      print('Update user metadata error: $e');
      rethrow;
    }
  }

  Future<UserResponse> updateEmail(String newEmail) async {
    try {
      final response = await _supabase.auth.updateUser(
        UserAttributes(
          email: newEmail,
        ),
      );
      return response;
    } catch (e) {
      print('Update email error: $e');
      rethrow;
    }
  }

  Future<void> signInWithOtp(String email) async {
    try {
      // Test/Demo mode for App Store/Google Play reviewers
      // Skip OTP email send for the test accounts
      final normalizedEmail = email.trim().toLowerCase();
      if (reviewerEmails.contains(normalizedEmail)) {
        print('[Auth] Test account detected - skipping OTP email send');
        // Return success without sending email
        // The actual authentication will happen in verifyOtp with hardcoded token '123456'
        return;
      }

      await _supabase.auth.signInWithOtp(
        email: email,
        emailRedirectTo: null,
        shouldCreateUser: false,
      );
    } catch (e) {
      print('OTP sign in error: $e');

      // Show more specific error messages based on the error type
      final errorString = e.toString().toLowerCase();
      if (errorString.contains('user not found') ||
          errorString.contains('email not confirmed') ||
          errorString.contains('signup')) {
        throw Exception(
            'No existing account was found for this email. Please use an account you already created.');
      }
      if (errorString.contains('invalid') || errorString.contains('email')) {
        throw Exception(
            'This email address cannot be used. Please try a different email.');
      } else if (errorString.contains('rate') ||
          errorString.contains('too many')) {
        throw Exception(
            'Too many attempts. Please wait a minute and try again.');
      }

      throw Exception('Could not send the code. Please try again.');
    }
  }

  Future<AuthResponse> verifyOtp({
    required String email,
    required String token,
  }) async {
    try {
      // Test/Demo mode for App Store/Google Play reviewers
      // Accept hardcoded OTP for the reviewer test accounts
      final normalizedEmail = email.trim().toLowerCase();
      if (reviewerEmails.contains(normalizedEmail) && token == '123456') {
        print('[Auth] Test account detected - using demo OTP bypass');

        final passwordCandidates =
            _reviewerPasswordCandidates[normalizedEmail] ?? const <String>[];
        Object? lastError;
        AuthResponse? response;

        // Sign in with password for the reviewer test account.
        // This allows reviewers to use a fixed OTP code instead of checking email.
        for (final password in passwordCandidates) {
          try {
            response = await _supabase.auth.signInWithPassword(
              email: normalizedEmail,
              password: password,
            );
            if (response.user != null) {
              break;
            }
          } catch (e) {
            lastError = e;
          }
        }

        if (response == null || response.user == null) {
          throw Exception(
            'Reviewer login failed for $normalizedEmail. '
            'Ensure the Supabase password matches one of the configured reviewer credentials. '
            'Last error: $lastError',
          );
        }

        // Update auth flag for share extension
        await _updateAuthFlag(
          true,
          userId: response.user?.id,
        );

        return response;
      }

      // Normal OTP verification for all other users
      final response = await _supabase.auth.verifyOTP(
        email: email,
        token: token,
        type: OtpType.email,
      );

      // Update auth flag for share extension
      await _updateAuthFlag(
        true,
        userId: response.user?.id,
      );

      return response;
    } catch (e) {
      print('OTP verification error: $e');
      rethrow;
    }
  }

  Future<User?> _waitForAuthenticatedUser({
    required String context,
    required Duration timeout,
  }) async {
    if (!isAuthenticated) {
      print('[Auth] INFO: Skipping user wait for $context - not authenticated');
      return null;
    }

    final stopwatch = Stopwatch()..start();
    const pollInterval = Duration(milliseconds: 100);

    while (stopwatch.elapsed < timeout) {
      final user = _supabase.auth.currentUser;
      if (user != null) {
        return user;
      }
      await Future.delayed(pollInterval);
    }

    try {
      print(
          '[Auth] INFO: Polling timed out for $context - attempting direct user fetch');
      final response = await _supabase.auth.getUser();
      return response.user;
    } catch (e) {
      print('[Auth] WARNING: Failed to fetch user for $context: $e');
      return null;
    }
  }
}
