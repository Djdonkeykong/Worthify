import SwiftUI
import UIKit

struct LoginView: View {
    @EnvironmentObject private var environment: AppEnvironment
    @State private var email = ""
    @State private var code = ""
    @State private var awaitingCode = false
    @State private var errorMessage: String?

    var body: some View {
        WorthifyScreen {
            HeroPanel(
                eyebrow: "Native iPhone App",
                title: "Sign in without friction.",
                subtitle: "Worthify now opens as a focused SwiftUI app with a lighter, more modern iOS flow."
            ) {
                HStack(spacing: 10) {
                    MetricPill(title: "Flow", value: "Email OTP")
                    MetricPill(title: "Session", value: "Restored")
                }
            }

            GlassCard {
                SectionHeading("Welcome back", subtitle: "Use the same backend and account you already had.")

                VStack(spacing: 14) {
                    inputField(
                        title: "Email",
                        prompt: "name@example.com",
                        text: $email,
                        keyboardType: .emailAddress
                    )

                    if awaitingCode {
                        inputField(
                            title: "Verification code",
                            prompt: "123456",
                            text: $code,
                            keyboardType: .numberPad
                        )
                    }
                }

                Button(awaitingCode ? "Verify code" : "Send code") {
                    Task { await handleEmailFlow() }
                }
                .buttonStyle(WorthifyPrimaryButtonStyle())
            }

            GlassCard {
                SectionHeading("What this build includes")

                VStack(alignment: .leading, spacing: 14) {
                    featureRow(symbol: "wand.and.stars", title: "Native analysis flow", subtitle: "Pick a photo, upload it, and run the artwork check.")
                    featureRow(symbol: "square.stack.3d.up", title: "Material-based UI", subtitle: "Layered cards and surfaces tuned for a polished iPhone feel.")
                    featureRow(symbol: "person.crop.circle.badge.checkmark", title: "Session persistence", subtitle: "Restore auth state directly from Supabase.")
                }
            }

            if let errorMessage {
                GlassCard {
                    Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.red)
                }
            }
        }
        .navigationTitle("Welcome")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func handleEmailFlow() async {
        do {
            if awaitingCode {
                let session = try await environment.authService.verifyEmailOTP(email: email, code: code)
                environment.sessionStore.setSignedIn(session)
                environment.router.rootRoute = .main
            } else {
                try await environment.authService.signInWithEmailOTP(email: email)
                awaitingCode = true
            }
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    @ViewBuilder
    private func inputField(
        title: String,
        prompt: String,
        text: Binding<String>,
        keyboardType: UIKeyboardType
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)

            TextField(prompt, text: text)
                .textInputAutocapitalization(.never)
                .keyboardType(keyboardType)
                .autocorrectionDisabled()
                .padding(.horizontal, 16)
                .padding(.vertical, 16)
                .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .stroke(.white.opacity(0.72), lineWidth: 1)
                )
        }
    }

    private func featureRow(symbol: String, title: String, subtitle: String) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: symbol)
                .font(.headline.weight(.bold))
                .foregroundStyle(AppTheme.accent)
                .frame(width: 32, height: 32)
                .background(AppTheme.accent.opacity(0.12), in: RoundedRectangle(cornerRadius: 12, style: .continuous))

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.headline)

                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
    }
}
