import SwiftUI

struct CollectionView: View {
    @EnvironmentObject private var environment: AppEnvironment
    @State private var items: [SavedArtwork] = []
    @State private var errorMessage: String?

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
        List {
            if isGuestMode {
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
                        VStack(alignment: .leading, spacing: 4) {
                            Text(item.titleText)
                                .font(.body.weight(.semibold))
                            Text(item.subtitleText)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                            Text(item.createdDateText)
                                .font(.footnote)
                                .foregroundStyle(.tertiary)
                        }
                        .padding(.vertical, 4)
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
        if isGuestMode {
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
