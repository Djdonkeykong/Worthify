import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../../../core/theme/app_colors.dart';
import '../../../../../core/theme/theme_extensions.dart';
import '../../domain/models/artwork_result.dart';

class ArtworkResultPage extends ConsumerStatefulWidget {
  final ArtworkResult result;
  final String imageUrl;

  const ArtworkResultPage({
    super.key,
    required this.result,
    required this.imageUrl,
  });

  @override
  ConsumerState<ArtworkResultPage> createState() => _ArtworkResultPageState();
}

class _ArtworkResultPageState extends ConsumerState<ArtworkResultPage> {
  bool _isSaved = false;
  bool _isSaving = false;

  Future<void> _saveToCollection() async {
    if (_isSaving || _isSaved) return;
    setState(() => _isSaving = true);

    try {
      final user = Supabase.instance.client.auth.currentUser;
      if (user == null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Sign in to save artworks')),
          );
        }
        setState(() => _isSaving = false);
        return;
      }

      final r = widget.result;
      await Supabase.instance.client.from('artwork_identifications').insert({
        'user_id': user.id,
        'image_url': widget.imageUrl,
        'identified_artist': r.identifiedArtist,
        'artwork_title': r.artworkTitle,
        'year_estimate': r.yearEstimate,
        'style': r.style,
        'medium_guess': r.mediumGuess,
        'is_original_or_print': r.isOriginalOrPrint,
        'confidence_level': r.confidenceLevel,
        'estimated_value_range': r.estimatedValueRange,
        'value_reasoning': r.valueReasoning,
        'comparable_examples_summary': r.comparableExamplesSummary,
        'disclaimer': r.disclaimer,
        'is_saved': true,
      });

      if (mounted) {
        HapticFeedback.mediumImpact();
        setState(() {
          _isSaved = true;
          _isSaving = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Saved to your collection')),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isSaving = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not save: $e')),
        );
      }
    }
  }

  Color _confidenceColor(String level) => switch (level.toLowerCase()) {
        'high' => const Color(0xFF22C55E),
        'medium' => const Color(0xFFF59E0B),
        'low' => const Color(0xFFEF4444),
        _ => const Color(0xFF9C9A97),
      };

  String _confidenceLabel(String level) => switch (level.toLowerCase()) {
        'high' => 'High confidence',
        'medium' => 'Medium confidence',
        'low' => 'Low confidence',
        _ => 'Confidence unknown',
      };

  @override
  Widget build(BuildContext context) {
    final r = widget.result;
    final spacing = context.spacing;
    final imageHeight = MediaQuery.of(context).size.height * 0.42;
    final bottomPad = MediaQuery.of(context).padding.bottom;

    return Scaffold(
      backgroundColor: AppColors.primary,
      body: Stack(
        children: [
          // Scrollable content
          CustomScrollView(
            slivers: [
              // Image hero
              SliverAppBar(
                expandedHeight: imageHeight,
                pinned: true,
                backgroundColor: AppColors.primary,
                elevation: 0,
                leading: _CircleBackButton(),
                flexibleSpace: FlexibleSpaceBar(
                  collapseMode: CollapseMode.pin,
                  background: CachedNetworkImage(
                    imageUrl: widget.imageUrl,
                    fit: BoxFit.cover,
                    placeholder: (_, __) =>
                        Container(color: AppColors.primaryDark),
                    errorWidget: (_, __, ___) =>
                        Container(color: AppColors.primaryDark),
                  ),
                ),
              ),

              SliverToBoxAdapter(
                child: Transform.translate(
                  offset: const Offset(0, -20),
                  child: Container(
                    decoration: const BoxDecoration(
                      color: AppColors.primary,
                      borderRadius:
                          BorderRadius.vertical(top: Radius.circular(20)),
                    ),
                    child: Padding(
                      padding: EdgeInsets.fromLTRB(
                        spacing.m,
                        spacing.l,
                        spacing.m,
                        120 + bottomPad,
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Handle
                          Center(
                            child: Container(
                              width: 40,
                              height: 4,
                              margin: EdgeInsets.only(bottom: spacing.l),
                              decoration: BoxDecoration(
                                color: AppColors.outline,
                                borderRadius: BorderRadius.circular(2),
                              ),
                            ),
                          ),

                          const Text(
                            'ESTIMATED ARTWORK',
                            style: TextStyle(
                              fontSize: 11,
                              letterSpacing: 1.2,
                              fontWeight: FontWeight.w600,
                              color: Color(0xFF9C9A97),
                            ),
                          ),
                          SizedBox(height: spacing.s),
                          const Text(
                            'Painting',
                            style: TextStyle(
                              fontSize: 38,
                              fontWeight: FontWeight.w700,
                              color: AppColors.secondary,
                              height: 1.02,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            (r.identifiedArtist != null &&
                                    r.identifiedArtist!.trim().isNotEmpty)
                                ? r.identifiedArtist!.trim()
                                : 'Unknown artist',
                            style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w500,
                              color: Color(0xFF6B6966),
                              height: 1.25,
                            ),
                          ),
                          SizedBox(height: spacing.m),
                          if (r.estimatedValueRange != null &&
                              r.estimatedValueRange!.trim().isNotEmpty) ...[
                            Text(
                              r.estimatedValueRange!.trim(),
                              style: const TextStyle(
                                fontSize: 28,
                                fontWeight: FontWeight.w600,
                                color: AppColors.secondary,
                                height: 1.1,
                              ),
                            ),
                            const SizedBox(height: 4),
                            const Text(
                              'Estimated market value',
                              style: TextStyle(
                                fontSize: 13,
                                color: Color(0xFF9C9A97),
                              ),
                            ),
                            SizedBox(height: spacing.m),
                          ],
                          _ConfidenceBadge(
                            label: _confidenceLabel(r.confidenceLevel),
                            color: _confidenceColor(r.confidenceLevel),
                          ),
                          Padding(
                            padding: EdgeInsets.symmetric(vertical: spacing.m),
                            child: Divider(color: AppColors.outline, height: 1),
                          ),
                          if (r.artworkTitle != null &&
                              r.artworkTitle!.trim().isNotEmpty) ...[
                            Text(
                              r.artworkTitle!.trim(),
                              style: const TextStyle(
                                fontSize: 21,
                                fontWeight: FontWeight.w600,
                                color: AppColors.secondary,
                                height: 1.2,
                              ),
                            ),
                            const SizedBox(height: 4),
                          ],
                          if (r.yearEstimate != null &&
                              r.yearEstimate!.trim().isNotEmpty) ...[
                            Text(
                              r.yearEstimate!.trim(),
                              style: const TextStyle(
                                fontSize: 15,
                                color: Color(0xFF6B6966),
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                            SizedBox(height: spacing.m),
                          ],
                          if ((r.style != null && r.style!.trim().isNotEmpty) ||
                              (r.mediumGuess != null &&
                                  r.mediumGuess!.trim().isNotEmpty) ||
                              (r.isOriginalOrPrint != null &&
                                  r.isOriginalOrPrint!.trim().isNotEmpty &&
                                  r.isOriginalOrPrint != 'unknown'))
                            _ExpandableSection(
                              title: 'Artwork details',
                              content: [
                                if (r.style != null &&
                                    r.style!.trim().isNotEmpty)
                                  'Style: ${r.style!.trim()}',
                                if (r.mediumGuess != null &&
                                    r.mediumGuess!.trim().isNotEmpty)
                                  'Medium: ${r.mediumGuess!.trim()}',
                                if (r.isOriginalOrPrint != null &&
                                    r.isOriginalOrPrint!.trim().isNotEmpty &&
                                    r.isOriginalOrPrint != 'unknown')
                                  'Type: ${_capitalize(r.isOriginalOrPrint!.trim())}',
                              ].join('\n'),
                            ),
                          SizedBox(height: spacing.m),
                          // ── EXPANDABLE SECTIONS ───────────────────────
                          if (r.valueReasoning != null &&
                              r.valueReasoning!.isNotEmpty)
                            _ExpandableSection(
                              title: 'About this estimate',
                              content: r.valueReasoning!,
                            ),

                          if (r.comparableExamplesSummary != null &&
                              r.comparableExamplesSummary!.isNotEmpty)
                            _ExpandableSection(
                              title: 'Comparable sales',
                              content: r.comparableExamplesSummary!,
                            ),

                          SizedBox(height: spacing.m),

                          // Disclaimer
                          Container(
                            padding: EdgeInsets.all(spacing.m),
                            decoration: BoxDecoration(
                              color: AppColors.primaryDark,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Text(
                              r.disclaimer,
                              style: TextStyle(
                                fontSize: 12,
                                color: const Color(0xFF9C9A97),
                                height: 1.6,
                              ),
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

          // ── STICKY SAVE BUTTON ───────────────────────────────────────
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: Container(
              padding: EdgeInsets.fromLTRB(16, 12, 16, bottomPad + 12),
              decoration: BoxDecoration(
                color: AppColors.primary,
                border: Border(
                  top: BorderSide(color: AppColors.outline),
                ),
              ),
              child: GestureDetector(
                onTap: _saveToCollection,
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  height: 52,
                  decoration: BoxDecoration(
                    color: _isSaved
                        ? AppColors.primaryDark
                        : AppColors.secondary,
                    borderRadius: BorderRadius.circular(28),
                  ),
                  child: Center(
                    child: _isSaving
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              color: Colors.white,
                              strokeWidth: 2,
                            ),
                          )
                        : Text(
                            _isSaved
                                ? 'Saved to Collection'
                                : 'Save to Collection',
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w600,
                              color: _isSaved
                                  ? const Color(0xFF6B6966)
                                  : Colors.white,
                            ),
                          ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

String _capitalize(String s) =>
    s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);

// ── Widgets ──────────────────────────────────────────────────────────────────

class _CircleBackButton extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(8),
      child: GestureDetector(
        onTap: () => Navigator.of(context).pop(),
        child: Container(
          decoration: BoxDecoration(
            color: Colors.black.withOpacity(0.45),
            shape: BoxShape.circle,
          ),
          child: const Icon(Icons.arrow_back, color: Colors.white, size: 20),
        ),
      ),
    );
  }
}

class _ConfidenceBadge extends StatelessWidget {
  final String label;
  final Color color;

  const _ConfidenceBadge({required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w500,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}

class _ExpandableSection extends StatefulWidget {
  final String title;
  final String content;

  const _ExpandableSection({required this.title, required this.content});

  @override
  State<_ExpandableSection> createState() => _ExpandableSectionState();
}

class _ExpandableSectionState extends State<_ExpandableSection> {
  bool _open = false;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        GestureDetector(
          onTap: () => setState(() => _open = !_open),
          behavior: HitTestBehavior.opaque,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 14),
            child: Row(
              children: [
                Text(
                  widget.title,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: AppColors.secondary,
                  ),
                ),
                const Spacer(),
                Icon(
                  _open
                      ? Icons.keyboard_arrow_up
                      : Icons.keyboard_arrow_down,
                  color: const Color(0xFF9C9A97),
                  size: 20,
                ),
              ],
            ),
          ),
        ),
        Divider(color: AppColors.outline, height: 1),
        if (_open)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Text(
              widget.content,
              style: TextStyle(
                fontSize: 14,
                color: const Color(0xFF6B6966),
                height: 1.65,
              ),
            ),
          ),
      ],
    );
  }
}

