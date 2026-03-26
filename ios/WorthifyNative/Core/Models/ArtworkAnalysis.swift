import Foundation

struct ArtworkAnalysis: Codable, Identifiable, Equatable, Hashable {
    let id: UUID
    let identifiedArtist: String?
    let artworkTitle: String?
    let yearEstimate: String?
    let style: String?
    let mediumGuess: String?
    let isOriginalOrPrint: String?
    let confidenceLevel: String
    let estimatedValueRange: String?
    let valueReasoning: String?
    let comparableExamplesSummary: String?
    let disclaimer: String
    let sourceImageURL: URL?

    init(
        id: UUID = UUID(),
        identifiedArtist: String?,
        artworkTitle: String?,
        yearEstimate: String?,
        style: String?,
        mediumGuess: String?,
        isOriginalOrPrint: String?,
        confidenceLevel: String,
        estimatedValueRange: String?,
        valueReasoning: String?,
        comparableExamplesSummary: String?,
        disclaimer: String,
        sourceImageURL: URL? = nil
    ) {
        self.id = id
        self.identifiedArtist = identifiedArtist
        self.artworkTitle = artworkTitle
        self.yearEstimate = yearEstimate
        self.style = style
        self.mediumGuess = mediumGuess
        self.isOriginalOrPrint = isOriginalOrPrint
        self.confidenceLevel = confidenceLevel
        self.estimatedValueRange = estimatedValueRange
        self.valueReasoning = valueReasoning
        self.comparableExamplesSummary = comparableExamplesSummary
        self.disclaimer = disclaimer
        self.sourceImageURL = sourceImageURL
    }

    enum CodingKeys: String, CodingKey {
        case identifiedArtist = "identified_artist"
        case artworkTitle = "artwork_title"
        case yearEstimate = "year_estimate"
        case style
        case mediumGuess = "medium_guess"
        case isOriginalOrPrint = "is_original_or_print"
        case confidenceLevel = "confidence_level"
        case estimatedValueRange = "estimated_value_range"
        case valueReasoning = "value_reasoning"
        case comparableExamplesSummary = "comparable_examples_summary"
        case disclaimer
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = UUID()
        identifiedArtist = container.decodeLossyStringIfPresent(forKey: .identifiedArtist)
        artworkTitle = container.decodeLossyStringIfPresent(forKey: .artworkTitle)
        yearEstimate = container.decodeLossyStringIfPresent(forKey: .yearEstimate)
        style = container.decodeLossyStringIfPresent(forKey: .style)
        mediumGuess = container.decodeLossyStringIfPresent(forKey: .mediumGuess)
        isOriginalOrPrint = container.decodeLossyStringIfPresent(forKey: .isOriginalOrPrint)
        confidenceLevel = container.decodeLossyStringIfPresent(forKey: .confidenceLevel) ?? "unknown"
        estimatedValueRange = container.decodeLossyStringIfPresent(forKey: .estimatedValueRange)
        valueReasoning = container.decodeLossyStringIfPresent(forKey: .valueReasoning)
        comparableExamplesSummary = container.decodeLossyStringIfPresent(forKey: .comparableExamplesSummary)
        disclaimer = container.decodeLossyStringIfPresent(forKey: .disclaimer) ?? "No disclaimer provided."
        sourceImageURL = nil
    }

    var titleText: String {
        artworkTitle?.nilIfEmpty ?? "Untitled"
    }

    var artistText: String {
        identifiedArtist?.nilIfEmpty ?? "Unknown artist"
    }

    var confidenceText: String {
        switch confidenceLevel.lowercased() {
        case "high":
            return "High"
        case "medium":
            return "Medium"
        case "low":
            return "Low"
        default:
            return "Unknown"
        }
    }

    var summaryText: String {
        let parts = [
            style?.nilIfEmpty,
            mediumGuess?.nilIfEmpty,
            valueReasoning?.nilIfEmpty,
            comparableExamplesSummary?.nilIfEmpty
        ].compactMap { $0 }

        if parts.isEmpty {
            return disclaimer
        }

        return parts.joined(separator: "\n\n")
    }

    static let placeholder = ArtworkAnalysis(
        identifiedArtist: "Unknown Artist",
        artworkTitle: "Untitled Composition",
        yearEstimate: nil,
        style: "Unknown",
        mediumGuess: "Unknown",
        isOriginalOrPrint: "unknown",
        confidenceLevel: "medium",
        estimatedValueRange: "$1,500 - $2,500",
        valueReasoning: "Placeholder analysis used by the SwiftUI skeleton until the live detection pipeline is wired.",
        comparableExamplesSummary: nil,
        disclaimer: "This is an AI-generated estimate for informational purposes only. Not a certified appraisal."
    )
}

struct SavedArtwork: Codable, Identifiable, Equatable {
    let id: UUID
    let userID: String
    let imageURL: String
    let identifiedArtist: String?
    let artworkTitle: String?
    let yearEstimate: String?
    let style: String?
    let mediumGuess: String?
    let isOriginalOrPrint: String?
    let estimatedValueRange: String?
    let confidenceLevel: String?
    let valueReasoning: String?
    let comparableExamplesSummary: String?
    let disclaimer: String?
    let createdAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case userID = "user_id"
        case imageURL = "image_url"
        case identifiedArtist = "identified_artist"
        case artworkTitle = "artwork_title"
        case yearEstimate = "year_estimate"
        case style
        case mediumGuess = "medium_guess"
        case isOriginalOrPrint = "is_original_or_print"
        case estimatedValueRange = "estimated_value_range"
        case confidenceLevel = "confidence_level"
        case valueReasoning = "value_reasoning"
        case comparableExamplesSummary = "comparable_examples_summary"
        case disclaimer
        case createdAt = "created_at"
    }

    var titleText: String {
        artworkTitle?.nilIfEmpty ?? "Untitled"
    }

    var subtitleText: String {
        identifiedArtist?.nilIfEmpty ?? estimatedValueRange?.nilIfEmpty ?? "Saved analysis"
    }

    var remoteImageURL: URL? {
        URL(string: imageURL)
    }

    var createdDateText: String {
        createdAt.formatted(date: .abbreviated, time: .omitted)
    }

    var confidenceText: String? {
        confidenceLevel?.nilIfEmpty?.capitalized
    }

    var asArtworkAnalysis: ArtworkAnalysis {
        ArtworkAnalysis(
            identifiedArtist: identifiedArtist,
            artworkTitle: artworkTitle,
            yearEstimate: yearEstimate,
            style: style,
            mediumGuess: mediumGuess,
            isOriginalOrPrint: isOriginalOrPrint,
            confidenceLevel: confidenceLevel?.nilIfEmpty ?? "unknown",
            estimatedValueRange: estimatedValueRange,
            valueReasoning: valueReasoning,
            comparableExamplesSummary: comparableExamplesSummary,
            disclaimer: disclaimer?.nilIfEmpty ?? "Saved analysis.",
            sourceImageURL: remoteImageURL
        )
    }
}

private extension String {
    var nilIfEmpty: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

private extension KeyedDecodingContainer where K == ArtworkAnalysis.CodingKeys {
    func decodeLossyStringIfPresent(forKey key: K) -> String? {
        if let value = try? decodeIfPresent(String.self, forKey: key) {
            return value
        }
        if let value = try? decodeIfPresent(Int.self, forKey: key) {
            return String(value)
        }
        if let value = try? decodeIfPresent(Double.self, forKey: key) {
            return String(value)
        }
        if let value = try? decodeIfPresent(Bool.self, forKey: key) {
            return value ? "true" : "false"
        }
        if let value = try? decodeIfPresent([String].self, forKey: key) {
            return value.joined(separator: ", ")
        }
        return nil
    }
}
