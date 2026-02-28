import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/favorite_item.dart';
import '../services/favorites_service.dart';
import '../../../auth/domain/providers/auth_provider.dart';

// Service provider
final favoritesServiceProvider = Provider((ref) => FavoritesService());

// State notifier for favorites list
class FavoritesNotifier extends StateNotifier<AsyncValue<List<FavoriteItem>>> {
  final FavoritesService _service;

  // Cache of favorite product IDs for quick lookup
  Set<String> _favoriteIds = {};

  FavoritesNotifier(this._service) : super(const AsyncValue.loading()) {
    loadFavorites();
  }

  Set<String> get favoriteIds => _favoriteIds;

  /// Load all favorites from Supabase
  Future<void> loadFavorites() async {
    state = const AsyncValue.loading();
    state = await AsyncValue.guard(() async {
      final favorites = await _service.getFavorites();
      _favoriteIds = favorites.map((f) => f.productId).toSet();
      return favorites;
    });
  }

  /// Remove a product from favorites (optimistic update)
  Future<void> removeFavorite(String productId) async {
    // Optimistic update - remove from local state immediately
    _favoriteIds.remove(productId);

    final previousState = state;
    state.whenData((favorites) {
      final updatedFavorites =
          favorites.where((f) => f.productId != productId).toList();
      state = AsyncValue.data(updatedFavorites);
    });

    // Sync with Supabase in background
    try {
      await _service.removeFavorite(productId);
    } catch (e) {
      // Rollback optimistic update on error
      _favoriteIds.add(productId);
      state = previousState;
      rethrow;
    }
  }

  /// Check if a product is favorited (local check, instant)
  bool isFavorite(String productId) {
    return _favoriteIds.contains(productId);
  }

  /// Refresh favorites from server (without losing current data)
  Future<void> refresh() async {
    // Don't set state to loading - keep existing data visible
    final result = await AsyncValue.guard(() async {
      final favorites = await _service.getFavorites();
      _favoriteIds = favorites.map((f) => f.productId).toSet();
      return favorites;
    });
    state = result;
  }

  void clear() {
    _favoriteIds = {};
    state = const AsyncValue.data([]);
  }
}

// Provider for favorites state
final favoritesProvider =
    StateNotifierProvider<FavoritesNotifier, AsyncValue<List<FavoriteItem>>>(
  (ref) {
    final notifier = FavoritesNotifier(ref.watch(favoritesServiceProvider));

    // Reload favorites when auth state changes (e.g., after login), and clear on logout
    ref.listen(authStateProvider, (previous, next) {
      final wasAuthenticated = previous?.value?.session != null;
      final isAuthenticated = next.value?.session != null;

      if (isAuthenticated && !wasAuthenticated) {
        notifier.loadFavorites();
      } else if (!isAuthenticated && wasAuthenticated) {
        notifier.clear();
      }
    });

    return notifier;
  },
);

// Provider to check if a specific product is favorited
final isFavoriteProvider = Provider.family<bool, String>((ref, productId) {
  final favoritesState = ref.watch(favoritesProvider);
  return favoritesState.maybeWhen(
    data: (favorites) => favorites.any((f) => f.productId == productId),
    orElse: () => false,
  );
});

// Provider for favorites count
final favoritesCountProvider = Provider<int>((ref) {
  return ref.watch(favoritesProvider).maybeWhen(
        data: (favorites) => favorites.length,
        orElse: () => 0,
      );
});
