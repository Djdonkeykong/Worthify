class ArtworkResult {
  const ArtworkResult({
    this.identifiedArtist,
    this.artworkTitle,
    this.yearEstimate,
    this.style,
    this.mediumGuess,
    this.isOriginalOrPrint,
    this.confidenceLevel = 'unknown',
    this.estimatedValueRange,
    this.valueReasoning,
    this.comparableExamplesSummary,
    this.disclaimer = 'This is an AI-generated estimate for informational purposes only. Not a certified appraisal.',
  });

  final String? identifiedArtist;
  final String? artworkTitle;
  final String? yearEstimate;
  final String? style;
  final String? mediumGuess;

  /// "original" | "print" | "unknown"
  final String? isOriginalOrPrint;

  /// "low" | "medium" | "high"
  final String confidenceLevel;

  final String? estimatedValueRange;
  final String? valueReasoning;
  final String? comparableExamplesSummary;
  final String disclaimer;

  factory ArtworkResult.fromJson(Map<String, dynamic> json) {
    return ArtworkResult(
      identifiedArtist: json['identified_artist'] as String?,
      artworkTitle: json['artwork_title'] as String?,
      yearEstimate: json['year_estimate'] as String?,
      style: json['style'] as String?,
      mediumGuess: json['medium_guess'] as String?,
      isOriginalOrPrint: json['is_original_or_print'] as String?,
      confidenceLevel: (json['confidence_level'] as String?) ?? 'unknown',
      estimatedValueRange: json['estimated_value_range'] as String?,
      valueReasoning: json['value_reasoning'] as String?,
      comparableExamplesSummary: json['comparable_examples_summary'] as String?,
      disclaimer: (json['disclaimer'] as String?) ??
          'This is an AI-generated estimate for informational purposes only. Not a certified appraisal.',
    );
  }

  Map<String, dynamic> toJson() => {
        'identified_artist': identifiedArtist,
        'artwork_title': artworkTitle,
        'year_estimate': yearEstimate,
        'style': style,
        'medium_guess': mediumGuess,
        'is_original_or_print': isOriginalOrPrint,
        'confidence_level': confidenceLevel,
        'estimated_value_range': estimatedValueRange,
        'value_reasoning': valueReasoning,
        'comparable_examples_summary': comparableExamplesSummary,
        'disclaimer': disclaimer,
      };
}
