import SwiftUI

struct ProfileView: View {
    @EnvironmentObject private var environment: AppEnvironment
    @State private var subscription = SubscriptionSnapshot.inactive
    @State private var profile: UserProfile?
    @State private var errorMessage: String?

    var body: some View {
        WorthifyScreen {
            HeroPanel(
                eyebrow: "Profile",
                title: profile?.fullName ?? "Worthify account",
                subtitle: profile?.email ?? currentSessionLabel
            ) {
                HStack(spacing: 10) {
                    MetricPill(title: "Status", value: subscription.isActive ? "Active" : "Free")
                    MetricPill(title: "Credits", value: "\(subscription.availableCredits)", tint: AppTheme.accentSecondary)
                }
            }

            GlassCard {
                HStack(spacing: 16) {
                    avatar

                    VStack(alignment: .leading, spacing: 6) {
                        Text(profile?.fullName ?? "Collector")
                            .font(.system(.title3, design: .rounded, weight: .bold))

                        Text(profile?.email ?? currentSessionLabel)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)

                        if let productIdentifier = subscription.productIdentifier {
                            InsightChip(text: productIdentifier, tint: AppTheme.accent)
                        }
                    }
                }
            }

            GlassCard {
                SectionHeading("Membership")

                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                    MetricPill(title: "Subscription", value: subscription.isActive ? "Active" : "Inactive")
                    MetricPill(title: "Credits", value: "\(subscription.availableCredits)", tint: AppTheme.accentSecondary)
                }

                if let email = profile?.email {
                    LabeledContent("Email", value: email)
                }
            }

            GlassCard {
                SectionHeading("Actions")

                Button("Sign out", role: .destructive) {
                    Task {
                        await environment.sessionStore.signOut()
                        environment.router.rootRoute = .auth
                    }
                }
                .buttonStyle(WorthifySecondaryButtonStyle())
            }

            if let errorMessage {
                GlassCard {
                    Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.red)
                }
            }
        }
        .navigationTitle("Profile")
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
        .refreshable { await load() }
    }

    private var avatar: some View {
        ZStack {
            Circle()
                .fill(AppTheme.heroGradient)
                .frame(width: 72, height: 72)

            Text(initials)
                .font(.system(.title2, design: .rounded, weight: .bold))
                .foregroundStyle(.white)
        }
    }

    private var initials: String {
        let name = profile?.fullName?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let name, !name.isEmpty {
            return String(name.split(separator: " ").compactMap(\.first).prefix(2))
        }
        return "W"
    }

    private var currentSessionLabel: String {
        switch environment.sessionStore.state {
        case .restoring:
            return "Restoring session"
        case .signedOut:
            return "Signed out"
        case let .signedIn(session):
            return session.email ?? session.userID
        }
    }

    private func load() async {
        do {
            async let snapshot = environment.subscriptionService.fetchSnapshot()
            async let fetchedProfile = environment.subscriptionService.fetchProfile()
            subscription = try await snapshot
            profile = try await fetchedProfile
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
