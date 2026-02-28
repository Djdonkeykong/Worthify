import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:easy_refresh/easy_refresh.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:flutter_slidable/flutter_slidable.dart';
import '../../../favorites/domain/providers/favorites_provider.dart';
import '../../../favorites/domain/models/favorite_item.dart';
import '../../../../../core/theme/theme_extensions.dart';
import '../../../../../core/theme/app_colors.dart';
import '../../../../../core/theme/worthify_icons.dart';
import '../../../../../shared/navigation/main_navigation.dart';
import '../../../../shared/widgets/worthify_circular_icon_button.dart';
import '../widgets/history_card.dart';

class WishlistPage extends ConsumerStatefulWidget {
  const WishlistPage({super.key});

  @override
  ConsumerState<WishlistPage> createState() => _WishlistPageState();
}

class _WishlistPageState extends ConsumerState<WishlistPage> {
  final ScrollController _scrollController = ScrollController();

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(scrollToTopTriggerProvider, (previous, next) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          0,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
    final spacing = context.spacing;
    final colorScheme = Theme.of(context).colorScheme;
    final favoritesAsync = ref.watch(favoritesProvider);

    final favorites = favoritesAsync.valueOrNull ?? [];
    final isInitialLoading =
        favoritesAsync.isLoading && !favoritesAsync.hasValue;
    final hasError = favoritesAsync.hasError && !favoritesAsync.hasValue;

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: true,
        automaticallyImplyLeading: false,
        title: Text(
          'Collection',
          style: TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.bold,
            fontFamily: 'PlusJakartaSans',
            color: colorScheme.onSurface,
            letterSpacing: -0.3,
          ),
        ),
      ),
      body: SafeArea(
        child: _buildFavoritesContent(
          isInitialLoading,
          hasError,
          favorites,
          spacing,
        ),
      ),
    );
  }

  Future<bool> _removeItem(String productId) async {
    final confirmed = await showDeleteConfirmDialog(
      context,
      title: 'Remove from collection',
      message: 'Are you sure you want to remove this artwork from your collection?',
      confirmLabel: 'Remove',
      cancelLabel: 'Cancel',
    );

    if (confirmed != true) return false;

    await ref.read(favoritesProvider.notifier).removeFavorite(productId);

    if (!mounted) return true;

    ScaffoldMessenger.of(context).clearSnackBars();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          'Removed from collection',
          style: context.snackTextStyle(
            merge: const TextStyle(fontFamily: 'PlusJakartaSans'),
          ),
        ),
        duration: const Duration(milliseconds: 2500),
      ),
    );
    return true;
  }

  Widget _buildFavoritesContent(bool isInitialLoading, bool hasError,
      List<FavoriteItem> favorites, dynamic spacing) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    if (isInitialLoading) {
      return Center(
        child: CircularProgressIndicator(
          valueColor:
              AlwaysStoppedAnimation<Color>(colorScheme.secondary),
          strokeWidth: 2,
        ),
      );
    }

    if (hasError) {
      final favoritesAsync = ref.watch(favoritesProvider);
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.error_outline,
                size: 64, color: colorScheme.error),
            const SizedBox(height: 16),
            Text(
              'Error: ${favoritesAsync.error}',
              style: textTheme.bodyMedium?.copyWith(
                color: colorScheme.onSurface,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: () {
                ref.read(favoritesProvider.notifier).refresh();
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

    if (favorites.isEmpty) {
      return _buildEmptyState(context, spacing);
    }

    return EasyRefresh(
      onRefresh: () async {
        await ref.read(favoritesProvider.notifier).refresh();
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
        safeArea: false,
        showMessage: false,
        showText: false,
        processedDuration: Duration.zero,
        succeededIcon: const SizedBox.shrink(),
        iconTheme: IconThemeData(
          color: AppColors.secondary,
          size: 24,
        ),
        backgroundColor: colorScheme.surface,
      ),
      child: ListView.builder(
        controller: _scrollController,
        padding: EdgeInsets.only(
          top: spacing.m,
          bottom: spacing.m,
        ),
        itemCount: favorites.length,
        itemBuilder: (context, index) {
          final favorite = favorites[index];
          return Padding(
            padding: EdgeInsets.only(bottom: spacing.m),
            child: Slidable(
              key: ValueKey(favorite.id),
              endActionPane: ActionPane(
                motion: const ScrollMotion(),
                extentRatio: 0.25,
                children: [
                  CustomSlidableAction(
                    onPressed: (_) async {
                      await _removeItem(favorite.productId);
                    },
                    backgroundColor: AppColors.secondary,
                    autoClose: false,
                    padding: EdgeInsets.zero,
                    child: SizedBox(
                      width: 86,
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                           Icon(
                             WorthifyIcons.trashBin,
                             color: Colors.white,
                             size: 18,
                           ),
                          const SizedBox(height: 4),
                          Text(
                            'Delete',
                            softWrap: false,
                            overflow: TextOverflow.visible,
                             style: TextStyle(
                               fontFamily: 'PlusJakartaSans',
                               fontWeight: FontWeight.w600,
                               fontSize: 13,
                               color: Colors.white,
                             ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
              child: _FavoriteCard(
                favorite: favorite,
                spacing: spacing,
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildEmptyState(BuildContext context, dynamic spacing) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Center(
      child: Padding(
        padding: EdgeInsets.all(spacing.xl),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: colorScheme.onSurface,
                  width: 1.5,
                ),
              ),
              child: Transform.translate(
                offset: const Offset(-2, 0),
                child: Icon(
                  WorthifyIcons.heartOutline,
                  size: 32,
                  color: colorScheme.onSurface,
                ),
              ),
            ),
            SizedBox(height: spacing.l),
            Text(
              'Save artworks you love to build your personal collection.',
              style: textTheme.bodyMedium?.copyWith(
                fontSize: 15,
                fontWeight: FontWeight.w500,
                color: colorScheme.onSurface,
                height: 1.35,
              ),
              textAlign: TextAlign.center,
            ),
            SizedBox(height: spacing.xl),
            GestureDetector(
              onTap: () {
                ref.read(selectedIndexProvider.notifier).state = 0;
              },
              child: Container(
                alignment: Alignment.center,
                padding: const EdgeInsets.only(
                  left: 24,
                  right: 24,
                  top: 16,
                  bottom: 18,
                ),
                constraints: const BoxConstraints(
                  minHeight: 52,
                  minWidth: 180,
                  maxWidth: 220,
                ),
                decoration: BoxDecoration(
                  color: AppColors.secondary,
                  borderRadius: BorderRadius.circular(28),
                ),
                child: Text(
                  'Scan Artwork',
                  style: textTheme.labelLarge?.copyWith(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: Colors.white,
                    height: 1.5,
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

class _FavoriteCard extends ConsumerWidget {
  final FavoriteItem favorite;
  final dynamic spacing;

  const _FavoriteCard({
    required this.favorite,
    required this.spacing,
  });

  Future<void> _openProductLink(BuildContext context, String productUrl) async {
    final uri = Uri.parse(productUrl);

    if (await canLaunchUrl(uri)) {
      final ok = await launchUrl(
        uri,
        mode: LaunchMode.inAppBrowserView,
      );
      if (ok) return;
    }

    if (await canLaunchUrl(uri)) {
      final ok = await launchUrl(
        uri,
        mode: LaunchMode.inAppWebView,
      );
      if (ok) return;
    }

    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } else {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Could not open product link',
              style: context.snackTextStyle(
                merge: const TextStyle(fontFamily: 'PlusJakartaSans'),
              ),
            ),
            duration: const Duration(seconds: 2),
          ),
        );
      }
    }
  }

  String _resolveProductUrl() {
    final candidates = [
      favorite.purchaseUrl,
    ];

    for (final candidate in candidates) {
      if (candidate == null) continue;
      final trimmed = candidate.trim();
      if (trimmed.isNotEmpty) {
        return trimmed;
      }
    }
    return '';
  }

  Rect _shareOriginForContext(BuildContext context) {
    final renderBox = context.findRenderObject() as RenderBox?;
    if (renderBox != null && renderBox.hasSize) {
      return renderBox.localToGlobal(Offset.zero) & renderBox.size;
    }
    final mediaSize = MediaQuery.of(context).size;
    return Rect.fromCenter(
      center: Offset(mediaSize.width / 2, mediaSize.height / 2),
      width: 1,
      height: 1,
    );
  }

  Future<void> _shareProductUrl(BuildContext context) async {
    HapticFeedback.mediumImpact();

    final productUrl = _resolveProductUrl();
    if (productUrl.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Product link unavailable',
            style: context.snackTextStyle(
              merge: const TextStyle(fontFamily: 'PlusJakartaSans'),
            ),
          ),
          duration: const Duration(seconds: 2),
        ),
      );
      return;
    }

    final shareOrigin = _shareOriginForContext(context);
    await Share.share(
      productUrl,
      subject: favorite.productName.isNotEmpty ? favorite.productName : null,
      sharePositionOrigin: shareOrigin,
    );
  }

  void _showShareMenu(BuildContext context) {
    final productBrand = favorite.brand;
    final productTitle = favorite.productName;
    final productUrl = _resolveProductUrl();

    showModalBottomSheet(
      context: context,
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        final messenger = ScaffoldMessenger.of(context);
        final shareTitle = '$productBrand $productTitle'.trim();
        final shareMessage = productUrl.isNotEmpty
            ? 'Check out this artwork I found on Worthify! $productUrl'
            : 'Check out this artwork I found on Worthify!';
        final shareOrigin = _shareOriginForContext(context);
        final colorScheme = Theme.of(context).colorScheme;

        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _SheetActionItem(
                  icon: Icons.share_outlined,
                  label: 'Share product',
                  onTap: () {
                    Navigator.pop(context);
                    Share.share(
                      shareMessage,
                      subject: shareTitle.isEmpty ? null : shareTitle,
                      sharePositionOrigin: shareOrigin,
                    );
                  },
                ),
                const SizedBox(height: 8),
                _SheetActionItem(
                  icon: Icons.link,
                  label: 'Copy link',
                  onTap: () {
                    Navigator.pop(context);
                    if (productUrl.isEmpty) {
                    messenger.hideCurrentSnackBar();
                    messenger.showSnackBar(
                      SnackBar(
                        content: Text(
                          'Link unavailable for this item.',
                          style: context.snackTextStyle(
                            merge: const TextStyle(fontFamily: 'PlusJakartaSans'),
                          ),
                        ),
                        duration: const Duration(seconds: 2),
                      ),
                    );
                    return;
                  }
                    Clipboard.setData(ClipboardData(text: productUrl));
                    messenger.hideCurrentSnackBar();
                    messenger.showSnackBar(
                      SnackBar(
                        content: Text(
                          'Link copied to clipboard',
                          style: context.snackTextStyle(
                            merge: const TextStyle(fontFamily: 'PlusJakartaSans'),
                          ),
                        ),
                        duration: const Duration(seconds: 2),
                      ),
                    );
                  },
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  void _rescanFavorite(BuildContext context) {
    final imageUrl = favorite.imageUrl.trim();
    if (imageUrl.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'No image available for this item.',
            style: context.snackTextStyle(
              merge: const TextStyle(fontFamily: 'PlusJakartaSans'),
            ),
          ),
          duration: const Duration(seconds: 2),
        ),
      );
      return;
    }

    final sourceUrl = (favorite.purchaseUrl?.isNotEmpty == true)
        ? favorite.purchaseUrl
        : imageUrl;

    // Rescan not available yet
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Rescan coming soon')),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final radius = context.radius;
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () async {
        final productUrl = _resolveProductUrl();

        if (productUrl.isEmpty) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                'Product link unavailable',
                style: context.snackTextStyle(
                  merge: const TextStyle(fontFamily: 'PlusJakartaSans'),
                ),
              ),
              duration: const Duration(seconds: 2),
            ),
          );
          return;
        }

        await _openProductLink(context, productUrl);
      },
      child: Container(
        width: double.infinity,
        padding: EdgeInsets.symmetric(horizontal: spacing.m, vertical: spacing.s * 0.75),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(radius.medium),
              child: SizedBox(
                width: 88,
                height: 88,
                child: CachedNetworkImage(
                  imageUrl: favorite.imageUrl,
                  fit: BoxFit.cover,
                  placeholder: (context, url) => Container(
                    color: colorScheme.surfaceVariant,
                  ),
                  errorWidget: (context, url, error) => Container(
                    color: colorScheme.surfaceVariant,
                    child: Icon(
                      Icons.error,
                      color: colorScheme.onSurfaceVariant,
                      size: 24,
                    ),
                  ),
                ),
              ),
            ),

            SizedBox(width: spacing.m),

            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              favorite.brand,
                              style: textTheme.titleMedium?.copyWith(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                                color: colorScheme.onSurface,
                                fontFamily: 'PlusJakartaSans',
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            const SizedBox(height: 6),
                            Text(
                              favorite.productName,
                              style: textTheme.bodyMedium?.copyWith(
                                fontSize: 14,
                                color: colorScheme.onSurfaceVariant,
                                fontFamily: 'PlusJakartaSans',
                              ),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 12),
                      Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          ActionIcon(
                            icon: Icons.share_outlined,
                            backgroundColor: colorScheme.onSurface,
                            iconColor: colorScheme.surface,
                            borderColor: null,
                            iconOffset: const Offset(-1, 0),
                            onTap: () => _shareProductUrl(context),
                          ),
                          const SizedBox(height: 8),
                          ActionIcon(
                            icon: Icons.more_horiz,
                            backgroundColor: Colors.transparent,
                            iconColor: colorScheme.secondary,
                            borderColor: colorScheme.secondary,
                            onTap: () => _showShareMenu(context),
                          ),
                        ],
                      ),
                    ],
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

class _SheetActionItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _SheetActionItem({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Row(
          children: [
            Icon(icon, color: colorScheme.onSurface, size: 24),
            const SizedBox(width: 24),
            Expanded(
              child: Text(
                label,
                style: textTheme.bodyLarge?.copyWith(
                  fontFamily: 'PlusJakartaSans',
                  fontWeight: FontWeight.w500,
                  fontSize: 16,
                  color: colorScheme.onSurface,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
