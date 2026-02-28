import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Provider to track when feed preferences change
/// This triggers a refresh of the home feed when the user updates their preference
final feedPreferenceChangeProvider = StateProvider<int>((ref) => 0);

/// Increment this to trigger a refresh of the home feed
void notifyFeedPreferenceChanged(WidgetRef ref) {
  ref.read(feedPreferenceChangeProvider.notifier).state++;
}
