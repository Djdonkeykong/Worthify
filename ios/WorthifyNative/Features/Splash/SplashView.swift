import SwiftUI

struct SplashView: View {
    var body: some View {
        ZStack {
            AppBackdrop()

            VStack(spacing: 20) {
                Image(systemName: "photo.stack")
                    .font(.system(size: 36, weight: .medium))
                    .foregroundStyle(AppTheme.accent)

                VStack(spacing: 8) {
                    Text("Worthify")
                        .font(.largeTitle.weight(.semibold))

                    Text("Preparing your session and syncing the app.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                ProgressView()
                    .controlSize(.regular)
            }
        }
    }
}
