import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../services/inspiration_service.dart';
import '../../../auth/domain/providers/auth_provider.dart';

class InspirationState {
  final List<Map<String, dynamic>> images;
  final bool isLoading;
  final bool hasMore;
  final String? error;

  const InspirationState({
    this.images = const [],
    this.isLoading = false,
    this.hasMore = true,
    this.error,
  });

  InspirationState copyWith({
    List<Map<String, dynamic>>? images,
    bool? isLoading,
    bool? hasMore,
    String? error,
  }) {
    return InspirationState(
      images: images ?? this.images,
      isLoading: isLoading ?? this.isLoading,
      hasMore: hasMore ?? this.hasMore,
      error: error ?? this.error,
    );
  }
}

class InspirationNotifier extends StateNotifier<InspirationState> {
  final InspirationService _service;
  final Ref _ref;
  int _currentPage = 0;
  final Set<String> _seenImageUrls = {}; // Track seen images to prevent duplicates

  InspirationNotifier(this._service, this._ref) : super(const InspirationState());

  /// Get user's gender filter preference from database
  Future<String> _getUserGenderFilter() async {
    try {
      final user = _ref.read(authServiceProvider).currentUser;
      if (user == null) {
        print('DEBUG: No authenticated user, using default filter (all)');
        return 'all';
      }

      final supabase = Supabase.instance.client;
      final response = await supabase
          .from('users')
          .select('preferred_gender_filter')
          .eq('id', user.id)
          .maybeSingle();

      final genderFilter = response?['preferred_gender_filter'] as String? ?? 'all';
      print('DEBUG: User gender filter: $genderFilter');
      return genderFilter;
    } catch (e) {
      print('DEBUG: Error fetching gender filter: $e');
      return 'all'; // Default to showing all if there's an error
    }
  }

  /// Load initial inspiration images
  Future<void> loadImages() async {
    if (state.isLoading) return;

    print('DEBUG: Loading inspiration images...');
    state = state.copyWith(isLoading: true, error: null);

    try {
      final genderFilter = await _getUserGenderFilter();
      final images = await _service.fetchInspirationImages(
        page: 0,
        excludeImageUrls: _seenImageUrls,
        genderFilter: genderFilter,
      );
      print('DEBUG: Loaded ${images.length} images');

  
      // Track new images
      for (final image in images) {
        final imageUrl = image['image_url'] as String?;
        if (imageUrl != null) {
          _seenImageUrls.add(imageUrl);
        }
      }

      final hasMore = images.isNotEmpty;
  
      state = state.copyWith(
        images: images,
        isLoading: false,
        hasMore: hasMore, // Keep loading as long as we get any images
      );

      _currentPage = 1;

    } catch (e) {
      print('DEBUG: Error loading images: $e');
      state = state.copyWith(
        isLoading: false,
        error: e.toString(),
      );
    }
  }

  /// Load more images for infinite scrolling
  Future<void> loadMoreImages() async {
    if (state.isLoading || !state.hasMore) {
      return;
    }

    state = state.copyWith(isLoading: true);

    try {
      final genderFilter = await _getUserGenderFilter();
      final newImages = await _service.fetchInspirationImages(
        page: _currentPage,
        excludeImageUrls: _seenImageUrls,
        genderFilter: genderFilter,
      );


      if (newImages.isEmpty) {
        // If we get no results, try again with a different offset
        // Don't set hasMore to false to maintain infinite scrolling
        _currentPage++; // Skip this problematic page
        state = state.copyWith(
          isLoading: false,
          hasMore: true, // Always keep infinite scrolling active
        );
        return;
      }

      // Track new images
      for (final image in newImages) {
        final imageUrl = image['image_url'] as String?;
        if (imageUrl != null) {
          _seenImageUrls.add(imageUrl);
        }
      }

      final totalImages = state.images.length + newImages.length;
      final hasMore = newImages.isNotEmpty;

      state = state.copyWith(
        images: [...state.images, ...newImages],
        isLoading: false,
        hasMore: hasMore, // Keep loading as long as we get any new images
      );

      _currentPage++;

    } catch (e) {
      state = state.copyWith(
        isLoading: false,
        error: e.toString(),
      );
    }
  }

  /// Refresh images (pull-to-refresh)
  Future<void> refreshImages() async {
    // Keep existing data visible during refresh
    _currentPage = 0;
    _seenImageUrls.clear(); // Clear seen images on refresh

    try {
      final genderFilter = await _getUserGenderFilter();
      final images = await _service.fetchInspirationImages(
        page: 0,
        excludeImageUrls: _seenImageUrls,
        genderFilter: genderFilter,
      );

      // Track new images
      for (final image in images) {
        final imageUrl = image['image_url'] as String?;
        if (imageUrl != null) {
          _seenImageUrls.add(imageUrl);
        }
      }

      final hasMore = images.isNotEmpty;

      state = state.copyWith(
        images: images,
        isLoading: false,
        hasMore: hasMore,
        error: null,
      );

      _currentPage = 1;
    } catch (e) {
      state = state.copyWith(
        isLoading: false,
        error: e.toString(),
      );
    }
  }

  /// Clear error
  void clearError() {
    state = state.copyWith(error: null);
  }
}

// Providers
final inspirationServiceProvider = Provider<InspirationService>((ref) {
  return InspirationService();
});

final inspirationProvider = StateNotifierProvider<InspirationNotifier, InspirationState>((ref) {
  final service = ref.watch(inspirationServiceProvider);
  return InspirationNotifier(service, ref);
});