import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter_slidable/flutter_slidable.dart';
import 'package:http/http.dart' as http;
import 'package:image/image.dart' as img;
import 'package:image_picker/image_picker.dart';
import 'package:share_plus/share_plus.dart';
import 'package:worthify/src/shared/utils/native_share_helper.dart';
import 'package:timeago/timeago.dart' as timeago;

import '../../../../../core/theme/app_colors.dart';
import '../../../../../core/theme/theme_extensions.dart';
import '../../../../../core/theme/worthify_icons.dart';
import '../../../../shared/services/supabase_service.dart';
import '../../../../shared/widgets/worthify_circular_icon_button.dart';
import '../../domain/providers/history_provider.dart';

Future<bool?> showDeleteConfirmDialog(
  BuildContext context, {
  required String title,
  required String message,
  required String confirmLabel,
  required String cancelLabel,
}) {
  final theme = Theme.of(context);
  final colorScheme = theme.colorScheme;
  final spacing = context.spacing;
  final outlineColor = colorScheme.outline;

  return showDialog<bool>(
    context: context,
    barrierDismissible: true,
    barrierColor: Colors.black.withOpacity(0.45),
    builder: (dialogContext) {
      return Dialog(
        clipBehavior: Clip.antiAlias,
        backgroundColor: colorScheme.surface,
        insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(22),
        ),
        child: Padding(
          padding: EdgeInsets.fromLTRB(spacing.l, spacing.l, spacing.l, spacing.l),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Expanded(
                    child: Text(
                      title,
                      style: TextStyle(
                        fontFamily: 'PlusJakartaSans',
                        fontSize: 20,
                        fontWeight: FontWeight.w700,
                        color: colorScheme.onSurface,
                      ),
                    ),
                  ),
                  WorthifyCircularIconButton(
                    icon: Icons.close,
                    size: 40,
                    iconSize: 18,
                    onPressed: () => Navigator.of(dialogContext).pop(false),
                    semanticLabel: 'Close',
                  ),
                ],
              ),
              SizedBox(height: spacing.sm),
              Text(
                message,
                style: TextStyle(
                  fontFamily: 'PlusJakartaSans',
                  fontSize: 16,
                  fontWeight: FontWeight.w500,
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
              SizedBox(height: spacing.l),
              Row(
                children: [
                  Expanded(
                    child: SizedBox(
                      height: 56,
                      child: OutlinedButton(
                        onPressed: () => Navigator.of(dialogContext).pop(false),
                        style: OutlinedButton.styleFrom(
                          minimumSize: const Size.fromHeight(56),
                          side: BorderSide(color: outlineColor, width: 1.4),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(30),
                          ),
                          foregroundColor: colorScheme.onSurface,
                          textStyle: const TextStyle(
                            fontFamily: 'PlusJakartaSans',
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        child: Text(cancelLabel, textAlign: TextAlign.center),
                      ),
                    ),
                  ),
                  SizedBox(width: spacing.sm),
                  Expanded(
                    child: SizedBox(
                      height: 56,
                      child: ElevatedButton(
                        onPressed: () => Navigator.of(dialogContext).pop(true),
                        style: ElevatedButton.styleFrom(
                          elevation: 0,
                          minimumSize: const Size.fromHeight(56),
                          backgroundColor: AppColors.secondary,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(30),
                          ),
                          textStyle: const TextStyle(
                            fontFamily: 'PlusJakartaSans',
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        child: Text(confirmLabel, textAlign: TextAlign.center),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      );
    },
  );
}

class HistoryCard extends ConsumerWidget {
  final Map<String, dynamic> search;
  final dynamic spacing;
  final dynamic radius;
  static const Set<String> _worthifyOriginTypes = {
    'camera',
    'photos',
    'home',
  };
  static const Size _shareCardSize = Size(648, 1290);
  static const double _shareCardPixelRatio = 2.0;

  const HistoryCard({
    super.key,
    required this.search,
    required this.spacing,
    required this.radius,
  });

  Future<void> _shareSearch(BuildContext context) async {
    HapticFeedback.mediumImpact();

    final box = context.findRenderObject() as RenderBox?;
    final origin = (box != null && box.hasSize)
        ? box.localToGlobal(Offset.zero) & box.size
        : const Rect.fromLTWH(0, 0, 1, 1);

    final searchId = search['id'] as String?;
    if (searchId == null) {
      _showToast(context, 'Unable to share this search.');
      return;
    }

    final supabaseService = SupabaseService();
    final fullSearch = await supabaseService.getSearchById(searchId);
    if (fullSearch == null) {
      _showToast(context, 'Unable to load search details to share.');
      return;
    }

    final payload = _buildSharePayload(fullSearch);
    final shareItems = _buildShareItems(fullSearch);
    final cloudinaryUrl =
        (fullSearch['cloudinary_url'] as String?)?.trim() ?? '';
    XFile? shareImage;
    if (cloudinaryUrl.isNotEmpty) {
      shareImage = await _downloadAndSquare(cloudinaryUrl);
    }

    final ImageProvider<Object>? heroProvider;
    if (shareImage != null) {
      heroProvider = FileImage(File(shareImage.path));
    } else if (cloudinaryUrl.isNotEmpty) {
      heroProvider = CachedNetworkImageProvider(cloudinaryUrl);
    } else {
      heroProvider = null;
    }
    final shareCard = await _buildShareCardFile(
      context,
      heroImage: heroProvider,
      shareItems: shareItems,
    );

    final primaryFile = shareCard ?? shareImage;

    if (primaryFile != null) {
      final handled = await NativeShareHelper.shareImageFirst(
        file: primaryFile,
        text: payload.message,
        subject: payload.subject,
        origin: origin,
        thumbnailPath: shareImage?.path,
      );
      if (!handled) {
        await Share.shareXFiles(
          [primaryFile],
          text: payload.message,
          subject: payload.subject,
          sharePositionOrigin: origin,
        );
      }
    } else {
      await Share.share(
        payload.message,
        subject: payload.subject,
        sharePositionOrigin: origin,
      );
    }
  }

  ({String subject, String message}) _buildSharePayload(
      Map<String, dynamic> searchData) {
    return (
      subject: 'Worthify Artwork Share',
      message: 'Get Worthify and try for yourself: https://worthify.app',
    );
  }

  List<_ShareCardItem> _buildShareItems(Map<String, dynamic> searchData) {
    final results = _extractSearchResults(searchData['search_results']);
    if (results.isEmpty) return const [];

    final items = <_ShareCardItem>[];
    for (final result in results.take(5)) {
      final item = _ShareCardItem.fromSearch(result);
      if (item != null) {
        items.add(item);
      }
    }
    return items;
  }

  List<Map<String, dynamic>> _extractSearchResults(dynamic rawResults) {
    dynamic decoded = rawResults;
    if (rawResults is String) {
      try {
        decoded = jsonDecode(rawResults);
      } catch (_) {
        return const [];
      }
    }

    if (decoded is List) {
      final results = <Map<String, dynamic>>[];
      for (final item in decoded) {
        if (item is Map) {
          results.add(Map<String, dynamic>.from(item));
        }
      }
      return results;
    }

    return const [];
  }

  Future<XFile?> _downloadAndSquare(String url) async {
    try {
      final response = await http.get(Uri.parse(url));
      if (response.statusCode != 200 || response.bodyBytes.isEmpty) return null;

      final decoded = img.decodeImage(response.bodyBytes);
      if (decoded == null) return null;

      final maxDim =
          decoded.width > decoded.height ? decoded.width : decoded.height;
      const cap = 1200;
      final targetSize = maxDim > cap ? cap : maxDim;
      final minDim =
          decoded.width < decoded.height ? decoded.width : decoded.height;
      final scale = targetSize / minDim;

      final resized = img.copyResize(
        decoded,
        width: (decoded.width * scale).round(),
        height: (decoded.height * scale).round(),
      );

      final cropX =
          ((resized.width - targetSize) / 2).round().clamp(0, resized.width - targetSize);
      final cropY = ((resized.height - targetSize) / 2)
          .round()
          .clamp(0, resized.height - targetSize);

      final square = img.copyCrop(
        resized,
        x: cropX,
        y: cropY,
        width: targetSize,
        height: targetSize,
      );

      final jpg = img.encodeJpg(square, quality: 90);
      final tempPath = '${Directory.systemTemp.path}/worthify_artwork_search.jpg';
      await File(tempPath).writeAsBytes(jpg, flush: true);
      return XFile(
        tempPath,
        mimeType: 'image/jpeg',
        name: 'worthify_artwork_search.jpg',
      );
    } catch (e) {
      debugPrint('Error preparing share image: $e');
      return null;
    }
  }

  Future<XFile?> _buildShareCardFile(
    BuildContext context, {
    required ImageProvider<Object>? heroImage,
    required List<_ShareCardItem> shareItems,
  }) async {
    try {
      await _precacheShareImages(
        context,
        [
          const AssetImage('assets/images/arrow-share-card.png'),
          heroImage,
          ...shareItems.map((item) => item.imageProvider),
        ],
      );
      final bytes = await _captureShareCardBytes(
        context,
        heroImage: heroImage,
        shareItems: shareItems,
      );
      if (bytes == null || bytes.isEmpty) return null;

      final filePath =
          '${Directory.systemTemp.path}/worthify_share_artwork.png';
      final file = File(filePath);
      await file.writeAsBytes(bytes, flush: true);
      return XFile(
        filePath,
        mimeType: 'image/png',
        name: 'worthify_share_artwork.png',
      );
    } catch (e) {
      debugPrint('Error creating share card: $e');
      return null;
    }
  }

  Future<void> _precacheShareImages(
    BuildContext context,
    List<ImageProvider<Object>?> images,
  ) async {
    for (final image in images) {
      if (image == null) continue;
      try {
        await precacheImage(image, context);
      } catch (e) {
        debugPrint('Error precaching share image: $e');
      }
    }
  }

  Future<Uint8List?> _captureShareCardBytes(
    BuildContext context, {
    required ImageProvider<Object>? heroImage,
    required List<_ShareCardItem> shareItems,
  }) async {
    final overlay = Overlay.of(context, rootOverlay: true);
    if (overlay == null) return null;

    final boundaryKey = GlobalKey();
    late OverlayEntry entry;

    entry = OverlayEntry(
      builder: (overlayContext) {
        return Positioned(
          left: -_shareCardSize.width - 20,
          top: 0,
          child: Material(
            type: MaterialType.transparency,
            child: MediaQuery(
              data: MediaQuery.of(overlayContext).copyWith(
                size: _shareCardSize,
              ),
              child: Directionality(
                textDirection: TextDirection.ltr,
                child: RepaintBoundary(
                  key: boundaryKey,
                  child: SizedBox(
                    width: _shareCardSize.width,
                    height: _shareCardSize.height,
                    child: _HistoryShareCard(
                      heroImage: heroImage,
                      shareItems: shareItems,
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );

    overlay.insert(entry);

    try {
      await Future.delayed(const Duration(milliseconds: 30));
      final boundary =
          boundaryKey.currentContext?.findRenderObject() as RenderRepaintBoundary?;
      if (boundary == null) return null;
      final image = await boundary.toImage(pixelRatio: _shareCardPixelRatio);
      final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      if (byteData == null) return null;
      return byteData.buffer.asUint8List();
    } catch (e) {
      debugPrint('Error capturing share card: $e');
      return null;
    } finally {
      entry.remove();
    }
  }

  void _showToast(BuildContext context, String message) {
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          message,
          style: context.snackTextStyle(
            merge: const TextStyle(fontFamily: 'PlusJakartaSans'),
          ),
        ),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  Future<bool> _deleteSearch(BuildContext context, WidgetRef ref) async {
    final searchId = search['id'] as String?;
    if (searchId == null) {
      _showToast(context, 'Unable to delete this search.');
      return false;
    }

    final confirmed = await showDeleteConfirmDialog(
      context,
      title: 'Delete search',
      message: 'Are you sure you want to remove this search from your history?',
      confirmLabel: 'Delete',
      cancelLabel: 'Cancel',
    );

    if (confirmed != true) return false;

    final supabaseService = SupabaseService();
    final success = await supabaseService.deleteSearch(searchId);

    if (success) {
      ref.invalidate(historyProvider);
      if (context.mounted) {
        _showToast(context, 'Search deleted from history');
      }
      return true;
    } else {
      if (context.mounted) {
        _showToast(context, 'Failed to delete search');
      }
      return false;
    }
  }

  Future<void> _rescanSearch(BuildContext context) async {
    final cloudinaryUrl = search['cloudinary_url'] as String?;
    if (cloudinaryUrl == null || cloudinaryUrl.isEmpty) {
      _showToast(context, 'No image available for re-search.');
      return;
    }

    final sourceUrl = (search['source_url'] as String?) ?? cloudinaryUrl;

    // Rescan not available yet
  }

  String _getSourceLabel() {
    final rawType = (search['search_type'] as String?)?.trim();
    final type = rawType?.toLowerCase();
    final sourceUrl = (search['source_url'] as String?)?.toLowerCase() ?? '';

    switch (type) {
      case 'instagram':
        return 'Instagram';
      case 'tiktok':
        return 'TikTok';
      case 'pinterest':
        return 'Pinterest';
      case 'twitter':
        return 'Twitter';
      case 'facebook':
        return 'Facebook';
      case 'youtube':
        final isShorts = sourceUrl.contains('youtube.com/shorts') ||
            sourceUrl.contains('youtu.be/shorts');
        return isShorts ? 'YouTube Shorts' : 'YouTube';
      case 'chrome':
        return 'Chrome';
      case 'firefox':
        return 'Firefox';
      case 'safari':
        return 'Safari';
      case 'web':
      case 'browser':
        if (sourceUrl.contains('imdb.com') || sourceUrl.contains('m.imdb.com')) {
          return 'IMDb';
        }
        return 'Web';
      case 'imdb':
        return 'IMDb';
      case 'share':
      case 'share_extension':
      case 'shareextension':
        return 'Worthify';
    }

    if (type == null || _worthifyOriginTypes.contains(type)) {
      return 'Worthify';
    }

    if (rawType != null && rawType.isNotEmpty) {
      return rawType
          .split(RegExp(r'[_-]+'))
          .map((word) =>
              word.isEmpty ? '' : '${word[0].toUpperCase()}${word.substring(1)}')
          .join(' ');
    }

    return 'Worthify';
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final double cardHeight = 88.0 + (spacing.s * 1.5);
    final cardRadius = BorderRadius.circular(radius.medium);
    final cloudinaryUrl = search['cloudinary_url'] as String?;
    final totalResults = (search['total_results'] as num?)?.toInt() ?? 0;
    final createdAt = search['created_at'] as String?;
    final sourceUsername = search['source_username'] as String?;
    final isSaved = search['is_saved'] as bool? ?? false;

    DateTime? createdDate;
    if (createdAt != null) {
      try {
        createdDate = DateTime.parse(createdAt);
      } catch (e) {
        debugPrint('Error parsing date: $e');
      }
    }

    final trimmedUsername = sourceUsername?.trim();
    final hasUsername = trimmedUsername != null && trimmedUsername.isNotEmpty;
    final createdLabel = createdDate != null ? timeago.format(createdDate) : null;
    final hasResults = totalResults > 0;

    return Slidable(
      key: ValueKey(search['id'] ?? search['created_at'] ?? cloudinaryUrl ?? UniqueKey()),
      endActionPane: ActionPane(
        extentRatio: 0.25,
        motion: const ScrollMotion(),
        children: [
          CustomSlidableAction(
            onPressed: (_) async {
              await _deleteSearch(context, ref);
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
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () async {
          if (!hasResults) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                  'No results to show for this search.',
                  style: context.snackTextStyle(
                    merge: const TextStyle(fontFamily: 'PlusJakartaSans'),
                  ),
                ),
                duration: const Duration(seconds: 2),
              ),
            );
            return;
          }

          final searchId = search['id'] as String?;
          if (searchId == null) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                  'Unable to load search results',
                  style: context.snackTextStyle(
                    merge: const TextStyle(fontFamily: 'PlusJakartaSans'),
                  ),
                ),
                duration: const Duration(seconds: 2),
              ),
            );
            return;
          }

          // Tap to view — coming soon
        },
        child: Container(
          height: cardHeight,
          padding: EdgeInsets.symmetric(horizontal: spacing.m, vertical: spacing.s * 0.75),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(radius.medium),
                child: SizedBox(
                  width: 88,
                  height: 88,
                  child: cloudinaryUrl != null
                      ? CachedNetworkImage(
                          imageUrl: cloudinaryUrl,
                          width: 88,
                          height: 88,
                          fit: BoxFit.cover,
                          placeholder: (context, url) => Container(
                            color: colorScheme.surfaceVariant,
                            width: 88,
                            height: 88,
                          ),
                          errorWidget: (context, url, error) => Container(
                            color: colorScheme.surfaceVariant,
                            width: 88,
                            height: 88,
                            child: Icon(
                              Icons.image,
                              color: colorScheme.onSurfaceVariant,
                              size: 24,
                            ),
                          ),
                        )
                      : Container(
                          width: 88,
                          height: 88,
                          color: colorScheme.surfaceVariant,
                          child: Icon(
                            Icons.image,
                            color: colorScheme.onSurfaceVariant,
                            size: 24,
                          ),
                        ),
                ),
              ),
              SizedBox(width: spacing.m),
              Expanded(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _getSourceLabel(),
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
                        if (hasUsername) ...[
                          Text(
                            '@$trimmedUsername',
                            style: textTheme.bodyMedium?.copyWith(
                              fontSize: 14,
                              color: colorScheme.onSurfaceVariant,
                              fontFamily: 'PlusJakartaSans',
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 4),
                        ],
                        Text(
                          totalResults == 1
                              ? '1 artwork found'
                              : '$totalResults artworks found',
                          style: textTheme.bodyMedium?.copyWith(
                            fontSize: 14,
                            color: colorScheme.onSurfaceVariant,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        if (createdLabel != null) ...[
                          const SizedBox(height: 4),
                          Text(
                            createdLabel,
                            style: textTheme.bodySmall?.copyWith(
                              fontSize: 12,
                              color: colorScheme.onSurfaceVariant.withOpacity(0.7),
                              fontFamily: 'PlusJakartaSans',
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ],
                    ),
                    ),
                    const SizedBox(width: 12),
                    Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        ActionIcon(
                          icon: Icons.search_rounded,
                          backgroundColor: colorScheme.secondary,
                          iconColor: colorScheme.onSecondary,
                          onTap: () => _rescanSearch(context),
                        ),
                        const SizedBox(height: 8),
                        ActionIcon(
                          icon: Icons.share_outlined,
                          backgroundColor: Colors.transparent,
                          iconColor: colorScheme.secondary,
                          borderColor: colorScheme.secondary,
                          iconOffset: const Offset(-1, 0),
                          onTap: () => _shareSearch(context),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class ActionIcon extends StatelessWidget {
  final IconData icon;
  final Color backgroundColor;
  final Color iconColor;
  final Color? borderColor;
  final VoidCallback onTap;
  final Offset iconOffset;

  const ActionIcon({
    super.key,
    required this.icon,
    required this.backgroundColor,
    required this.iconColor,
    this.borderColor,
    this.iconOffset = Offset.zero,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(
          color: backgroundColor,
          borderRadius: BorderRadius.circular(10),
          border: borderColor != null
              ? Border.all(color: borderColor!, width: 1.3)
              : null,
        ),
        child: Transform.translate(
          offset: iconOffset,
          child: Icon(
            icon,
            color: iconColor,
            size: 16,
          ),
        ),
      ),
    );
  }
}

class _HistoryShareCard extends StatelessWidget {
  final ImageProvider<Object>? heroImage;
  final List<_ShareCardItem> shareItems;

  const _HistoryShareCard({
    required this.heroImage,
    required this.shareItems,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final height = constraints.maxHeight;
        final scale = width / 1080;
        double s(double value) => value * scale;

        final cardPadding = s(40);
        final heroPadding = s(240);
        final heroHeight = s(600);
        final heroRadius = s(72);

        return Container(
          width: width,
          height: height,
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(s(96)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.08),
                blurRadius: s(40),
                offset: Offset(0, s(20)),
              ),
            ],
          ),
          child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.center,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  SizedBox(height: s(60)),

                  Text(
                    'I snapped this',
                    style: TextStyle(
                      fontFamily: 'PlusJakartaSans',
                      fontSize: s(48),
                      fontWeight: FontWeight.w600,
                      color: const Color(0xFF2B2B2B),
                      letterSpacing: 0.3,
                    ),
                  ),

                  SizedBox(height: s(32)),

                  Padding(
                    padding: EdgeInsets.symmetric(horizontal: heroPadding),
                    child: Container(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(heroRadius),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.20),
                            blurRadius: s(40),
                            offset: Offset(0, s(16)),
                          ),
                        ],
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(heroRadius),
                        child: Container(
                          height: heroHeight,
                          width: double.infinity,
                          decoration: BoxDecoration(
                            color: const Color(0xFFF5F5F5),
                            borderRadius: BorderRadius.circular(heroRadius),
                          ),
                          child: heroImage != null
                              ? Image(
                                  image: heroImage!,
                                  fit: BoxFit.fitWidth,
                                )
                              : const Icon(
                                  Icons.image_rounded,
                                  color: Color(0xFFBDBDBD),
                                  size: 64,
                                ),
                        ),
                      ),
                    ),
                  ),

                  SizedBox(height: s(32)),

                  SizedBox(
                    height: s(120),
                    child: Image.asset(
                      'assets/images/arrow-share-card.png',
                      height: s(120),
                      fit: BoxFit.contain,
                      errorBuilder: (context, error, stackTrace) {
                        return Container(
                          height: s(120),
                          width: s(100),
                          color: Colors.red.withOpacity(0.3),
                          child: const Center(child: Icon(Icons.error)),
                        );
                      },
                    ),
                  ),

                  SizedBox(height: s(24)),

                  Text(
                    'Top Visual Matches',
                    style: TextStyle(
                      fontFamily: 'PlusJakartaSans',
                      fontSize: s(48),
                      fontWeight: FontWeight.w600,
                      color: const Color(0xFF2B2B2B),
                      letterSpacing: 0.3,
                    ),
                  ),

                  SizedBox(height: s(40)),

                  if (shareItems.isNotEmpty)
                    Center(
                      child: SizedBox(
                        height: s(480),
                        width: width,
                        child: Stack(
                          alignment: Alignment.center,
                          clipBehavior: Clip.none,
                          children: [
                            for (int i = 0; i < shareItems.take(3).length; i++)
                              Positioned(
                                left: (width - s(680)) / 2 + (i * s(170)),
                                top: i * s(30),
                                child: _StackedProductImage(
                                  item: shareItems[i],
                                  size: s(390),
                                  radius: s(68),
                                  elevation: 8 + (i * 3).toDouble(),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),

                  SizedBox(height: s(100)),

                  Image.asset(
                    'assets/images/logo.png',
                    height: s(64),
                    fit: BoxFit.contain,
                  ),

                  SizedBox(height: s(80)),
                ],
              ),
        );
      },
    );
  }
}

class _StackedProductImage extends StatelessWidget {
  final _ShareCardItem item;
  final double size;
  final double radius;
  final double elevation;

  const _StackedProductImage({
    required this.item,
    required this.size,
    required this.radius,
    required this.elevation,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(radius),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.12),
            blurRadius: elevation * 2,
            offset: Offset(0, elevation),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(radius),
        child: item.imageProvider != null
            ? Image(
                image: item.imageProvider!,
                fit: BoxFit.cover,
              )
            : Container(
                color: const Color(0xFFF5F5F5),
                child: Icon(
                  Icons.image_rounded,
                  color: const Color(0xFFCCCCCC),
                  size: size * 0.4,
                ),
              ),
      ),
    );
  }
}

class _ShareCardItem {
  final String brand;
  final String title;
  final String? priceText;
  final ImageProvider<Object>? imageProvider;

  const _ShareCardItem({
    required this.brand,
    required this.title,
    required this.priceText,
    required this.imageProvider,
  });

  static _ShareCardItem? fromSearch(Map<String, dynamic> data) {
    final brand =
        (data['brand'] as String?)?.trim().isNotEmpty == true
            ? (data['brand'] as String).trim()
            : 'Brand';
    final title =
        (data['product_name'] as String?)?.trim().isNotEmpty == true
            ? (data['product_name'] as String).trim()
            : 'Item';
    final priceText = _formatSharePrice(data);
    final imageUrl = (data['image_url'] as String?)?.trim();
    final imageProvider = imageUrl != null && imageUrl.isNotEmpty
        ? CachedNetworkImageProvider(imageUrl)
        : null;

    return _ShareCardItem(
      brand: brand,
      title: title,
      priceText: priceText,
      imageProvider: imageProvider,
    );
  }
}

String? _formatSharePrice(Map<String, dynamic> data) {
  String? currency = (data['currency'] as String?)?.toUpperCase();
  String? display;
  final priceData = data['price'];

  if (priceData is Map<String, dynamic>) {
    display = (priceData['display'] as String?) ??
        (priceData['text'] as String?) ??
        (priceData['raw'] as String?) ??
        (priceData['formatted'] as String?);
    currency ??= (priceData['currency'] as String?)?.toUpperCase();
    final extracted = (priceData['extracted_value'] as num?)?.toDouble();
    if ((display == null || display.isEmpty) && extracted != null) {
      display = _formatCurrency(extracted, currency);
    }
  } else if (priceData is num) {
    display = _formatCurrency(priceData.toDouble(), currency);
  } else if (priceData is String) {
    display = priceData.trim();
  }

  display ??= (data['price_display'] as String?) ??
      (data['price_text'] as String?) ??
      (data['price_raw'] as String?) ??
      (data['price_formatted'] as String?);

  return display != null && display.trim().isNotEmpty ? display.trim() : null;
}

String _formatCurrency(double value, String? currency) {
  final formatted = value.toStringAsFixed(2);
  if (currency == null || currency.isEmpty || currency == 'USD') {
    return '\$$formatted';
  }
  return '$currency $formatted';
}
