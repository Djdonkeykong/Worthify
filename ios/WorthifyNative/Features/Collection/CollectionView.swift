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
                                    Text(item.subtitleText)
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
}

private struct CollectionValueBanner: View {
    let summary: CollectionValueSummary

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Potential Collection Value")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            Text(summary.totalEstimateText)
                .font(.title3.weight(.bold))
                .foregroundStyle(.primary)

            Text(summary.coverageText)
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color.black.opacity(0.06), lineWidth: 1)
        }
        .shadow(color: Color.black.opacity(0.08), radius: 12, y: 4)
    }
}

struct CollectionValueSummary {
    let estimatedLowerBound: Double
    let estimatedUpperBound: Double
    let valuedItemCount: Int
    let totalItemCount: Int

    init(items: [SavedArtwork]) {
        var lowerBound = 0.0
        var upperBound = 0.0
        var matchedCount = 0

        for item in items {
            guard let bounds = Self.parseValueBounds(from: item.estimatedValueRange) else {
                continue
            }

            lowerBound += bounds.lowerBound
            upperBound += bounds.upperBound
            matchedCount += 1
        }

        estimatedLowerBound = lowerBound
        estimatedUpperBound = upperBound
        valuedItemCount = matchedCount
        totalItemCount = items.count
    }

    var totalEstimateText: String {
        guard valuedItemCount > 0 else {
            return "No collection estimate yet"
        }

        let lower = Self.currencyFormatter.string(from: NSNumber(value: estimatedLowerBound)) ?? "$0"
        let upper = Self.currencyFormatter.string(from: NSNumber(value: estimatedUpperBound)) ?? "$0"

        if abs(estimatedUpperBound - estimatedLowerBound) < 0.5 {
            return lower
        }

        return "\(lower) - \(upper)"
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

    private static let currencyFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.maximumFractionDigits = 0
        return formatter
    }()

    private static func parseValueBounds(from text: String?) -> ClosedRange<Double>? {
        guard let text = text?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else {
            return nil
        }

        let normalized = text
            .replacingOccurrences(of: "\u{00A0}", with: " ")
            .replacingOccurrences(of: "\u{2013}", with: "-")
            .replacingOccurrences(of: "\u{2014}", with: "-")

        let pattern = #"(\d{1,3}(?:,\d{3})*(?:\.\d+)?|\d+(?:\.\d+)?)"#
        guard let expression = try? NSRegularExpression(pattern: pattern) else {
            return nil
        }

        let range = NSRange(normalized.startIndex..<normalized.endIndex, in: normalized)
        let values = expression.matches(in: normalized, range: range).compactMap { match -> Double? in
            guard let valueRange = Range(match.range(at: 1), in: normalized) else {
                return nil
            }
            return Double(normalized[valueRange].replacingOccurrences(of: ",", with: ""))
        }

        guard let first = values.first else {
            return nil
        }

        guard let last = values.last else {
            return first...first
        }

        return min(first, last)...max(first, last)
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
