import Foundation
import SwiftUI

struct ResultsView: View {
    @EnvironmentObject private var environment: AppEnvironment
    let result: ArtworkAnalysis

    @State private var saveMessage: String?
    @State private var isSaving = false
    @State private var showFullDescription = false

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

            ScrollView(.vertical) {
                VStack(alignment: .leading, spacing: 22) {
                    ImageCard(url: result.sourceImageURL, height: 340)

                    summarySection

                    Divider()

                    detailsSection

                    if let saveMessage {
                        GlassCard {
                            Label(
                                saveMessage,
                                systemImage: isPositiveSaveMessage(saveMessage) ? "checkmark.circle.fill" : "exclamationmark.triangle.fill"
                            )
                            .foregroundStyle(isPositiveSaveMessage(saveMessage) ? .green : .secondary)
                        }
                    } else if requiresSignIn {
                        GlassCard {
                            Label("Sign in to save this result to your collection.", systemImage: "lock.slash")
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 120)
            }
            .scrollBounceBehavior(.basedOnSize, axes: .vertical)
        }
        .navigationTitle("Result")
        .navigationBarTitleDisplayMode(.inline)
        .safeAreaInset(edge: .bottom) {
            Button(saveButtonTitle) {
                Task { await saveResult() }
            }
            .buttonStyle(WorthifyPrimaryButtonStyle())
            .disabled(!canSave)
            .padding(.horizontal, 20)
            .padding(.top, 10)
            .padding(.bottom, 20)
            .background(.ultraThinMaterial)
        }
        .sheet(isPresented: $showFullDescription) {
            DescriptionSheet(text: fullSummaryText)
                .presentationDetents([.large])
                .presentationDragIndicator(.hidden)
        }
    }

    private var summarySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 10) {
                Text(displayTitleText)
                    .font(.system(size: 34, weight: .bold))
                    .lineLimit(2)
                    .minimumScaleFactor(0.75)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .layoutPriority(1)

                ConfidenceBadge(label: confidenceBadgeLabel)
                    .padding(.top, 6)
            }

            Text(displayValueText)
                .font(.title3.weight(.semibold))
                .foregroundStyle(AppTheme.accentSecondary)

            HStack(spacing: 10) {
                Circle()
                    .fill(Color(uiColor: .tertiarySystemFill))
                    .frame(width: 36, height: 36)
                    .overlay {
                        Text(artistInitial)
                            .font(.subheadline.weight(.semibold))
                    }

                Text(displayArtistText)
                    .font(.title3.weight(.semibold))
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text(fullSummaryText)
                    .font(.body)
                    .lineLimit(5)
                    .foregroundStyle(AppTheme.ink)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)

                if shouldShowMore {
                    Button("more") {
                        AppHaptics.mediumImpact()
                        showFullDescription = true
                    }
                    .font(.body.weight(.semibold))
                    .foregroundStyle(AppTheme.ink)
                    .frame(maxWidth: .infinity, alignment: .trailing)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var detailsSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Details")
                .font(.title2.weight(.bold))

            ForEach(Array(detailRows.enumerated()), id: \.offset) { index, row in
                ResultDetailRow(icon: row.icon, title: row.title, value: row.value)

                if index != detailRows.count - 1 {
                    Divider()
                        .padding(.leading, 32)
                }
            }

            if let disclaimer = cleanedInlineText(result.disclaimer) {
                Text(disclaimer)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .padding(.top, 4)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(AppTheme.cardBackground, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
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

    private var artistInitial: String {
        let artist = cleanedInlineText(result.identifiedArtist) ?? ""
        guard let first = artist.first else { return "?" }
        return String(first).uppercased()
    }

    private var displayValueText: String {
        cleanedInlineText(result.estimatedValueRange) ?? "Value unavailable"
    }

    private var confidenceBadgeLabel: String {
        cleanedInlineText(result.confidenceText) ?? "Unknown"
    }

    private var fullSummaryText: String {
        if !isArtworkIdentified {
            var parts = ["We couldn't confidently identify this artwork yet."]
            if let candidate = cleanedInlineText(result.identifiedArtist) {
                parts.append("Possible artist match: \(candidate).")
            }
            if let value = cleanedInlineText(result.estimatedValueRange) {
                parts.append("Estimated value from available signals: \(value).")
            }
            parts.append("Try a straight-on photo with less glare and tighter framing.")
            return parts.joined(separator: " ")
        }

        var parts: [String] = []
        var traits: [String] = []

        if let year = cleanedInlineText(result.yearEstimate) {
            traits.append("Year: \(year)")
        }
        if let medium = cleanedInlineText(result.mediumGuess) {
            traits.append("Medium: \(medium)")
        }
        if let style = cleanedInlineText(result.style) {
            traits.append("Style: \(style)")
        }
        if let format = cleanedInlineText(result.isOriginalOrPrint) {
            traits.append("Format: \(format.capitalized)")
        }
        if !traits.isEmpty {
            parts.append(traits.joined(separator: " | "))
        }

        if let value = cleanedInlineText(result.estimatedValueRange) {
            parts.append("Estimated value: \(value).")
        }
        if let reasoning = cleanedBlockText(result.valueReasoning) {
            parts.append(reasoning)
        } else if let comps = cleanedBlockText(result.comparableExamplesSummary) {
            parts.append("Comparable examples: \(comps)")
        }

        if parts.isEmpty, let fallback = cleanedBlockText(result.summaryText) {
            return fallback
        }

        if parts.isEmpty {
            return "No additional details are available for this artwork."
        }
        return parts.joined(separator: "\n\n")
    }

    private var shouldShowMore: Bool {
        fullSummaryText.count > 220 || fullSummaryText.contains("\n")
    }

    private var detailRows: [(icon: String, title: String, value: String)] {
        var rows: [(icon: String, title: String, value: String)] = [
            ("checkmark.seal", "Confidence", cleanedInlineText(result.confidenceText) ?? "Unknown")
        ]

        if let artist = cleanedInlineText(result.identifiedArtist) {
            rows.append(("person", "Artist", artist))
        }
        if let value = cleanedInlineText(result.estimatedValueRange) {
            rows.append(("banknote", "Estimated value", value))
        }
        if let year = cleanedInlineText(result.yearEstimate) {
            rows.append(("hourglass", "Year estimate", year))
        }
        if let medium = cleanedInlineText(result.mediumGuess) {
            rows.append(("paintpalette", "Medium", medium))
        }
        if let style = cleanedInlineText(result.style) {
            rows.append(("swatchpalette", "Style", style))
        }
        if let format = cleanedInlineText(result.isOriginalOrPrint) {
            rows.append(("doc.on.doc", "Format", format.capitalized))
        }
        if let reasoning = cleanedBlockText(result.valueReasoning) {
            rows.append(("text.quote", "Value reasoning", reasoning))
        }
        if let comps = cleanedBlockText(result.comparableExamplesSummary) {
            rows.append(("list.bullet.rectangle.portrait", "Comparable examples", comps))
        }

        if !isArtworkIdentified {
            rows.append(("camera.viewfinder", "Retake tip", "Use a straight-on photo with less glare and tighter framing."))
        }

        if rows.count == 1 {
            rows.append(("info.circle", "Status", "Limited metadata available"))
        }

        return rows
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

private struct ResultDetailRow: View {
    let icon: String
    let title: String
    let value: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 18, weight: .medium))
                .foregroundStyle(.primary)
                .frame(width: 20)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)

                Text(value)
                    .font(.body)
                    .foregroundStyle(.primary)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct DescriptionSheet: View {
    let text: String
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            Capsule()
                .fill(Color(uiColor: .tertiaryLabel))
                .frame(width: 46, height: 5)
                .opacity(0.35)
                .padding(.top, 10)
                .padding(.bottom, 12)

            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(.primary)
                    }
                    .buttonStyle(.plain)

                    Text(text)
                        .font(.title3)
                        .foregroundStyle(.primary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 26)
            }
        }
    }
}
