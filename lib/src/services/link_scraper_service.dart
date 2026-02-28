import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import 'instagram_service.dart';

class LinkScraperService {
  static const String _userAgent =
      'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36';

  /// Attempts to scrape generic web pages for <img> tags and downloads the images.
  /// Returns a list of locally saved [XFile]s.
  static Future<List<XFile>> downloadImagesFromUrl(String url) async {
    final decodedUrl = _safeDecode(url);
    if (isGoogleImageResultUrl(url) ||
        (decodedUrl != null && isGoogleImageResultUrl(decodedUrl))) {
      return downloadImageFromGoogleImageResult(decodedUrl ?? url);
    }

    final resolvedUrl = await _resolveFinalUrl(url) ?? url;
    print('[LINK SCRAPER] Resolved shared URL -> $resolvedUrl');

    // Direct image URL: download immediately (no credits)
    if (_looksLikeImageUrl(resolvedUrl)) {
      final file = await InstagramService.downloadExternalImage(resolvedUrl);
      if (file != null) {
        return [file];
      }
    }

    // Lightweight HTML fetch to grab og:image/twitter:image/first img (no credits).
    final directImages = await _fetchImagesDirect(resolvedUrl);
    if (directImages.isNotEmpty) {
      print(
        '[LINK SCRAPER] Direct HTML scrape succeeded with ${directImages.length} image(s)',
      );
      return [directImages.first];
    }

    // If resolved URL is a Google image result, use imgurl extraction (creditless).
    if (isGoogleImageResultUrl(resolvedUrl)) {
      final googleImages = await downloadImageFromGoogleImageResult(resolvedUrl);
      if (googleImages.isNotEmpty) {
        return googleImages;
      }
    }

    print('[LINK SCRAPER] Direct HTML scrape found no images for $resolvedUrl');
    return [];
  }

  static Future<String?> _resolveFinalUrl(String url) async {
    try {
      Uri? current = Uri.tryParse(url);
      if (current == null) return null;

      final client = http.Client();
      try {
        for (int i = 0; i < 5; i++) {
          final uri = current;
          if (uri == null) break;

          final request = http.Request('GET', uri)
            ..followRedirects = false
            ..headers['User-Agent'] = _userAgent;
          final response = await client.send(request);

          if (response.isRedirect) {
            final location = response.headers['location'];
            if (location == null) break;
            current = uri.resolve(location);
            continue;
          }

          return response.request?.url.toString() ?? uri.toString();
        }
      } finally {
        client.close();
      }
    } catch (e) {
      print('[LINK SCRAPER] Failed to resolve redirects: $e');
    }
    return null;
  }

  static bool isGoogleImageResultUrl(String url) {
    final lower = url.toLowerCase().trim();
    final hasGoogleHost = lower.contains('://www.google.') ||
        lower.contains('://google.') ||
        lower.startsWith('www.google.') ||
        lower.startsWith('google.');
    if (!hasGoogleHost) return false;
    final hasImgresPath =
        lower.contains('/imgres') || lower.contains('/search');
    if (!hasImgresPath) return false;
    return lower.contains('imgurl=');
  }

  static Future<List<XFile>> downloadImageFromGoogleImageResult(
      String url) async {
    final rawImageUrl = _extractImgUrlFromGoogleUrl(url);
    if (rawImageUrl == null || rawImageUrl.isEmpty) {
      print('[LINK SCRAPER] Could not parse imgurl from Google link');
      return [];
    }

    final cleanedUrl =
        rawImageUrl.startsWith('http') ? rawImageUrl : 'https://$rawImageUrl';

    final XFile? file =
        await InstagramService.downloadExternalImage(cleanedUrl);
    if (file == null) {
      return [];
    }
    print('[LINK SCRAPER] Downloaded image directly from Google imgurl');
    return [file];
  }

  static String? _extractImgUrlFromGoogleUrl(String url) {
    final lower = url.toLowerCase();
    final index = lower.indexOf('imgurl=');
    if (index == -1) return null;

    final raw = url.substring(index + 7);
    final endIndex = raw.indexOf('&');
    final candidate = endIndex == -1 ? raw : raw.substring(0, endIndex);
    final decoded = Uri.decodeFull(candidate);
    return decoded.trim();
  }

  static String? _safeDecode(String value) {
    try {
      return Uri.decodeFull(value);
    } catch (_) {
      return null;
    }
  }

  static bool _looksLikeImageUrl(String url) {
    final lower = url.toLowerCase();
    return lower.endsWith('.jpg') ||
        lower.endsWith('.jpeg') ||
        lower.endsWith('.png') ||
        lower.endsWith('.webp') ||
        lower.contains('.jpg?') ||
        lower.contains('.jpeg?') ||
        lower.contains('.png?') ||
        lower.contains('.webp?');
  }

  static Future<List<XFile>> _fetchImagesDirect(String url) async {
    try {
      final uri = Uri.parse(url);
      final resp = await http.get(
        uri,
        headers: {'User-Agent': _userAgent},
      ).timeout(const Duration(seconds: 6));

      if (resp.statusCode != 200) {
        print('[LINK SCRAPER] Direct fetch failed with ${resp.statusCode}');
        return [];
      }

      final html = resp.body;
      final candidates = _extractImageCandidates(html, uri).toList();
      if (candidates.isEmpty) return [];

      final best = _pickBestImage(candidates);
      if (best == null) return [];

      final file = await InstagramService.downloadExternalImage(best);
      if (file != null) return [file];
      return [];
    } catch (e) {
      print('[LINK SCRAPER] Direct fetch error: $e');
      return [];
    }
  }

  static Set<String> _extractImageCandidates(String html, Uri base) {
    final results = <String>{};

    String? resolve(String? raw) {
      if (raw == null || raw.isEmpty) return null;
      if (raw.startsWith('data:')) return null;
      final lower = raw.toLowerCase();
      if (lower.contains('favicon') ||
          lower.contains('googlelogo') ||
          lower.contains('gstatic.com/favicon') ||
          lower.contains('tbn:') ||
          lower.contains('tbn0.gstatic.com')) {
        return null;
      }
      try {
        final resolved = base.resolve(raw);
        if (resolved.hasScheme) return resolved.toString();
      } catch (_) {}
      return null;
    }

    final patterns = [
      RegExp(r'<meta[^>]+property="og:image"[^>]+content="([^"]+)"', caseSensitive: false),
      RegExp(r'<meta[^>]+name="twitter:image"[^>]+content="([^"]+)"', caseSensitive: false),
    ];

    for (final pattern in patterns) {
      final match = pattern.firstMatch(html);
      if (match != null) {
        final url = resolve(match.group(1));
        if (url != null) results.add(url);
      }
    }

    final imgPattern = RegExp(r'<img[^>]+src="([^"]+)"', caseSensitive: false);
    for (final match in imgPattern.allMatches(html).take(5)) {
      final url = resolve(match.group(1));
      if (url != null) results.add(url);
    }

    return results;
  }

  static String? _pickBestImage(List<String> urls) {
    bool isBadThumb(String u) {
      final lower = u.toLowerCase();
      return lower.contains('favicon') ||
          lower.contains('googlelogo') ||
          lower.contains('gstatic.com/favicon') ||
          lower.contains('tbn:') ||
          lower.contains('tbn0.gstatic.com');
    }

    final filtered = urls.where((u) => !isBadThumb(u)).toList();
    if (filtered.isEmpty) return null;

    // Prefer file extensions that indicate full images
    String scoreExt(String u) {
      final lower = u.toLowerCase();
      if (lower.endsWith('.jpg') || lower.endsWith('.jpeg')) return '1';
      if (lower.endsWith('.png')) return '2';
      if (lower.endsWith('.webp')) return '3';
      return '9';
    }

    filtered.sort((a, b) {
      final sa = scoreExt(a);
      final sb = scoreExt(b);
      if (sa != sb) return sa.compareTo(sb);
      return b.length.compareTo(a.length); // longer URL often has full image params
    });

    return filtered.first;
  }
}
