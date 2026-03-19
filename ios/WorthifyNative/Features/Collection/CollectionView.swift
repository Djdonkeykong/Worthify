import SwiftUI

struct CollectionView: View {
    @EnvironmentObject private var environment: AppEnvironment
    @State private var favorites: [SavedArtwork] = []
    @State private var history: [SavedArtwork] = []
    @State private var errorMessage: String?
    @State private var searchText = ""

    private var isGuestMode: Bool {
        environment.config.bypassAuth && signedInSession == nil
    }

    private var signedInSession: AppSession? {
        if case let .signedIn(session) = environment.sessionStore.state {
            return session
        }
        return nil
    }

    var body: some View {
        WorthifyScreen {
            HeroPanel(
                eyebrow: "Collection",
                title: "Saved estimates and favorites.",
                subtitle: "Browse what you have already analyzed without dropping into a dense table view."
            ) {
                HStack(spacing: 10) {
                    MetricPill(title: "Favorites", value: "\(filteredFavorites.count)")
                    MetricPill(title: "History", value: "\(filteredHistory.count)", tint: AppTheme.accentSecondary)
                }
            }

            if isGuestMode {
                EmptyStateCard(
                    title: "Guest mode",
                    subtitle: "Collection data is hidden until sign-in is enabled again.",
                    systemImage: "lock.slash"
                )
            } else {
                GlassCard {
                    SectionHeading("Search collection")

                    HStack(spacing: 12) {
                        Image(systemName: "magnifyingglass")
                            .foregroundStyle(.secondary)

                        TextField("Search by title or artist", text: $searchText)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 16)
                    .background(Color(uiColor: .systemBackground), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                }

                collectionSection(title: "Favorites", items: filteredFavorites, emptyTitle: "No favorites yet", emptySubtitle: "Saved pieces will start appearing here once that backend distinction is wired.")
                collectionSection(title: "History", items: filteredHistory, emptyTitle: "No history yet", emptySubtitle: "Run and save an analysis to build your archive.")
            }

            if let errorMessage {
                GlassCard {
                    Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.red)
                }
            }
        }
        .navigationTitle("Collection")
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
        .refreshable { await load() }
    }

    private func load() async {
        if isGuestMode {
            favorites = []
            history = []
            errorMessage = nil
            return
        }

        do {
            async let favoritesItems = environment.favoritesService.fetchFavorites()
            async let historyItems = environment.collectionService.fetchRecentItems()
            favorites = try await favoritesItems
            history = try await historyItems
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private var filteredFavorites: [SavedArtwork] {
        filter(items: favorites)
    }

    private var filteredHistory: [SavedArtwork] {
        filter(items: history)
    }

    private func filter(items: [SavedArtwork]) -> [SavedArtwork] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !query.isEmpty else {
            return items
        }

        return items.filter { item in
            item.titleText.lowercased().contains(query) || item.subtitleText.lowercased().contains(query)
        }
    }

    @ViewBuilder
    private func collectionSection(title: String, items: [SavedArtwork], emptyTitle: String, emptySubtitle: String) -> some View {
        SectionHeading(title)

        if items.isEmpty {
            EmptyStateCard(title: emptyTitle, subtitle: emptySubtitle, systemImage: "square.stack.3d.up.slash")
        } else {
            LazyVStack(spacing: 16) {
                ForEach(items) { item in
                    GlassCard {
                        HStack(alignment: .top, spacing: 14) {
                            ImageCard(url: item.remoteImageURL, height: 110)
                                .frame(width: 112)

                            VStack(alignment: .leading, spacing: 8) {
                                Text(item.titleText)
                                    .font(.headline)

                                Text(item.subtitleText)
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)

                                HStack(spacing: 8) {
                                    if let confidence = item.confidenceText {
                                        ConfidenceBadge(label: confidence)
                                    }

                                    Text(item.createdDateText)
                                        .font(.footnote.weight(.medium))
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
