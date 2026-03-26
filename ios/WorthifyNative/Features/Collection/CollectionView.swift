import SwiftUI

struct CollectionView: View {
    @EnvironmentObject private var environment: AppEnvironment
    @State private var items: [SavedArtwork] = []
    @State private var errorMessage: String?

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
