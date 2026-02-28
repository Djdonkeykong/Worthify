import 'package:path_provider/path_provider.dart';
import 'package:path_provider_foundation/path_provider_foundation.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:receive_sharing_intent/receive_sharing_intent.dart';
import 'package:image_picker/image_picker.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'dart:async';
import 'core/constants/app_constants.dart';
import 'core/theme/app_theme.dart';
import 'core/theme/app_colors.dart';
import 'core/theme/theme_mode_provider.dart';
import 'shared/navigation/main_navigation.dart';
import 'shared/navigation/route_observer.dart';
import 'src/features/home/domain/providers/image_provider.dart';
import 'src/features/home/domain/providers/pending_share_provider.dart';
import 'src/features/splash/presentation/pages/splash_page.dart';
import 'src/services/instagram_service.dart';
import 'src/shared/services/video_preloader.dart';
import 'src/shared/services/share_import_status.dart';
import 'src/services/link_scraper_service.dart';
import 'src/services/share_extension_config_service.dart';
import 'src/features/auth/domain/services/auth_service.dart';
import 'src/features/auth/domain/providers/auth_provider.dart';
import 'src/features/auth/presentation/pages/login_page.dart';
import 'src/features/favorites/domain/providers/favorites_provider.dart';
import 'src/services/analytics_service.dart';
import 'src/services/superwall_service.dart';
import 'src/services/revenuecat_service.dart';
import 'src/services/notification_service.dart';
import 'src/services/debug_log_service.dart';
import 'dart:io';

// Top-level background message handler for push notifications
@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp();
  debugPrint('[FCM Background] Message received: ${message.messageId}');
  debugPrint('[FCM Background] Title: ${message.notification?.title}');
  debugPrint('[FCM Background] Body: ${message.notification?.body}');
}

Future<void> _precacheSplashLogo() async {
  final binding = WidgetsFlutterBinding.ensureInitialized();
  final provider = const AssetImage('assets/images/worthify-logo-splash.png');
  final devicePixelRatio =
      binding.platformDispatcher.implicitView?.devicePixelRatio ??
          (binding.platformDispatcher.views.isNotEmpty
              ? binding.platformDispatcher.views.first.devicePixelRatio
              : 1.0);
  final configuration = ImageConfiguration(
    bundle: rootBundle,
    devicePixelRatio: devicePixelRatio,
  );

  final stream = provider.resolve(configuration);
  final completer = Completer<void>();
  late final ImageStreamListener listener;
  listener = ImageStreamListener(
    (image, synchronousCall) => completer.complete(),
    onError: (error, stackTrace) {
      debugPrint('[Splash] precache error: $error');
      completer.complete();
    },
  );

  stream.addListener(listener);
  await completer.future;
  stream.removeListener(listener);
}

// Custom LocalStorage implementation using SharedPreferences
// This avoids flutter_secure_storage crash on iOS 18.6.2
class SharedPreferencesLocalStorage extends LocalStorage {
  static const _sessionKey = 'supabaseSession';

  // SECURITY: Use FlutterSecureStorage for sensitive authentication tokens
  static const _secureStorage = FlutterSecureStorage(
    aOptions: AndroidOptions(
      encryptedSharedPreferences: true,
    ),
    iOptions: IOSOptions(
      accessibility: KeychainAccessibility.first_unlock,
    ),
  );

  @override
  Future<void> initialize() async {
    // No initialization needed
  }

  @override
  Future<bool> hasAccessToken() async {
    try {
      final token = await _secureStorage.read(key: _sessionKey);
      return token != null && token.isNotEmpty;
    } catch (e) {
      debugPrint('[SecureStorage] Error checking token: $e');
      return false;
    }
  }

  @override
  Future<String?> accessToken() async {
    try {
      return await _secureStorage.read(key: _sessionKey);
    } catch (e) {
      debugPrint('[SecureStorage] Error reading token: $e');
      return null;
    }
  }

  @override
  Future<void> removePersistedSession() async {
    try {
      await _secureStorage.delete(key: _sessionKey);
      debugPrint('[SecureStorage] Session removed');
    } catch (e) {
      debugPrint('[SecureStorage] Error removing session: $e');
    }
  }

  @override
  Future<void> persistSession(String persistSessionString) async {
    try {
      await _secureStorage.write(key: _sessionKey, value: persistSessionString);
      debugPrint('[SecureStorage] Session persisted securely');
    } catch (e) {
      debugPrint('[SecureStorage] Error persisting session: $e');
      // Fallback to SharedPreferences if secure storage fails
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_sessionKey, persistSessionString);
      debugPrint('[SecureStorage] Fallback to SharedPreferences');
    }
  }
}

Future<bool> _initializeFirebase() async {
  try {
    await Firebase.initializeApp();
    FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);
    debugPrint('[Firebase] Initialized successfully');
    return true;
  } catch (e, stackTrace) {
    debugPrint('[Firebase] Initialization failed: $e');
    debugPrint('[Firebase] Stack trace: $stackTrace');
    debugPrint('[Firebase] Push notifications will be disabled');
    return false;
  }
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize debug log service FIRST to capture all logs
  DebugLogService().initialize();

  // Lock orientation to portrait mode only
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);

  if (Platform.isIOS) {
    PathProviderPlatform.instance = PathProviderFoundation();
    try {
      await DefaultCacheManager().getFileFromCache('__warmup__');
    } catch (e) {
      debugPrint('[Config] cache warmup skipped: $e');
    }
  }

  // Load environment variables (optional - won't crash if missing)
  try {
    await dotenv.load(fileName: ".env");
  } catch (e) {
    debugPrint(
      'Warning: .env file not found. Using environment variables from build.',
    );
  }

  // Initialize analytics (Amplitude)
  try {
    final amplitudeApiKey = AppConstants.amplitudeApiKey;
    if (amplitudeApiKey != null) {
      await AnalyticsService().initialize(
        apiKey: amplitudeApiKey,
        enabled: AppConstants.enableAnalytics,
      );
      debugPrint('[Analytics] Amplitude initialized');
    } else {
      debugPrint('[Analytics] AMPLITUDE_API_KEY not set - skipping');
    }
  } catch (e) {
    debugPrint('[Analytics] Initialization failed: $e');
  }
  // 🧠 Log which endpoint is active
  debugPrint(
      '[Config] SERP_DETECT_ENDPOINT = ${AppConstants.serpDetectEndpoint}');
  debugPrint(
      '[Config] SERP_DETECT_AND_SEARCH_ENDPOINT = ${AppConstants.serpDetectAndSearchEndpoint}');

  // Warm up path_provider so method channels are registered before cache usage.
  try {
    await getTemporaryDirectory();
  } catch (e) {
    debugPrint('[Config] path_provider warmup failed: $e');
  }

  await Supabase.initialize(
    url: AppConstants.supabaseUrl,
    anonKey: AppConstants.supabaseAnonKey,
    authOptions: FlutterAuthClientOptions(
      localStorage: SharedPreferencesLocalStorage(),
    ),
  );

  // Handle refresh token errors during session recovery
  try {
    final session = Supabase.instance.client.auth.currentSession;
    if (session != null) {
      debugPrint('[Auth] Session exists, attempting to refresh if needed');
    }
  } catch (e) {
    debugPrint('[Auth] Session recovery failed: $e');
    // Clear invalid session data
    if (e.toString().contains('refresh_token_not_found') ||
        e.toString().contains('Invalid Refresh Token')) {
      debugPrint('[Auth] Clearing invalid session data');
      try {
        await Supabase.instance.client.auth.signOut();
      } catch (signOutError) {
        debugPrint('[Auth] Error during signOut: $signOutError');
      }
    }
  }

  final firebaseInitialized = await _initializeFirebase();

  // Sync auth state to share extension
  try {
    final authService = AuthService();
    await authService.syncAuthState();
  } catch (e) {
    debugPrint('[Auth] Failed to sync auth state: $e');
  }

  // Initialize RevenueCat for subscriptions
  try {
    // Use platform-specific API key
    final revenueCatApiKey = Platform.isIOS
        ? (dotenv.env['REVENUECAT_IOS_API_KEY'] ??
            dotenv.env['REVENUECAT_APPLE_KEY'] ??
            dotenv.env['REVENUECAT_API_KEY'])
        : (dotenv.env['REVENUECAT_ANDROID_API_KEY'] ??
            dotenv.env['REVENUECAT_GOOGLE_KEY'] ??
            dotenv.env['REVENUECAT_API_KEY']);

    if (revenueCatApiKey != null && revenueCatApiKey.isNotEmpty) {
      await RevenueCatService().initialize(apiKey: revenueCatApiKey);
    } else {
      debugPrint('[RevenueCat] No API key set — skipping initialization');
    }
    debugPrint(
        '[RevenueCat] Initialized successfully with ${Platform.isIOS ? "iOS" : "Android"} API key');
  } catch (e) {
    debugPrint('[RevenueCat] Initialization failed: $e');
  }

  // Preload video immediately on app startup
  VideoPreloader.instance.preloadShareVideo();

  // Initialize shared config for iOS share extension
  unawaited(ShareExtensionConfigService.initializeSharedConfig());

  // Precache splash logo so the splash displays without a flicker
  await _precacheSplashLogo();

  final app =
      ProviderScope(child: WorthifyApp(isFirebaseReady: firebaseInitialized));
  final debugLog = DebugLogService();

  Future<void> initializeSuperwallAfterStartup() async {
    // Android can keep Superwall in pending state if initialized before the
    // activity is fully attached. Delay until after first frame.
    await Future.delayed(const Duration(milliseconds: 900));

    try {
      final superwallApiKey = Platform.isIOS
          ? (dotenv.env['SUPERWALL_IOS_API_KEY'] ??
              dotenv.env['SUPERWALL_API_KEY'])
          : (dotenv.env['SUPERWALL_ANDROID_API_KEY'] ??
              dotenv.env['SUPERWALL_API_KEY']);

      debugLog.log(
        'API key from .env: ${superwallApiKey != null ? "present (${superwallApiKey.substring(0, 5)}...)" : "NULL"}',
        tag: 'Main',
        level: DebugLogLevel.info,
      );

      if (superwallApiKey != null && superwallApiKey.isNotEmpty) {
        debugLog.log(
          'Starting Superwall initialization (post-startup)...',
          tag: 'Main',
          level: DebugLogLevel.info,
        );
        await SuperwallService().initialize(apiKey: superwallApiKey);
        debugLog.log(
          'Superwall initialized successfully',
          tag: 'Main',
          level: DebugLogLevel.info,
        );
      } else {
        debugLog.log(
          'ERROR - SUPERWALL_API_KEY not found in .env',
          tag: 'Main',
          level: DebugLogLevel.error,
        );
      }
    } catch (e, stackTrace) {
      debugLog.log(
        'Superwall initialization failed: $e\nStack trace: $stackTrace',
        tag: 'Main',
        level: DebugLogLevel.error,
      );
    }
  }

  runZonedGuarded(
    () {
      runApp(app);
      unawaited(initializeSuperwallAfterStartup());
    },
    (error, stackTrace) =>
        debugPrint('Uncaught zone error: $error\n$stackTrace'),
    zoneSpecification: ZoneSpecification(
      print: (self, parent, zone, line) {
        if (kDebugMode) {
          parent.print(zone, line);
        }
      },
    ),
  );
}

class _FetchingOverlay extends StatefulWidget {
  const _FetchingOverlay({
    super.key,
    required this.message,
    this.isInstagram = false,
    this.isX = false,
  });

  final String message;
  final bool isInstagram;
  final bool isX;

  @override
  State<_FetchingOverlay> createState() => _FetchingOverlayState();
}

class _FetchingOverlayState extends State<_FetchingOverlay>
    with TickerProviderStateMixin {
  static const double _pendingProgressCap = 0.9;
  late AnimationController _controller;
  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;
  late List<String> _messages;
  int _messageIndex = 0;
  Timer? _messageTimer;
  bool _isFinishing = false;

  @override
  void initState() {
    super.initState();

    // Match iOS share extension smooth progress animation
    // iOS uses 0.03s timer interval with adaptive increment toward target
    // Instagram downloads are slower (8s) due to ScrapingBee API + cache check
    // Other downloads are faster (3s)
    final duration = widget.isInstagram
        ? const Duration(seconds: 8)
        : (widget.isX
            ? const Duration(seconds: 10)
            : const Duration(seconds: 3));

    _controller = AnimationController(
      vsync: this,
      duration: duration,
    );

    _controller.forward();

    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    );
    _pulseAnimation = Tween<double>(begin: 0.5, end: 1.0).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );
    _pulseController.repeat(reverse: true);

    _messages = _buildMessages();
    _messageIndex = 0;
    _startMessageRotation();
  }

  @override
  void dispose() {
    _messageTimer?.cancel();
    _pulseController.dispose();
    _controller.dispose();
    super.dispose();
  }

  List<String> _buildMessages() {
    if (widget.isInstagram) {
      return const [
        "Getting image...",
        "Downloading image...",
        "Fetching image...",
        "Almost there...",
      ];
    }
    if (widget.isX) {
      return const [
        "Downloading image...",
        "Fetching media...",
        "Still working...",
        "Almost there...",
      ];
    }
    return [widget.message];
  }

  void _startMessageRotation() {
    _messageTimer?.cancel();
    if (_messages.length <= 1) return;
    _messageTimer = Timer.periodic(const Duration(seconds: 3), (_) {
      setState(() {
        _messageIndex = (_messageIndex + 1) % _messages.length;
      });
    });
  }

  String get _currentMessage =>
      _messages.isNotEmpty ? _messages[_messageIndex] : widget.message;

  double get _progressValue {
    final normalized = _controller.value.clamp(0.0, 1.0);
    if (!widget.isInstagram) {
      return normalized;
    }
    if (_isFinishing) {
      return normalized;
    }
    return (normalized * _pendingProgressCap).clamp(0.0, _pendingProgressCap);
  }

  Future<void> completeQuickly() async {
    if (!mounted) return;
    if (widget.isInstagram && !_isFinishing) {
      setState(() {
        _isFinishing = true;
      });
    }
    _controller.stop();
    if (_controller.value < 0.999) {
      await _controller.animateTo(
        1.0,
        duration: const Duration(milliseconds: 280),
        curve: Curves.easeOutCubic,
      );
    }
    if (widget.isInstagram) {
      await Future.delayed(const Duration(milliseconds: 120));
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      color: Colors.black.withOpacity(0.6),
      child: SafeArea(
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const CupertinoActivityIndicator(
                radius: 18,
                color: Colors.white,
              ),
              const SizedBox(height: 26),
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 300),
                transitionBuilder: (child, animation) =>
                    FadeTransition(opacity: animation, child: child),
                child: FadeTransition(
                  key: ValueKey(_currentMessage),
                  opacity: _pulseAnimation,
                  child: Text(
                    _currentMessage,
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                      color: Colors.white,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ),
              ),
              const SizedBox(height: 20),
              SizedBox(
                width: 180,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(3),
                  child: AnimatedBuilder(
                    animation: _controller,
                    builder: (context, child) {
                      return LinearProgressIndicator(
                        value: _progressValue,
                        minHeight: 6,
                        valueColor: const AlwaysStoppedAnimation<Color>(
                            Color(0xFFf2003c)),
                        backgroundColor: const Color(0xFFE5E5EA),
                      );
                    },
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class WorthifyApp extends ConsumerStatefulWidget {
  const WorthifyApp({super.key, required this.isFirebaseReady});

  final bool isFirebaseReady;

  @override
  ConsumerState<WorthifyApp> createState() => _WorthifyAppState();
}

class _WorthifyAppState extends ConsumerState<WorthifyApp>
    with WidgetsBindingObserver {
  late StreamSubscription _intentSub;
  final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();
  final GlobalKey<_FetchingOverlayState> _fetchingOverlayKey =
      GlobalKey<_FetchingOverlayState>();

  bool _isNavigatingToDetection = false;
  bool _hasHandledInitialShare = false;
  bool _shouldIgnoreNextStreamEmission = false;
  bool _skipNextResumePendingCheck = false;
  List<String>? _lastInitialSharePaths;

  bool _isFetchingOverlayVisible = false;
  String _fetchingOverlayMessage = 'Downloading image...';
  bool _isInstagramDownload = false;
  bool _isXDownload = false;
  AppLifecycleState _appLifecycleState = AppLifecycleState.resumed;
  bool _uiReadyForOverlays = false;
  bool _overlaysAllowed = false;
  String? _queuedOverlayMessage;
  static const bool _enableShareLogs = false;

  void _logShare(String message) {
    if (!_enableShareLogs) return;
    debugPrint(message);
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      // Delay enabling overlays until first frame + brief grace period
      WidgetsBinding.instance.endOfFrame.then((_) {
        Future.delayed(const Duration(milliseconds: 100), () {
          if (!mounted) return;
          setState(() {
            _uiReadyForOverlays = true;
            _overlaysAllowed = true;
            if (_queuedOverlayMessage != null &&
                _appLifecycleState == AppLifecycleState.resumed &&
                !_isFetchingOverlayVisible) {
              _fetchingOverlayMessage = _queuedOverlayMessage!;
              _isFetchingOverlayVisible = true;
              _queuedOverlayMessage = null;
            }
          });
        });
      });
    });

    // Sync auth state to share extension (runs on widget init, including after hot reload)
    _syncAuthState();

    // ShareHandlerService is NO LONGER NEEDED!
    // The receive_sharing_intent package's RSIShareViewController
    // automatically handles everything via ReceiveSharingIntent.getInitialMedia()
    // which we're already listening to above

    // Listen to media sharing coming from outside the app while the app is in the memory.
    _intentSub = ReceiveSharingIntent.instance.getMediaStream().listen(
      (value) {
        if (_shouldIgnoreNextStreamEmission && value.isNotEmpty) {
          final currentPaths = value.map((f) => f.path).toList(growable: false);
          final shouldSkip = _lastInitialSharePaths != null &&
              _arePathListsEqual(currentPaths, _lastInitialSharePaths!);
          if (shouldSkip) {
            _lastInitialSharePaths = null;
            _shouldIgnoreNextStreamEmission = false;
            return;
          }
          _shouldIgnoreNextStreamEmission = false;
        }
        if (value.isNotEmpty) {
          debugPrint(
            "[Share] Processing ${value.length} shared file(s) while app is active",
          );
          unawaited(_handleSharedMedia(value));
        }
      },
      onError: (err) {
        debugPrint("[Share] getIntentDataStream error: $err");
      },
    );

    // Get the media sharing coming from outside the app while the app is closed.
    ReceiveSharingIntent.instance.getInitialMedia().then((value) {
      if (_hasHandledInitialShare) {
        return;
      }
      if (value.isNotEmpty) {
        _hasHandledInitialShare = true;
        _skipNextResumePendingCheck = true;
        _shouldIgnoreNextStreamEmission = true;
        _lastInitialSharePaths =
            value.map((f) => f.path).toList(growable: false);
        ReceiveSharingIntent.instance.reset();
        debugPrint("[Share] Processing ${value.length} initial shared file(s)");
        unawaited(_handleSharedMedia(value, isInitial: true));
      }
    }).catchError((error) {
      debugPrint("[Share] Error getting initial media: $error");
    });

    if (widget.isFirebaseReady) {
      _setupFirebaseMessaging();
    } else {
      debugPrint(
        '[Firebase] Skipping Firebase Messaging setup because initialization failed',
      );
    }

    // Ensure we catch any pending share when the app is already running.
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _appLifecycleState = state;
    if (state == AppLifecycleState.resumed) {
      _checkForPendingSharedMediaOnResume();
      // Also sync auth state when app resumes
      _syncAuthState();
      _refreshFavoritesOnResume();

      // Show queued overlay message if UI is ready and we have one waiting
      if (_uiReadyForOverlays &&
          _overlaysAllowed &&
          _queuedOverlayMessage != null &&
          !_isFetchingOverlayVisible &&
          mounted) {
        setState(() {
          _fetchingOverlayMessage = _queuedOverlayMessage!;
          _isFetchingOverlayVisible = true;
          _queuedOverlayMessage = null;
        });
      }
    }
    super.didChangeAppLifecycleState(state);
  }

  void _setupFirebaseMessaging() {
    // Setup FCM foreground message handler
    FirebaseMessaging.onMessage.listen((RemoteMessage message) {
      debugPrint('[FCM Foreground] Message received: ${message.messageId}');
      debugPrint('[FCM Foreground] Title: ${message.notification?.title}');
      debugPrint('[FCM Foreground] Body: ${message.notification?.body}');
      debugPrint('[FCM Foreground] Data: ${message.data}');

      // Show notification banner when app is in foreground
      if (message.notification != null && mounted) {
        ScaffoldMessenger.of(navigatorKey.currentContext!).showSnackBar(
          SnackBar(
            content: Text(
              message.notification!.body ?? 'New notification',
              style: const TextStyle(fontFamily: 'PlusJakartaSans'),
            ),
            duration: const Duration(seconds: 4),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    });

    // Handle notification tap when app was in background/terminated
    FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) {
      debugPrint('[FCM] Notification tapped: ${message.messageId}');
      debugPrint('[FCM] Data: ${message.data}');

      // Handle navigation based on notification data
      // For re-engagement: navigate to home
      if (message.data['type'] == 're_engagement') {
        // Navigate to home tab
        if (mounted && navigatorKey.currentContext != null) {
          ref.read(selectedIndexProvider.notifier).state = 0;
        }
      }
    });

    // Check if app was opened from a terminated state via notification
    FirebaseMessaging.instance
        .getInitialMessage()
        .then((RemoteMessage? message) {
      if (message != null) {
        debugPrint(
            '[FCM] App opened from terminated state: ${message.messageId}');
        debugPrint('[FCM] Data: ${message.data}');

        // Handle the notification when app starts
        if (message.data['type'] == 're_engagement') {
          if (mounted) {
            ref.read(selectedIndexProvider.notifier).state = 0;
          }
        }
      }
    });
  }

  void _syncAuthState() async {
    try {
      debugPrint('[Auth] Syncing auth state to share extension...');

      // Check current session (automatically restored from localStorage if available)
      final session = Supabase.instance.client.auth.currentSession;
      final user = Supabase.instance.client.auth.currentUser;

      debugPrint(
          '[Auth] Current session: ${session != null ? "exists" : "null"}');
      debugPrint('[Auth] Current user: ${user?.id ?? "null"}');

      if (session == null) {
        debugPrint('[Auth] WARNING: No auth session - user needs to sign in');
      }

      final authService = AuthService();
      await authService.syncAuthState();

      debugPrint('[Auth] Sync complete');
    } catch (e) {
      debugPrint('[Auth] Failed to sync auth state: $e');

      // Handle refresh token errors
      if (e.toString().contains('refresh_token_not_found') ||
          e.toString().contains('Invalid Refresh Token')) {
        debugPrint('[Auth] Refresh token error - clearing session');
        try {
          await Supabase.instance.client.auth.signOut();
        } catch (signOutError) {
          debugPrint('[Auth] Error during signOut: $signOutError');
        }
      }
    }
  }

  void _refreshFavoritesOnResume() {
    if (!mounted) {
      return;
    }

    final user = Supabase.instance.client.auth.currentUser;
    if (user == null) {
      debugPrint('[Favorites] Skipping refresh - no authenticated user');
      return;
    }

    try {
      debugPrint('[Favorites] Refreshing favorites after resume');
      unawaited(ref.read(favoritesProvider.notifier).refresh());
    } catch (e) {
      debugPrint('[Favorites] Failed to refresh favorites on resume: $e');
    }
  }

  Future<void> _checkForPendingSharedMediaOnResume() async {
    try {
      // Check if there's a pending search_id from "Analyze now" + "Analyze in app" flow
      final searchId = await ShareImportStatus.getPendingSearchId();
      if (searchId != null && searchId.isNotEmpty) {
        _logShare("[SHARE EXTENSION] Found pending search_id: $searchId");
        _logShare(
            "[SHARE EXTENSION] Navigating to detection page with existing results");

        // Navigate to detection page with this search_id to load existing results
        _navigateToDetectionWithSearchId(searchId);
        return;
      }
    } catch (e) {
      debugPrint(
        "[SHARE EXTENSION ERROR] Error checking pending search_id: $e",
      );
    }

    if (_skipNextResumePendingCheck) {
      _skipNextResumePendingCheck = false;
      return;
    }
    if (_hasHandledInitialShare) {
      // Initial share already queued for HomePage; avoid double-handling before UI is ready.
      return;
    }

    try {
      // Check if user tapped "Open Worthify" from login modal in share extension
      final prefs = await SharedPreferences.getInstance();
      final needsSignin =
          prefs.getBool('needs_signin_from_share_extension') ?? false;
      if (needsSignin) {
        _logShare(
            "[SHARE EXTENSION] User needs to sign in - navigating to login page");
        prefs.remove('needs_signin_from_share_extension');

        // Navigate to login page
        _navigateToLoginPage();
        return;
      }

      final pendingMedia =
          await ReceiveSharingIntent.instance.getInitialMedia();
      if (pendingMedia.isNotEmpty) {
        _logShare(
          "[SHARE EXTENSION] Found pending media after resume: ${pendingMedia.length} files",
        );
        ReceiveSharingIntent.instance.reset();
        await _handleSharedMedia(pendingMedia);
      }
    } catch (e) {
      debugPrint(
        "[SHARE EXTENSION ERROR] Error checking pending media on resume: $e",
      );
    }
  }

  void _navigateToDetectionWithSearchId(String searchId) {
    if (_isNavigatingToDetection) {
      _logShare("[SHARE EXTENSION] Navigation already in progress");
      return;
    }
    _isNavigatingToDetection = true;

    // Ensure the main navigation is showing the home tab
    ref.read(selectedIndexProvider.notifier).state = 0;

    void pushRoute() {
      final navigator = navigatorKey.currentState;
      if (navigator == null) {
        WidgetsBinding.instance.addPostFrameCallback((_) => pushRoute());
        return;
      }

      _logShare("[SHARE EXTENSION] Share via searchId not yet supported");
      _isNavigatingToDetection = false;
    }

    pushRoute();
  }

  void _navigateToLoginPage() {
    if (_isNavigatingToDetection) {
      _logShare("[SHARE EXTENSION] Navigation already in progress");
      return;
    }
    _isNavigatingToDetection = true;

    void pushRoute() {
      final navigator = navigatorKey.currentState;
      if (navigator == null) {
        WidgetsBinding.instance.addPostFrameCallback((_) => pushRoute());
        return;
      }

      _logShare("[SHARE EXTENSION] Navigating to login page");

      // Navigate to login page with root navigator
      Navigator.of(navigator.context, rootNavigator: true)
          .push(
        MaterialPageRoute(
          builder: (context) => const LoginPage(),
        ),
      )
          .then((_) {
        _isNavigatingToDetection = false;
        _logShare("[SHARE EXTENSION] Login page dismissed");
      });
    }

    pushRoute();
  }

  SharedMediaFile _selectSharedFile(List<SharedMediaFile> sharedFiles) {
    if (sharedFiles.length == 1) {
      final file = sharedFiles.first;
      _logShare(
        "[SHARE EXTENSION] Single shared file received - using ${file.path} (${file.type})",
      );
      return file;
    }

    SharedMediaFile? firstExistingImage;
    SharedMediaFile? firstImage;
    SharedMediaFile? firstVideo;
    SharedMediaFile? firstFile;
    SharedMediaFile? firstTextOrUrl;
    SharedMediaFile? firstFallback;

    for (final file in sharedFiles) {
      firstFallback ??= file;
      final type = file.type;
      if (type == SharedMediaType.image) {
        firstImage ??= file;
        final normalizedPath = file.path.startsWith('file://')
            ? Uri.parse(file.path).toFilePath()
            : file.path;
        if (normalizedPath.isNotEmpty && File(normalizedPath).existsSync()) {
          firstExistingImage ??= file;
        }
      } else if (type == SharedMediaType.video) {
        firstVideo ??= file;
      } else if (type == SharedMediaType.file) {
        firstFile ??= file;
      } else if (type == SharedMediaType.text || type == SharedMediaType.url) {
        firstTextOrUrl ??= file;
      }

      if (firstExistingImage != null) {
        break;
      }
    }

    final selected = firstExistingImage ??
        firstImage ??
        firstVideo ??
        firstFile ??
        firstTextOrUrl ??
        firstFallback!;

    _logShare(
      "[SHARE EXTENSION] Selected shared file: ${selected.path} (type: ${selected.type})",
    );

    return selected;
  }

  bool _arePathListsEqual(List<String> a, List<String> b) {
    if (identical(a, b)) return true;
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) {
        return false;
      }
    }
    return true;
  }

  Future<void> _handleSharedMedia(
    List<SharedMediaFile> sharedFiles, {
    bool isInitial = false,
  }) async {
    _logShare(
      "[SHARE EXTENSION] _handleSharedMedia called - isInitial: $isInitial, files: ${sharedFiles.length}",
    );
    if (sharedFiles.isEmpty) {
      _logShare("[SHARE EXTENSION] No files to handle - returning");
      return;
    }

    unawaited(ShareImportStatus.markProcessing());

    final sharedFile = _selectSharedFile(sharedFiles);
    _logShare("[SHARE EXTENSION] Processing first file: ${sharedFile.path}");
    _logShare("[SHARE EXTENSION] File type: ${sharedFile.type}");

    if (sharedFile.type == SharedMediaType.image) {
      _logShare("[SHARE EXTENSION] Handling image file");
      // Handle actual image files
      final String normalizedPath = sharedFile.path.startsWith('file://')
          ? Uri.parse(sharedFile.path).toFilePath()
          : sharedFile.path;
      final imageFile = XFile(normalizedPath);
      final fileExists = File(imageFile.path).existsSync();
      _logShare("[SHARE EXTENSION] Normalized path: ${imageFile.path}");
      _logShare("[SHARE EXTENSION] File exists: $fileExists");
      ref.read(selectedImagesProvider.notifier).setImage(imageFile);

      // Pre-cache the shared image so DetectionPage shows it instantly (avoids black flash)
      if (navigatorKey.currentContext != null) {
        final fileImage = FileImage(File(imageFile.path));
        await precacheImage(fileImage, navigatorKey.currentContext!).catchError(
          (e) => debugPrint('[ShareExtension] Precaching error: $e'),
        );
      }

      // Also set in pending share provider so HomePage can handle navigation
      if (isInitial) {
        _logShare(
          "[SHARE EXTENSION] Setting pending shared image for HomePage (initial share)",
        );
        _logShare(
            "[SHARE EXTENSION] Source URL for initial share: ${sharedFile.message}");
        _skipNextResumePendingCheck = true;
        ref.read(pendingSharedImageProvider.notifier).state = imageFile;
        ref.read(pendingShareSourceUrlProvider.notifier).state =
            sharedFile.message;
        _hasHandledInitialShare = true;
        _shouldIgnoreNextStreamEmission = true;
        unawaited(ShareImportStatus.markComplete());
        _logShare("[SHARE EXTENSION] Deferring navigation to home init");
        return;
      }

      // Clear any stale pending share and navigate immediately when the app is already running.
      unawaited(ShareImportStatus.markComplete());
      ref.read(pendingSharedImageProvider.notifier).state = null;
      FocusManager.instance.primaryFocus?.unfocus();
      _logShare("[SHARE EXTENSION] Navigating to DetectionPage immediately");
      _logShare(
          "[SHARE EXTENSION] Source URL from share extension: ${sharedFile.message}");
      _navigateToDetection(sourceUrl: sharedFile.message);
    } else if (sharedFile.type == SharedMediaType.text ||
        sharedFile.type == SharedMediaType.url) {
      _logShare("[SHARE EXTENSION] Handling text/URL: ${sharedFile.path}");
      await _handleSharedText(sharedFile.path, fromShareExtension: true);
    } else {
      _logShare("[SHARE EXTENSION] Unknown file type: ${sharedFile.type}");
    }
  }

  Future<void> _navigateToDetection(
      {String? overrideSearchType, String? sourceUrl}) async {
    if (_isNavigatingToDetection) {
      _logShare("[SHARE EXTENSION] Navigation already in progress");
      return;
    }
    _isNavigatingToDetection = true;

    // Use override if provided, otherwise get from share extension
    String searchType;
    if (overrideSearchType != null) {
      searchType = overrideSearchType;
    } else {
      final platformType = await ShareImportStatus.getPendingPlatformType();
      searchType = platformType ?? 'share';
    }
    _logShare("[SHARE EXTENSION] Using searchType: $searchType");
    _logShare("[SHARE EXTENSION] Using sourceUrl: $sourceUrl");

    // Ensure the main navigation is showing the home tab before pushing detection.
    ref.read(selectedIndexProvider.notifier).state = 0;

    void pushRoute() {
      final navigator = navigatorKey.currentState;
      if (navigator == null) {
        WidgetsBinding.instance.addPostFrameCallback((_) => pushRoute());
        return;
      }

      ref.read(pendingSharedImageProvider.notifier).state = null;

      _logShare("[SHARE EXTENSION] Share via URL not yet supported");
      _isNavigatingToDetection = false;
      ref.read(shareNavigationInProgressProvider.notifier).state = false;
    }

    WidgetsBinding.instance.addPostFrameCallback((_) {
      final homeNavigator = homeNavigatorKey.currentState;
      if (homeNavigator?.canPop() ?? false) {
        homeNavigator!.popUntil((route) => route.isFirst);
      }
      WidgetsBinding.instance.addPostFrameCallback((_) => pushRoute());
    });
  }

  Future<void> _handleSharedText(
    String text, {
    bool fromShareExtension = false,
  }) async {
    _logShare("Handling shared text: $text");

    final extractedUrl = _extractFirstUrl(text);
    final effectiveText = extractedUrl ?? text.trim();

    if (extractedUrl != null) {
      _logShare("Extracted URL from text: $extractedUrl");
    }

    // Check if user is authenticated before downloading
    final isAuthenticated = ref.read(isAuthenticatedProvider);
    if (!isAuthenticated) {
      _logShare(
          "[SHARE EXTENSION] User not authenticated - showing login required");
      await ShareImportStatus.markComplete();
      _showLoginRequiredMessage();
      return;
    }

    final decodedText = _decodeUrlOrNull(effectiveText);
    final hasGoogleImageLink =
        LinkScraperService.isGoogleImageResultUrl(effectiveText) ||
            (decodedText != null &&
                LinkScraperService.isGoogleImageResultUrl(decodedText));

    // Check if URL is from a specific platform but not supported in tutorial
    final isFromKnownPlatform =
        InstagramService.isInstagramUrl(effectiveText) ||
            InstagramService.isTikTokUrl(effectiveText) ||
            InstagramService.isPinterestUrl(effectiveText) ||
            InstagramService.isXUrl(effectiveText) ||
            InstagramService.isRedditUrl(effectiveText) ||
            InstagramService.isFacebookUrl(effectiveText) ||
            InstagramService.isImdbUrl(effectiveText) ||
            InstagramService.isSnapchatUrl(effectiveText) ||
            InstagramService.isYouTubeUrl(effectiveText);

    if (isFromKnownPlatform && !_isTutorialSupportedUrl(effectiveText)) {
      // Known platform but not in tutorial - show unsupported message
      _showUnsupportedPlatformMessage();
      await ShareImportStatus.markComplete();
      return;
    }

    if (InstagramService.isInstagramUrl(effectiveText)) {
      await _downloadInstagramImage(effectiveText);
    } else if (InstagramService.isTikTokUrl(effectiveText)) {
      await _downloadTikTokImage(effectiveText);
    } else if (InstagramService.isPinterestUrl(effectiveText)) {
      await _downloadPinterestImage(effectiveText);
    } else if (InstagramService.isXUrl(effectiveText)) {
      await _downloadXImage(effectiveText);
    } else if (InstagramService.isRedditUrl(effectiveText)) {
      await _downloadRedditImage(effectiveText);
    } else if (InstagramService.isFacebookUrl(effectiveText)) {
      await _downloadFacebookImage(effectiveText);
    } else if (InstagramService.isImdbUrl(effectiveText)) {
      await _downloadImdbImage(effectiveText);
    } else if (InstagramService.isSnapchatUrl(effectiveText)) {
      await _downloadSnapchatImage(effectiveText);
    } else if (hasGoogleImageLink) {
      await _downloadGoogleImageResult(decodedText ?? effectiveText);
    } else if (InstagramService.isYouTubeUrl(effectiveText)) {
      await _downloadYouTubeImage(effectiveText);
    } else {
      final parsed = Uri.tryParse(effectiveText.trim());
      if (parsed != null &&
          (parsed.scheme == 'http' || parsed.scheme == 'https')) {
        _showUnsupportedMessage(text);
        await ShareImportStatus.markComplete();
      } else {
        _showUnsupportedMessage(text);
        await ShareImportStatus.markComplete();
      }
    }
  }

  String? _decodeUrlOrNull(String value) {
    try {
      return Uri.decodeFull(value);
    } catch (_) {
      return null;
    }
  }

  String? _extractFirstUrl(String text) {
    if (text.isEmpty) {
      _logShare("[SHARE EXTENSION] No text provided for URL extraction");
      return null;
    }

    final urlRegex = RegExp(
      r'(https?:\/\/[^\s<>"]+|www\.[^\s<>"]+)',
      caseSensitive: false,
    );
    final match = urlRegex.firstMatch(text);

    if (match == null) {
      _logShare("[SHARE EXTENSION] No URL detected in shared text");
      return null;
    }

    var matchedUrl = match.group(0);
    if (matchedUrl == null || matchedUrl.isEmpty) {
      _logShare("[SHARE EXTENSION] URL match found but empty");
      return null;
    }

    matchedUrl = matchedUrl.replaceAll(RegExp(r'[).,!?;:]+$'), '');
    if (!matchedUrl.toLowerCase().startsWith('http')) {
      matchedUrl = 'https://$matchedUrl';
    }

    _logShare("[SHARE EXTENSION] Extracted URL: $matchedUrl");
    return matchedUrl;
  }

  void _showFetchingOverlay(
      {required String title, bool isInstagram = false, bool isX = false}) {
    if (!mounted) {
      return;
    }
    if (!_uiReadyForOverlays ||
        !_overlaysAllowed ||
        _appLifecycleState != AppLifecycleState.resumed) {
      _queuedOverlayMessage = title;
      _isInstagramDownload = isInstagram;
      _isXDownload = isX;
      return;
    }
    setState(() {
      _fetchingOverlayMessage = title;
      _isInstagramDownload = isInstagram;
      _isXDownload = isX;
      _isFetchingOverlayVisible = true;
    });
  }

  Future<void> _hideFetchingOverlay({bool completeBeforeHide = false}) async {
    if (!mounted || !_isFetchingOverlayVisible) {
      return;
    }
    if (completeBeforeHide) {
      final overlayState = _fetchingOverlayKey.currentState;
      if (overlayState != null) {
        await overlayState.completeQuickly();
      }
    }
    if (!mounted) {
      return;
    }
    setState(() {
      _isFetchingOverlayVisible = false;
      _isInstagramDownload = false;
      _isXDownload = false;
      _queuedOverlayMessage = null;
    });
  }

  Future<void> _downloadInstagramImage(String instagramUrl) async {
    _showFetchingOverlay(title: 'Downloading image...', isInstagram: true);
    try {
      ref.read(shareNavigationInProgressProvider.notifier).state = true;

      final imageFiles = await InstagramService.downloadImageFromInstagramUrl(
        instagramUrl,
      );

      if (InstagramService.lastDownloadWasCacheHit) {
        final overlayState = _fetchingOverlayKey.currentState;
        if (overlayState != null) {
          await overlayState.completeQuickly();
          await Future.delayed(const Duration(milliseconds: 120));
        }
      }

      if (imageFiles.isNotEmpty) {
        ref.read(selectedImagesProvider.notifier).setImages(imageFiles);
        ref.read(pendingSharedImageProvider.notifier).state = imageFiles.first;

        // Pre-cache the image for instant display
        if (navigatorKey.currentContext != null) {
          final fileImage = FileImage(File(imageFiles.first.path));
          await precacheImage(fileImage, navigatorKey.currentContext!)
              .catchError((e) {
            debugPrint('[Instagram] Precaching error: $e');
          });
        }

        await ShareImportStatus.markComplete();

        _navigateToDetection(
            overrideSearchType: 'instagram', sourceUrl: instagramUrl);
      } else {
        ref.read(pendingSharedImageProvider.notifier).state = null;
        await ShareImportStatus.markComplete();
        _showInstagramErrorMessage();
        ref.read(shareNavigationInProgressProvider.notifier).state = false;
      }
    } catch (e) {
      debugPrint('Error downloading Instagram image: $e');

      ref.read(pendingSharedImageProvider.notifier).state = null;
      await ShareImportStatus.markComplete();
      _showInstagramErrorMessage();
      ref.read(shareNavigationInProgressProvider.notifier).state = false;
    } finally {
      await _hideFetchingOverlay(completeBeforeHide: true);
    }
  }

  Future<void> _downloadTikTokImage(String tiktokUrl) async {
    _showFetchingOverlay(title: 'Downloading image...');
    try {
      ref.read(shareNavigationInProgressProvider.notifier).state = true;
      final imageFiles = await InstagramService.downloadImageFromTikTokUrl(
        tiktokUrl,
      );

      if (imageFiles.isNotEmpty) {
        ref.read(selectedImagesProvider.notifier).setImages(imageFiles);
        ref.read(pendingSharedImageProvider.notifier).state = imageFiles.first;

        // Pre-cache the image for instant display
        if (navigatorKey.currentContext != null) {
          final fileImage = FileImage(File(imageFiles.first.path));
          await precacheImage(fileImage, navigatorKey.currentContext!)
              .catchError((e) {
            debugPrint('[TikTok] Precaching error: $e');
          });
        }

        await ShareImportStatus.markComplete();

        _navigateToDetection(
            overrideSearchType: 'tiktok', sourceUrl: tiktokUrl);
      } else {
        ref.read(pendingSharedImageProvider.notifier).state = null;
        await ShareImportStatus.markComplete();
        _showTikTokErrorMessage();
        ref.read(shareNavigationInProgressProvider.notifier).state = false;
      }
    } catch (e) {
      debugPrint('Error downloading TikTok image: $e');

      ref.read(pendingSharedImageProvider.notifier).state = null;
      await ShareImportStatus.markComplete();
      _showTikTokErrorMessage();
      ref.read(shareNavigationInProgressProvider.notifier).state = false;
    } finally {
      _hideFetchingOverlay();
    }
  }

  Future<void> _downloadPinterestImage(String pinterestUrl) async {
    _showFetchingOverlay(title: 'Downloading image...');
    try {
      ref.read(shareNavigationInProgressProvider.notifier).state = true;
      final imageFiles = await InstagramService.downloadImageFromPinterestUrl(
        pinterestUrl,
      );

      if (imageFiles.isNotEmpty) {
        ref.read(selectedImagesProvider.notifier).setImages(imageFiles);
        ref.read(pendingSharedImageProvider.notifier).state = imageFiles.first;

        // Pre-cache the image for instant display
        if (navigatorKey.currentContext != null) {
          final fileImage = FileImage(File(imageFiles.first.path));
          await precacheImage(fileImage, navigatorKey.currentContext!)
              .catchError((e) {
            debugPrint('[Pinterest] Precaching error: $e');
          });
        }

        await ShareImportStatus.markComplete();

        _navigateToDetection(
            overrideSearchType: 'pinterest', sourceUrl: pinterestUrl);
      } else {
        ref.read(pendingSharedImageProvider.notifier).state = null;
        await ShareImportStatus.markComplete();
        _showPinterestErrorMessage();
        ref.read(shareNavigationInProgressProvider.notifier).state = false;
      }
    } catch (e) {
      debugPrint('Error downloading Pinterest image: $e');

      ref.read(pendingSharedImageProvider.notifier).state = null;
      await ShareImportStatus.markComplete();
      _showPinterestErrorMessage();
      ref.read(shareNavigationInProgressProvider.notifier).state = false;
    } finally {
      _hideFetchingOverlay();
    }
  }

  Future<void> _downloadXImage(String xUrl) async {
    _showFetchingOverlay(title: 'Downloading image...', isX: true);
    try {
      ref.read(shareNavigationInProgressProvider.notifier).state = true;
      final imageFiles = await InstagramService.downloadImageFromXUrl(xUrl);

      if (imageFiles.isNotEmpty) {
        ref.read(selectedImagesProvider.notifier).setImages(imageFiles);
        ref.read(pendingSharedImageProvider.notifier).state = imageFiles.first;

        if (navigatorKey.currentContext != null) {
          final fileImage = FileImage(File(imageFiles.first.path));
          await precacheImage(fileImage, navigatorKey.currentContext!)
              .catchError(
            (e) => debugPrint('[X] Precaching error: $e'),
          );
        }

        await ShareImportStatus.markComplete();
        _navigateToDetection(overrideSearchType: 'twitter', sourceUrl: xUrl);
      } else {
        ref.read(pendingSharedImageProvider.notifier).state = null;
        await ShareImportStatus.markComplete();
        _showXErrorMessage();
        ref.read(shareNavigationInProgressProvider.notifier).state = false;
      }
    } catch (e) {
      debugPrint('Error downloading X image: $e');
      ref.read(pendingSharedImageProvider.notifier).state = null;
      await ShareImportStatus.markComplete();
      _showXErrorMessage();
      ref.read(shareNavigationInProgressProvider.notifier).state = false;
    } finally {
      _hideFetchingOverlay();
    }
  }

  Future<void> _downloadFacebookImage(String facebookUrl) async {
    _showFetchingOverlay(title: 'Downloading image...');
    try {
      ref.read(shareNavigationInProgressProvider.notifier).state = true;
      final imageFiles =
          await InstagramService.downloadImageFromFacebookUrl(facebookUrl);

      if (imageFiles.isNotEmpty) {
        ref.read(selectedImagesProvider.notifier).setImages(imageFiles);
        ref.read(pendingSharedImageProvider.notifier).state = imageFiles.first;

        if (navigatorKey.currentContext != null) {
          final fileImage = FileImage(File(imageFiles.first.path));
          await precacheImage(fileImage, navigatorKey.currentContext!)
              .catchError(
            (e) => debugPrint('[Facebook] Precaching error: $e'),
          );
        }

        await ShareImportStatus.markComplete();
        _navigateToDetection(
            overrideSearchType: 'facebook', sourceUrl: facebookUrl);
      } else {
        ref.read(pendingSharedImageProvider.notifier).state = null;
        await ShareImportStatus.markComplete();
        _showFacebookErrorMessage();
        ref.read(shareNavigationInProgressProvider.notifier).state = false;
      }
    } catch (e) {
      debugPrint('Error downloading Facebook image: $e');
      ref.read(pendingSharedImageProvider.notifier).state = null;
      await ShareImportStatus.markComplete();
      _showFacebookErrorMessage();
      ref.read(shareNavigationInProgressProvider.notifier).state = false;
    } finally {
      _hideFetchingOverlay();
    }
  }

  Future<void> _downloadImdbImage(String imdbUrl) async {
    _showFetchingOverlay(title: 'Downloading image...');
    try {
      ref.read(shareNavigationInProgressProvider.notifier).state = true;
      final imageFiles =
          await InstagramService.downloadImageFromImdbUrl(imdbUrl);

      if (imageFiles.isNotEmpty) {
        ref.read(selectedImagesProvider.notifier).setImages(imageFiles);
        ref.read(pendingSharedImageProvider.notifier).state = imageFiles.first;

        if (navigatorKey.currentContext != null) {
          final fileImage = FileImage(File(imageFiles.first.path));
          await precacheImage(fileImage, navigatorKey.currentContext!)
              .catchError(
            (e) => debugPrint('[IMDb] Precaching error: $e'),
          );
        }

        await ShareImportStatus.markComplete();
        _navigateToDetection(overrideSearchType: 'imdb', sourceUrl: imdbUrl);
      } else {
        ref.read(pendingSharedImageProvider.notifier).state = null;
        await ShareImportStatus.markComplete();
        _showUnsupportedMessage(imdbUrl);
        ref.read(shareNavigationInProgressProvider.notifier).state = false;
      }
    } catch (e) {
      debugPrint('Error downloading IMDb image: $e');
      ref.read(pendingSharedImageProvider.notifier).state = null;
      await ShareImportStatus.markComplete();
      _showUnsupportedMessage(imdbUrl);
      ref.read(shareNavigationInProgressProvider.notifier).state = false;
    } finally {
      _hideFetchingOverlay();
    }
  }

  Future<void> _downloadRedditImage(String redditUrl) async {
    _showFetchingOverlay(title: 'Downloading image...');
    try {
      ref.read(shareNavigationInProgressProvider.notifier).state = true;
      final imageFiles =
          await InstagramService.downloadImageFromRedditUrl(redditUrl);

      if (imageFiles.isNotEmpty) {
        ref.read(selectedImagesProvider.notifier).setImages(imageFiles);
        ref.read(pendingSharedImageProvider.notifier).state = imageFiles.first;

        if (navigatorKey.currentContext != null) {
          final fileImage = FileImage(File(imageFiles.first.path));
          await precacheImage(fileImage, navigatorKey.currentContext!)
              .catchError(
            (e) => debugPrint('[Reddit] Precaching error: $e'),
          );
        }

        await ShareImportStatus.markComplete();
        _navigateToDetection(
            overrideSearchType: 'reddit', sourceUrl: redditUrl);
      } else {
        ref.read(pendingSharedImageProvider.notifier).state = null;
        await ShareImportStatus.markComplete();
        _showRedditErrorMessage();
        ref.read(shareNavigationInProgressProvider.notifier).state = false;
      }
    } catch (e) {
      debugPrint('Error downloading Reddit image: $e');
      ref.read(pendingSharedImageProvider.notifier).state = null;
      await ShareImportStatus.markComplete();
      _showRedditErrorMessage();
      ref.read(shareNavigationInProgressProvider.notifier).state = false;
    } finally {
      _hideFetchingOverlay();
    }
  }

  Future<void> _downloadSnapchatImage(String snapchatUrl) async {
    _showFetchingOverlay(title: 'Downloading image...');
    try {
      ref.read(shareNavigationInProgressProvider.notifier).state = true;
      final imageFiles = await InstagramService.downloadImageFromSnapchatUrl(
        snapchatUrl,
      );

      if (imageFiles.isNotEmpty) {
        ref.read(selectedImagesProvider.notifier).setImages(imageFiles);
        ref.read(pendingSharedImageProvider.notifier).state = imageFiles.first;

        // Pre-cache the image for instant display
        if (navigatorKey.currentContext != null) {
          final fileImage = FileImage(File(imageFiles.first.path));
          await precacheImage(fileImage, navigatorKey.currentContext!)
              .catchError((e) {
            debugPrint('[Snapchat] Precaching error: $e');
          });
        }

        await ShareImportStatus.markComplete();

        _navigateToDetection(
            overrideSearchType: 'snapchat', sourceUrl: snapchatUrl);
      } else {
        ref.read(pendingSharedImageProvider.notifier).state = null;
        await ShareImportStatus.markComplete();
        _showSnapchatErrorMessage();
        ref.read(shareNavigationInProgressProvider.notifier).state = false;
      }
    } catch (e) {
      debugPrint('Error downloading Snapchat image: $e');

      ref.read(pendingSharedImageProvider.notifier).state = null;
      await ShareImportStatus.markComplete();
      _showSnapchatErrorMessage();
      ref.read(shareNavigationInProgressProvider.notifier).state = false;
    } finally {
      _hideFetchingOverlay();
    }
  }

  Future<void> _downloadYouTubeImage(String youtubeUrl) async {
    _showFetchingOverlay(title: 'Downloading image...');
    try {
      ref.read(shareNavigationInProgressProvider.notifier).state = true;
      final imageFiles = await InstagramService.downloadImageFromYouTubeUrl(
        youtubeUrl,
      );

      if (imageFiles.isNotEmpty) {
        ref.read(selectedImagesProvider.notifier).setImages(imageFiles);
        ref.read(pendingSharedImageProvider.notifier).state = imageFiles.first;

        // Pre-cache the image for instant display
        if (navigatorKey.currentContext != null) {
          final fileImage = FileImage(File(imageFiles.first.path));
          await precacheImage(fileImage, navigatorKey.currentContext!)
              .catchError((e) {
            debugPrint('[YouTube] Precaching error: $e');
          });
        }

        await ShareImportStatus.markComplete();

        _navigateToDetection(
            overrideSearchType: 'youtube', sourceUrl: youtubeUrl);
      } else {
        ref.read(pendingSharedImageProvider.notifier).state = null;
        await ShareImportStatus.markComplete();
        _showYouTubeErrorMessage();
        ref.read(shareNavigationInProgressProvider.notifier).state = false;
      }
    } catch (e) {
      debugPrint('Error downloading YouTube thumbnail: $e');

      ref.read(pendingSharedImageProvider.notifier).state = null;
      await ShareImportStatus.markComplete();
      _showYouTubeErrorMessage();
      ref.read(shareNavigationInProgressProvider.notifier).state = false;
    } finally {
      _hideFetchingOverlay();
    }
  }

  Future<void> _downloadGoogleImageResult(String url) async {
    _showFetchingOverlay(title: 'Downloading image...');
    try {
      ref.read(shareNavigationInProgressProvider.notifier).state = true;
      final imageFiles =
          await LinkScraperService.downloadImageFromGoogleImageResult(url);
      if (imageFiles.isNotEmpty) {
        ref.read(selectedImagesProvider.notifier).setImages(imageFiles);
        ref.read(pendingSharedImageProvider.notifier).state = imageFiles.first;

        // Pre-cache the image for instant display
        if (navigatorKey.currentContext != null) {
          final fileImage = FileImage(File(imageFiles.first.path));
          await precacheImage(fileImage, navigatorKey.currentContext!)
              .catchError((e) {
            debugPrint('[Google Image] Precaching error: $e');
          });
        }

        await ShareImportStatus.markComplete();

        _navigateToDetection(overrideSearchType: 'web', sourceUrl: url);
      } else {
        ref.read(pendingSharedImageProvider.notifier).state = null;
        await ShareImportStatus.markComplete();
        _showGenericLinkErrorMessage(url);
        ref.read(shareNavigationInProgressProvider.notifier).state = false;
      }
    } catch (e) {
      debugPrint('Error downloading Google image result: $e');

      ref.read(pendingSharedImageProvider.notifier).state = null;
      await ShareImportStatus.markComplete();
      _showGenericLinkErrorMessage(url);
      ref.read(shareNavigationInProgressProvider.notifier).state = false;
    } finally {
      _hideFetchingOverlay();
    }
  }

  Future<void> _downloadGenericLink(String url) async {
    _showFetchingOverlay(title: 'Downloading image...');
    try {
      ref.read(shareNavigationInProgressProvider.notifier).state = true;
      final imageFiles = await LinkScraperService.downloadImagesFromUrl(url);

      if (imageFiles.isNotEmpty) {
        ref.read(selectedImagesProvider.notifier).setImages(imageFiles);
        ref.read(pendingSharedImageProvider.notifier).state = imageFiles.first;

        // Pre-cache the image for instant display
        if (navigatorKey.currentContext != null) {
          final fileImage = FileImage(File(imageFiles.first.path));
          await precacheImage(fileImage, navigatorKey.currentContext!)
              .catchError((e) {
            debugPrint('[Generic Link] Precaching error: $e');
          });
        }

        await ShareImportStatus.markComplete();

        _navigateToDetection(overrideSearchType: 'web', sourceUrl: url);
      } else {
        ref.read(pendingSharedImageProvider.notifier).state = null;
        await ShareImportStatus.markComplete();
        _showGenericLinkErrorMessage(url);
        ref.read(shareNavigationInProgressProvider.notifier).state = false;
      }
    } catch (e) {
      debugPrint('Error downloading images from shared link: $e');
      ref.read(pendingSharedImageProvider.notifier).state = null;
      await ShareImportStatus.markComplete();
      _showGenericLinkErrorMessage(url);
      ref.read(shareNavigationInProgressProvider.notifier).state = false;
    } finally {
      _hideFetchingOverlay();
    }
  }

  void _showLoginRequiredMessage() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (navigatorKey.currentContext != null) {
        final context = navigatorKey.currentContext!;
        showDialog(
          context: context,
          barrierDismissible: false,
          builder: (dialogContext) => AlertDialog(
            backgroundColor: Theme.of(dialogContext).colorScheme.surface,
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            title: const Text(
              'Login Required',
              style: TextStyle(
                fontFamily: 'PlusJakartaSans',
                fontWeight: FontWeight.bold,
              ),
            ),
            content: const Text(
              'You need to be logged in to analyze images from shared links.\n\n'
              'Please log in to continue.',
              style: TextStyle(fontFamily: 'PlusJakartaSans'),
            ),
            actions: [
              TextButton(
                onPressed: () {
                  Navigator.of(dialogContext).pop();
                },
                style: TextButton.styleFrom(
                  foregroundColor:
                      Theme.of(dialogContext).colorScheme.onSurface,
                  textStyle: const TextStyle(
                    fontFamily: 'PlusJakartaSans',
                    fontWeight: FontWeight.w600,
                  ),
                ),
                child: const Text('Cancel'),
              ),
              TextButton(
                onPressed: () {
                  Navigator.of(dialogContext).pop();
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (context) => const LoginPage(),
                    ),
                  );
                },
                style: TextButton.styleFrom(
                  foregroundColor: AppColors.secondary,
                  textStyle: const TextStyle(
                    fontFamily: 'PlusJakartaSans',
                    fontWeight: FontWeight.w600,
                  ),
                ),
                child: const Text('Log In'),
              ),
            ],
          ),
        );
      }
    });
  }

  void _showInstagramErrorMessage() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (navigatorKey.currentContext != null) {
        showDialog(
          context: navigatorKey.currentContext!,
          builder: (context) => AlertDialog(
            title: const Text('Instagram Image Download Failed'),
            content: const Text(
              'Unable to download the image from Instagram. This can happen due to:\n\n'
              '- Privacy settings on the post\n'
              '- Network connectivity issues\n'
              '- Instagram\'s anti-scraping measures\n\n'
              'Try taking a screenshot instead and use the "Upload" button to analyze it.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('OK'),
              ),
            ],
          ),
        );
      }
    });
  }

  void _showTikTokErrorMessage() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (navigatorKey.currentContext != null) {
        showDialog(
          context: navigatorKey.currentContext!,
          builder: (context) => AlertDialog(
            title: const Text('TikTok Image Download Failed'),
            content: const Text(
              'Unable to download the image from TikTok. This can happen due to:\n\n'
              '- Privacy settings on the video\n'
              '- Network connectivity issues\n'
              '- TikTok\'s anti-scraping measures\n\n'
              'Try taking a screenshot instead and use the "Upload" button to analyze it.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('OK'),
              ),
            ],
          ),
        );
      }
    });
  }

  void _showPinterestErrorMessage() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (navigatorKey.currentContext != null) {
        showDialog(
          context: navigatorKey.currentContext!,
          builder: (context) => AlertDialog(
            title: const Text('Pinterest Image Download Failed'),
            content: const Text(
              'Unable to download the image from Pinterest. This can happen due to:\n\n'
              '- Privacy settings on the pin\n'
              '- Network connectivity issues\n'
              '- Pinterest\'s anti-scraping measures\n\n'
              'Try taking a screenshot instead and use the "Upload" button to analyze it.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('OK'),
              ),
            ],
          ),
        );
      }
    });
  }

  void _showXErrorMessage() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (navigatorKey.currentContext != null) {
        showDialog(
          context: navigatorKey.currentContext!,
          builder: (context) => AlertDialog(
            title: const Text('X Image Download Failed'),
            content: const Text(
              'Unable to download the image from X. This can happen due to:\n\n'
              '- Privacy/settings on the post\n'
              '- Network connectivity issues\n'
              '- Platform anti-scraping measures\n\n'
              'Try taking a screenshot instead and use the "Upload" button to analyze it.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('OK'),
              ),
            ],
          ),
        );
      }
    });
  }

  void _showFacebookErrorMessage() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (navigatorKey.currentContext != null) {
        showDialog(
          context: navigatorKey.currentContext!,
          builder: (context) => AlertDialog(
            title: const Text('Facebook Image Download Failed'),
            content: const Text(
              'Unable to download the image from Facebook. This can happen due to:\n\n'
              '- Privacy/settings on the post\n'
              '- Network connectivity issues\n'
              '- Platform anti-scraping measures\n\n'
              'Try taking a screenshot instead and use the "Upload" button to analyze it.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('OK'),
              ),
            ],
          ),
        );
      }
    });
  }

  void _showRedditErrorMessage() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (navigatorKey.currentContext != null) {
        showDialog(
          context: navigatorKey.currentContext!,
          builder: (context) => AlertDialog(
            title: const Text('Reddit Image Download Failed'),
            content: const Text(
              'Unable to download the image from Reddit. This can happen due to:\n\n'
              '- Privacy/settings on the post\n'
              '- Network connectivity issues\n'
              '- Platform anti-scraping measures\n\n'
              'Try taking a screenshot instead and use the "Upload" button to analyze it.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('OK'),
              ),
            ],
          ),
        );
      }
    });
  }

  void _showSnapchatErrorMessage() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (navigatorKey.currentContext != null) {
        showDialog(
          context: navigatorKey.currentContext!,
          builder: (context) => AlertDialog(
            title: const Text('Snapchat Image Download Failed'),
            content: const Text(
              'Unable to download the image from this Snapchat link. This can happen due to:\n\n'
              '- The Spotlight video is private or restricted\n'
              '- Snapchat\'s anti-scraping measures\n'
              '- Network connectivity issues\n\n'
              'Try taking a screenshot instead and use the "Upload" button to analyze it.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('OK'),
              ),
            ],
          ),
        );
      }
    });
  }

  void _showYouTubeErrorMessage() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (navigatorKey.currentContext != null) {
        showDialog(
          context: navigatorKey.currentContext!,
          builder: (context) => AlertDialog(
            title: const Text('YouTube Thumbnail Download Failed'),
            content: const Text(
              'Unable to download the thumbnail from this YouTube link. This can happen due to:\n\n'
              '- The Shorts video is private or restricted\n'
              '- YouTube temporarily blocked thumbnail access\n'
              '- Network connectivity issues\n\n'
              'Try copying a different Shorts link or take a screenshot and upload it manually.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('OK'),
              ),
            ],
          ),
        );
      }
    });
  }

  void _showGenericLinkErrorMessage(String url) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (navigatorKey.currentContext != null) {
        showDialog(
          context: navigatorKey.currentContext!,
          builder: (context) => AlertDialog(
            title: const Text('Couldn\'t Fetch Shared Link'),
            content: Text(
              'We weren\'t able to find any usable images on:\n\n$url\n\nTry sharing a page that includes photo content.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('OK'),
              ),
            ],
          ),
        );
      }
    });
  }

  bool _isTutorialSupportedUrl(String url) {
    // Apps shown in "Add your first style" tutorial page + YouTube and Google Images which work
    return InstagramService.isInstagramUrl(url) ||
        InstagramService.isPinterestUrl(url) ||
        InstagramService.isTikTokUrl(url) ||
        InstagramService.isImdbUrl(url) ||
        InstagramService.isYouTubeUrl(url) ||
        InstagramService.isXUrl(url) ||
        LinkScraperService.isGoogleImageResultUrl(url);
  }

  void _showUnsupportedPlatformMessage() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (navigatorKey.currentContext != null) {
        showDialog(
          context: navigatorKey.currentContext!,
          builder: (context) => AlertDialog(
            titlePadding: const EdgeInsets.fromLTRB(24, 24, 24, 16),
            contentPadding: const EdgeInsets.fromLTRB(24, 0, 24, 0),
            actionsPadding: const EdgeInsets.only(bottom: 16),
            title: const Text(
              'Not supported',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w600,
              ),
            ),
            content: const Text(
              'This link isn\'t supported yet. Try Instagram, TikTok, Pinterest, IMDb, YouTube, X, or any website.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 14,
              ),
            ),
            actions: [
              Center(
                child: TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('OK'),
                ),
              ),
            ],
            insetPadding: const EdgeInsets.symmetric(horizontal: 40),
          ),
        );
      }
    });
  }

  void _showUnsupportedMessage(String content) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (navigatorKey.currentContext != null) {
        showDialog(
          context: navigatorKey.currentContext!,
          builder: (context) => AlertDialog(
            title: const Text('Text Share Detected'),
            content: Text(
              'Received text content, but Worthify analyzes images.\n\n'
              'Content: ${content.length > 100 ? content.substring(0, 100) + '...' : content}\n\n'
              'Please share an image file instead.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('OK'),
              ),
            ],
          ),
        );
      }
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _intentSub.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Disabled dark mode - not fully implemented yet
    // final themeMode = ref.watch(themeModeProvider);

    return MaterialApp(
      navigatorKey: navigatorKey,
      builder: (context, child) {
        return Stack(
          fit: StackFit.expand,
          children: [
            if (child != null) child,
            if (_isFetchingOverlayVisible)
              Positioned.fill(
                child: _FetchingOverlay(
                  key: _fetchingOverlayKey,
                  message: _fetchingOverlayMessage,
                  isInstagram: _isInstagramDownload,
                  isX: _isXDownload,
                ),
              ),
          ],
        );
      },
      title: 'Worthify',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.lightTheme,
      // darkTheme: AppTheme.darkTheme,  // Disabled until dark mode is complete
      themeMode: ThemeMode.light, // Force light mode only
      navigatorObservers: [routeObserver],
      home: const SplashPage(),
      onGenerateRoute: (settings) => null,
    );
  }
}
