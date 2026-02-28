import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

/// Provider to hold pending shared media from iOS Share Extension
/// This allows the share data to be passed from main.dart to HomePage
final pendingSharedImageProvider = StateProvider<XFile?>((ref) => null);

/// Provider to hold the source URL for pending shared media (e.g., Instagram post URL)
/// Used for cache matching when the same image is analyzed again
final pendingShareSourceUrlProvider = StateProvider<String?>((ref) => null);

/// Tracks whether the native share flow already triggered navigation so the
/// HomePage listener can avoid pushing a duplicate DetectionPage.
final shareNavigationInProgressProvider =
    StateProvider<bool>((ref) => false);
