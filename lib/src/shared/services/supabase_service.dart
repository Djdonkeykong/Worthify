import 'package:supabase_flutter/supabase_flutter.dart';

class SupabaseService {
  static final SupabaseService _instance = SupabaseService._internal();
  factory SupabaseService() => _instance;
  SupabaseService._internal();

  SupabaseClient get client => Supabase.instance.client;

  Future<List<Map<String, dynamic>>> getUserSearches({
    required String userId,
    int limit = 20,
    int offset = 0,
  }) async {
    try {
      print(
        '[SupabaseService] getUserSearches user=$userId limit=$limit offset=$offset',
      );

      // Single JOIN query - only fetch fields needed for history list display
      final response = await client
          .from('user_searches')
          .select(
            'id, user_id, search_type, source_url, source_username, created_at, image_cache_id, '
            'saved:user_saved_searches!left (id), '
            'cache:image_cache!left (cloudinary_url, total_results)',
          )
          .eq('user_id', userId)
          .order('created_at', ascending: false)
          .range(offset, offset + limit - 1);

      final searches = List<Map<String, dynamic>>.from(response);
      final mapped = <Map<String, dynamic>>[];

      for (final search in searches) {
        final cacheId = search['image_cache_id'] as String?;
        final cacheData = search['cache'] as Map<String, dynamic>?;
        final savedEntries = search['saved'] as List<dynamic>?;

        final cloudinaryUrl = cacheData?['cloudinary_url'] as String?;
        final totalResults = (cacheData?['total_results'] as num?)?.toInt() ?? 0;

        mapped.add({
          'id': search['id'],
          'user_id': search['user_id'],
          'search_type': search['search_type'],
          'source_url': search['source_url'],
          'source_username': search['source_username'],
          'created_at': search['created_at'],
          'image_cache_id': cacheId,
          'cloudinary_url': cloudinaryUrl,
          'total_results': totalResults,
          'is_saved': savedEntries != null && savedEntries.isNotEmpty,
        });
      }

      print(
        '[SupabaseService] getUserSearches returned ${mapped.length} rows',
      );

      return mapped;
    } catch (e) {
      print('Error fetching user searches: $e');
      return [];
    }
  }

  Future<List<Map<String, dynamic>>> getUserFavorites({
    required String userId,
    int limit = 50,
    int offset = 0,
  }) async {
    try {
      final response = await client
          .from('user_favorites')
          .select()
          .eq('user_id', userId)
          .order('created_at', ascending: false)
          .range(offset, offset + limit - 1);

      return List<Map<String, dynamic>>.from(response);
    } catch (e) {
      print('Error fetching user favorites: $e');
      return [];
    }
  }

  Future<bool> removeFavorite(String favoriteId) async {
    try {
      await client
          .from('user_favorites')
          .delete()
          .eq('id', favoriteId);

      return true;
    } catch (e) {
      print('Error removing favorite: $e');
      return false;
    }
  }

  Future<bool> saveSearch({
    required String userId,
    required String searchId,
    String? name,
  }) async {
    try {
      await client.from('user_saved_searches').insert({
        'user_id': userId,
        'search_id': searchId,
        'name': name,
      });

      return true;
    } catch (e) {
      print('Error saving search: $e');
      return false;
    }
  }

  Future<bool> removeSavedSearch(String savedSearchId) async {
    try {
      await client
          .from('user_saved_searches')
          .delete()
          .eq('id', savedSearchId);

      return true;
    } catch (e) {
      print('Error removing saved search: $e');
      return false;
    }
  }

  Future<bool> deleteSearch(String searchId) async {
    try {
      print('[SupabaseService] deleteSearch attempting to delete searchId=$searchId');

      final response = await client
          .from('user_searches')
          .delete()
          .eq('id', searchId)
          .select();

      print('[SupabaseService] deleteSearch response: $response');
      print('[SupabaseService] deleteSearch successful');
      return true;
    } catch (e, stackTrace) {
      print('[SupabaseService] Error deleting search: $e');
      print('[SupabaseService] Stack trace: $stackTrace');
      return false;
    }
  }

  Future<Map<String, dynamic>?> getSearchById(String searchId) async {
    try {
      print('[SupabaseService] getSearchById searchId=$searchId');

      final searchResponse = await client
          .from('user_searches')
          .select('id, user_id, search_type, source_url, source_username, created_at, image_cache_id')
          .eq('id', searchId)
          .maybeSingle();

      if (searchResponse == null) {
        print('[SupabaseService] Search not found: $searchId');
        return null;
      }

      final cacheId = searchResponse['image_cache_id'] as String?;
      if (cacheId == null) {
        print('[SupabaseService] No cache ID for search $searchId');
        return null;
      }

      final cacheResponse = await client
          .from('image_cache')
          .select('cloudinary_url, total_results, detected_garments, search_results')
          .eq('id', cacheId)
          .maybeSingle();

      if (cacheResponse == null) {
        print('[SupabaseService] Cache not found for cache_id: $cacheId');
        return null;
      }

      final result = {
        'id': searchResponse['id'],
        'user_id': searchResponse['user_id'],
        'search_type': searchResponse['search_type'],
        'source_url': searchResponse['source_url'],
        'source_username': searchResponse['source_username'],
        'created_at': searchResponse['created_at'],
        'image_cache_id': cacheId,
        'cloudinary_url': cacheResponse['cloudinary_url'],
        'total_results': (cacheResponse['total_results'] as num?)?.toInt() ?? 0,
        'detected_garments': cacheResponse['detected_garments'] as List<dynamic>?,
        'search_results': cacheResponse['search_results'] as List<dynamic>?,
      };

      print('[SupabaseService] getSearchById found search with ${result['total_results']} results');
      return result;
    } catch (e) {
      print('Error fetching search by ID: $e');
      return null;
    }
  }
}
