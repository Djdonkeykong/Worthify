import Foundation
import SwiftUI

struct ResultsView: View {
    @EnvironmentObject private var environment: AppEnvironment
    let result: ArtworkAnalysis

    @State private var saveMessage: String?
    @State private var isSaving = false

    private let headerHeight: CGFloat = 360

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
        ZStack {
            AppBackdrop()

            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 0) {
                    StretchyHeaderImage(url: result.sourceImageURL, baseHeight: headerHeight)

                    VStack(alignment: .leading, spacing: 12) {
                        Text("Details")
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .textCase(.uppercase)

                        GlassCard(padding: 0) {
                            VStack(spacing: 0) {
                                ForEach(Array(detailItems.enumerated()), id: \.offset) { index, item in
                                    detailItemView(item)
                                        .padding(.horizontal, 16)
                                        .padding(.vertical, item.verticalPadding)

                                    if index != detailItems.count - 1 {
                                        Divider()
                                            .padding(.leading, 16)
                                    }
                                }
                            }
                        }

                        if let disclaimer = cleanedBlockText(result.disclaimer) {
                            Text(disclaimer)
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 18)
                    .padding(.bottom, 32)
                }
            }
            .coordinateSpace(name: "results-scroll")
        }
        .navigationTitle("Details")
        .navigationBarTitleDisplayMode(.inline)
    }

    @ViewBuilder
    private func detailItemView(_ item: DetailItem) -> some View {
        switch item {
        case let .keyValue(title, value):
            LabeledContent(title) {
                Text(value)
                    .multilineTextAlignment(.trailing)
                    .foregroundStyle(.primary)
            }

        case let .confidence(label):
            LabeledContent("Confidence") {
                ConfidenceBadge(label: label)
            }

        case let .note(title, value):
            VStack(alignment: .leading, spacing: 6) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)

                Text(value)
                    .foregroundStyle(.primary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)
            }

        case .save:
            saveActionContent
        }
    }

    private var saveActionContent: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Collection")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)

            Button(saveButtonTitle) {
                Task { await saveResult() }
            }
            .buttonStyle(WorthifyPrimaryButtonStyle())
            .disabled(!canSave)

            Text(saveStatusText)
                .font(.footnote)
                .foregroundStyle(saveStatusColor)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var detailItems: [DetailItem] {
        var items: [DetailItem] = [
            .keyValue("Title", displayTitleText),
            .keyValue("Artist", displayArtistText),
            .confidence(result.confidenceText)
        ]

        if let value = localizedEstimatedValueText {
            items.append(.keyValue("Estimated Value", value))
        }
        if let year = cleanedInlineText(result.yearEstimate) {
            items.append(.keyValue("Year Estimate", year))
        }
        if let medium = cleanedInlineText(result.mediumGuess) {
            items.append(.keyValue("Medium", medium))
        }
        if let style = cleanedInlineText(result.style) {
            items.append(.keyValue("Style", style))
        }
        if let format = cleanedInlineText(result.isOriginalOrPrint) {
            items.append(.keyValue("Format", format.capitalized))
        }
        if let reasoning = cleanedBlockText(result.valueReasoning) {
            items.append(.note("Value Reasoning", reasoning))
        }
        if let comparables = cleanedBlockText(result.comparableExamplesSummary) {
            items.append(.note("Comparable Examples", comparables))
        }
        if !isArtworkIdentified {
            items.append(.note("Retake Tip", "Use a straight-on photo with less glare and tighter framing."))
        }

        items.append(.save)
        return items
    }

    private var saveButtonTitle: String {
        if isSaving {
            return "Saving..."
        }
        if isSaveCompleted {
            return "Saved"
        }
        return "Save to collection"
    }

    private var canSave: Bool {
        !isSaving && result.sourceImageURL != nil && !requiresSignIn && !isSaveCompleted
    }

    private var saveStatusText: String {
        if let saveMessage {
            return saveMessage
        }
        if requiresSignIn {
            return "Sign in to save this result to your collection."
        }
        if result.sourceImageURL == nil {
            return "This result cannot be saved because the source image is unavailable."
        }
        if isSaveCompleted {
            return "This analysis is already in your collection."
        }
        return "Save this analysis to your collection for later."
    }

    private var saveStatusColor: Color {
        if let saveMessage, isPositiveSaveMessage(saveMessage) {
            return .green
        }
        return .secondary
    }

    private func saveResult() async {
        guard let sourceImageURL = result.sourceImageURL else { return }

        isSaving = true
        defer { isSaving = false }

        do {
            try await environment.collectionService.saveAnalysis(result, sourceImageURL: sourceImageURL)
            saveMessage = "Saved."
        } catch {
            saveMessage = error.localizedDescription
        }
    }

    private var isArtworkIdentified: Bool {
        cleanedInlineText(result.artworkTitle) != nil
    }

    private var displayTitleText: String {
        if let title = cleanedInlineText(result.artworkTitle), isArtworkIdentified {
            return title
        }
        return "Artwork not identified yet"
    }

    private var displayArtistText: String {
        if isArtworkIdentified {
            return cleanedInlineText(result.artistText) ?? "Unknown artist"
        }
        if let candidate = cleanedInlineText(result.identifiedArtist) {
            return "Possible artist: \(candidate)"
        }
        return "No confident artist match yet"
    }

    private var localizedEstimatedValueText: String? {
        let formattedValue = EstimatedValueFormatter.displayText(from: result.estimatedValueRange)
        return cleanedInlineText(formattedValue ?? result.estimatedValueRange)
    }

    private func cleanedInlineText(_ value: String?) -> String? {
        guard let value else { return nil }
        let normalized = value
            .replacingOccurrences(of: "\u{00A0}", with: " ")
            .replacingOccurrences(of: "\u{200B}", with: "")
            .replacingOccurrences(of: "\u{200C}", with: "")
            .replacingOccurrences(of: "\u{200D}", with: "")
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "\r", with: " ")
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")

        if normalized.isEmpty {
            return nil
        }

        return softWrapLongTokens(in: normalized)
    }

    private func cleanedBlockText(_ value: String?) -> String? {
        guard let value else { return nil }
        let normalized = value
            .replacingOccurrences(of: "\u{00A0}", with: " ")
            .replacingOccurrences(of: "\u{200B}", with: "")
            .replacingOccurrences(of: "\u{200C}", with: "")
            .replacingOccurrences(of: "\u{200D}", with: "")
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        if normalized.isEmpty {
            return nil
        }

        let lines = normalized
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map { rawLine in
                let compactLine = rawLine
                    .split(whereSeparator: \.isWhitespace)
                    .joined(separator: " ")
                return softWrapLongTokens(in: compactLine)
            }
            .joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        return lines.isEmpty ? nil : lines
    }

    private func isPositiveSaveMessage(_ message: String) -> Bool {
        message == "Saved." || message == "Already saved."
    }

    private var isSaveCompleted: Bool {
        guard let saveMessage else { return false }
        return isPositiveSaveMessage(saveMessage)
    }

    private func softWrapLongTokens(in text: String, chunkSize: Int = 20) -> String {
        let softBreak = "\u{200B}"
        return text
            .split(separator: " ", omittingEmptySubsequences: false)
            .map { token in
                let raw = String(token)
                guard raw.count > chunkSize else { return raw }
                return stride(from: 0, to: raw.count, by: chunkSize).map { index in
                    let start = raw.index(raw.startIndex, offsetBy: index)
                    let end = raw.index(start, offsetBy: min(chunkSize, raw.count - index))
                    return String(raw[start..<end])
                }.joined(separator: softBreak)
            }
            .joined(separator: " ")
    }
}

private extension ResultsView {
    enum DetailItem {
        case keyValue(String, String)
        case confidence(String)
        case note(String, String)
        case save

        var verticalPadding: CGFloat {
            switch self {
            case .note, .save:
                return 14
            case .keyValue, .confidence:
                return 12
            }
        }
    }
}

private struct StretchyHeaderImage: View {
    let url: URL?
    let baseHeight: CGFloat

    var body: some View {
        GeometryReader { proxy in
            let minY = proxy.frame(in: .named("results-scroll")).minY
            let extraHeight = max(minY, 0)

            headerImage
                .frame(width: proxy.size.width, height: baseHeight + extraHeight)
                .clipped()
                .offset(y: minY > 0 ? -minY : 0)
                .overlay(alignment: .bottom) {
                    LinearGradient(
                        colors: [Color.clear, AppTheme.pageBackground.opacity(0.9)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    .frame(height: 88)
                }
        }
        .frame(height: baseHeight)
    }

    private var headerImage: some View {
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
        .background(Color(uiColor: .tertiarySystemFill))
    }

    private var placeholder: some View {
        ZStack {
            Color(uiColor: .tertiarySystemFill)

            Image(systemName: "photo")
                .font(.title)
                .foregroundStyle(.secondary)
        }
    }
}
