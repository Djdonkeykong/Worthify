import SwiftUI

struct CollectionView: View {
    @EnvironmentObject private var environment: AppEnvironment
    @State private var items: [SavedArtwork] = []
    @State private var errorMessage: String?
    @State private var searchText = ""
    @State private var sortOption: CollectionSortOption = .newest
    @State private var confidenceFilter: CollectionConfidenceFilter = .all

    private var collectionValueSummary: CollectionValueSummary {
        CollectionValueSummary(items: items)
    }

    private var filteredItems: [SavedArtwork] {
        let normalizedQuery = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()

        let matchingItems = items.filter { item in
            let matchesQuery: Bool
            if normalizedQuery.isEmpty {
                matchesQuery = true
            } else {
                let haystacks = [
                    item.artworkTitle ?? "",
                    item.identifiedArtist ?? "",
                    item.estimatedValueRange ?? ""
                ].map { $0.lowercased() }

                matchesQuery = haystacks.contains { $0.contains(normalizedQuery) }
            }

            let matchesConfidence = confidenceFilter.matches(item)
            return matchesQuery && matchesConfidence
        }

        return sortOption.sorted(using: matchingItems)
    }

    private var hasActiveFilters: Bool {
        !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || confidenceFilter != .all
    }

    private var requiresSignIn: Bool {
        !environment.config.bypassAuth && signedInSession == nil
    }

    private var signedInSession: AppSession? {
        if case let .signedIn(session) = environment.sessionStore.state {
            return session
        }
        return nil
    }

    var body: some View {
        List {
            if !requiresSignIn && !items.isEmpty {
                Section {
                    CollectionInsightsCard(
                        summary: collectionValueSummary,
                        visibleItemCount: filteredItems.count,
                        sortOptionTitle: sortOption.title,
                        hasActiveFilters: hasActiveFilters
                    )
                }
                .listRowBackground(Color.clear)
            }

            if requiresSignIn {
                Section("Collection") {
                    Text("Sign in to view saved items.")
                        .foregroundStyle(.secondary)
                }
            } else if items.isEmpty {
                Section("Collection") {
                    Text("No saved artworks yet.")
                        .foregroundStyle(.secondary)
                }
            } else if filteredItems.isEmpty {
                Section("Collection") {
                    Text("No artworks match your current search or filters.")
                        .foregroundStyle(.secondary)
                }
            } else {
                Section("Collection") {
                    ForEach(filteredItems) { item in
                        NavigationLink {
                            ResultsView(result: item.asArtworkAnalysis)
                        } label: {
                            HStack(spacing: 12) {
                                ArtworkThumbnail(url: item.remoteImageURL)

                                VStack(alignment: .leading, spacing: 4) {
                                    Text(item.titleText)
                                        .font(.body.weight(.semibold))
                                        .lineLimit(2)
                                    Text(subtitleText(for: item))
                                        .font(.subheadline)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                    HStack(spacing: 8) {
                                        Text(item.createdDateText)
                                            .font(.footnote)
                                            .foregroundStyle(.tertiary)

                                        if let confidence = item.confidenceText {
                                            ConfidenceBadge(label: confidence)
                                        }
                                    }
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            .padding(.vertical, 4)
                        }
                    }
                }
            }

            if let errorMessage {
                Section("Error") {
                    Text(errorMessage)
                        .foregroundStyle(.red)
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Collection")
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $searchText, prompt: "Search artist, title, or value")
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Menu {
                    Picker("Sort", selection: $sortOption) {
                        ForEach(CollectionSortOption.allCases) { option in
                            Text(option.title).tag(option)
                        }
                    }

                    Picker("Confidence", selection: $confidenceFilter) {
                        ForEach(CollectionConfidenceFilter.allCases) { filter in
                            Text(filter.title).tag(filter)
                        }
                    }

                    if hasActiveFilters {
                        Button("Clear Filters") {
                            searchText = ""
                            confidenceFilter = .all
                        }
                    }
                } label: {
                    Image(systemName: hasActiveFilters ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease.circle")
                }
            }
        }
        .task { await load() }
        .refreshable { await load() }
    }

    private func load() async {
        if requiresSignIn {
            items = []
            errorMessage = nil
            return
        }

        do {
            items = try await environment.collectionService.fetchRecentItems()
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func subtitleText(for item: SavedArtwork) -> String {
        if let artist = item.identifiedArtist?.trimmingCharacters(in: .whitespacesAndNewlines), !artist.isEmpty {
            return artist
        }

        if let localizedValue = EstimatedValueFormatter.displayText(from: item.estimatedValueRange) {
            return localizedValue
        }

        return "Saved analysis"
    }
}

private struct CollectionInsightsCard: View {
    let summary: CollectionValueSummary
    let visibleItemCount: Int
    let sortOptionTitle: String
    let hasActiveFilters: Bool

    private let columns = [
        GridItem(.flexible(), spacing: 10),
        GridItem(.flexible(), spacing: 10)
    ]

    var body: some View {
        GlassCard {
            SectionHeading("Collection Snapshot", subtitle: summary.coverageText)

            LazyVGrid(columns: columns, spacing: 10) {
                MetricPill(title: "Collection value", value: summary.totalEstimateText)
                MetricPill(title: "Saved works", value: "\(summary.totalItemCount)")
                MetricPill(title: "Valued works", value: "\(summary.valuedItemCount)")
                MetricPill(title: "Avg confidence", value: summary.averageConfidenceText)
            }

            HStack {
                Text(hasActiveFilters ? "Showing \(visibleItemCount) of \(summary.totalItemCount)" : "Showing all \(summary.totalItemCount)")
                    .font(.footnote)
                    .foregroundStyle(.secondary)

                Spacer(minLength: 12)

                Text("Sorted by \(sortOptionTitle)")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
        }
    }
}

private struct ArtworkThumbnail: View {
    let url: URL?

    var body: some View {
        Group {
            if let url {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case let .success(image):
                        image
                            .resizable()
                            .scaledToFill()
                    case .failure, .empty:
                        placeholder
                    @unknown default:
                        placeholder
                    }
                }
            } else {
                placeholder
            }
        }
        .frame(width: 64, height: 64)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private var placeholder: some View {
        ZStack {
            Color(uiColor: .tertiarySystemFill)
            Image(systemName: "photo")
                .foregroundStyle(.secondary)
        }
    }
}

private enum CollectionSortOption: String, CaseIterable, Identifiable {
    case newest
    case oldest
    case highestValue
    case lowestValue
    case artistAZ

    var id: String { rawValue }

    var title: String {
        switch self {
        case .newest:
            return "Newest"
        case .oldest:
            return "Oldest"
        case .highestValue:
            return "Highest Value"
        case .lowestValue:
            return "Lowest Value"
        case .artistAZ:
            return "Artist A-Z"
        }
    }

    func sorted(using items: [SavedArtwork]) -> [SavedArtwork] {
        switch self {
        case .newest:
            return items.sorted { $0.createdAt > $1.createdAt }
        case .oldest:
            return items.sorted { $0.createdAt < $1.createdAt }
        case .highestValue:
            return items.sorted { valueScore(for: $0) > valueScore(for: $1) }
        case .lowestValue:
            return items.sorted { valueScore(for: $0) < valueScore(for: $1) }
        case .artistAZ:
            return items.sorted { normalizedArtist(for: $0) < normalizedArtist(for: $1) }
        }
    }

    private func valueScore(for item: SavedArtwork) -> Double {
        guard let bounds = EstimatedValueFormatter.parse(item.estimatedValueRange) else {
            return self == .lowestValue ? .greatestFiniteMagnitude : -.greatestFiniteMagnitude
        }
        return (bounds.lowerBound + bounds.upperBound) / 2
    }

    private func normalizedArtist(for item: SavedArtwork) -> String {
        (item.identifiedArtist ?? item.artworkTitle ?? "").lowercased()
    }
}

private enum CollectionConfidenceFilter: String, CaseIterable, Identifiable {
    case all
    case high
    case medium
    case low

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all:
            return "All Confidence"
        case .high:
            return "High Confidence"
        case .medium:
            return "Medium Confidence"
        case .low:
            return "Low Confidence"
        }
    }

    func matches(_ item: SavedArtwork) -> Bool {
        guard self != .all else { return true }
        return item.confidenceLevel?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == rawValue
    }
}

struct CollectionValueSummary {
    let estimatedLowerBound: Double
    let estimatedUpperBound: Double
    let currencyCode: String?
    let valuedItemCount: Int
    let totalItemCount: Int
    let hasMixedCurrencies: Bool
    let confidenceSampleCount: Int
    let confidenceScoreTotal: Double

    init(items: [SavedArtwork]) {
        var lowerBound = 0.0
        var upperBound = 0.0
        var summaryCurrencyCode: String?
        var mixedCurrencies = false
        var matchedCount = 0
        var confidenceCount = 0
        var confidenceTotal = 0.0

        for item in items {
            if let bounds = EstimatedValueFormatter.parse(item.estimatedValueRange) {
                lowerBound += bounds.lowerBound
                upperBound += bounds.upperBound
                matchedCount += 1

                if let boundsCurrencyCode = bounds.currencyCode {
                    if let summaryCurrencyCode, summaryCurrencyCode != boundsCurrencyCode {
                        mixedCurrencies = true
                    } else {
                        summaryCurrencyCode = boundsCurrencyCode
                    }
                }
            }

            if let score = confidenceScore(for: item.confidenceLevel) {
                confidenceCount += 1
                confidenceTotal += score
            }
        }

        estimatedLowerBound = lowerBound
        estimatedUpperBound = upperBound
        currencyCode = summaryCurrencyCode
        valuedItemCount = matchedCount
        totalItemCount = items.count
        hasMixedCurrencies = mixedCurrencies
        confidenceSampleCount = confidenceCount
        confidenceScoreTotal = confidenceTotal
    }

    var totalEstimateText: String {
        guard valuedItemCount > 0 else {
            return "No collection estimate yet"
        }

        if hasMixedCurrencies {
            return "Mixed currencies"
        }

        let range = EstimatedValueRange(
            lowerBound: estimatedLowerBound,
            upperBound: estimatedUpperBound,
            currencyCode: currencyCode
        )

        return EstimatedValueFormatter.format(range) ?? "No collection estimate yet"
    }

    var coverageText: String {
        if valuedItemCount == 0 {
            return totalItemCount == 1
                ? "The saved artwork does not have a parsable value estimate yet."
                : "None of the saved artworks have parsable value estimates yet."
        }

        if valuedItemCount == totalItemCount {
            return totalItemCount == 1
                ? "Based on the saved artwork's estimated value."
                : "Based on all \(totalItemCount) saved artworks with value estimates."
        }

        return "Based on \(valuedItemCount) of \(totalItemCount) saved artworks with value estimates."
    }

    var averageConfidenceText: String {
        guard confidenceSampleCount > 0 else {
            return "Unknown"
        }

        let average = confidenceScoreTotal / Double(confidenceSampleCount)
        switch average {
        case 2.5...:
            return "High"
        case 1.5..<2.5:
            return "Medium"
        default:
            return "Low"
        }
    }

    private func confidenceScore(for rawValue: String?) -> Double? {
        switch rawValue?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "high":
            return 3
        case "medium":
            return 2
        case "low":
            return 1
        default:
            return nil
        }
    }
}
