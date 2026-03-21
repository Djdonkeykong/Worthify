import SwiftUI
import Foundation

struct ResultsView: View {
    @EnvironmentObject private var environment: AppEnvironment
    let result: ArtworkAnalysis
    @State private var saveMessage: String?
    @State private var isSaving = false
    @State private var showFullDescription = false

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
        ZStack {
            AppBackdrop()

            ScrollView(.vertical) {
                VStack(alignment: .leading, spacing: 22) {
                        resultImage

                        VStack(alignment: .leading, spacing: 12) {
                            Text(layoutSafeTitleText)
                                .font(.system(size: 34, weight: .bold))
                                .lineLimit(2)
                                .minimumScaleFactor(0.75)
                                .multilineTextAlignment(.leading)
                                .frame(maxWidth: .infinity, alignment: .leading)

                            Text(displayValue)
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

                                Text(layoutSafeArtistText)
                                    .font(.title3.weight(.semibold))
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }

                            VStack(alignment: .leading, spacing: 6) {
                                Text(layoutSafeSummaryText)
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

                        Divider()

                        VStack(alignment: .leading, spacing: 14) {
                            Text("Details")
                                .font(.title2.weight(.bold))

                            ForEach(Array(detailRows.enumerated()), id: \.offset) { index, row in
                                DetailRow(icon: row.icon, title: row.title, value: row.value)

                                if index != detailRows.count - 1 {
                                    Divider()
                                        .padding(.leading, 32)
                                }
                            }

                            Text(result.disclaimer)
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                                .padding(.top, 4)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(16)
                        .background(AppTheme.cardBackground, in: RoundedRectangle(cornerRadius: 16, style: .continuous))

                        if let saveMessage {
                            GlassCard {
                                Label(saveMessage, systemImage: saveMessage == "Saved." ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                                    .foregroundStyle(saveMessage == "Saved." ? .green : .secondary)
                            }
                        } else if isGuestMode {
                            GlassCard {
                                Label("Guest mode is enabled. Saving to collection is disabled for now.", systemImage: "lock.slash")
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
        .clipped()
        .navigationTitle("Result")
        .navigationBarTitleDisplayMode(.inline)
        .safeAreaInset(edge: .bottom) {
            Button(isSaving ? "Saving..." : "Save to collection") {
                Task { await saveResult() }
            }
            .buttonStyle(WorthifyPrimaryButtonStyle())
            .disabled(isSaving || result.sourceImageURL == nil || isGuestMode || signedInSession == nil)
            .padding(.horizontal, 20)
            .padding(.top, 10)
            .padding(.bottom, 20)
            .background(.ultraThinMaterial)
        }
        .sheet(isPresented: $showFullDescription) {
            DescriptionSheet(text: layoutSafeSummaryText)
                .presentationDetents([.large])
                .presentationDragIndicator(.hidden)
        }
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

    @ViewBuilder
    private var resultImage: some View {
        Group {
            if let sourceImageURL = result.sourceImageURL {
                AsyncImage(url: sourceImageURL) { phase in
                    switch phase {
                    case let .success(image):
                        image
                            .resizable()
                            .scaledToFill()
                    case .failure:
                        imagePlaceholder
                    case .empty:
                        ZStack {
                            imagePlaceholder
                            ProgressView()
                        }
                    @unknown default:
                        imagePlaceholder
                    }
                }
            } else {
                imagePlaceholder
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: 340)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private var imagePlaceholder: some View {
        ZStack {
            Color(uiColor: .tertiarySystemFill)
            Image(systemName: "photo")
                .font(.title2)
                .foregroundStyle(.secondary)
        }
    }

    private var artistInitial: String {
        let artist = (nonEmpty(result.identifiedArtist) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard let first = artist.first else { return "?" }
        return String(first).uppercased()
    }

    private var isArtworkIdentified: Bool {
        nonEmpty(result.artworkTitle) != nil
    }

    private var displayTitleText: String {
        if isArtworkIdentified {
            return singleSentenceTitle(from: result.titleText)
        }
        return "Artwork not identified yet"
    }

    private var displayArtistText: String {
        if isArtworkIdentified {
            return result.artistText
        }
        if let artist = nonEmpty(result.identifiedArtist) {
            return "Possible artist: \(artist)"
        }
        return "No confident artist match yet"
    }

    private var layoutSafeTitleText: String {
        layoutSafeInlineText(displayTitleText)
    }

    private var layoutSafeArtistText: String {
        layoutSafeInlineText(displayArtistText)
    }

    private var displayValue: String {
        guard let value = nonEmpty(result.estimatedValueRange) else {
            return "Value unavailable"
        }

        return extractedPrice(from: value) ?? value
    }

    private var shouldShowMore: Bool {
        summaryText.count > 220
    }

    private var layoutSafeSummaryText: String {
        addSoftWrapOpportunities(to: summaryText)
    }

    private var summaryText: String {
        if !isArtworkIdentified {
            var snippets: [String] = [
                "We couldn't confidently identify this artwork yet."
            ]

            if let artist = nonEmpty(result.identifiedArtist) {
                snippets.append("Possible artist match: \(artist).")
            }

            if displayValue != "Value unavailable" {
                snippets.append("Estimated value from available signals: \(displayValue).")
            }

            snippets.append("Try a straight-on photo with less glare and tighter framing.")
            return snippets.joined(separator: " ")
        }

        var snippets: [String] = []
        var coreTraits: [String] = []
        if let year = nonEmpty(result.yearEstimate) {
            coreTraits.append("year estimate \(year)")
        }
        if let medium = nonEmpty(result.mediumGuess) {
            coreTraits.append("medium \(medium)")
        }
        if let style = nonEmpty(result.style) {
            coreTraits.append("style \(style)")
        }
        if let originality = nonEmpty(result.isOriginalOrPrint) {
            coreTraits.append("\(originality.capitalized) format")
        }
        if !coreTraits.isEmpty {
            snippets.append("Short summary: \(sentenceCase(coreTraits.joined(separator: ", "))).")
        }

        if displayValue != "Value unavailable" {
            snippets.append("Estimated value: \(displayValue).")
        }

        if let reasoning = nonEmpty(result.valueReasoning) {
            snippets.append(sentenceCase(firstSentence(in: reasoning, fallbackLimit: 160)))
        } else if let comps = nonEmpty(result.comparableExamplesSummary) {
            snippets.append(sentenceCase(firstSentence(in: comps, fallbackLimit: 160)))
        }

        if let summaryText = nonEmpty(result.summaryText), snippets.isEmpty {
            return summaryText
        }

        if snippets.isEmpty {
            return "No additional details are available for this artwork."
        }
        return snippets.joined(separator: " ")
    }

    private var detailRows: [(icon: String, title: String, value: String)] {
        var rows: [(icon: String, title: String, value: String)] = [
            ("checkmark.seal", "Confidence", result.confidenceText)
        ]

        if let artist = nonEmpty(result.identifiedArtist) {
            rows.append(("person", "Artist", layoutSafeInlineText(artist)))
        }

        if displayValue != "Value unavailable" {
            rows.append(("banknote", "Estimated value", displayValue))
        }

        if let year = nonEmpty(result.yearEstimate) {
            rows.append(("hourglass", "Year estimate", layoutSafeInlineText(year)))
        }

        if let medium = nonEmpty(result.mediumGuess) {
            rows.append(("paintpalette", "Medium", layoutSafeInlineText(medium)))
        }

        if let style = nonEmpty(result.style) {
            rows.append(("swatchpalette", "Style", layoutSafeInlineText(style)))
        }

        if let originality = nonEmpty(result.isOriginalOrPrint) {
            rows.append(("doc.on.doc", "Format", layoutSafeInlineText(originality.capitalized)))
        }

        if let reasoning = nonEmpty(result.valueReasoning) {
            rows.append(("text.quote", "Value reasoning", layoutSafeInlineText(sentenceCase(reasoning))))
        }

        if let comps = nonEmpty(result.comparableExamplesSummary) {
            rows.append(("list.bullet.rectangle.portrait", "Comparable examples", layoutSafeInlineText(sentenceCase(comps))))
        }

        if !isArtworkIdentified {
            rows.append(("camera.viewfinder", "Retake tip", "Use a straight-on photo with less glare and tighter framing."))
        }

        if rows.count == 1 {
            rows.append(("info.circle", "Status", "Limited metadata available"))
        }

        return rows
    }

    private func nonEmpty(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private func singleSentenceTitle(from rawTitle: String) -> String {
        let normalized = rawTitle
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "\r", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard !normalized.isEmpty else { return rawTitle }

        if let range = normalized.range(of: #"[.!?]"#, options: .regularExpression) {
            let sentence = String(normalized[..<range.upperBound]).trimmingCharacters(in: .whitespacesAndNewlines)
            return sentence.isEmpty ? normalized : sentence
        }

        // If there's no sentence punctuation, keep title concise.
        if normalized.count > 90 {
            return String(normalized.prefix(90)).trimmingCharacters(in: .whitespacesAndNewlines) + "..."
        }

        return normalized
    }

    private func sentenceCase(_ text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let first = trimmed.first else { return trimmed }
        return first.uppercased() + trimmed.dropFirst()
    }

    private func firstSentence(in text: String, fallbackLimit: Int) -> String {
        let normalized = text
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "\r", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard !normalized.isEmpty else { return text }

        if let range = normalized.range(of: #"[.!?]"#, options: .regularExpression) {
            let sentence = String(normalized[..<range.upperBound]).trimmingCharacters(in: .whitespacesAndNewlines)
            return sentence.isEmpty ? normalized : sentence
        }

        if normalized.count > fallbackLimit {
            return String(normalized.prefix(fallbackLimit)).trimmingCharacters(in: .whitespacesAndNewlines) + "..."
        }

        return normalized
    }

    private func layoutSafeInlineText(_ text: String) -> String {
        let normalized = text
            .replacingOccurrences(of: "\u{00A0}", with: " ")
            .replacingOccurrences(of: "\u{200B}", with: "")
            .replacingOccurrences(of: "\u{200C}", with: "")
            .replacingOccurrences(of: "\u{200D}", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return addSoftWrapOpportunities(to: normalized)
    }

    private func extractedPrice(from value: String) -> String? {
        let amountPattern = #"(?:[$]\s*\d[\d,]*(?:\.\d+)?(?:\s?[kKmMbB])?|(?:USD|EUR|GBP|NOK|SEK|DKK|CAD|AUD|CHF|JPY|CNY|HKD|SGD|NZD)\s*\d[\d,]*(?:\.\d+)?(?:\s?[kKmMbB])?|\d[\d,]*(?:\.\d+)?\s*(?:USD|EUR|GBP|NOK|SEK|DKK|CAD|AUD|CHF|JPY|CNY|HKD|SGD|NZD))"#
        let rangePattern = #"(?:[$]\s*\d[\d,]*(?:\.\d+)?(?:\s?[kKmMbB])?|(?:USD|EUR|GBP|NOK|SEK|DKK|CAD|AUD|CHF|JPY|CNY|HKD|SGD|NZD)\s*\d[\d,]*(?:\.\d+)?(?:\s?[kKmMbB])?|\d[\d,]*(?:\.\d+)?\s*(?:USD|EUR|GBP|NOK|SEK|DKK|CAD|AUD|CHF|JPY|CNY|HKD|SGD|NZD))\s*(?:to|-)\s*(?:[$]\s*\d[\d,]*(?:\.\d+)?(?:\s?[kKmMbB])?|(?:USD|EUR|GBP|NOK|SEK|DKK|CAD|AUD|CHF|JPY|CNY|HKD|SGD|NZD)\s*\d[\d,]*(?:\.\d+)?(?:\s?[kKmMbB])?|\d[\d,]*(?:\.\d+)?\s*(?:USD|EUR|GBP|NOK|SEK|DKK|CAD|AUD|CHF|JPY|CNY|HKD|SGD|NZD))"#
        let source = value as NSString
        let fullRange = NSRange(location: 0, length: source.length)

        if let rangeRegex = try? NSRegularExpression(pattern: rangePattern, options: [.caseInsensitive]),
           let match = rangeRegex.firstMatch(in: value, options: [], range: fullRange) {
            let matched = source.substring(with: match.range)
            return cleanedAmount(matched)
        }

        if let amountRegex = try? NSRegularExpression(pattern: amountPattern, options: [.caseInsensitive]),
           let match = amountRegex.firstMatch(in: value, options: [], range: fullRange) {
            let matched = source.substring(with: match.range)
            return cleanedAmount(matched)
        }

        return nil
    }

    private func cleanedAmount(_ value: String) -> String {
        var cleaned = value.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
        cleaned = cleaned.replacingOccurrences(
            of: #"([$])\s+(\d)"#,
            with: "$1$2",
            options: .regularExpression
        )
        return cleaned.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    private func addSoftWrapOpportunities(to text: String) -> String {
        text
            .split(separator: " ", omittingEmptySubsequences: false)
            .map { token in
                let raw = String(token)
                guard raw.count > 28 else { return raw }
                return softWrappedToken(raw)
            }
            .joined(separator: " ")
    }

    private func softWrappedToken(_ token: String) -> String {
        let softBreak = "\u{200B}"
        let punctuated = token
            .replacingOccurrences(of: "/", with: "/\(softBreak)")
            .replacingOccurrences(of: "_", with: "_\(softBreak)")
            .replacingOccurrences(of: "-", with: "-\(softBreak)")

        var result = ""
        for (index, character) in punctuated.enumerated() {
            if index > 0, index.isMultiple(of: 18) {
                result.append(softBreak)
            }
            result.append(character)
        }
        return result
    }
}

private struct DetailRow: View {
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

