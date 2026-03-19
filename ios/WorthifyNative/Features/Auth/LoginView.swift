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
                eyebrow: "Account",
                title: "Sign in",
                subtitle: "Use the same email account as before."
            )

            GlassCard {
                SectionHeading("Email login")

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
                .padding(.vertical, 14)
                .background(Color(uiColor: .systemBackground), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
    }
}
