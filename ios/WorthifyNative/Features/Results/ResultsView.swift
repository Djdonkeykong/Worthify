import SwiftUI

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

            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    resultImage

                    VStack(alignment: .leading, spacing: 12) {
                        Text(result.titleText)
                            .font(.system(size: 40, weight: .bold, design: .rounded))
                            .lineLimit(2)
                            .minimumScaleFactor(0.75)

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

                            Text(result.artistText)
                                .font(.title3.weight(.semibold))
                        }

                        VStack(alignment: .leading, spacing: 6) {
                            Text(descriptionText)
                                .font(.body)
                                .foregroundStyle(AppTheme.ink)
                                .lineLimit(5)

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

                    Divider()

                    VStack(alignment: .leading, spacing: 14) {
                        Text("Details")
                            .font(.title2.weight(.bold))

                        ForEach(Array(detailRows.enumerated()), id: \.offset) { index, row in
                            DetailRow(icon: row.icon, value: row.value)

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
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 120)
            }
        }
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
            DescriptionSheet(text: descriptionText)
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
        let artist = result.artistText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let first = artist.first else { return "A" }
        return String(first).uppercased()
    }

    private var displayValue: String {
        nonEmpty(result.estimatedValueRange) ?? "Value unavailable"
    }

    private var descriptionText: String {
        let blocks = [
            nonEmpty(result.valueReasoning),
            nonEmpty(result.comparableExamplesSummary)
        ].compactMap { $0 }

        if !blocks.isEmpty {
            return blocks.joined(separator: "\n\n")
        }

        if let summaryText = nonEmpty(result.summaryText) {
            return summaryText
        }

        if let style = nonEmpty(result.style) {
            return style
        }

        if let medium = nonEmpty(result.mediumGuess) {
            return medium
        }

        return "No additional details are available for this artwork."
    }

    private var shouldShowMore: Bool {
        descriptionText.count > 220
    }

    private var detailRows: [(icon: String, value: String)] {
        var rows: [(icon: String, value: String)] = [
            ("checkmark.seal", "Confidence: \(result.confidenceText)")
        ]

        if let year = nonEmpty(result.yearEstimate) {
            rows.append(("hourglass", year))
        }

        if let medium = nonEmpty(result.mediumGuess) {
            rows.append(("paintpalette", medium))
        }

        if let style = nonEmpty(result.style) {
            rows.append(("swatchpalette", style))
        }

        if let originality = nonEmpty(result.isOriginalOrPrint) {
            rows.append(("doc.on.doc", originality.capitalized))
        }

        if rows.count == 1 {
            rows.append(("banknote", displayValue))
        }

        return rows
    }

    private func nonEmpty(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

private struct DetailRow: View {
    let icon: String
    let value: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 18, weight: .medium))
                .foregroundStyle(.primary)
                .frame(width: 20)

            Text(value)
                .font(.body)
                .foregroundStyle(.primary)
        }
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
