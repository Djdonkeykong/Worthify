import Foundation

struct ArtworkAnalysis: Codable, Identifiable, Equatable {
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
        identifiedArtist = try container.decodeIfPresent(String.self, forKey: .identifiedArtist)
        artworkTitle = try container.decodeIfPresent(String.self, forKey: .artworkTitle)
        yearEstimate = try container.decodeIfPresent(String.self, forKey: .yearEstimate)
        style = try container.decodeIfPresent(String.self, forKey: .style)
        mediumGuess = try container.decodeIfPresent(String.self, forKey: .mediumGuess)
        isOriginalOrPrint = try container.decodeIfPresent(String.self, forKey: .isOriginalOrPrint)
        confidenceLevel = try container.decode(String.self, forKey: .confidenceLevel)
        estimatedValueRange = try container.decodeIfPresent(String.self, forKey: .estimatedValueRange)
        valueReasoning = try container.decodeIfPresent(String.self, forKey: .valueReasoning)
        comparableExamplesSummary = try container.decodeIfPresent(String.self, forKey: .comparableExamplesSummary)
        disclaimer = try container.decode(String.self, forKey: .disclaimer)
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
    let estimatedValueRange: String?
    let confidenceLevel: String?
    let createdAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case userID = "user_id"
        case imageURL = "image_url"
        case identifiedArtist = "identified_artist"
        case artworkTitle = "artwork_title"
        case estimatedValueRange = "estimated_value_range"
        case confidenceLevel = "confidence_level"
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
}

private extension String {
    var nilIfEmpty: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
