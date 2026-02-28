import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'dart:convert';
import 'package:image/image.dart' as img;
import 'package:http/http.dart' as http;
import 'package:html/parser.dart' as html_parser;
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../core/constants/app_constants.dart';

class InstagramService {
  static bool lastDownloadWasCacheHit = false;

  static const String _userAgent =
      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36';

  static const String _jinaProxyBase = 'https://r.jina.ai/';

  /// Apify Instagram scraper - Returns a single high-quality image
  static Future<List<XFile>> _apifyInstagramScraper(
    String instagramUrl,
  ) async {
    print('Attempting Apify Instagram scraper for URL: $instagramUrl');

    final apifyToken = AppConstants.apifyApiToken;
    if (apifyToken.isEmpty) {
      print('Apify API token not configured');
      return [];
    }

    // Apify Instagram Post Scraper actor
    final uri = Uri.parse(
      'https://api.apify.com/v2/acts/nH2AHrwxeTRJoN5hX/run-sync-get-dataset-items'
      '?token=$apifyToken&timeout=60&memory=2048',
    );

    final payload = {
      'resultsLimit': 1,
      'skipPinnedPosts': false,
      'username': [instagramUrl],
    };

    print('Apify Instagram request (timeout=60s)');

    http.Response response;
    try {
      response = await http
          .post(
            uri,
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode(payload),
          )
          .timeout(const Duration(seconds: 65));
    } on TimeoutException {
      print('Apify Instagram request timed out');
      return [];
    } catch (error) {
      print('Apify Instagram request error: ${error.toString()}');
      return [];
    }

    if (response.statusCode < 200 || response.statusCode >= 300) {
      print('Apify Instagram failed with status ${response.statusCode}');
      return [];
    }

    final result =
        await _extractImagesFromApifyResponse(response.body, instagramUrl);
    if (result.isNotEmpty) {
      return result;
    }

    print('No image URL found in Apify results');
    return [];
  }

  static Future<List<XFile>> _extractImagesFromApifyResponse(
    String responseBody,
    String instagramUrl,
  ) async {
    try {
      final List<dynamic> items = jsonDecode(responseBody) as List<dynamic>;

      if (items.isEmpty) {
        print('Apify returned empty results array');
        return [];
      }

      // Get first item from results
      final item = items.first as Map<String, dynamic>;

      // Try displayUrl first (highest quality)
      String? imageUrl = item['displayUrl'] as String?;

      if (imageUrl != null && imageUrl.isNotEmpty) {
        print('Found Instagram displayUrl from Apify: ${_previewUrl(imageUrl)}');

        final downloadedImage = await _downloadImage(imageUrl);
        if (downloadedImage != null) {
          // Save to cache for future requests
          await _saveToInstagramCache(instagramUrl, imageUrl, 'apify_display_url');
          return [downloadedImage];
        }
      }

      // Fallback: try images array if displayUrl failed
      final images = item['images'] as List<dynamic>?;
      if (images != null && images.isNotEmpty) {
        for (final img in images) {
          if (img is String && img.isNotEmpty) {
            print('Found Instagram image from Apify images array: ${_previewUrl(img)}');
            final downloadedImage = await _downloadImage(img);
            if (downloadedImage != null) {
              await _saveToInstagramCache(instagramUrl, img, 'apify_images_array');
              return [downloadedImage];
            }
          }
        }
      }

      // Fallback: check childPosts for carousel posts
      final childPosts = item['childPosts'] as List<dynamic>?;
      if (childPosts != null && childPosts.isNotEmpty) {
        for (final child in childPosts) {
          if (child is Map<String, dynamic>) {
            final childDisplayUrl = child['displayUrl'] as String?;
            if (childDisplayUrl != null && childDisplayUrl.isNotEmpty) {
              print('Found Instagram childPost displayUrl from Apify: ${_previewUrl(childDisplayUrl)}');
              final downloadedImage = await _downloadImage(childDisplayUrl);
              if (downloadedImage != null) {
                await _saveToInstagramCache(instagramUrl, childDisplayUrl, 'apify_child_display_url');
                return [downloadedImage];
              }
            }
          }
        }
      }

      print('No valid image URLs found in Apify response');
      return [];
    } catch (e) {
      print('Error parsing Apify response: $e');
      return [];
    }
  }

  static String _previewUrl(String url) {
    return url.length <= 80 ? url : '${url.substring(0, 80)}...';
  }

  static String _sanitizeTikTokUrl(String value) {
    return value
        .replaceAll('\\u0026', '&')
        .replaceAll('\\/', '/')
        .replaceAll('&amp;', '&')
        .trim();
  }

  /// Download image from URL and return as XFile
  static Future<XFile?> downloadExternalImage(String imageUrl) =>
      _downloadImage(imageUrl);

  static Future<XFile?> _downloadImage(
    String imageUrl, {
    double? cropToAspectRatio,
  }) async {
    try {
      print('Downloading image from: $imageUrl');

      final uri = Uri.tryParse(imageUrl);
      final host = uri?.host.toLowerCase() ?? '';
      String refererHeader = 'https://www.instagram.com/';
      if (!host.contains('insta')) {
        refererHeader = uri != null ? '${uri.scheme}://${uri.host}/' : '';
      }

      final imageResponse = await http.get(
        Uri.parse(imageUrl),
        headers: {
          'User-Agent': _userAgent,
          if (refererHeader.isNotEmpty) 'Referer': refererHeader,
        },
      ).timeout(const Duration(seconds: 10)); // Timeout for image download

      if (imageResponse.statusCode != 200) {
        print('Failed to download image: ${imageResponse.statusCode}');
        return null;
      }

      print(
        'Image downloaded successfully, size: ${imageResponse.bodyBytes.length} bytes',
      );

      // Validate that the payload is actually an image
      final decodedImage = img.decodeImage(imageResponse.bodyBytes);
      if (decodedImage == null) {
        print('Downloaded data is not a valid image');
        return null;
      }

      // Optionally crop to a target aspect ratio (e.g., 9:16 for Shorts thumbnails)
      Uint8List imageBytes = Uint8List.fromList(imageResponse.bodyBytes);
      if (cropToAspectRatio != null) {
        final decoded = img.decodeImage(imageBytes);
        if (decoded != null && decoded.width > 0 && decoded.height > 0) {
          final currentAspect = decoded.width / decoded.height;
          if ((currentAspect - cropToAspectRatio).abs() > 0.01) {
            // Too wide: crop width; too tall: crop height.
            int cropWidth = decoded.width;
            int cropHeight = decoded.height;
            int offsetX = 0;
            int offsetY = 0;

            if (currentAspect > cropToAspectRatio) {
              cropWidth = (decoded.height * cropToAspectRatio).round();
              offsetX = ((decoded.width - cropWidth) / 2)
                  .round()
                  .clamp(0, decoded.width - cropWidth)
                  .toInt();
            } else {
              cropHeight = (decoded.width / cropToAspectRatio).round();
              offsetY = ((decoded.height - cropHeight) / 2)
                  .round()
                  .clamp(0, decoded.height - cropHeight)
                  .toInt();
            }

            final cropped = img.copyCrop(
              decoded,
              x: offsetX,
              y: offsetY,
              width: cropWidth,
              height: cropHeight,
            );
            imageBytes = Uint8List.fromList(
              img.encodeJpg(cropped, quality: 90),
            );
            print(
              'Cropped image to aspect ${cropToAspectRatio.toStringAsFixed(2)} -> ${cropWidth}x$cropHeight',
            );
          }
        } else {
          print('Skipping crop: unable to decode image');
        }
      }

      // Save image to temporary file
      final tempDir = Directory.systemTemp;
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final fileName = 'instagram_image_$timestamp.jpg';
      final file = File('${tempDir.path}/$fileName');

      await file.writeAsBytes(imageBytes);
      print('Image saved to: ${file.path}');

      return XFile(file.path);
    } catch (e) {
      print('Error downloading image: $e');
      return null;
    }
  }

  /// Normalizes Instagram URL by removing query parameters for better cache matching
  static String _normalizeInstagramUrl(String url) {
    try {
      final uri = Uri.parse(url);
      // Keep only the path, remove query params like ?igsh=...
      return '${uri.scheme}://${uri.host}${uri.path}';
    } catch (e) {
      return url;
    }
  }

  /// Checks cache for Instagram URL and returns cached image URL if available
  static Future<String?> _checkInstagramCache(String instagramUrl) async {
    try {
      final normalized = _normalizeInstagramUrl(instagramUrl);
      print('Checking cache for Instagram URL: $normalized');

      final supabase = Supabase.instance.client;
      final response = await supabase
          .from('instagram_url_cache')
          .select('image_url, id')
          .or('instagram_url.eq.$instagramUrl,normalized_url.eq.$normalized')
          .limit(1)
          .maybeSingle();

      if (response != null) {
        final imageUrl = response['image_url'] as String;
        final id = response['id'];
        print('✅ Cache HIT! Found cached image URL');

        // Update access tracking
        await supabase
            .from('instagram_url_cache')
            .update({'last_accessed_at': DateTime.now().toIso8601String()}).eq(
                'id', id);

        return imageUrl;
      }

      print('Cache MISS - will fetch from Instagram');
      return null;
    } catch (e) {
      print('Error checking Instagram cache: $e');
      return null;
    }
  }

  /// Saves Instagram URL and extracted image URL to cache
  static Future<void> _saveToInstagramCache(
    String instagramUrl,
    String imageUrl,
    String extractionMethod,
  ) async {
    try {
      final normalized = _normalizeInstagramUrl(instagramUrl);
      final supabase = Supabase.instance.client;

      await supabase.from('instagram_url_cache').upsert({
        'instagram_url': instagramUrl,
        'normalized_url': normalized,
        'image_url': imageUrl,
        'extraction_method': extractionMethod,
        'created_at': DateTime.now().toIso8601String(),
        'last_accessed_at': DateTime.now().toIso8601String(),
      }, onConflict: 'normalized_url');

      print('✅ Saved to Instagram cache: $normalized -> $imageUrl');
    } catch (e) {
      print('Error saving to Instagram cache: $e');
    }
  }

  /// Extracts image URLs from Instagram post URL and downloads the images
  /// Returns a list of XFile objects - single item for regular posts, multiple items for carousels
  static Future<List<XFile>> downloadImageFromInstagramUrl(
    String instagramUrl,
  ) async {
    try {
      print('Fetching Instagram post: $instagramUrl');
      lastDownloadWasCacheHit = false;

      final apifyToken = AppConstants.apifyApiToken;
      if (apifyToken.isEmpty) {
        print('❌ Apify API token not configured');
        return [];
      }

      // Check cache first
      final cachedImageUrl = await _checkInstagramCache(instagramUrl);
      if (cachedImageUrl != null) {
        print('📦 Using cached image URL - saving Apify credits!');
        lastDownloadWasCacheHit = true;
        final cachedImage = await _downloadImage(cachedImageUrl);
        if (cachedImage != null) {
          return [cachedImage];
        }
        print('⚠️ Cached image download failed, falling back to Apify');
        lastDownloadWasCacheHit = false;
      }

      // Cache miss or failed - scrape Instagram via Apify
      print('Fetching from Apify API...');
      final result = await _apifyInstagramScraper(instagramUrl);
      if (result.isNotEmpty) {
        print(
          '✅ Successfully extracted ${result.length} image(s) using Apify!',
        );
        return result;
      }

      print('❌ Apify failed to extract images');
      return [];
    } catch (e) {
      print('❌ Error downloading Instagram images: $e');
      return [];
    }
  }

  /// Checks if a URL is an Instagram post URL
  static bool isInstagramUrl(String url) {
    return url.contains('instagram.com/p/') ||
        url.contains('instagram.com/reel/');
  }

  /// Checks if a URL is an X/Twitter post URL
  static bool isXUrl(String url) {
    final lower = url.toLowerCase();
    final hasDomain = lower.contains('x.com') || lower.contains('twitter.com');
    if (!hasDomain) return false;
    return lower.contains('/status/') ||
        lower.contains('/statuses/') ||
        lower.contains('/i/web/status/') ||
        lower.contains('/i/status/') ||
        lower.contains('/photo/');
  }

  /// Checks if a URL is a Facebook share/photo/video URL
  static bool isFacebookUrl(String url) {
    final lower = url.toLowerCase();
    final hasDomain =
        lower.contains('facebook.com') || lower.contains('fb.watch');
    if (!hasDomain) return false;
    return lower.contains('/share/') ||
        lower.contains('/photo') ||
        lower.contains('/photos/') ||
        lower.contains('/permalink.php') ||
        lower.contains('/watch/') ||
        lower.contains('fb.watch/');
  }

  /// Checks if a URL is a Reddit post URL
  static bool isRedditUrl(String url) {
    final lower = url.toLowerCase();
    final hasDomain = lower.contains('reddit.com') || lower.contains('redd.it');
    if (!hasDomain) return false;
    return lower.contains('/comments/') ||
        lower.contains('/r/') ||
        lower.contains('redd.it/');
  }

  /// Checks if a URL is a TikTok video URL
  static bool isTikTokUrl(String url) {
    final lowercased = url.toLowerCase();
    return lowercased.contains('tiktok.com/') &&
        (lowercased.contains('/video/') ||
            lowercased.contains('/@') ||
            lowercased.contains('/t/'));
  }

  /// Checks if a URL is a Pinterest pin URL
  static bool isPinterestUrl(String url) {
    final lowercased = url.toLowerCase();
    return lowercased.contains('pinterest.com/pin/') ||
        lowercased.contains('pin.it/');
  }

  /// Checks if a URL is a Snapchat Spotlight/Story URL
  static bool isSnapchatUrl(String url) {
    final lowercased = url.toLowerCase();
    return lowercased.contains('snapchat.com/spotlight/') ||
        lowercased.contains('snapchat.com/t/') ||
        lowercased.contains('snapchat.com/add/');
  }

  /// Checks if a URL is an IMDb link
  static bool isImdbUrl(String url) {
    final lowercased = url.toLowerCase();
    return lowercased.contains('imdb.com');
  }

  /// Checks if a URL is a YouTube Shorts/Video URL
  static bool isYouTubeUrl(String url) {
    final lowercased = url.toLowerCase();
    if (!lowercased.contains('youtube.com') &&
        !lowercased.contains('youtu.be')) {
      return false;
    }

    return lowercased.contains('/shorts/') ||
        lowercased.contains('watch?v=') ||
        lowercased.contains('youtu.be/') ||
        lowercased.contains('/embed/');
  }

  /// Downloads image from TikTok video URL using ScrapingBee
  /// Uses priority-based extraction to get the video thumbnail
  static Future<List<XFile>> downloadImageFromTikTokUrl(
    String tiktokUrl,
  ) async {
    final resolvedUrl = await _resolveTikTokRedirect(tiktokUrl) ?? tiktokUrl;

    // Free path: TikTok oEmbed exposes a direct thumbnail without credits.
    final oembedThumb = await _fetchTikTokOembedThumbnail(resolvedUrl);
    if (oembedThumb != null) {
      final oembedImage = await _downloadImage(
        oembedThumb,
        cropToAspectRatio: 9 / 16,
      );
      if (oembedImage != null) {
        print('Successfully downloaded TikTok thumbnail via oEmbed');
        return [oembedImage];
      }
    }

    print('No usable TikTok images extracted');
    return [];
  }

  static Future<String?> _fetchTikTokOembedThumbnail(String tiktokUrl) async {
    try {
      final resolvedUrl = await _resolveTikTokRedirect(tiktokUrl) ?? tiktokUrl;

      final oembedUri = Uri.https(
        'www.tiktok.com',
        '/oembed',
        {'url': resolvedUrl},
      );
      final response = await http.get(
        oembedUri,
        headers: {
          'User-Agent': _userAgent,
        },
      ).timeout(const Duration(seconds: 8));

      if (response.statusCode != 200) {
        print('TikTok oEmbed request failed with ${response.statusCode}');
        return null;
      }

      final decoded = jsonDecode(response.body);
      if (decoded is Map<String, dynamic>) {
        final thumb = (decoded['thumbnail_url'] ??
            decoded['thumbnailUrl'] ??
            decoded['thumbnailURL']) as String?;
        if (thumb != null && thumb.isNotEmpty) {
          final sanitized = _sanitizeTikTokUrl(thumb);
          print('TikTok oEmbed thumbnail: ${_previewUrl(sanitized)}');
          return sanitized;
        }
      }
    } on TimeoutException {
      print('TikTok oEmbed request timed out');
    } catch (e) {
      print('TikTok oEmbed error: $e');
    }
    return null;
  }

  static Future<String?> _resolveTikTokRedirect(String url) async {
    try {
      final uri = Uri.parse(url);
      final request = http.Request('GET', uri);
      request.followRedirects = true;
      request.maxRedirects = 5;
      final client = http.Client();
      final response =
          await client.send(request).timeout(const Duration(seconds: 8));
      client.close();
      final finalUrl = response.request?.url.toString();
      if (finalUrl != null && finalUrl.isNotEmpty && finalUrl != url) {
        print('Resolved TikTok URL redirect: ${_previewUrl(finalUrl)}');
        return finalUrl;
      }
    } catch (e) {
      print('TikTok redirect resolution failed: $e');
    }
    return null;
  }

  /// Extract images from TikTok HTML with priority-based selection
  /// Matches iOS share extension patterns that work successfully
  static Future<List<XFile>> _extractImagesFromTikTokHtml(
    String htmlContent,
  ) async {
    final priorityResults = <String>[];
    final fallbackResults = <String>[];
    final seenUrls = <String>{};

    // Pattern 1: High-quality tplv-tiktokx-origin.image with src attribute (highest priority)
    // Matches iOS pattern: src="(https://[^"]*tiktokcdn[^"]*tplv-tiktokx-origin\.image[^"]*)"
    final originPattern = RegExp(
      r'src="(https://[^"]*tiktokcdn[^"]*tplv-tiktokx-origin\.image[^"]*)"',
    );
    final originMatches = originPattern.allMatches(htmlContent).toList();
    print(
        'Pattern 1 (src + tplv-tiktokx-origin): ${originMatches.length} matches');
    for (final match in originMatches) {
      var url = match.group(1);
      if (url != null) {
        // Sanitize HTML entities in URL
        url = _sanitizeTikTokUrl(url);
        if (!seenUrls.contains(url)) {
          // Filter out avatars and small images
          if (!url.contains('avt-') &&
              !url.contains('100x100') &&
              !url.contains('cropcenter') &&
              !url.contains('music')) {
            seenUrls.add(url);
            priorityResults.add(url);
            print('Found priority TikTok image: ${_previewUrl(url)}');
          }
        }
      }
    }

    // If we found high-quality images, use them
    if (priorityResults.isNotEmpty) {
      for (final imageUrl in priorityResults.take(1)) {
        final downloadedImage = await _downloadImage(imageUrl);
        if (downloadedImage != null) {
          return [downloadedImage];
        }
      }
    }

    // Pattern 2: poster attribute with tiktokcdn URL
    // Matches iOS pattern: poster="(https://[^"]*tiktokcdn[^"]*)"
    final posterPattern = RegExp(
      r'poster="(https://[^"]*tiktokcdn[^"]*)"',
    );
    final posterMatches = posterPattern.allMatches(htmlContent).toList();
    print('Pattern 2 (poster + tiktokcdn): ${posterMatches.length} matches');
    for (final match in posterMatches) {
      var url = match.group(1);
      if (url != null) {
        url = _sanitizeTikTokUrl(url);
        if (!seenUrls.contains(url)) {
          if (!url.contains('avt-') &&
              !url.contains('100x100') &&
              !url.contains('cropcenter') &&
              !url.contains('music')) {
            seenUrls.add(url);
            // Poster images are high priority (video thumbnails)
            priorityResults.add(url);
            print('Found poster TikTok image: ${_previewUrl(url)}');
          }
        }
      }
    }

    // Try poster images if we have them
    if (priorityResults.isNotEmpty) {
      for (final imageUrl in priorityResults) {
        final downloadedImage = await _downloadImage(imageUrl);
        if (downloadedImage != null) {
          return [downloadedImage];
        }
      }
    }

    // Pattern 3: img tag with src containing tiktokcdn
    // Matches iOS pattern: <img[^>]+src="(https://[^"]*tiktokcdn[^"]+)"
    final imgPattern = RegExp(
      r'<img[^>]+src="(https://[^"]*tiktokcdn[^"]+)"',
    );
    final imgMatches = imgPattern.allMatches(htmlContent).toList();
    print('Pattern 3 (img src + tiktokcdn): ${imgMatches.length} matches');
    for (final match in imgMatches) {
      var url = match.group(1);
      if (url != null) {
        url = _sanitizeTikTokUrl(url);
        if (!seenUrls.contains(url)) {
          if (!url.contains('avt-') &&
              !url.contains('100x100') &&
              !url.contains('cropcenter') &&
              !url.contains('music')) {
            seenUrls.add(url);
            fallbackResults.add(url);
            print('Found img src TikTok image: ${_previewUrl(url)}');
          }
        }
      }
    }

    // Check if tiktokcdn exists at all in the HTML
    if (htmlContent.contains('tiktokcdn')) {
      print('HTML contains "tiktokcdn" - checking for patterns');
      // Debug: show sample of how tiktokcdn appears in the HTML
      final contextPattern = RegExp(r'.{0,40}tiktokcdn.{0,80}');
      final contextMatches =
          contextPattern.allMatches(htmlContent).take(3).toList();
      for (final match in contextMatches) {
        print('  Context: ${match.group(0)}');
      }
    } else {
      print('HTML does NOT contain "tiktokcdn"');
    }

    // Pattern 4: og:image meta tag - try both attribute orders
    print('Checking for og:image in HTML...');
    if (htmlContent.contains('og:image')) {
      print('HTML contains "og:image"');
    } else {
      print('HTML does NOT contain "og:image"');
    }
    final ogImagePatterns = [
      RegExp(r'property="og:image"\s*content="([^"]+)"'),
      RegExp(r'content="([^"]+)"\s*property="og:image"'),
      RegExp(r"property='og:image'\s*content='([^']+)'"),
      RegExp(r"content='([^']+)'\s*property='og:image'"),
    ];
    for (final pattern in ogImagePatterns) {
      final ogMatch = pattern.firstMatch(htmlContent);
      if (ogMatch != null) {
        final url = ogMatch.group(1);
        if (url != null && !seenUrls.contains(url)) {
          seenUrls.add(url);
          fallbackResults.add(url);
          print('Found og:image TikTok image: ${_previewUrl(url)}');
          break;
        }
      }
    }

    // Pattern 5: JSON-LD thumbnailUrl (TikTok often uses this)
    print('Checking for thumbnailUrl in HTML...');
    if (htmlContent.contains('thumbnailUrl')) {
      print('HTML contains "thumbnailUrl"');
    } else {
      print('HTML does NOT contain "thumbnailUrl"');
    }
    final thumbnailPattern = RegExp(
      r'"thumbnailUrl"\s*:\s*\[\s*"([^"]+)"',
    );
    final thumbMatch = thumbnailPattern.firstMatch(htmlContent);
    if (thumbMatch != null) {
      final url = thumbMatch.group(1);
      if (url != null && !seenUrls.contains(url)) {
        seenUrls.add(url);
        fallbackResults.add(url);
        print('Found JSON-LD thumbnail TikTok image: ${_previewUrl(url)}');
      }
    }

    // Pattern 6: contentUrl from JSON-LD
    final contentUrlPattern = RegExp(
      r'"contentUrl"\s*:\s*"([^"]+)"',
    );
    final contentMatch = contentUrlPattern.firstMatch(htmlContent);
    if (contentMatch != null) {
      final url = contentMatch.group(1);
      if (url != null && !seenUrls.contains(url) && url.contains('tiktokcdn')) {
        seenUrls.add(url);
        fallbackResults.add(url);
        print('Found JSON-LD contentUrl TikTok image: ${_previewUrl(url)}');
      }
    }

    print(
        'TikTok extraction results: ${priorityResults.length} priority, ${fallbackResults.length} fallback');

    // Pattern 7: Markdown/plaintext tiktokcdn URLs (photo mode, etc.)
    // Pattern 7: Markdown/plaintext tiktokcdn URLs (photo mode, may lack file extension)
    // Pattern 7: Markdown/plaintext tiktokcdn URLs (photo mode, may lack extension)
    final markdownCdnPattern = RegExp(
      r'https?://\S*tiktokcdn\S*',
      caseSensitive: false,
    );
    final markdownMatches = markdownCdnPattern.allMatches(htmlContent).toList();
    if (markdownMatches.isNotEmpty) {
      print(
          'Markdown/plaintext tiktokcdn URLs found: ${markdownMatches.length}');
    }
    for (final match in markdownMatches) {
      final url = match.group(0);
      if (url != null) {
        final sanitized = _sanitizeTikTokUrl(url);
        if (sanitized.isNotEmpty &&
            !seenUrls.contains(sanitized) &&
            !sanitized.contains('avt-') &&
            !sanitized.contains('100x100') &&
            !sanitized.contains('cropcenter') &&
            !sanitized.contains('music')) {
          seenUrls.add(sanitized);
          fallbackResults.add(sanitized);
          print('Found markdown TikTok image: ${_previewUrl(sanitized)}');
        }
      }
    }

    // Pattern 8: Markdown image syntax ![](url) capturing tiktokcdn URLs specifically
    final markdownImagePattern = RegExp(
      r'!\[[^\]]*\]\((https?://[^)]+tiktokcdn[^)]+)\)',
      caseSensitive: false,
    );
    final mdImageMatches =
        markdownImagePattern.allMatches(htmlContent).toList();
    if (mdImageMatches.isNotEmpty) {
      print('Markdown image tiktokcdn URLs found: ${mdImageMatches.length}');
    }
    for (final match in mdImageMatches) {
      final url = match.group(1);
      if (url != null) {
        final sanitized = _sanitizeTikTokUrl(url);
        if (sanitized.isNotEmpty &&
            !seenUrls.contains(sanitized) &&
            !sanitized.contains('avt-') &&
            !sanitized.contains('100x100') &&
            !sanitized.contains('cropcenter') &&
            !sanitized.contains('music')) {
          seenUrls.add(sanitized);
          fallbackResults.add(sanitized);
          print('Found markdown image TikTok URL: ${_previewUrl(sanitized)}');
        }
      }
    }

    // Try fallback images
    for (final imageUrl in fallbackResults.take(5)) {
      final downloadedImage = await _downloadImage(imageUrl);
      if (downloadedImage != null) {
        return [downloadedImage];
      }
    }

    return [];
  }

  /// Downloads image from Pinterest pin URL using ScrapingBee
  static Future<List<XFile>> downloadImageFromPinterestUrl(
    String pinterestUrl,
  ) async {
    try {
      print('Attempting Pinterest scrape (direct): $pinterestUrl');

      final html = await _fetchHtmlDirect(pinterestUrl,
          timeout: const Duration(seconds: 12));
      if (html != null && html.isNotEmpty) {
        final images = await _extractImagesFromPinterestHtml(html);
        if (images.isNotEmpty) {
          print(
            'Successfully extracted ${images.length} image(s) from Pinterest via direct scrape!',
          );
          return images;
        }
      }

      print('No images extracted from Pinterest via direct scrape');
      return [];
    } catch (e) {
      print('Error downloading Pinterest images: $e');
      return [];
    }
  }

  /// Extract images from Pinterest HTML
  static Future<List<XFile>> _extractImagesFromPinterestHtml(
    String htmlContent,
  ) async {
    final results = <String>[];
    final seenUrls = <String>{};

    // Pattern 1: High-resolution pinimg URLs (originals folder has highest quality)
    final originalsPattern = RegExp(
      r'src="(https://i\.pinimg\.com/originals/[^"]+)"',
    );
    for (final match in originalsPattern.allMatches(htmlContent)) {
      final url = match.group(1);
      if (url != null && !seenUrls.contains(url)) {
        seenUrls.add(url);
        results.add(url);
        print('Found Pinterest originals image: ${_previewUrl(url)}');
      }
    }

    // Pattern 2: 736x resolution (good quality, commonly used)
    final hdPattern = RegExp(
      r'src="(https://i\.pinimg\.com/736x/[^"]+)"',
    );
    for (final match in hdPattern.allMatches(htmlContent)) {
      final url = match.group(1);
      if (url != null && !seenUrls.contains(url)) {
        seenUrls.add(url);
        results.add(url);
        print('Found Pinterest 736x image: ${_previewUrl(url)}');
      }
    }

    // Pattern 3: 564x resolution (medium quality fallback)
    final medPattern = RegExp(
      r'src="(https://i\.pinimg\.com/564x/[^"]+)"',
    );
    for (final match in medPattern.allMatches(htmlContent)) {
      final url = match.group(1);
      if (url != null && !seenUrls.contains(url)) {
        seenUrls.add(url);
        results.add(url);
        print('Found Pinterest 564x image: ${_previewUrl(url)}');
      }
    }

    // Pattern 4: Any pinimg URL as fallback
    final anyPinimgPattern = RegExp(
      r'src="(https://i\.pinimg\.com/[^"]+\.(?:jpg|jpeg|png|webp))"',
    );
    for (final match in anyPinimgPattern.allMatches(htmlContent)) {
      final url = match.group(1);
      if (url != null && !seenUrls.contains(url)) {
        seenUrls.add(url);
        results.add(url);
        print('Found Pinterest pinimg image: ${_previewUrl(url)}');
      }
    }

    // Pattern 5: og:image meta tag
    final ogImagePattern = RegExp(
      r'<meta[^>]+property="og:image"[^>]+content="([^"]+)"',
      caseSensitive: false,
    );
    final ogMatch = ogImagePattern.firstMatch(htmlContent);
    if (ogMatch != null) {
      final url = ogMatch.group(1);
      if (url != null && !seenUrls.contains(url)) {
        seenUrls.add(url);
        results.add(url);
        print('Found Pinterest og:image: ${_previewUrl(url)}');
      }
    }

    print('Pinterest extraction results: ${results.length} images found');

    // Try to download images in order of quality
    for (final imageUrl in results.take(5)) {
      final downloadedImage = await _downloadImage(imageUrl);
      if (downloadedImage != null) {
        return [downloadedImage];
      }
    }

    return [];
  }

  /// Downloads image from a YouTube video/short by fetching thumbnails directly
  static Future<List<XFile>> downloadImageFromYouTubeUrl(
    String youtubeUrl,
  ) async {
    final shouldCropToPortrait = _isYouTubeShortsUrl(youtubeUrl);
    final videoId = _extractYouTubeVideoId(youtubeUrl);
    if (videoId == null || videoId.isEmpty) {
      print('Unable to extract YouTube video ID from $youtubeUrl');
      return [];
    }

    final thumbnailCandidates = _buildYouTubeThumbnailCandidates(videoId);
    print(
      'Attempting to download YouTube thumbnail for $videoId with ${thumbnailCandidates.length} candidates',
    );

    for (final candidate in thumbnailCandidates) {
      print('Trying YouTube thumbnail candidate: ${_previewUrl(candidate)}');
      final downloadedImage = await _downloadImage(
        candidate,
        cropToAspectRatio: shouldCropToPortrait ? 9 / 16 : null,
      );
      if (downloadedImage != null) {
        print(
            'Successfully downloaded YouTube thumbnail: ${_previewUrl(candidate)}');
        return [downloadedImage];
      }
    }

    print('Failed to download any YouTube thumbnail for video $videoId');
    return [];
  }

  /// Downloads image from Snapchat Spotlight/Story URL
  static Future<List<XFile>> downloadImageFromSnapchatUrl(
    String snapchatUrl,
  ) async {
    // ScrapingBee removed - Snapchat downloads no longer supported
    print('Snapchat downloads not supported (ScrapingBee removed)');
    return [];
  }

  static Future<List<XFile>> _extractImagesFromSnapchatHtml(
    String htmlContent,
    String snapchatUrl,
  ) async {
    final seenUrls = <String>{};

    Future<XFile?> tryDownload(String? url, {String label = ''}) async {
      if (url == null || url.isEmpty) return null;
      final trimmed = url.trim();
      if (trimmed.isEmpty || seenUrls.contains(trimmed)) return null;
      seenUrls.add(trimmed);

      String sanitized = trimmed;
      if (sanitized.startsWith('//')) {
        sanitized = 'https:$sanitized';
      } else if (!sanitized.startsWith('http')) {
        sanitized = 'https://www.snapchat.com$sanitized';
      }

      if (label.isNotEmpty) {
        print('$label: ${_previewUrl(sanitized)}');
      }

      return await _downloadImage(sanitized);
    }

    // Pattern 1: Look for video poster/thumbnail images (these don't have play button overlay)
    final posterPattern = RegExp(
      r'<meta\s+property="og:image"\s+content="([^"]+)"',
      caseSensitive: false,
    );
    final posterMatch = posterPattern.firstMatch(htmlContent);
    if (posterMatch != null) {
      final url = posterMatch.group(1);
      final download =
          await tryDownload(url, label: 'Found Snapchat og:image (poster)');
      if (download != null) {
        return [download];
      }
    }

    // Pattern 2: Look for video thumbnail in video tags
    final videoThumbPattern = RegExp(
      r'poster="([^"]+)"',
      caseSensitive: false,
    );
    final thumbMatch = videoThumbPattern.firstMatch(htmlContent);
    if (thumbMatch != null) {
      final url = thumbMatch.group(1);
      final download =
          await tryDownload(url, label: 'Found Snapchat video poster');
      if (download != null) {
        return [download];
      }
    }

    // Pattern 3: Look for any image in Snapchat CDN
    final cdnPattern = RegExp(
      r'https://[^"]*\.snapchat\.com/[^"]*\.(jpg|jpeg|png|webp)',
      caseSensitive: false,
    );
    final cdnMatches = cdnPattern.allMatches(htmlContent);
    for (final match in cdnMatches) {
      final url = match.group(0);
      final download =
          await tryDownload(url, label: 'Found Snapchat CDN image');
      if (download != null) {
        return [download];
      }
    }

    print('No suitable Snapchat image found');
    return [];
  }

  static List<String> _buildYouTubeThumbnailCandidates(String videoId) {
    final jpgHosts = [
      'https://i.ytimg.com/vi',
      'https://img.youtube.com/vi',
    ];

    final jpgVariants = [
      'maxresdefault.jpg',
      'maxres1.jpg',
      'maxres2.jpg',
      'maxres3.jpg',
      'sddefault.jpg',
      'hq720.jpg',
      'hqdefault.jpg',
      'mqdefault.jpg',
    ];

    final candidates = <String>[];

    for (final host in jpgHosts) {
      for (final variant in jpgVariants) {
        candidates.add('$host/$videoId/$variant');
      }
    }

    // Live thumbnails sometimes use a dedicated suffix
    candidates.add('https://i.ytimg.com/vi/$videoId/maxresdefault_live.jpg');

    // WebP variants are added last as a final fallback
    candidates.add('https://i.ytimg.com/vi_webp/$videoId/maxresdefault.webp');
    candidates.add('https://i.ytimg.com/vi_webp/$videoId/hqdefault.webp');

    return candidates;
  }

  static bool _isYouTubeShortsUrl(String url) {
    final lower = url.toLowerCase();
    return lower.contains('/shorts');
  }

  static String? _extractYouTubeVideoId(String url) {
    try {
      final uri = Uri.parse(url);
      final host = uri.host.toLowerCase();
      final segments =
          uri.pathSegments.where((segment) => segment.isNotEmpty).toList();

      if (host.contains('youtu.be')) {
        return segments.isNotEmpty ? segments.first : null;
      }

      if (uri.queryParameters.containsKey('v')) {
        return uri.queryParameters['v'];
      }

      final shortsIndex = segments.indexOf('shorts');
      if (shortsIndex != -1 && shortsIndex + 1 < segments.length) {
        return segments[shortsIndex + 1];
      }

      final embedIndex = segments.indexOf('embed');
      if (embedIndex != -1 && embedIndex + 1 < segments.length) {
        return segments[embedIndex + 1];
      }

      // Direct path /live/<id> etc (ignore /watch with no query)
      if (segments.isNotEmpty) {
        final candidate = segments.last;
        if (candidate.toLowerCase() != 'watch') {
          return candidate;
        }
      }
    } catch (e) {
      print('Error parsing YouTube URL $url: $e');
    }
    return null;
  }

  /// Downloads image(s) from an X/Twitter post using Jina.
  static Future<List<XFile>> downloadImageFromXUrl(String url) async {
    try {
      print('Attempting X scrape via Jina: $url');
      final urlsToTry = <String>[url];
      const altHosts = ['fxtwitter.com', 'vxtwitter.com'];
      for (final host in altHosts) {
        final rewritten = _rewriteXHost(url, host);
        if (rewritten != null) {
          urlsToTry.add(rewritten);
        }
      }

      for (final candidate in urlsToTry) {
        final files = await _scrapeXViaJina(candidate);
        if (files.isNotEmpty) {
          print(
              'Successfully extracted ${files.length} image(s) from X via Jina');
          return files;
        }
      }

      print('No images extracted from X content via Jina');
    } catch (e) {
      print('Error downloading X images: $e');
    }
    return [];
  }

  /// Downloads image(s) from a Facebook post using direct HTML scrape.
  static Future<List<XFile>> downloadImageFromFacebookUrl(String url) async {
    try {
      print('Attempting Facebook scrape (direct): $url');

      final userAgents = [
        // Facebook scraper UA
        'facebookexternalhit/1.1 (+http://www.facebook.com/externalhit_uatext.html)',
        // Mobile Safari UA
        'Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1',
        // Desktop Chrome UA
        'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/119.0.0.0 Safari/537.36',
      ];

      final candidates = _buildFacebookCandidates(url);

      for (final candidate in candidates) {
        for (final ua in userAgents) {
          final html = await _fetchHtmlWithHeaders(
            candidate,
            headers: {
              'User-Agent': ua,
              'Accept-Language': 'en-US,en;q=0.9',
            },
            timeout: const Duration(seconds: 15),
          );
          if (html == null || html.isEmpty) continue;

          final urls = _extractFacebookImageUrls(html);
          final files = await _downloadCandidateImages(urls);
          if (files.isNotEmpty) {
            print(
                'Successfully extracted ${files.length} image(s) from Facebook via direct scrape');
            return files;
          }
        }
      }

      print('No images extracted from Facebook via direct scrape');
    } catch (e) {
      print('Error downloading Facebook images: $e');
    }
    return [];
  }

  /// Downloads image(s) from a Reddit post using direct HTML scrape.
  static Future<List<XFile>> downloadImageFromRedditUrl(String url) async {
    try {
      print('Attempting Reddit scrape (direct): $url');
      final html = await _fetchHtmlDirect(url);
      if (html != null && html.isNotEmpty) {
        final candidates = _extractRedditImageUrls(html);
        final files = await _downloadCandidateImages(candidates);
        if (files.isNotEmpty) {
          print(
              'Successfully extracted ${files.length} image(s) from Reddit via direct scrape');
          return files;
        }
      }
      print('No images extracted from Reddit content via direct scrape');
    } catch (e) {
      print('Error downloading Reddit images: $e');
    }
    return [];
  }

  /// Downloads image(s) from an IMDb page using direct HTML scrape.
  static Future<List<XFile>> downloadImageFromImdbUrl(String url) async {
    try {
      print('Attempting IMDb scrape (direct): $url');
      final html = await _fetchHtmlDirect(url);
      if (html != null && html.isNotEmpty) {
        final candidates = _extractImdbImageUrls(html);
        final files = await _downloadCandidateImages(candidates);
        if (files.isNotEmpty) {
          print(
              'Successfully extracted ${files.length} image(s) from IMDb via direct scrape');
          return files;
        }
      }
      print('No images extracted from IMDb content via direct scrape');
    } catch (e) {
      print('Error downloading IMDb images: $e');
    }
    return [];
  }

  static String? _rewriteXHost(String originalUrl, String newHost) {
    try {
      final uri = Uri.parse(originalUrl);
      if (uri.host.toLowerCase().contains('twitter.com') ||
          uri.host.toLowerCase().contains('x.com')) {
        final rebuilt = uri.replace(host: newHost);
        return rebuilt.toString();
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  static List<String> _buildFacebookCandidates(String urlString) {
    final urls = <String>{urlString};
    try {
      final uri = Uri.parse(urlString);
      final host = uri.host.toLowerCase();
      if (host.contains('facebook.com')) {
        urls.add(uri.replace(host: 'm.facebook.com').toString());
        urls.add(uri.replace(host: 'mbasic.facebook.com').toString());
        urls.add(uri.replace(host: 'touch.facebook.com').toString());
      }
    } catch (_) {}
    return urls.toList();
  }

  static Future<String?> _fetchHtmlDirect(
    String url, {
    Duration timeout = const Duration(seconds: 12),
  }) async {
    try {
      final response = await http.get(Uri.parse(url),
          headers: {'User-Agent': _userAgent}).timeout(timeout);
      if (response.statusCode >= 200 &&
          response.statusCode < 300 &&
          response.body.isNotEmpty) {
        print('Direct fetch returned ${response.body.length} bytes for $url');
        return response.body;
      }
      print('Direct fetch failed for $url with status ${response.statusCode}');
    } on TimeoutException {
      print('Direct fetch timed out for $url');
    } catch (e) {
      print('Direct fetch error for $url: $e');
    }
    return null;
  }

  static Future<String?> _fetchHtmlWithHeaders(
    String url, {
    Map<String, String>? headers,
    Duration timeout = const Duration(seconds: 12),
  }) async {
    try {
      final response = await http
          .get(Uri.parse(url), headers: headers)
          .timeout(timeout);
      if (response.statusCode >= 200 &&
          response.statusCode < 300 &&
          response.bodyBytes.isNotEmpty) {
        final body = utf8.decode(response.bodyBytes, allowMalformed: true);
        print('Direct fetch returned ${body.length} bytes for $url');
        return body;
      }
      print('Direct fetch failed for $url with status ${response.statusCode}');
    } on TimeoutException {
      print('Direct fetch timed out for $url');
    } catch (e) {
      print('Direct fetch error for $url: $e');
    }
    return null;
  }

  static Future<List<XFile>> _scrapeXViaJina(String url) async {
    final html = await _fetchViaJinaForX(url);
    if (html == null || html.isEmpty) return [];
    final candidates = _extractXImageUrls(html);
    return _downloadCandidateImages(candidates);
  }

  static Future<String?> _fetchViaJinaForX(String targetUrl) async {
    try {
      final proxyUri =
          Uri.parse('https://r.jina.ai/${Uri.encodeFull(targetUrl)}');
      final response = await http.get(proxyUri, headers: {
        'User-Agent': _userAgent
      }).timeout(const Duration(seconds: 15));
      if (response.statusCode >= 200 &&
          response.statusCode < 300 &&
          response.body.isNotEmpty) {
        return response.body;
      }
      print('Jina request failed for $targetUrl with ${response.statusCode}');
    } on TimeoutException {
      print('Jina request timed out for $targetUrl');
    } catch (e) {
      print('Jina request error for $targetUrl: $e');
    }
    return null;
  }

  static Future<List<XFile>> _downloadCandidateImages(
    List<String> urls, {
    double? cropToAspect,
  }) async {
    for (final url in urls) {
      final file = await _downloadImage(url, cropToAspectRatio: cropToAspect);
      if (file != null) return [file];
    }
    return [];
  }

  static List<String> _extractXImageUrls(String html) {
    final results = <String>{};
    String upgrade(String url) {
      final uri = Uri.tryParse(url);
      if (uri == null) return url;
      final host = uri.host.toLowerCase();
      // Only allow media hosts we care about.
      final isMediaHost =
          host.contains('pbs.twimg.com') || host.contains('video.twimg.com');
      if (!isMediaHost) return url;
      // Reject emoji/svg assets.
      if (uri.path.contains('/emoji/') || uri.path.endsWith('.svg')) return '';
      final query = Map<String, String>.from(uri.queryParameters);
      query['name'] = 'orig';
      final updated = uri.replace(queryParameters: query);
      return updated.toString();
    }

    void addIfValid(String? candidate) {
      if (candidate == null || candidate.isEmpty) return;
      final cleaned = candidate.replaceAll('&amp;', '&');
      final lower = cleaned.toLowerCase();
      if (!lower.contains('twimg.com')) return;
      if (lower.contains('/emoji/') || lower.endsWith('.svg')) return;
      // Exclude known emoji assets explicitly
      if (cleaned.contains('abs-0.twimg.com/emoji')) return;
      final upgraded = upgrade(cleaned);
      if (upgraded.isEmpty) return;
      results.add(upgraded);
    }

    final ogPattern = RegExp(
      r'''<meta\s+(?:[^>]*?\s+)?property\s*=\s*["']og:image["']\s+(?:[^>]*?\s+)?content\s*=\s*["']([^"']+)["']''',
      caseSensitive: false,
    );
    for (final match in ogPattern.allMatches(html)) {
      addIfValid(match.group(1));
    }

    final twPattern = RegExp(
      r'''<meta\s+(?:[^>]*?\s+)?name\s*=\s*["']twitter:image["']\s+(?:[^>]*?\s+)?content\s*=\s*["']([^"']+)["']''',
      caseSensitive: false,
    );
    for (final match in twPattern.allMatches(html)) {
      addIfValid(match.group(1));
    }

    final cdnPattern = RegExp(
      r'''(https?://(?:pbs\.twimg\.com|video\.twimg\.com)/[^\s"'<>]+)''',
      caseSensitive: false,
    );
    for (final match in cdnPattern.allMatches(html)) {
      addIfValid(match.group(1));
    }

    final imgPattern = RegExp(
      r'''<img\s+[^>]*?src\s*=\s*["']([^"']+twimg\.com[^"']+)["']''',
      caseSensitive: false,
    );
    for (final match in imgPattern.allMatches(html)) {
      addIfValid(match.group(1));
    }

    // Pattern 5: background-image style URLs that may not appear in attrs
    final bgPattern = RegExp(
      r'''background-image:\s*url\((["']?)(https?://[^"')]+twimg\.com[^"')]+)\1\)''',
      caseSensitive: false,
    );
    for (final match in bgPattern.allMatches(html)) {
      addIfValid(match.group(2));
    }

    // Pattern 6: bare media IDs without query params
    final mediaIdPattern = RegExp(
      r'''https?://pbs\.twimg\.com/media/([A-Za-z0-9_-]+)''',
      caseSensitive: false,
    );
    for (final match in mediaIdPattern.allMatches(html)) {
      final id = match.group(1);
      if (id != null && id.isNotEmpty) {
        addIfValid('https://pbs.twimg.com/media/$id?format=jpg&name=orig');
      }
    }

    return results.toList();
  }

  static String? _extractXStatusId(String url) {
    try {
      final uri = Uri.parse(url);
      final segments =
          uri.pathSegments.where((s) => s.isNotEmpty).toList(growable: false);
      final statusIndex = segments.indexOf('status');
      if (statusIndex != -1 && statusIndex + 1 < segments.length) {
        return segments[statusIndex + 1];
      }
    } catch (_) {
      return null;
    }
    return null;
  }

  static Future<List<XFile>> _fetchXImagesViaSyndication(
    String statusId,
  ) async {
    final endpoints = [
      'https://cdn.syndication.twimg.com/tweet-result?id=$statusId',
      'https://cdn.syndication.twimg.com/tweet?id=$statusId',
    ];

    for (final endpoint in endpoints) {
      try {
        final response = await http.get(Uri.parse(endpoint), headers: {
          'User-Agent': _userAgent
        }).timeout(const Duration(seconds: 10));
        if (response.statusCode != 200 || response.body.isEmpty) {
          continue;
        }

        final mediaUrls = _extractXMediaFromSyndication(response.body);

        if (mediaUrls.isNotEmpty) {
          final files = await _downloadCandidateImages(mediaUrls.toList());
          if (files.isNotEmpty) {
            return files;
          }
        }
      } on TimeoutException {
        print('Syndication fetch timed out for tweet $statusId');
      } catch (e) {
        print('Syndication fetch error for tweet $statusId: $e');
      }
    }

    return [];
  }

  static String _upgradeXImageUrl(String url) {
    try {
      final uri = Uri.parse(url.replaceAll('&amp;', '&'));
      if (!uri.host.toLowerCase().contains('twimg.com')) return url;
      final query = Map<String, String>.from(uri.queryParameters);
      query['name'] = 'orig';
      final upgraded = uri.replace(queryParameters: query);
      return upgraded.toString();
    } catch (_) {
      return url;
    }
  }

  static Set<String> _extractXMediaFromSyndication(String body) {
    final mediaUrls = <String>{};
    try {
      final decoded = jsonDecode(body);
      if (decoded is Map<String, dynamic>) {
        final photos = decoded['photos'];
        if (photos is List) {
          for (final p in photos) {
            if (p is Map && p['url'] is String) {
              mediaUrls.add(_upgradeXImageUrl(p['url'] as String));
            }
          }
        }
        final mediaDetails = decoded['mediaDetails'];
        if (mediaDetails is List) {
          for (final m in mediaDetails) {
            if (m is Map && m['media_url_https'] is String) {
              mediaUrls.add(_upgradeXImageUrl(m['media_url_https'] as String));
            }
          }
        }
        final entities = decoded['entities'];
        if (entities is Map && entities['media'] is List) {
          for (final m in (entities['media'] as List)) {
            if (m is Map && m['media_url_https'] is String) {
              mediaUrls.add(_upgradeXImageUrl(m['media_url_https'] as String));
            }
          }
        }
      }
    } catch (e) {
      print('Syndication JSON parse error: $e');
    }

    // Fallback: regex for pbs.twimg.com in the body
    final regex = RegExp(
      r'''https://pbs\.twimg\.com/[^\s"'<>\)]+''',
      caseSensitive: false,
    );
    for (final match in regex.allMatches(body)) {
      mediaUrls.add(_upgradeXImageUrl(match.group(0)!));
    }

    // Filter emoji/svg
    return mediaUrls.where((u) {
      final lower = u.toLowerCase();
      return !(lower.contains('/emoji/') ||
          lower.endsWith('.svg') ||
          lower.contains('abs-0.twimg.com/emoji'));
    }).toSet();
  }

  static List<String> _extractFacebookImageUrls(String html) {
    final results = <String>{};

    void addIfValid(String? candidate) {
      if (candidate == null || candidate.isEmpty) return;
      results.add(candidate.replaceAll('&amp;', '&'));
    }

    final ogPattern = RegExp(
      r'''<meta\s+(?:[^>]*?\s+)?property\s*=\s*["']og:image(?::secure_url)?["']\s+(?:[^>]*?\s+)?content\s*=\s*["']([^"']+)["']''',
      caseSensitive: false,
    );
    for (final match in ogPattern.allMatches(html)) {
      addIfValid(match.group(1));
    }

    final cdnPattern = RegExp(
      r'''(https?://(?:scontent[^/]*\.fbcdn\.net|external[^/]*\.fbcdn\.net)/[^\s"'<>]+\.(?:jpg|jpeg|png|webp))''',
      caseSensitive: false,
    );
    for (final match in cdnPattern.allMatches(html)) {
      addIfValid(match.group(1));
    }

    final imgPattern = RegExp(
      r'''<img\s+[^>]*?src\s*=\s*["']([^"']+fbcdn\.net[^"']+)["']''',
      caseSensitive: false,
    );
    for (final match in imgPattern.allMatches(html)) {
      addIfValid(match.group(1));
    }

    return results.toList();
  }

  static List<String> _extractRedditImageUrls(String html) {
    final results = <String>{};

    void addIfValid(String? candidate) {
      if (candidate == null || candidate.isEmpty) return;
      final cleaned = candidate.replaceAll('&amp;', '&');
      if (!(cleaned.contains('redd.it') ||
          cleaned.contains('redditmedia.com') ||
          cleaned.contains('imgur.com'))) return;
      results.add(cleaned);
    }

    final ogPattern = RegExp(
      r'''<meta\s+(?:[^>]*?\s+)?property\s*=\s*["']og:image["']\s+(?:[^>]*?\s+)?content\s*=\s*["']([^"']+)["']''',
      caseSensitive: false,
    );
    for (final match in ogPattern.allMatches(html)) {
      addIfValid(match.group(1));
    }

    final previewPattern = RegExp(
      r'''(https?://preview\.redd\.it/[^\s"'<>]+)''',
      caseSensitive: false,
    );
    for (final match in previewPattern.allMatches(html)) {
      addIfValid(match.group(1));
    }

    final iRedditPattern = RegExp(
      r'''(https?://i\.redd\.it/[^\s"'<>]+)''',
      caseSensitive: false,
    );
    for (final match in iRedditPattern.allMatches(html)) {
      addIfValid(match.group(1));
    }

    final imgPattern = RegExp(
      r'''<img\s+[^>]*?src\s*=\s*["']([^"']+redd\.it[^"']+)["']''',
      caseSensitive: false,
    );
    for (final match in imgPattern.allMatches(html)) {
      addIfValid(match.group(1));
    }

    return results.toList();
  }

  static List<String> _extractImdbImageUrls(String html) {
    final results = <String>{};

    void addIfValid(String? candidate) {
      if (candidate == null || candidate.isEmpty) return;
      results.add(candidate.replaceAll('&amp;', '&'));
    }

    final ogPattern = RegExp(
      r'''<meta\s+(?:[^>]*?\s+)?property\s*=\s*["']og:image["']\s+(?:[^>]*?\s+)?content\s*=\s*["']([^"']+)["']''',
      caseSensitive: false,
    );
    for (final match in ogPattern.allMatches(html)) {
      addIfValid(match.group(1));
    }

    final twPattern = RegExp(
      r'''<meta\s+(?:[^>]*?\s+)?name\s*=\s*["']twitter:image["']\s+(?:[^>]*?\s+)?content\s*=\s*["']([^"']+)["']''',
      caseSensitive: false,
    );
    for (final match in twPattern.allMatches(html)) {
      addIfValid(match.group(1));
    }

    final imgPattern = RegExp(
      r'''<img\s+[^>]*?src\s*=\s*["']([^"']+m\.media-amazon\.com[^"']+)["']''',
      caseSensitive: false,
    );
    for (final match in imgPattern.allMatches(html)) {
      addIfValid(match.group(1));
    }

    return results.toList();
  }
}
