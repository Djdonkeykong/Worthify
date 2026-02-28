import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../shared/services/supabase_service.dart';
import '../../../auth/domain/providers/auth_provider.dart';

final historyProvider =
    FutureProvider.autoDispose<List<Map<String, dynamic>>>((ref) async {
  final supabaseService = SupabaseService();
  // Wait for auth initialization so we don't briefly emit empty history
  // during app startup before session restoration completes.
  final authState = await ref.watch(authStateProvider.future);
  final userId = authState.session?.user.id;

  if (userId == null) {
    debugPrint('[History] No authenticated user - returning empty history');
    return const [];
  }

  debugPrint('[History] Fetching history for user $userId');
  return await supabaseService.getUserSearches(userId: userId);
});
