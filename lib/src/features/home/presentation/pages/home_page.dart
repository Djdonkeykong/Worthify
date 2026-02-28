import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:image_picker/image_picker.dart';
import 'package:easy_refresh/easy_refresh.dart';
import 'package:in_app_review/in_app_review.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../domain/providers/history_bootstrap_provider.dart';
import '../../domain/providers/pending_share_provider.dart';
import '../../../detection/presentation/pages/analyzing_page.dart';
import '../../../paywall/models/subscription_plan.dart';
import '../../../paywall/providers/credit_provider.dart';
import '../../../wardrobe/domain/providers/history_provider.dart';
import '../../../../shared/services/supabase_service.dart';
import '../../../wardrobe/presentation/widgets/history_card.dart';
import '../../../../../core/theme/app_colors.dart';
import '../../../../../core/theme/theme_extensions.dart';
import '../../../../shared/widgets/bottom_sheet_handle.dart';
import '../../../../shared/widgets/worthify_circular_icon_button.dart';
import '../../../../shared/services/review_prompt_logs_service.dart';
import '../../../../../shared/navigation/main_navigation.dart';
import '../../../../services/notification_service.dart';

const String _snapActionIcon = 'assets/icons/solar--camera-square-bold-new.svg';
const String _uploadActionIcon = 'assets/icons/upload_filled.svg';
const String _shareActionIcon = 'assets/icons/solar--share-bold-duotone.svg';
const double _importOptionSpacing = 9.0;

class HomePage extends ConsumerStatefulWidget {
  const HomePage({super.key});

  @override
  ConsumerState<HomePage> createState() => _HomePageState();
}

class _HomePageState extends ConsumerState<HomePage>
    with WidgetsBindingObserver, SingleTickerProviderStateMixin {
  static const _firstAnalysisReviewPromptedKeyPrefix =
      'review_prompted_after_first_analysis_';
  static const _homePolaroidsAsset =
      AssetImage('assets/images/home-polaroids.png');
  static const _homeLogoAsset = AssetImage('assets/images/logo.png');
  final ImagePicker _picker = ImagePicker();
  ProviderSubscription<XFile?>? _pendingShareListener;
  bool _isProcessingPendingNavigation = false;
  bool _isCheckingReviewPrompt = false;
  late final AnimationController _addButtonTapController;
  late final Animation<double> _addButtonScaleAnimation;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _addButtonTapController = AnimationController(
      duration: const Duration(milliseconds: 250),
      vsync: this,
    );
    _addButtonScaleAnimation = TweenSequence<double>([
      TweenSequenceItem(
        tween: Tween<double>(
          begin: 1.0,
          end: 1.08,
        ).chain(CurveTween(curve: Curves.easeOut)),
        weight: 40,
      ),
      TweenSequenceItem(
        tween: Tween<double>(
          begin: 1.08,
          end: 1.0,
        ).chain(CurveTween(curve: Curves.easeInOut)),
        weight: 60,
      ),
    ]).animate(_addButtonTapController);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(_precacheHomeAssets());

      Future.delayed(const Duration(milliseconds: 1000), () {
        _checkPendingSharedImage();
      });

      unawaited(_maybeRequestReviewFromExistingFirstAnalysis());
      unawaited(_maybeRequestNotificationPermission());
    });

    _pendingShareListener ??= ref.listenManual<XFile?>(
      pendingSharedImageProvider,
      (previous, next) {
        if (next != null && mounted) {
          _handlePendingSharedImage(next);
        }
      },
    );
  }

  static const _notificationPermissionRequestedKey =
      'home_notification_permission_requested';

  Future<void> _maybeRequestNotificationPermission() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (prefs.getBool(_notificationPermissionRequestedKey) ?? false) return;

      await prefs.setBool(_notificationPermissionRequestedKey, true);
      await NotificationService().initialize();
    } catch (e) {
      debugPrint('[HomePage] Error requesting notification permission: $e');
    }
  }

  Future<void> _precacheHomeAssets() async {
    if (!mounted) return;
    try {
      await precacheImage(_homePolaroidsAsset, context);
      await precacheImage(_homeLogoAsset, context);
    } catch (e) {
      debugPrint('[HomePage] Failed to precache home assets: $e');
    }
  }

  void _checkPendingSharedImage() {
    final pendingImage = ref.read(pendingSharedImageProvider);

    if (pendingImage != null && mounted) {
      _handlePendingSharedImage(pendingImage);
    }
  }

  void _handlePendingSharedImage(XFile image) {
    if (_isProcessingPendingNavigation || !mounted) {
      return;
    }

    if (ref.read(shareNavigationInProgressProvider)) {
      return;
    }

    _isProcessingPendingNavigation = true;

    final sourceUrl = ref.read(pendingShareSourceUrlProvider);

    ref.read(pendingSharedImageProvider.notifier).state = null;
    ref.read(pendingShareSourceUrlProvider.notifier).state = null;

    () async {
      try {
        debugPrint('[HomePage] Share extension navigation is disabled.');
      } catch (e) {
        debugPrint('Error handling pending shared image: $e');
      } finally {
        _isProcessingPendingNavigation = false;
      }
    }();
  }

  @override
  void dispose() {
    _pendingShareListener?.close();
    WidgetsBinding.instance.removeObserver(this);
    _addButtonTapController.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      ref.invalidate(historyProvider);
      unawaited(_maybeRequestReviewFromExistingFirstAnalysis());
    }
  }

  Future<void> _maybeRequestReviewFromExistingFirstAnalysis() async {
    if (_isCheckingReviewPrompt) return;

    final userId = Supabase.instance.client.auth.currentUser?.id;
    if (userId == null) return;

    _isCheckingReviewPrompt = true;
    try {
      final storageKey = '$_firstAnalysisReviewPromptedKeyPrefix$userId';
      final prefs = await SharedPreferences.getInstance();
      final alreadyPrompted = prefs.getBool(storageKey) ?? false;
      if (alreadyPrompted) return;

      final existingSearches = await Supabase.instance.client
          .from('user_searches')
          .select('id')
          .eq('user_id', userId)
          .limit(1);
      final hasAnyAnalysis = (existingSearches as List).isNotEmpty;
      if (!hasAnyAnalysis) return;

      final timestamp = DateTime.now().toIso8601String();
      final inAppReview = InAppReview.instance;
      try {
        final available = await inAppReview.isAvailable();
        await ReviewPromptLogsService.addLog(
          '[$timestamp] home fallback requestReview() available=$available',
        );
        if (available) {
          await inAppReview.requestReview();
          await ReviewPromptLogsService.addLog(
            '[$timestamp] home fallback requestReview() invoked successfully',
          );
        } else {
          await ReviewPromptLogsService.addLog(
            '[$timestamp] home fallback requestReview() skipped (not available)',
          );
        }
      } catch (e) {
        await ReviewPromptLogsService.addLog(
          '[$timestamp] home fallback requestReview() error: $e',
        );
      } finally {
        await prefs.setBool(storageKey, true);
      }
    } catch (e) {
      debugPrint('[ReviewPrompt] Home fallback error: $e');
    } finally {
      _isCheckingReviewPrompt = false;
    }
  }

  Future<void> _pickImage(ImageSource source) async {
    try {
      final XFile? image = await _picker.pickImage(
        source: source,
        maxWidth: 1024,
        maxHeight: 1024,
        imageQuality: 85,
      );

      if (image != null) {
        if (mounted) {
          Navigator.of(context, rootNavigator: true).push(
            MaterialPageRoute(builder: (context) => AnalyzingPage(imageFile: image)),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Error picking image: $e',
              style: context.snackTextStyle(),
            ),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final spacing = context.spacing;
    final radius = context.radius;
    final historyAsync = ref.watch(historyProvider);
    final historyBootstrap = ref.watch(historyBootstrapProvider);

    final searches = historyAsync.valueOrNull ?? [];
    final isInitialHistoryLoading =
        historyAsync.isLoading && !historyAsync.hasValue;
    final shouldShowSpinnerWhileLoading = isInitialHistoryLoading &&
        historyBootstrap == HistoryBootstrapState.hasHistory;
    final hasHistoryError = historyAsync.hasError && !historyAsync.hasValue;
    final hasHistory = searches.isNotEmpty;

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: Stack(
        children: [
          // Main content
          if (shouldShowSpinnerWhileLoading)
            Center(
              child: CircularProgressIndicator(
                valueColor: AlwaysStoppedAnimation<Color>(AppColors.secondary),
                strokeWidth: 2,
              ),
            )
          else if (isInitialHistoryLoading)
            _buildCtaView(colorScheme)
          else if (hasHistoryError)
            _buildErrorState(colorScheme)
          else if (!hasHistory)
            _buildCtaView(colorScheme)
          else
            _buildHistoryList(searches, spacing, radius, colorScheme),

          if (hasHistory)
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: IgnorePointer(
                child: Container(
                  height: MediaQuery.of(context).padding.top + 68,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Theme.of(context).scaffoldBackgroundColor,
                        Theme.of(context)
                            .scaffoldBackgroundColor
                            .withValues(alpha: 0.78),
                        Theme.of(context)
                            .scaffoldBackgroundColor
                            .withValues(alpha: 0.34),
                        Theme.of(context)
                            .scaffoldBackgroundColor
                            .withValues(alpha: 0.0),
                      ],
                      stops: const [0.0, 0.35, 0.72, 1.0],
                    ),
                  ),
                ),
              ),
            ),

          // Top bar
          Positioned(
            top: MediaQuery.of(context).padding.top + 12,
            left: 16,
            right: 16,
            child:
                _buildTopBar(colorScheme, hasHistory, isInitialHistoryLoading),
          ),

          // Floating action bar (slide up + fade in once history is confirmed)
          Positioned(
            bottom: 24,
            left: MediaQuery.of(context).size.width * 0.09,
            right: MediaQuery.of(context).size.width * 0.09,
            child: _AnimatedFloatingBar(
              visible: hasHistory && !isInitialHistoryLoading,
              child: _FloatingActionBar(
                onSnapTap: () => _pickImage(ImageSource.camera),
                onUploadTap: () => _pickImage(ImageSource.gallery),
                onImportTap: () {},
                onInfoTap: () => _showInfoBottomSheet(context),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTopBar(
      ColorScheme colorScheme, bool hasHistory, bool isLoading) {
    // Show info icon only when we've confirmed there's no history (not still loading)
    final showInfoIcon = !hasHistory && !isLoading;

    return Row(
      children: [
        Image.asset(
          'assets/images/logo.png',
          height: 32,
          fit: BoxFit.contain,
        ),
        const Spacer(),
        AnimatedOpacity(
          opacity: showInfoIcon ? 1.0 : 0.0,
          duration: const Duration(milliseconds: 300),
          child: IgnorePointer(
            ignoring: !showInfoIcon,
            child: GestureDetector(
              onTap: () {
                HapticFeedback.lightImpact();
                _showInfoBottomSheet(context);
              },
              child: Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: colorScheme.surfaceContainerHighest.withOpacity(0.5),
                  shape: BoxShape.circle,
                ),
                child: Center(
                  child: SvgPicture.asset(
                    'assets/icons/info_icon.svg',
                    width: 24,
                    height: 24,
                    colorFilter: ColorFilter.mode(
                      colorScheme.onSurface,
                      BlendMode.srcIn,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildCtaView(ColorScheme colorScheme) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Image.asset(
            'assets/images/home-polaroids.png',
            width: 200,
            fit: BoxFit.contain,
          ),
          const SizedBox(height: 24),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: Text(
              'Identify your first\nartwork',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 28,
                fontWeight: FontWeight.bold,
                color: colorScheme.onSurface,
                letterSpacing: -0.5,
                height: 1.2,
              ),
            ),
          ),
          const SizedBox(height: 24),
          GestureDetector(
            onTap: () {
              HapticFeedback.mediumImpact();
              _addButtonTapController.forward(from: 0.0);
              _showImportOptionsSheet();
            },
            child: AnimatedBuilder(
              animation: _addButtonTapController,
              builder: (context, child) {
                return Transform.scale(
                  scale: _addButtonScaleAnimation.value,
                  child: child,
                );
              },
              child: Container(
                width: 88,
                height: 52,
                decoration: BoxDecoration(
                  color: AppColors.secondary,
                  borderRadius: BorderRadius.circular(26),
                  border: Border.all(
                    color: AppColors.secondary,
                    width: 1.0,
                  ),
                ),
                child: Icon(
                  Icons.add,
                  size: 28,
                  color: colorScheme.surface,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildErrorState(ColorScheme colorScheme) {
    final textTheme = Theme.of(context).textTheme;
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.error_outline, size: 64, color: colorScheme.error),
          const SizedBox(height: 16),
          Text(
            'Error loading history',
            style: textTheme.bodyMedium?.copyWith(
              color: colorScheme.onSurface,
            ),
          ),
          const SizedBox(height: 16),
          ElevatedButton(
            onPressed: () {
              ref.invalidate(historyProvider);
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: colorScheme.secondary,
              foregroundColor: colorScheme.onSecondary,
            ),
            child: const Text('Retry'),
          ),
        ],
      ),
    );
  }

  Widget _buildHistoryList(
    List<Map<String, dynamic>> searches,
    AppSpacingExtension spacing,
    AppRadiusExtension radius,
    ColorScheme colorScheme,
  ) {
    return EasyRefresh(
      onRefresh: () async {
        ref.invalidate(historyProvider);
      },
      header: ClassicHeader(
        dragText: '',
        armedText: '',
        readyText: '',
        processingText: '',
        processedText: '',
        noMoreText: '',
        failedText: '',
        messageText: '',
        safeArea: true,
        showMessage: false,
        showText: false,
        processedDuration: Duration.zero,
        succeededIcon: const SizedBox.shrink(),
        iconTheme: const IconThemeData(
          color: Color(0xFFf2003c),
          size: 24,
        ),
        backgroundColor: colorScheme.surface,
      ),
      child: GridView.builder(
        // Account for top bar and floating bar
        padding: EdgeInsets.only(
          top: MediaQuery.of(context).padding.top + 68,
          bottom: 110,
          left: spacing.m,
          right: spacing.m,
        ),
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 2,
          crossAxisSpacing: spacing.m,
          mainAxisSpacing: spacing.m,
          childAspectRatio: 0.78,
        ),
        itemCount: searches.length,
        itemBuilder: (context, index) {
          final search = searches[index];
          return _HomeHistoryGridCard(
            search: search,
          );
        },
      ),
    );
  }

  void _showTutorialOptionsSheet() {}

  void _showImportOptionsSheet() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      useRootNavigator: true,
      builder: (sheetContext) {
        return _ImportOptionsBottomSheet(
          onSnapTap: () async {
            await Navigator.of(sheetContext).maybePop();
            await Future.delayed(const Duration(milliseconds: 200));
            if (!mounted) return;
            await _pickImage(ImageSource.camera);
          },
          onUploadTap: () async {
            await Navigator.of(sheetContext).maybePop();
            await Future.delayed(const Duration(milliseconds: 200));
            if (!mounted) return;
            await _pickImage(ImageSource.gallery);
          },
        );
      },
    );
  }

  Future<void> _showInfoBottomSheet(BuildContext context) async {
    final spacing = context.spacing;

    await ref.read(creditBalanceProvider.notifier).refresh();

    if (!mounted) return;

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      useRootNavigator: true,
      builder: (context) => _InfoBottomSheetContent(spacing: spacing),
    );
  }
}

class _AnimatedFloatingBar extends StatefulWidget {
  final bool visible;
  final Widget child;

  const _AnimatedFloatingBar({
    required this.visible,
    required this.child,
  });

  @override
  State<_AnimatedFloatingBar> createState() => _AnimatedFloatingBarState();
}

class _AnimatedFloatingBarState extends State<_AnimatedFloatingBar>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _fadeAnimation;
  late final Animation<Offset> _slideAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 900),
      vsync: this,
    );

    _fadeAnimation = CurvedAnimation(
      parent: _controller,
      curve: const Interval(0.0, 0.7, curve: Curves.easeOut),
    );

    _slideAnimation = Tween<Offset>(
      begin: const Offset(0.0, 1.2),
      end: Offset.zero,
    ).animate(CurvedAnimation(
      parent: _controller,
      curve: Curves.easeOutCubic,
    ));

    if (widget.visible) {
      _controller.value = 1.0;
    }
  }

  @override
  void didUpdateWidget(_AnimatedFloatingBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.visible && !oldWidget.visible) {
      _controller.forward();
    } else if (!widget.visible && oldWidget.visible) {
      _controller.reverse();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _fadeAnimation,
      child: SlideTransition(
        position: _slideAnimation,
        child: IgnorePointer(
          ignoring: !widget.visible,
          child: widget.child,
        ),
      ),
    );
  }
}

class _FloatingActionBar extends StatelessWidget {
  final VoidCallback onSnapTap;
  final VoidCallback onUploadTap;
  final VoidCallback onImportTap;
  final VoidCallback onInfoTap;

  const _FloatingActionBar({
    required this.onSnapTap,
    required this.onUploadTap,
    required this.onImportTap,
    required this.onInfoTap,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 70,
      margin: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: AppColors.secondary,
        borderRadius: BorderRadius.circular(35),
        border: Border.all(
          color: AppColors.secondary,
          width: 1.0,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.06),
            blurRadius: 18,
            offset: const Offset(0, -6),
            spreadRadius: 1,
          ),
          BoxShadow(
            color: Colors.black.withOpacity(0.03),
            blurRadius: 6,
            offset: const Offset(0, -1),
            spreadRadius: 0,
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: _FloatingActionButtonSvg(
                svgIcon: _snapActionIcon,
                label: 'Snap',
                onTap: onSnapTap,
              ),
            ),
            const SizedBox(width: 4),
            Expanded(
              child: _FloatingActionButtonSvg(
                svgIcon: _uploadActionIcon,
                label: 'Upload',
                onTap: onUploadTap,
              ),
            ),
            const SizedBox(width: 4),
            Expanded(
              child: _FloatingActionButtonSvg(
                svgIcon: _shareActionIcon,
                label: 'Discover',
                onTap: onImportTap,
              ),
            ),
            const SizedBox(width: 4),
            Expanded(
              child: _FloatingActionButtonSvg(
                svgIcon: 'assets/icons/info_icon.svg',
                label: 'Info',
                onTap: onInfoTap,
                iconSize: 23.5,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _FloatingActionButtonSvg extends StatefulWidget {
  final String svgIcon;
  final String label;
  final VoidCallback onTap;
  final double iconSize;

  const _FloatingActionButtonSvg({
    required this.svgIcon,
    required this.label,
    required this.onTap,
    this.iconSize = 24,
  });

  @override
  State<_FloatingActionButtonSvg> createState() =>
      _FloatingActionButtonSvgState();
}

class _FloatingActionButtonSvgState extends State<_FloatingActionButtonSvg>
    with SingleTickerProviderStateMixin {
  late final AnimationController _tapController;
  late final Animation<double> _scaleAnimation;

  @override
  void initState() {
    super.initState();
    _tapController = AnimationController(
      duration: const Duration(milliseconds: 220),
      vsync: this,
    );
    _scaleAnimation = TweenSequence<double>([
      TweenSequenceItem(
        tween: Tween<double>(
          begin: 1.0,
          end: 1.06,
        ).chain(CurveTween(curve: Curves.easeOut)),
        weight: 45,
      ),
      TweenSequenceItem(
        tween: Tween<double>(
          begin: 1.06,
          end: 1.0,
        ).chain(CurveTween(curve: Curves.easeInOut)),
        weight: 55,
      ),
    ]).animate(_tapController);
  }

  @override
  void dispose() {
    _tapController.dispose();
    super.dispose();
  }

  void _handleTap() {
    HapticFeedback.mediumImpact();
    _tapController.forward(from: 0.0);
    widget.onTap();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: _handleTap,
      child: SizedBox.expand(
        child: Center(
          child: AnimatedBuilder(
            animation: _tapController,
            builder: (context, child) {
              return Transform.scale(
                scale: _scaleAnimation.value,
                child: child,
              );
            },
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  SvgPicture.asset(
                    widget.svgIcon,
                    width: widget.iconSize,
                    height: widget.iconSize,
                    colorFilter:
                        const ColorFilter.mode(Colors.white, BlendMode.srcIn),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    widget.label,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ImportOptionsBottomSheet extends StatelessWidget {
  final VoidCallback onSnapTap;
  final VoidCallback onUploadTap;

  const _ImportOptionsBottomSheet({
    required this.onSnapTap,
    required this.onUploadTap,
  });

  @override
  Widget build(BuildContext context) {
    final spacing = context.spacing;
    final colorScheme = Theme.of(context).colorScheme;

    return Container(
      decoration: BoxDecoration(
        color: colorScheme.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
      ),
      child: SafeArea(
        top: false,
        child: Stack(
          children: [
            Padding(
              padding: EdgeInsets.symmetric(
                horizontal: spacing.l,
                vertical: spacing.l,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  BottomSheetHandle(
                    margin: EdgeInsets.only(bottom: spacing.m),
                  ),
                  Text(
                    'Pick your source',
                    style: TextStyle(
                      fontSize: 32,
                      fontFamily: 'PlusJakartaSans',
                      letterSpacing: -1.0,
                      fontWeight: FontWeight.bold,
                      color: colorScheme.onSurface,
                      height: 1.3,
                    ),
                  ),
                  SizedBox(height: spacing.xs),
                  Text(
                    'Choose your starting point',
                    style: TextStyle(
                      fontSize: 15,
                      color: colorScheme.onSurfaceVariant,
                      fontWeight: FontWeight.w500,
                      fontFamily: 'PlusJakartaSans',
                    ),
                  ),
                  SizedBox(height: spacing.l),
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: _importOptionSpacing,
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: _ImportOptionTile(
                            label: 'Snap',
                            svgIcon: _snapActionIcon,
                            onTap: onSnapTap,
                          ),
                        ),
                        SizedBox(width: _importOptionSpacing),
                        Expanded(
                          child: _ImportOptionTile(
                            label: 'Upload',
                            svgIcon: _uploadActionIcon,
                            onTap: onUploadTap,
                          ),
                        ),
                      ],
                    ),
                  ),
                  SizedBox(height: spacing.l),
                ],
              ),
            ),
            Positioned(
              top: spacing.l,
              right: spacing.l,
              child: WorthifyCircularIconButton(
                icon: Icons.close,
                iconSize: 18,
                backgroundColor: colorScheme.surfaceContainerHighest,
                iconColor: colorScheme.onSurface,
                onPressed: () => Navigator.of(context).pop(),
                tooltip: 'Close',
                semanticLabel: 'Close',
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ImportOptionTile extends StatelessWidget {
  final String label;
  final String svgIcon;
  final VoidCallback onTap;

  const _ImportOptionTile({
    required this.label,
    required this.svgIcon,
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
      child: Container(
        width: double.infinity,
        height: 97,
        decoration: BoxDecoration(
          color: colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 11),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              SvgPicture.asset(
                svgIcon,
                width: 26,
                height: 26,
                colorFilter: const ColorFilter.mode(
                  AppColors.secondary,
                  BlendMode.srcIn,
                ),
              ),
              const SizedBox(height: _importOptionSpacing),
              Text(
                label,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: colorScheme.onSurface,
                  fontFamily: 'PlusJakartaSans',
                  letterSpacing: -0.2,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _HomeHistoryGridCard extends ConsumerWidget {
  final Map<String, dynamic> search;

  const _HomeHistoryGridCard({
    required this.search,
  });

  String _timeAgo() {
    final raw = search['created_at'];
    if (raw == null) return '';
    final date = DateTime.tryParse(raw.toString());
    if (date == null) return '';
    final diff = DateTime.now().toUtc().difference(date);
    if (diff.inMinutes < 1) return 'Just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    if (diff.inDays == 1) return 'Yesterday';
    if (diff.inDays < 7) return '${diff.inDays}d ago';
    if (diff.inDays < 30) return '${(diff.inDays / 7).floor()}w ago';
    if (diff.inDays < 365) return '${(diff.inDays / 30).floor()}mo ago';
    return '${(diff.inDays / 365).floor()}y ago';
  }

  String _sourceLabelFromSearch() {
    final rawType =
        (search['search_type'] ?? search['source_type'])?.toString();
    final type = rawType?.trim().toLowerCase();
    final sourceUrl = (search['source_url'] as String?)?.toLowerCase() ?? '';

    switch (type) {
      case 'ig':
      case 'instagram':
        return 'Instagram';
      case 'pin':
      case 'pinterest':
        return 'Pinterest';
      case 'tt':
      case 'tiktok':
        return 'TikTok';
      case 'photos':
      case 'photo':
      case 'gallery':
        return 'Photos';
      case 'imdb':
        return 'IMDb';
      case 'x':
      case 'twitter':
        return 'X';
      case 'web':
      case 'browser':
        if (sourceUrl.contains('imdb.com') ||
            sourceUrl.contains('m.imdb.com')) {
          return 'IMDb';
        }
        return 'Web';
      case 'share':
      case 'share_extension':
      case 'shareextension':
      case 'camera':
      case 'home':
      case null:
        return 'Worthify';
      default:
        return rawType!
            .split(RegExp(r'[_-]+'))
            .map((word) => word.isEmpty
                ? ''
                : '${word[0].toUpperCase()}${word.substring(1)}')
            .join(' ');
    }
  }

  Future<void> _deleteSearch(BuildContext context, WidgetRef ref) async {
    final searchId = search['id'] as String?;
    if (searchId == null) return;

    final confirmed = await showDeleteConfirmDialog(
      context,
      title: 'Delete search',
      message: 'This will permanently remove this search from your history.',
      confirmLabel: 'Delete',
      cancelLabel: 'Cancel',
    );

    if (confirmed != true) return;

    final success = await SupabaseService().deleteSearch(searchId);
    if (success) {
      ref.invalidate(historyProvider);
    }
  }

  Future<void> _rescanSearch(BuildContext context) async {
    final cloudinaryUrl = (search['cloudinary_url'] as String?)?.trim();
    if (cloudinaryUrl == null || cloudinaryUrl.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'No image available for re-scan.',
            style: context.snackTextStyle(
              merge: const TextStyle(fontFamily: 'PlusJakartaSans'),
            ),
          ),
          duration: const Duration(seconds: 2),
        ),
      );
      return;
    }

    return;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colorScheme = Theme.of(context).colorScheme;
    final cloudinaryUrl = (search['cloudinary_url'] as String?)?.trim();
    final totalResults = (search['total_results'] as num?)?.toInt() ?? 0;
    final searchId = search['id'] as String?;
    const cardRadius = 24.0;

    return GestureDetector(
      onTap: () {
        if (searchId == null) return;
      },
      onLongPress: () {
        HapticFeedback.mediumImpact();
        _deleteSearch(context, ref);
      },
      child: Container(
        decoration: BoxDecoration(
          color: colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(cardRadius),
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Stack(
                fit: StackFit.expand,
                children: [
                  cloudinaryUrl != null && cloudinaryUrl.isNotEmpty
                      ? CachedNetworkImage(
                          imageUrl: cloudinaryUrl,
                          fit: BoxFit.cover,
                          width: double.infinity,
                          placeholder: (_, __) => Container(
                            color: colorScheme.surfaceContainerHighest,
                          ),
                          errorWidget: (_, __, ___) => Container(
                            color: colorScheme.surfaceContainerHighest,
                            child: Icon(
                              Icons.image_outlined,
                              color: colorScheme.onSurfaceVariant,
                            ),
                          ),
                        )
                      : Container(
                          color: colorScheme.surfaceContainerHighest,
                          width: double.infinity,
                          child: Icon(
                            Icons.image_outlined,
                            color: colorScheme.onSurfaceVariant,
                          ),
                        ),
                  if (cloudinaryUrl != null && cloudinaryUrl.isNotEmpty)
                    Positioned(
                      bottom: 8,
                      right: 8,
                      child: GestureDetector(
                        onTap: () => _rescanSearch(context),
                        child: Container(
                          width: 36,
                          height: 36,
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.9),
                            shape: BoxShape.circle,
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withOpacity(0.1),
                                blurRadius: 8,
                                offset: const Offset(0, 2),
                              ),
                            ],
                          ),
                          child: Icon(
                            Icons.search_rounded,
                            color: colorScheme.onSurface,
                            size: 18,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 10, 10, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _sourceLabelFromSearch(),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: colorScheme.onSurface,
                      fontFamily: 'PlusJakartaSans',
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '${totalResults == 1 ? '1 result' : '$totalResults results'} - ${_timeAgo()}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 12,
                      color: colorScheme.onSurfaceVariant,
                      fontFamily: 'PlusJakartaSans',
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _InfoBottomSheetContent extends ConsumerWidget {
  final AppSpacingExtension spacing;

  const _InfoBottomSheetContent({required this.spacing});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final creditBalance = ref.watch(creditBalanceProvider);
    final colorScheme = Theme.of(context).colorScheme;

    return Container(
      decoration: BoxDecoration(
        color: colorScheme.surface,
        borderRadius: const BorderRadius.vertical(
          top: Radius.circular(20),
        ),
      ),
      child: SafeArea(
        child: Stack(
          children: [
            Padding(
              padding: EdgeInsets.all(spacing.l),
              child: creditBalance.when(
                data: (balance) {
                  final membershipType = balance.hasActiveSubscription
                      ? (balance.isTrialSubscription
                          ? 'Premium (Trial)'
                          : 'Premium')
                      : 'Free';
                  final maxCredits = SubscriptionPlan.monthly.creditsPerMonth;
                  final creditsRemaining =
                      balance.availableCredits.clamp(0, maxCredits).toInt();
                  final creditsPercentage = maxCredits > 0
                      ? (creditsRemaining / maxCredits).clamp(0.0, 1.0)
                      : 0.0;

                  return Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      BottomSheetHandle(
                        margin: EdgeInsets.only(bottom: spacing.m),
                      ),
                      Text(
                        'Membership',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                          color: colorScheme.onSurfaceVariant,
                          fontFamily: 'PlusJakartaSans',
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        membershipType,
                        style: TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.w600,
                          color: colorScheme.onSurface,
                          fontFamily: 'PlusJakartaSans',
                          letterSpacing: -0.3,
                        ),
                      ),
                      SizedBox(height: spacing.l),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.baseline,
                        textBaseline: TextBaseline.alphabetic,
                        children: [
                          Text(
                            '$creditsRemaining',
                            style: TextStyle(
                              fontSize: 48,
                              fontWeight: FontWeight.bold,
                              color: Theme.of(context).brightness ==
                                      Brightness.dark
                                  ? colorScheme.onSurface
                                  : AppColors.secondary,
                              fontFamily: 'PlusJakartaSans',
                              letterSpacing: -2,
                            ),
                          ),
                          Text(
                            ' / $maxCredits',
                            style: TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.w500,
                              color: colorScheme.onSurfaceVariant,
                              fontFamily: 'PlusJakartaSans',
                            ),
                          ),
                        ],
                      ),
                      SizedBox(height: spacing.xs),
                      Text(
                        'Credits Remaining',
                        style: TextStyle(
                          fontSize: 13,
                          color: colorScheme.onSurfaceVariant,
                          fontFamily: 'PlusJakartaSans',
                        ),
                      ),
                      SizedBox(height: spacing.l),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: LinearProgressIndicator(
                          value: creditsPercentage,
                          minHeight: 6,
                          backgroundColor: colorScheme.surfaceContainerHighest,
                          valueColor: AlwaysStoppedAnimation<Color>(
                            Theme.of(context).brightness == Brightness.dark
                                ? colorScheme.onSurface
                                : AppColors.secondary,
                          ),
                        ),
                      ),
                      SizedBox(height: spacing.m),
                      Text(
                        'Resets monthly on the 1st',
                        style: TextStyle(
                          fontSize: 12,
                          color: colorScheme.onSurfaceVariant,
                          fontFamily: 'PlusJakartaSans',
                        ),
                      ),
                      SizedBox(height: spacing.l),
                      Container(
                        width: double.infinity,
                        padding: EdgeInsets.all(spacing.m),
                        decoration: BoxDecoration(
                          color:
                              colorScheme.surfaceContainerHighest.withOpacity(
                            Theme.of(context).brightness == Brightness.dark
                                ? 0.4
                                : 0.6,
                          ),
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            Icon(
                              Icons.info_outline,
                              size: 20,
                              color: colorScheme.onSurfaceVariant,
                            ),
                            SizedBox(width: spacing.m),
                            Expanded(
                              child: Text(
                                'Each artwork scan costs 1 credit. Cropping to just the artwork helps improve identification accuracy.',
                                style: TextStyle(
                                  fontSize: 13,
                                  height: 1.4,
                                  color: colorScheme.onSurfaceVariant,
                                  fontFamily: 'PlusJakartaSans',
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      SizedBox(height: spacing.l),
                    ],
                  );
                },
                loading: () => const SizedBox.shrink(),
                error: (error, stackTrace) => Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    BottomSheetHandle(
                      margin: EdgeInsets.only(bottom: spacing.m),
                    ),
                    Icon(
                      Icons.error_outline,
                      size: 28,
                      color: colorScheme.onSurfaceVariant,
                    ),
                    SizedBox(height: spacing.s),
                    Text(
                      'Unable to load credits',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: colorScheme.onSurface,
                        fontFamily: 'PlusJakartaSans',
                      ),
                    ),
                    SizedBox(height: spacing.xs),
                    Text(
                      'Please try again.',
                      style: TextStyle(
                        fontSize: 13,
                        color: colorScheme.onSurfaceVariant,
                        fontFamily: 'PlusJakartaSans',
                      ),
                      textAlign: TextAlign.center,
                    ),
                    SizedBox(height: spacing.m),
                  ],
                ),
              ),
            ),
            Positioned(
              top: spacing.l,
              right: spacing.l,
              child: WorthifyCircularIconButton(
                icon: Icons.close,
                iconSize: 18,
                backgroundColor: colorScheme.surfaceContainerHighest,
                iconColor: colorScheme.onSurface,
                onPressed: () => Navigator.pop(context),
                tooltip: 'Close',
                semanticLabel: 'Close',
              ),
            ),
          ],
        ),
      ),
    );
  }
}


class _BrowserIconStack extends StatelessWidget {
  final double size;

  const _BrowserIconStack({this.size = 28});

  @override
  Widget build(BuildContext context) {
    final iconSize = size * 0.62;
    final step = iconSize * 0.6;
    final totalWidth = iconSize + (step * 2);

    return SizedBox(
      width: totalWidth,
      height: iconSize,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned(
            left: 0,
            child: Image.asset(
              'assets/icons/firefox.png',
              width: iconSize,
              height: iconSize,
              gaplessPlayback: true,
            ),
          ),
          Positioned(
            left: step,
            child: Image.asset(
              'assets/icons/brave.png',
              width: iconSize,
              height: iconSize,
              gaplessPlayback: true,
            ),
          ),
          Positioned(
            left: step * 2,
            child: Image.asset(
              'assets/icons/safari.png',
              width: iconSize,
              height: iconSize,
              gaplessPlayback: true,
            ),
          ),
        ],
      ),
    );
  }
}
