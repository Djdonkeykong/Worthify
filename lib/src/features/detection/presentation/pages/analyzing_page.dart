import 'dart:io';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
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
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        fit: StackFit.expand,
        children: [
          // Background image
          Image.file(
            File(widget.imageFile.path),
            fit: BoxFit.cover,
          ),

          // Gradient overlay
          const DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Color(0x55000000), Color(0xDD000000)],
                stops: [0.3, 1.0],
              ),
            ),
          ),

          // UI
          SafeArea(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Back button
                GestureDetector(
                  onTap: () => Navigator.of(context).pop(),
                  child: Container(
                    margin: const EdgeInsets.all(16),
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.2),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.arrow_back,
                      color: Colors.white,
                      size: 20,
                    ),
                  ),
                ),

                const Spacer(),

                // Status area
                Padding(
                  padding: const EdgeInsets.fromLTRB(32, 0, 32, 52),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      _AnimatedDots(controller: _dotController),
                      const SizedBox(height: 20),
                      Text(
                        _status,
                        style: GoogleFonts.inter(
                          color: Colors.white,
                          fontSize: 17,
                          fontWeight: FontWeight.w500,
                        ),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'This usually takes 5–10 seconds',
                        style: GoogleFonts.inter(
                          color: Colors.white60,
                          fontSize: 13,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _AnimatedDots extends AnimatedWidget {
  const _AnimatedDots({required AnimationController controller})
      : super(listenable: controller);

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
              decoration: const BoxDecoration(
                color: Colors.white,
                shape: BoxShape.circle,
              ),
            ),
          ),
        );
      }),
    );
  }
}
