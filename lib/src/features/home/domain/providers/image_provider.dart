import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as path;

class SelectedImagesState {
  final List<XFile> images;
  final int currentIndex;
  final String? networkImageUrl; // Add support for network images

  const SelectedImagesState({
    required this.images,
    this.currentIndex = 0,
    this.networkImageUrl,
  });

  XFile? get currentImage => images.isEmpty ? null : images[currentIndex];
  bool get hasMultipleImages => images.length > 1;
  int get totalImages => images.length;
  bool get hasNetworkImage => networkImageUrl != null;

  SelectedImagesState copyWith({
    List<XFile>? images,
    int? currentIndex,
    String? networkImageUrl,
  }) {
    return SelectedImagesState(
      images: images ?? this.images,
      currentIndex: currentIndex ?? this.currentIndex,
      networkImageUrl: networkImageUrl ?? this.networkImageUrl,
    );
  }
}

class SelectedImagesNotifier extends StateNotifier<SelectedImagesState> {
  SelectedImagesNotifier() : super(const SelectedImagesState(images: []));

  void setImage(XFile image) {
    state = SelectedImagesState(images: [image], currentIndex: 0, networkImageUrl: null);
  }

  void setImages(List<XFile> images) {
    state = SelectedImagesState(images: images, currentIndex: 0, networkImageUrl: null);
  }

  void setNetworkImage(String imageUrl) {
    state = SelectedImagesState(images: [], currentIndex: 0, networkImageUrl: imageUrl);
  }

  Future<void> setNetworkImageAsFile(String imageUrl) async {
    try {
      // Download the image and create an XFile from it
      final response = await http.get(Uri.parse(imageUrl));
      if (response.statusCode == 200) {
        final tempDir = Directory.systemTemp;
        final fileName = path.basename(Uri.parse(imageUrl).path);
        final file = File('${tempDir.path}/scan_$fileName');
        await file.writeAsBytes(response.bodyBytes);
        final xFile = XFile(file.path);
        setImage(xFile);
      } else {
        throw Exception('Failed to download image');
      }
    } catch (e) {
      // Fallback to network URL if download fails
      setNetworkImage(imageUrl);
    }
  }

  void setCurrentIndex(int index) {
    if (index >= 0 && index < state.images.length) {
      state = state.copyWith(currentIndex: index);
    }
  }

  void clearImages() {
    state = const SelectedImagesState(images: [], networkImageUrl: null);
  }
}

final selectedImagesProvider = StateNotifierProvider<SelectedImagesNotifier, SelectedImagesState>(
  (ref) => SelectedImagesNotifier(),
);

// Legacy provider for backward compatibility
final selectedImageProvider = Provider<XFile?>((ref) {
  return ref.watch(selectedImagesProvider).currentImage;
});