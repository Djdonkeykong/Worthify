import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter/services.dart';
import '../../src/features/home/presentation/pages/home_page.dart';
import '../../src/features/wardrobe/presentation/pages/wishlist_page.dart';
import '../../src/features/profile/presentation/pages/profile_page.dart';
import '../../src/features/favorites/domain/providers/favorites_provider.dart';

import '../../core/theme/theme_extensions.dart';
import '../../core/theme/worthify_icons.dart';
import '../../src/features/paywall/providers/credit_provider.dart';

final selectedIndexProvider = StateProvider<int>((ref) => 0);
final scrollToTopTriggerProvider = StateProvider<int>((ref) => 0);
final isAtHomeRootProvider = StateProvider<bool>((ref) => true);

// Global navigator keys
final homeNavigatorKey = GlobalKey<NavigatorState>();
final wishlistNavigatorKey = GlobalKey<NavigatorState>();
final profileNavigatorKey = GlobalKey<NavigatorState>();

final homeScrollControllerProvider = Provider<ScrollController?>((ref) => null);

class MainNavigation extends ConsumerStatefulWidget {
  const MainNavigation({super.key});

  @override
  ConsumerState<MainNavigation> createState() => _MainNavigationState();
}

class _MainNavigationState extends ConsumerState<MainNavigation> {
  static const SystemUiOverlayStyle _mainOverlayStyle = SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.dark, // Android
    statusBarBrightness: Brightness.light, // iOS => dark icons
    systemNavigationBarColor: Colors.white,
    systemNavigationBarIconBrightness: Brightness.dark,
  );

  @override
  void initState() {
    super.initState();
    Future.microtask(() => ref.read(creditBalanceProvider));
    SystemChrome.setSystemUIOverlayStyle(_mainOverlayStyle);
  }

  void _handleTabTap(int index) {
    final currentIndex = ref.read(selectedIndexProvider);

    if (currentIndex == index) {
      final navigatorKey = _getNavigatorKey(index);
      if (navigatorKey?.currentState?.canPop() ?? false) {
        navigatorKey!.currentState!.popUntil((route) => route.isFirst);
      } else {
        _scrollToTop(index);
      }
    } else {
      ref.read(selectedIndexProvider.notifier).state = index;
    }
  }

  GlobalKey<NavigatorState>? _getNavigatorKey(int index) {
    switch (index) {
      case 0:
        return homeNavigatorKey;
      case 1:
        return wishlistNavigatorKey;
      case 2:
        return profileNavigatorKey;
      default:
        return null;
    }
  }

  void _scrollToTop(int index) {
    ref.read(scrollToTopTriggerProvider.notifier).state++;
  }

  @override
  Widget build(BuildContext context) {
    final selectedIndex = ref.watch(selectedIndexProvider);
    final favoritesAsync = ref.watch(favoritesProvider);
    final favoritesCount = favoritesAsync.maybeWhen(
      data: (favorites) => favorites.length,
      orElse: () => 0,
    );

    final pages = [
      Navigator(
        key: homeNavigatorKey,
        initialRoute: '/',
        onGenerateRoute: (settings) {
          return PageRouteBuilder(
            settings: settings,
            pageBuilder: (context, animation, secondaryAnimation) {
              return const HomePage();
            },
            transitionDuration: const Duration(milliseconds: 300),
            reverseTransitionDuration: const Duration(milliseconds: 300),
          );
        },
      ),
      Navigator(
        key: wishlistNavigatorKey,
        initialRoute: '/',
        onGenerateRoute: (settings) {
          return MaterialPageRoute(
            builder: (context) => const WishlistPage(),
            settings: settings,
          );
        },
      ),
      Navigator(
        key: profileNavigatorKey,
        initialRoute: '/',
        onGenerateRoute: (settings) {
          return MaterialPageRoute(
            builder: (context) => const ProfilePage(),
            settings: settings,
          );
        },
      ),
    ];

    final colorScheme = Theme.of(context).colorScheme;
    final navColors = context.navigation;

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: _mainOverlayStyle,
      child: Scaffold(
        backgroundColor: colorScheme.surface,
        body: IndexedStack(index: selectedIndex, children: pages),
        bottomNavigationBar: Container(
          decoration: BoxDecoration(
            color: navColors.navBarBackground,
            border: Border(
              top: BorderSide(
                color: colorScheme.outlineVariant.withOpacity(0.08),
                width: 0.5,
              ),
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
          child: SafeArea(
            minimum: const EdgeInsets.only(bottom: 4),
            child: Container(
              height: 56,
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
              child: Row(
                children: [
                  // Home icon
                  Expanded(
                    child: Center(
                      child: Transform.translate(
                        offset: const Offset(-8, 0),
                        child: _NavigationItem(
                          icon: WorthifyIcons.homeOutline,
                          selectedIcon: WorthifyIcons.homeFilled,
                          label: 'Home',
                          index: 0,
                          isSelected: selectedIndex == 0,
                          onTap: () => _handleTabTap(0),
                          iconSize: 25.0,
                          selectedIconSize: 25.0,
                        ),
                      ),
                    ),
                  ),
                  // Heart icon with badge
                  Expanded(
                    child: Center(
                      child: Stack(
                        clipBehavior: Clip.none,
                        children: [
                          _NavigationItem(
                            icon: WorthifyIcons.heartOutline,
                            selectedIcon: WorthifyIcons.heartFilled,
                            label: 'Collection',
                            index: 1,
                            isSelected: selectedIndex == 1,
                            onTap: () => _handleTabTap(1),
                            iconSize: 25.0,
                            selectedIconSize: 29.0,
                            iconOffset: const Offset(-2, 0),
                            selectedIconOffset: Offset.zero,
                          ),
                          if (favoritesCount > 0)
                            Positioned(
                              right: 12,
                              top: 10,
                              child: IgnorePointer(
                                child: Container(
                                  width: 20,
                                  height: 20,
                                  decoration: BoxDecoration(
                                    color: navColors.navBarBadgeBackground,
                                    shape: BoxShape.circle,
                                    border: Border.all(
                                      color: navColors.navBarBadgeBorder,
                                      width: 1.5,
                                    ),
                                  ),
                                  child: Center(
                                    child: Text(
                                      favoritesCount > 99
                                          ? '99+'
                                          : '$favoritesCount',
                                      style: TextStyle(
                                        color: navColors.navBarBadgeBorder,
                                        fontSize: 10,
                                        fontWeight: FontWeight.bold,
                                                        height: 1.0,
                                      ),
                                      textAlign: TextAlign.center,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                  // Profile icon
                  Expanded(
                    child: Center(
                      child: Transform.translate(
                        offset: const Offset(8, 0),
                        child: _NavigationItem(
                          icon: WorthifyIcons.profileOutline,
                          selectedIcon: WorthifyIcons.profileFilled,
                          label: 'Profile',
                          index: 2,
                          isSelected: selectedIndex == 2,
                          onTap: () => _handleTabTap(2),
                          iconSize: 25.0,
                          selectedIconSize: 25.0,
                        ),
                      ),
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

class _NavigationItem extends StatefulWidget {
  final IconData? icon;
  final IconData? selectedIcon;
  final String? svgIcon;
  final String? selectedSvgIcon;
  final String label;
  final int index;
  final bool isSelected;
  final VoidCallback onTap;
  final double? iconSize;
  final double? selectedIconSize;
  final double? topPadding;
  final Offset? selectedIconOffset;
  final Offset? iconOffset;

  const _NavigationItem({
    this.icon,
    this.selectedIcon,
    this.svgIcon,
    this.selectedSvgIcon,
    required this.label,
    required this.index,
    required this.isSelected,
    required this.onTap,
    this.iconSize,
    this.selectedIconSize,
    this.topPadding,
    this.selectedIconOffset,
    this.iconOffset,
  });

  @override
  State<_NavigationItem> createState() => _NavigationItemState();
}

class _NavigationItemState extends State<_NavigationItem>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _scaleAnimation;
  late Animation<double> _fadeAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 350),
      vsync: this,
    );

    _scaleAnimation = TweenSequence<double>([
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
    ]).animate(_controller);

    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _controller,
        curve: const Interval(0.0, 0.5, curve: Curves.easeIn),
      ),
    );

    if (widget.isSelected) {
      _controller.value = 1.0;
    }
  }

  @override
  void didUpdateWidget(_NavigationItem oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isSelected && !oldWidget.isSelected) {
      _controller.forward(from: 0.0);
    } else if (!widget.isSelected && oldWidget.isSelected) {
      _controller.value = 0.0;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () {
        HapticFeedback.mediumImpact();
        widget.onTap();
      },
      splashColor: Colors.transparent,
      highlightColor: Colors.transparent,
      child: SizedBox(
        width: 80,
        height: 48,
        child: Center(
          child: Padding(
            padding: EdgeInsets.only(top: widget.topPadding ?? 0.0),
            child: AnimatedBuilder(
              animation: _controller,
              builder: (context, child) {
                return Transform.scale(
                  scale: widget.isSelected ? _scaleAnimation.value : 1.0,
                  child: _buildIcon(),
                );
              },
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildIcon() {
    final navColors = context.navigation;
    final selectedColor = navColors.navBarActiveIcon;
    final unselectedColor = navColors.navBarInactiveIcon;
    final color = widget.isSelected ? selectedColor : unselectedColor;

    final size = widget.isSelected && widget.selectedIconSize != null
        ? widget.selectedIconSize!
        : (widget.iconSize ?? 28.0);

    Widget iconWidget;

    if (widget.svgIcon != null && widget.selectedSvgIcon != null) {
      iconWidget = AnimatedSwitcher(
        duration: widget.isSelected
            ? const Duration(milliseconds: 300)
            : Duration.zero,
        transitionBuilder: (child, animation) {
          return FadeTransition(
            opacity: animation,
            child: ScaleTransition(
              scale: Tween<double>(begin: 0.8, end: 1.0).animate(animation),
              child: child,
            ),
          );
        },
        child: SvgPicture.asset(
          widget.isSelected ? widget.selectedSvgIcon! : widget.svgIcon!,
          key: ValueKey(widget.isSelected),
          width: size,
          height: size,
          colorFilter: ColorFilter.mode(color, BlendMode.srcIn),
        ),
      );
    } else if (widget.icon != null && widget.selectedIcon != null) {
      iconWidget = AnimatedSwitcher(
        duration: widget.isSelected
            ? const Duration(milliseconds: 300)
            : Duration.zero,
        transitionBuilder: (child, animation) {
          return FadeTransition(
            opacity: animation,
            child: ScaleTransition(
              scale: Tween<double>(begin: 0.8, end: 1.0).animate(animation),
              child: child,
            ),
          );
        },
        child: Icon(
          widget.isSelected ? widget.selectedIcon! : widget.icon!,
          key: ValueKey(widget.isSelected),
          color: color,
          size: size,
        ),
      );
    } else {
      iconWidget = const SizedBox.shrink();
    }

    final Offset resolvedOffset = widget.isSelected
        ? (widget.selectedIconOffset ?? widget.iconOffset ?? Offset.zero)
        : (widget.iconOffset ?? Offset.zero);

    if (resolvedOffset != Offset.zero) {
      return Transform.translate(offset: resolvedOffset, child: iconWidget);
    }

    return iconWidget;
  }
}
