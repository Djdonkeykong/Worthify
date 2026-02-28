import 'package:flutter_riverpod/flutter_riverpod.dart';

enum HistoryBootstrapState {
  unknown,
  hasHistory,
  noHistory,
}

final historyBootstrapProvider =
    StateProvider<HistoryBootstrapState>((ref) => HistoryBootstrapState.unknown);

