import SwiftUI

struct ProfileView: View {
    @EnvironmentObject private var environment: AppEnvironment
    @State private var subscription = SubscriptionSnapshot.inactive
    @State private var profile: UserProfile?
    @State private var errorMessage: String?
    @State private var automaticTimeZone = true
    @State private var appearance = "System"

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
            Section("Account") {
                LabeledContent("Name", value: displayName)
                LabeledContent("Email", value: displayEmail)
                LabeledContent("Status", value: isGuestMode ? "Guest" : "Signed in")
                LabeledContent("Credits", value: "\(subscription.availableCredits)")
            }

            Section("Preferences") {
                Picker("Appearance", selection: $appearance) {
                    Text("System").tag("System")
                    Text("Light").tag("Light")
                    Text("Dark").tag("Dark")
                }
                Toggle("Automatic Time Zone", isOn: $automaticTimeZone)
                settingsDisclosureRow("Dictation Language", value: "Auto-detect")
            }

            Section("Subscription") {
                if subscription.isActive {
                    settingsDisclosureRow("Manage Subscription", value: "Active")
                } else {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("No Subscription Active")
                            Text("Activate to unlock all features")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }

                        Spacer()

                        Button("Upgrade") {}
                            .buttonStyle(.borderedProminent)
                            .tint(.yellow)
                    }
                }
            }

            Section("Support") {
                settingsDisclosureRow("Give Feedback")
                settingsDisclosureRow("About the App")
                Button {
                } label: {
                    Text("Contact Support")
                }
            }

            Section("Data") {
                Button("Clear Local Cache", role: .destructive) {}
                Button("Export Data") {}
            }

            Section("Account Actions") {
                if isGuestMode {
                    Text("Sign-in is currently bypassed for this build.")
                        .foregroundStyle(.secondary)
                } else {
                    Button("Sign Out", role: .destructive) {
                        Task {
                            await environment.sessionStore.signOut()
                            environment.router.rootRoute = .auth
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
        .navigationTitle("Settings")
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
        .refreshable { await load() }
    }

    private func settingsDisclosureRow(_ title: String, value: String? = nil) -> some View {
        HStack(spacing: 8) {
            Text(title)
            Spacer()
            if let value {
                Text(value)
                    .foregroundStyle(.secondary)
            }
            Image(systemName: "chevron.right")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.tertiary)
        }
    }

    private var displayName: String {
        if let fullName = profile?.fullName, !fullName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return fullName
        }
        return isGuestMode ? "Guest" : "Worthify User"
    }

    private var displayEmail: String {
        if let profileEmail = profile?.email, !profileEmail.isEmpty {
            return profileEmail
        }

        switch environment.sessionStore.state {
        case .restoring:
            return "Restoring session"
        case .signedOut:
            return isGuestMode ? "Browsing without sign-in" : "Signed out"
        case let .signedIn(session):
            return session.email ?? session.userID
        }
    }

    private func load() async {
        if isGuestMode {
            subscription = .inactive
            profile = nil
            errorMessage = nil
            return
        }

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
