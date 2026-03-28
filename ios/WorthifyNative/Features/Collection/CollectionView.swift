import SwiftUI

struct CollectionView: View {
    @EnvironmentObject private var environment: AppEnvironment
    @State private var items: [SavedArtwork] = []
    @State private var errorMessage: String?

    private var collectionValueSummary: CollectionValueSummary {
        CollectionValueSummary(items: items)
    }

    private var shouldShowCollectionValueBanner: Bool {
        !requiresSignIn && !items.isEmpty
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
            } else {
                Section("Collection") {
                    ForEach(items) { item in
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
                                    Text(item.createdDateText)
                                        .font(.footnote)
                                        .foregroundStyle(.tertiary)
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
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if shouldShowCollectionValueBanner {
                CollectionValueBanner(summary: collectionValueSummary)
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
                    .padding(.bottom, 8)
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

private struct CollectionValueBanner: View {
    let summary: CollectionValueSummary

    var body: some View {
        HStack(spacing: 12) {
            Text("Collection value")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.secondary)

            Spacer(minLength: 12)

            Text(summary.totalEstimateText)
                .font(.subheadline.weight(.bold))
                .foregroundStyle(.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(Color(uiColor: .secondarySystemGroupedBackground), in: Capsule())
        .overlay {
            Capsule()
                .stroke(Color.black.opacity(0.06), lineWidth: 1)
        }
        .shadow(color: Color.black.opacity(0.05), radius: 10, y: 3)
    }
}

struct CollectionValueSummary {
    let estimatedLowerBound: Double
    let estimatedUpperBound: Double
    let currencyCode: String?
    let valuedItemCount: Int
    let totalItemCount: Int
    let hasMixedCurrencies: Bool

    init(items: [SavedArtwork]) {
        var lowerBound = 0.0
        var upperBound = 0.0
        var summaryCurrencyCode: String?
        var mixedCurrencies = false
        var matchedCount = 0

        for item in items {
            guard let bounds = EstimatedValueFormatter.parse(item.estimatedValueRange) else {
                continue
            }

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

        estimatedLowerBound = lowerBound
        estimatedUpperBound = upperBound
        currencyCode = summaryCurrencyCode
        valuedItemCount = matchedCount
        totalItemCount = items.count
        hasMixedCurrencies = mixedCurrencies
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
