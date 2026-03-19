import SwiftUI

struct ResultsView: View {
    @EnvironmentObject private var environment: AppEnvironment
    let result: ArtworkAnalysis
    @State private var saveMessage: String?
    @State private var isSaving = false

    var body: some View {
        WorthifyScreen {
            HeroPanel(
                eyebrow: "Result",
                title: result.titleText,
                subtitle: result.artistText
            ) {
                HStack(spacing: 8) {
                    ConfidenceBadge(label: result.confidenceText)
                    if let value = result.estimatedValueRange {
                        InsightChip(text: value, tint: AppTheme.accentSecondary)
                    }
                }
            }

            ImageCard(url: result.sourceImageURL, height: 250)

            GlassCard {
                SectionHeading("Overview")

                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                    MetricPill(title: "Confidence", value: result.confidenceText)
                    MetricPill(title: "Value", value: result.estimatedValueRange ?? "Unknown", tint: AppTheme.accentSecondary)

                    if let yearEstimate = result.yearEstimate {
                        MetricPill(title: "Year", value: yearEstimate, tint: AppTheme.gold)
                    }

                    if let mediumGuess = result.mediumGuess {
                        MetricPill(title: "Medium", value: mediumGuess, tint: AppTheme.rose)
                    }
                }

                if let style = result.style {
                    InsightChip(text: style)
                }
            }

            GlassCard {
                SectionHeading("Interpretation")
                Text(result.summaryText)
                    .font(.body)
                    .foregroundStyle(AppTheme.ink)
            }

            GlassCard {
                SectionHeading("Disclaimer")
                Text(result.disclaimer)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            if let saveMessage {
                GlassCard {
                    Label(saveMessage, systemImage: saveMessage == "Saved." ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                        .foregroundStyle(saveMessage == "Saved." ? .green : .secondary)
                }
            }
        }
        .navigationTitle("Result")
        .navigationBarTitleDisplayMode(.inline)
        .safeAreaInset(edge: .bottom) {
            Button(isSaving ? "Saving..." : "Save to collection") {
                Task { await saveResult() }
            }
            .buttonStyle(WorthifyPrimaryButtonStyle())
            .disabled(isSaving || result.sourceImageURL == nil)
            .padding(.horizontal, 20)
            .padding(.top, 10)
            .padding(.bottom, 8)
            .background(.ultraThinMaterial)
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
}
