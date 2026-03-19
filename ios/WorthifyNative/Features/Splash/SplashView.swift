import SwiftUI

struct SplashView: View {
    @State private var isVisible = false

    var body: some View {
        ZStack {
            AppBackdrop()

            VStack(spacing: 26) {
                ZStack {
                    Circle()
                        .fill(.white.opacity(0.44))
                        .frame(width: 110, height: 110)
                        .blur(radius: 10)

                    Circle()
                        .fill(.ultraThinMaterial)
                        .frame(width: 92, height: 92)

                    Image(systemName: "sparkles.rectangle.stack.fill")
                        .font(.system(size: 34, weight: .bold))
                        .foregroundStyle(AppTheme.accent)
                }
                .scaleEffect(isVisible ? 1 : 0.92)

                VStack(spacing: 10) {
                    Text("Worthify")
                        .font(.system(.largeTitle, design: .rounded, weight: .bold))
                        .foregroundStyle(AppTheme.ink)

                    Text("Preparing your session and syncing the app.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                ProgressView()
                    .tint(AppTheme.accent)
                    .scaleEffect(1.1)
            }
        }
        .onAppear {
            withAnimation(.easeOut(duration: 0.6)) {
                isVisible = true
            }
        }
    }
}
