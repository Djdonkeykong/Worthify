import SwiftUI

struct HomeView: View {
    @EnvironmentObject private var environment: AppEnvironment
    @State private var recentItems: [SavedArtwork] = []
    @State private var subscription = SubscriptionSnapshot.inactive
    @State private var profile: UserProfile?
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
        WorthifyScreen {
            HeroPanel(
                eyebrow: "Worthify",
                title: "Your collection at a glance.",
                subtitle: "Track credits, jump into a fresh analysis, and keep recent results close."
            ) {
                HStack(spacing: 10) {
                    MetricPill(title: "Plan", value: isGuestMode ? "Guest" : (subscription.isActive ? "Active" : "Free"))
                    MetricPill(title: "Credits", value: "\(subscription.availableCredits)", tint: AppTheme.accentSecondary)
                }
            }

            GlassCard {
                SectionHeading("Account snapshot")

                HStack(alignment: .top, spacing: 16) {
                    ZStack {
                        Circle()
                            .fill(AppTheme.accent.opacity(0.12))
                            .frame(width: 56, height: 56)

                        Image(systemName: "person.fill")
                            .font(.title3.weight(.semibold))
                            .foregroundStyle(AppTheme.accent)
                    }

                    VStack(alignment: .leading, spacing: 6) {
                        Text(profile?.fullName ?? (isGuestMode ? "Guest mode" : "Worthify collector"))
                            .font(.headline)
                            .foregroundStyle(AppTheme.ink)

                        Text(profile?.email ?? signedInSession?.email ?? (isGuestMode ? "Browsing without sign-in" : "No email available"))
                            .font(.subheadline)
                            .foregroundStyle(.secondary)

                        if let productIdentifier = subscription.productIdentifier {
                            InsightChip(text: productIdentifier, tint: AppTheme.accentSecondary)
                        }
                    }
                }
            }

            if isGuestMode {
                GlassCard {
                    Label("Guest mode is enabled. History, favorites, and saving are disabled until sign-in is restored.", systemImage: "person.crop.circle.badge.exclamationmark")
                        .foregroundStyle(AppTheme.accent)
                }
            }

            NavigationLink {
                AnalyzeView()
            } label: {
                HeroPanel(
                    eyebrow: "Analyze",
                    title: "Estimate an artwork in seconds.",
                    subtitle: "Choose an image, send it to the backend, and review the result in a cleaner native flow."
                ) {
                    HStack(spacing: 12) {
                        Label("Open analysis", systemImage: "arrow.right.circle.fill")
                            .font(.headline.weight(.semibold))
                            .foregroundStyle(.white)

                        Spacer()

                        Image(systemName: "sparkles")
                            .foregroundStyle(.white.opacity(0.86))
                    }
                }
            }
            .buttonStyle(.plain)

            SectionHeading("Recent analyses", subtitle: "The latest saved items from your account.")

            if recentItems.isEmpty {
                EmptyStateCard(
                    title: "No saved results yet",
                    subtitle: "Run an analysis and save it to start building your collection.",
                    systemImage: "photo.on.rectangle.angled"
                )
            } else {
                LazyVStack(spacing: 16) {
                    ForEach(recentItems.prefix(6)) { item in
                        GlassCard {
                            HStack(alignment: .top, spacing: 14) {
                                ImageCard(url: item.remoteImageURL, height: 92)
                                    .frame(width: 96)

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

            if let errorMessage {
                GlassCard {
                    Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.red)
                }
            }
        }
        .navigationTitle("Home")
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
        .refreshable { await load() }
    }

    private func load() async {
        if isGuestMode {
            recentItems = []
            subscription = .inactive
            profile = nil
            errorMessage = nil
            return
        }

        do {
            async let collectionItems = environment.collectionService.fetchRecentItems()
            async let subscriptionSnapshot = environment.subscriptionService.fetchSnapshot()
            async let userProfile = environment.subscriptionService.fetchProfile()
            recentItems = try await collectionItems
            subscription = try await subscriptionSnapshot
            profile = try await userProfile
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
