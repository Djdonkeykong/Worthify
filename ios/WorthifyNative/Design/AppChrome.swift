import SwiftUI

enum AppTheme {
    static let accent = Color(red: 0.14, green: 0.44, blue: 0.96)
    static let accentSecondary = Color(red: 0.13, green: 0.78, blue: 0.80)
    static let rose = Color(red: 0.93, green: 0.42, blue: 0.49)
    static let gold = Color(red: 0.89, green: 0.74, blue: 0.35)
    static let ink = Color(red: 0.10, green: 0.12, blue: 0.18)
    static let pageGradient = LinearGradient(
        colors: [
            Color(red: 0.95, green: 0.97, blue: 1.00),
            Color(red: 0.91, green: 0.95, blue: 0.99),
            Color.white
        ],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )
    static let heroGradient = LinearGradient(
        colors: [
            accent,
            Color(red: 0.34, green: 0.24, blue: 0.95),
            accentSecondary
        ],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )
}

struct AppBackdrop: View {
    var body: some View {
        ZStack {
            AppTheme.pageGradient

            Circle()
                .fill(AppTheme.accent.opacity(0.22))
                .frame(width: 320, height: 320)
                .blur(radius: 24)
                .offset(x: -120, y: -260)

            Circle()
                .fill(AppTheme.accentSecondary.opacity(0.18))
                .frame(width: 280, height: 280)
                .blur(radius: 18)
                .offset(x: 140, y: -180)

            Circle()
                .fill(AppTheme.rose.opacity(0.12))
                .frame(width: 360, height: 360)
                .blur(radius: 40)
                .offset(x: 140, y: 360)
        }
        .ignoresSafeArea()
    }
}

struct WorthifyScreen<Content: View>: View {
    let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        ZStack {
            AppBackdrop()

            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    content
                }
                .padding(.horizontal, 20)
                .padding(.top, 20)
                .padding(.bottom, 120)
            }
            .scrollIndicators(.hidden)
        }
    }
}

struct HeroPanel<Content: View>: View {
    let eyebrow: String
    let title: String
    let subtitle: String
    let content: Content

    init(
        eyebrow: String,
        title: String,
        subtitle: String,
        @ViewBuilder content: () -> Content = { EmptyView() }
    ) {
        self.eyebrow = eyebrow
        self.title = title
        self.subtitle = subtitle
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 10) {
                Text(eyebrow.uppercased())
                    .font(.caption.weight(.semibold))
                    .tracking(1.4)
                    .foregroundStyle(.white.opacity(0.82))

                Text(title)
                    .font(.system(.largeTitle, design: .rounded, weight: .bold))
                    .foregroundStyle(.white)

                Text(subtitle)
                    .font(.body)
                    .foregroundStyle(.white.opacity(0.88))
            }

            content
        }
        .padding(24)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppTheme.heroGradient, in: RoundedRectangle(cornerRadius: 30, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 30, style: .continuous)
                .stroke(.white.opacity(0.22), lineWidth: 1)
        )
        .shadow(color: AppTheme.accent.opacity(0.18), radius: 28, y: 12)
    }
}

struct GlassCard<Content: View>: View {
    let padding: CGFloat
    let content: Content

    init(
        padding: CGFloat = 18,
        @ViewBuilder content: () -> Content
    ) {
        self.padding = padding
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            content
        }
        .padding(padding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 26, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .stroke(.white.opacity(0.60), lineWidth: 1)
        )
        .shadow(color: AppTheme.ink.opacity(0.08), radius: 20, y: 10)
    }
}

struct SectionHeading: View {
    let title: String
    let subtitle: String?

    init(_ title: String, subtitle: String? = nil) {
        self.title = title
        self.subtitle = subtitle
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.system(.title3, design: .rounded, weight: .bold))
                .foregroundStyle(AppTheme.ink)

            if let subtitle {
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

struct MetricPill: View {
    let title: String
    let value: String
    var tint: Color = AppTheme.accent

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title.uppercased())
                .font(.caption2.weight(.semibold))
                .tracking(1.0)
                .foregroundStyle(.secondary)

            Text(value)
                .font(.system(.headline, design: .rounded, weight: .bold))
                .foregroundStyle(AppTheme.ink)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(tint.opacity(0.10), in: Capsule())
        .overlay(
            Capsule()
                .stroke(tint.opacity(0.16), lineWidth: 1)
        )
    }
}

struct InsightChip: View {
    let text: String
    var tint: Color = AppTheme.accent

    var body: some View {
        Text(text)
            .font(.subheadline.weight(.medium))
            .foregroundStyle(tint)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(tint.opacity(0.12), in: Capsule())
    }
}

struct ImageCard: View {
    let url: URL?
    var height: CGFloat = 210

    var body: some View {
        Group {
            if let url {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case let .success(image):
                        image
                            .resizable()
                            .scaledToFill()
                    case .failure:
                        placeholder
                    case .empty:
                        ZStack {
                            placeholder
                            ProgressView()
                        }
                    @unknown default:
                        placeholder
                    }
                }
            } else {
                placeholder
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: height)
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(.white.opacity(0.65), lineWidth: 1)
        )
    }

    private var placeholder: some View {
        ZStack {
            AppTheme.heroGradient

            Image(systemName: "photo.artframe")
                .font(.system(size: 34, weight: .semibold))
                .foregroundStyle(.white.opacity(0.92))
        }
    }
}

struct ConfidenceBadge: View {
    let label: String

    var body: some View {
        Text(label)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(color)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(color.opacity(0.12), in: Capsule())
    }

    private var color: Color {
        switch label.lowercased() {
        case "high":
            return .green
        case "medium":
            return AppTheme.gold
        case "low":
            return AppTheme.rose
        default:
            return .secondary
        }
    }
}

struct WorthifyPrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline.weight(.semibold))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 18)
            .foregroundStyle(.white)
            .background(
                AppTheme.heroGradient.opacity(configuration.isPressed ? 0.88 : 1),
                in: RoundedRectangle(cornerRadius: 22, style: .continuous)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .stroke(.white.opacity(0.24), lineWidth: 1)
            )
            .scaleEffect(configuration.isPressed ? 0.985 : 1)
            .shadow(color: AppTheme.accent.opacity(configuration.isPressed ? 0.10 : 0.22), radius: 18, y: 10)
            .animation(.easeOut(duration: 0.18), value: configuration.isPressed)
    }
}

struct WorthifySecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline.weight(.semibold))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 18)
            .foregroundStyle(AppTheme.ink)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .stroke(.white.opacity(0.72), lineWidth: 1)
            )
            .scaleEffect(configuration.isPressed ? 0.985 : 1)
            .animation(.easeOut(duration: 0.18), value: configuration.isPressed)
    }
}

struct EmptyStateCard: View {
    let title: String
    let subtitle: String
    let systemImage: String

    var body: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 12) {
                Image(systemName: systemImage)
                    .font(.system(size: 28, weight: .semibold))
                    .foregroundStyle(AppTheme.accent)

                Text(title)
                    .font(.system(.headline, design: .rounded, weight: .bold))

                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
    }
}
