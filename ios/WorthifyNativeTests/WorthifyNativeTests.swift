import XCTest
@testable import WorthifyNative

final class WorthifyNativeTests: XCTestCase {
    func testPlaceholderAnalysisHasArtist() {
        XCTAssertFalse(ArtworkAnalysis.placeholder.artistText.isEmpty)
    }

    func testEstimatedValueFormatterLocalizesUsdRangeForNorwegianLocale() {
        let text = EstimatedValueFormatter.displayText(
            from: "$1,500 - $2,500",
            locale: Locale(identifier: "nb_NO")
        )

        XCTAssertNotNil(text)
        XCTAssertTrue(text?.contains("USD") == true)
        XCTAssertTrue(text?.contains("1") == true)
        XCTAssertTrue(text?.contains("500") == true)
        XCTAssertTrue(text?.contains("2") == true)
    }

    func testEstimatedValueFormatterParsesCurrencyCode() {
        let range = EstimatedValueFormatter.parse("$1,500 - $2,500")

        XCTAssertEqual(range?.currencyCode, "USD")
        XCTAssertEqual(range?.lowerBound, 1_500, accuracy: 0.001)
        XCTAssertEqual(range?.upperBound, 2_500, accuracy: 0.001)
    }

    func testCollectionValueSummarySumsEstimatedRanges() {
        let summary = CollectionValueSummary(items: [
            makeSavedArtwork(estimatedValueRange: "$1,500 - $2,500"),
            makeSavedArtwork(estimatedValueRange: "$750 - $1,250"),
            makeSavedArtwork(estimatedValueRange: nil)
        ])

        XCTAssertEqual(summary.estimatedLowerBound, 2_250, accuracy: 0.001)
        XCTAssertEqual(summary.estimatedUpperBound, 3_750, accuracy: 0.001)
        XCTAssertEqual(summary.currencyCode, "USD")
        XCTAssertEqual(summary.valuedItemCount, 2)
        XCTAssertEqual(summary.totalItemCount, 3)
    }

    func testCollectionValueSummaryParsesSingleValueEstimate() {
        let summary = CollectionValueSummary(items: [
            makeSavedArtwork(estimatedValueRange: "$500")
        ])

        XCTAssertEqual(summary.estimatedLowerBound, 500, accuracy: 0.001)
        XCTAssertEqual(summary.estimatedUpperBound, 500, accuracy: 0.001)
        XCTAssertEqual(summary.valuedItemCount, 1)
    }

    func testCollectionValueSummaryFlagsMixedCurrencies() {
        let summary = CollectionValueSummary(items: [
            makeSavedArtwork(estimatedValueRange: "$500"),
            makeSavedArtwork(estimatedValueRange: "\u{20AC}700")
        ])

        XCTAssertTrue(summary.hasMixedCurrencies)
        XCTAssertEqual(summary.totalEstimateText, "Mixed currencies")
    }
}

private func makeSavedArtwork(estimatedValueRange: String?) -> SavedArtwork {
    SavedArtwork(
        id: UUID(),
        userID: "test-user",
        imageURL: "https://example.com/image.jpg",
        identifiedArtist: "Test Artist",
        artworkTitle: "Test Work",
        yearEstimate: nil,
        style: nil,
        mediumGuess: nil,
        isOriginalOrPrint: nil,
        estimatedValueRange: estimatedValueRange,
        confidenceLevel: "medium",
        valueReasoning: nil,
        comparableExamplesSummary: nil,
        disclaimer: nil,
        createdAt: Date(timeIntervalSince1970: 0)
    )
}
