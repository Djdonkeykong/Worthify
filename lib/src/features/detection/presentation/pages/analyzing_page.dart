import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../../../../core/theme/app_colors.dart';
import '../../../../services/cloudinary_service.dart';
import '../../domain/services/artwork_service.dart';
import 'artwork_result_page.dart';

class AnalyzingPage extends StatefulWidget {
  final XFile imageFile;

  const AnalyzingPage({super.key, required this.imageFile});

  @override
  State<AnalyzingPage> createState() => _AnalyzingPageState();
}

class _AnalyzingPageState extends State<AnalyzingPage>
    with SingleTickerProviderStateMixin {
  late final AnimationController _dotController;
  String _status = 'Uploading image...';

  @override
  void initState() {
    super.initState();
    _dotController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat();
    _runAnalysis();
  }

  @override
  void dispose() {
    _dotController.dispose();
    super.dispose();
  }

  Future<void> _runAnalysis() async {
    try {
      _setStatus('Uploading image...');
      final bytes = await File(widget.imageFile.path).readAsBytes();
      final cloudinaryUrl = await CloudinaryService().uploadImage(bytes);

      if (!mounted) return;

      if (cloudinaryUrl == null) {
        _showError(
          'Image upload failed. Please add Cloudinary credentials to your .env file.',
        );
        return;
      }

      _setStatus('Searching art databases...');
      final result = await ArtworkService().identifyArtwork(cloudinaryUrl);

      if (!mounted) return;

      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (_) => ArtworkResultPage(
            result: result,
            imageUrl: cloudinaryUrl,
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      _showError('Could not identify artwork. Please try again.');
    }
  }

  void _setStatus(String status) {
    if (mounted) setState(() => _status = status);
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: const Color(0xFFEF4444),
        duration: const Duration(seconds: 5),
      ),
    );
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final imageFile = File(widget.imageFile.path);

    return Scaffold(
      backgroundColor: const Color(0xFFF3F3F6),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
          child: Column(
            children: [
              Align(
                alignment: Alignment.centerLeft,
                child: GestureDetector(
                  onTap: () => Navigator.of(context).pop(),
                  child: Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.92),
                      shape: BoxShape.circle,
                      boxShadow: const [
                        BoxShadow(
                          color: Color(0x11000000),
                          blurRadius: 14,
                          offset: Offset(0, 4),
                        ),
                      ],
                    ),
                    child: const Icon(
                      Icons.arrow_back,
                      color: AppColors.secondary,
                      size: 20,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Expanded(
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 560),
                    child: Container(
                      decoration: BoxDecoration(
                        color: AppColors.primary,
                        borderRadius: BorderRadius.circular(36),
                        boxShadow: const [
                          BoxShadow(
                            color: Color(0x18000000),
                            blurRadius: 26,
                            offset: Offset(0, 12),
                          ),
                        ],
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Padding(
                            padding: EdgeInsets.fromLTRB(26, 28, 26, 14),
                            child: Text(
                              'Add an Artwork',
                              style: TextStyle(
                                fontSize: 26,
                                fontWeight: FontWeight.w700,
                                color: AppColors.secondary,
                                height: 1.05,
                              ),
                            ),
                          ),
                          Expanded(
                            child: Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 16),
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(24),
                                child: Container(
                                  color: const Color(0xFFEDEBF0),
                                  child: Image.file(
                                    imageFile,
                                    fit: BoxFit.contain,
                                    width: double.infinity,
                                    height: double.infinity,
                                  ),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(height: 12),
                          Padding(
                            padding: const EdgeInsets.fromLTRB(24, 16, 24, 28),
                            child: Column(
                              children: [
                                _AnimatedDots(
                                  controller: _dotController,
                                  color: const Color(0xFFC2971A),
                                ),
                                const SizedBox(height: 14),
                                Text(
                                  _status.replaceAll('...', '...'),
                                  style: const TextStyle(
                                    color: Color(0xFFC2971A),
                                    fontSize: 16,
                                    fontWeight: FontWeight.w500,
                                    height: 1.2,
                                  ),
                                  textAlign: TextAlign.center,
                                ),
                                const SizedBox(height: 6),
                                const Text(
                                  'This usually takes 5-10 seconds',
                                  style: TextStyle(
                                    color: Color(0xFF8F8B95),
                                    fontSize: 13,
                                    fontWeight: FontWeight.w500,
                                  ),
                                  textAlign: TextAlign.center,
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AnimatedDots extends AnimatedWidget {
  final Color color;

  const _AnimatedDots({
    required AnimationController controller,
    this.color = Colors.white,
  }) : super(listenable: controller);

  @override
  Widget build(BuildContext context) {
    final t = (listenable as AnimationController).value;
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List.generate(3, (i) {
        final phase = ((t + i / 3) % 1.0);
        final opacity = phase < 0.5 ? phase * 2 : (1.0 - phase) * 2;
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 5),
          child: Opacity(
            opacity: 0.3 + opacity * 0.7,
            child: Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                color: color,
                shape: BoxShape.circle,
              ),
            ),
          ),
        );
      }),
    );
  }
}
