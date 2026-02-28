import 'dart:math';
import 'package:supabase_flutter/supabase_flutter.dart';

class InspirationService {
  /// Check if an image URL indicates high quality based on common patterns.
  bool isHighQualityImage(String imageUrl) {
    try {
      final uri = Uri.parse(imageUrl);
      final path = uri.path.toLowerCase();
      final query = uri.query.toLowerCase();

      final sizePatterns = [
        RegExp(r'w=(\d+)'),
        RegExp(r'width=(\d+)'),
        RegExp(r'h=(\d+)'),
        RegExp(r'height=(\d+)'),
        RegExp(r'size=(\d+)'),
        RegExp(r's=(\d+)'),
      ];

      for (final pattern in sizePatterns) {
        final match = pattern.firstMatch(query);
        if (match != null) {
          final size = int.tryParse(match.group(1) ?? '0') ?? 0;
          if (size >= 400) return true;
          if (size > 0 && size < 200) return false;
        }
      }

      final filenamePattern = RegExp(r'_(\d+)x(\d+)\.');
      final filenameMatch = filenamePattern.firstMatch(path);
      if (filenameMatch != null) {
        final width = int.tryParse(filenameMatch.group(1) ?? '0') ?? 0;
        final height = int.tryParse(filenameMatch.group(2) ?? '0') ?? 0;
        if (width >= 400 && height >= 400) return true;
        if (width < 300 || height < 300) return false;
      }

      if (path.contains('thumb') ||
          path.contains('small') ||
          path.contains('mini') ||
          path.contains('xs') ||
          path.contains('_s.') ||
          path.contains('_small.')) {
        return false;
      }

      if (path.contains('large') ||
          path.contains('big') ||
          path.contains('full') ||
          path.contains('hd') ||
          path.contains('_l.') ||
          path.contains('_large.') ||
          path.contains('original')) {
        return true;
      }

      return true;
    } catch (_) {
      return true;
    }
  }

  /// Fetch inspiration images from Supabase.
  /// Uses the `get_random_products` RPC for random results.
  /// Falls back to normal query + shuffle if the RPC fails.
  ///
  /// [genderFilter] can be 'men', 'women', or 'all' (default)
  Future<List<Map<String, dynamic>>> fetchInspirationImages({
    int page = 0,
    int limit = 50,
    Set<String>? excludeImageUrls,
    String genderFilter = 'all',
  }) async {
    final supabase = Supabase.instance.client;

    try {
      // 🌀 Try using the random RPC first with gender filter
      final response = await supabase.rpc(
        'get_random_products',
        params: {
          'limit_count': limit,
          'gender_filter': genderFilter,
        },
      );

      final data = List<Map<String, dynamic>>.from(response ?? []);

      // Filter out duplicates or excluded URLs
      final filtered = data.where((item) {
        final url = item['image_url'] as String?;
        return url != null && !(excludeImageUrls?.contains(url) ?? false);
      }).toList();

      print('🎲 Randomly fetched ${filtered.length} inspiration images (filter: $genderFilter)');
      return filtered;
    } catch (e) {
      // 🔁 Fallback to standard query if RPC fails
      print('⚠️ Random RPC failed, falling back to ordered fetch: $e');
      try {
        var query = supabase
            .from('products')
            .select('id, title, image_url, category, brand')
            .neq('image_url', '');

        // Apply gender filter if not 'all'
        if (genderFilter != 'all') {
          query = query.eq('target_gender', genderFilter);
        }

        final fallback = await query
            .order('created_at', ascending: false)
            .range(page * limit, (page * limit) + limit * 3 - 1);

        final data = List<Map<String, dynamic>>.from(fallback ?? []);
        data.shuffle(Random(DateTime.now().millisecondsSinceEpoch));
        final filtered = data.where((item) {
          final url = item['image_url'] as String?;
          return url != null && !(excludeImageUrls?.contains(url) ?? false);
        }).take(limit).toList();

        print('🪄 Fallback loaded ${filtered.length} inspiration images (filter: $genderFilter)');
        return filtered;
      } catch (err) {
        print('❌ Failed to fetch inspiration images: $err');
        return [];
      }
    }
  }

  /// Search inspiration images by keyword.
  /// [genderFilter] can be 'men', 'women', or 'all' (default)
  Future<List<Map<String, dynamic>>> searchInspirationImages(
    String query, {
    String genderFilter = 'all',
  }) async {
    try {
      final supabase = Supabase.instance.client;
      var queryBuilder = supabase
          .from('products')
          .select('id, title, image_url, category, brand')
          .neq('image_url', '')
          .or('category.ilike.%$query%,brand.ilike.%$query%');

      // Apply gender filter if not 'all'
      if (genderFilter != 'all') {
        queryBuilder = queryBuilder.eq('target_gender', genderFilter);
      }

      final response = await queryBuilder
          .order('created_at', ascending: false)
          .limit(50);

      final data = List<Map<String, dynamic>>.from(response ?? []);
      print('🔍 Found ${data.length} inspiration images for "$query" (filter: $genderFilter)');
      return data;
    } catch (e) {
      print('❌ Search failed: $e');
      return [];
    }
  }

  /// Fetch featured or trending images.
  /// [genderFilter] can be 'men', 'women', or 'all' (default)
  Future<List<Map<String, dynamic>>> fetchTrendingImages({
    int limit = 20,
    String genderFilter = 'all',
  }) async {
    try {
      final supabase = Supabase.instance.client;
      var query = supabase
          .from('products')
          .select('id, title, image_url, category, brand')
          .neq('image_url', '');

      // Apply gender filter if not 'all'
      if (genderFilter != 'all') {
        query = query.eq('target_gender', genderFilter);
      }

      final response = await query
          .order('created_at', ascending: false)
          .limit(limit);

      final data = List<Map<String, dynamic>>.from(response ?? []);
      data.shuffle();
      print('🔥 Fetched ${data.length} trending images (filter: $genderFilter)');
      return data;
    } catch (e) {
      print('❌ Failed to fetch trending images: $e');
      return [];
    }
  }
}
