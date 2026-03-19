import PhotosUI
import SwiftUI
import UIKit

struct AnalyzeView: View {
    @EnvironmentObject private var environment: AppEnvironment
    @State private var isRunning = false
    @State private var result: ArtworkAnalysis?
    @State private var errorMessage: String?
    @State private var selectedItem: PhotosPickerItem?
    @State private var selectedImageData: Data?
    @State private var previewImage: Image?

    var body: some View {
        WorthifyScreen {
            HeroPanel(
                eyebrow: "Analyze",
                title: "Bring the artwork forward.",
                subtitle: "Pick a clear photo, upload it, and let the backend return a structured estimate."
            ) {
                HStack(spacing: 10) {
                    MetricPill(title: "Upload", value: "Cloudinary")
                    MetricPill(title: "Result", value: result == nil ? "Pending" : "Ready", tint: AppTheme.accentSecondary)
                }
            }

            GlassCard {
                SectionHeading("Selected image", subtitle: "A tight, glare-free photo gives the best result.")

                if let previewImage {
                    previewImage
                        .resizable()
                        .scaledToFill()
                        .frame(maxWidth: .infinity)
                        .frame(height: 280)
                        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 24, style: .continuous)
                                .stroke(.white.opacity(0.72), lineWidth: 1)
                        )
                } else {
                    VStack(alignment: .leading, spacing: 12) {
                        ZStack {
                            RoundedRectangle(cornerRadius: 24, style: .continuous)
                                .fill(.thinMaterial)
                                .frame(height: 220)

                            Image(systemName: "photo.badge.plus")
                                .font(.system(size: 34, weight: .semibold))
                                .foregroundStyle(AppTheme.accent)
                        }

                        Text("No image selected")
                            .font(.system(.headline, design: .rounded, weight: .bold))

                        Text("Choose an artwork photo from your library to begin.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }

                PhotosPicker(selection: $selectedItem, matching: .images) {
                    Label(selectedImageData == nil ? "Choose image" : "Change image", systemImage: "photo.fill.on.rectangle.fill")
                }
                .buttonStyle(WorthifySecondaryButtonStyle())
            }

            if let result {
                NavigationLink {
                    ResultsView(result: result)
                } label: {
                    GlassCard {
                        SectionHeading("Latest result")

                        VStack(alignment: .leading, spacing: 8) {
                            Text(result.titleText)
                                .font(.system(.title3, design: .rounded, weight: .bold))
                            Text(result.artistText)
                                .foregroundStyle(.secondary)

                            HStack(spacing: 8) {
                                ConfidenceBadge(label: result.confidenceText)
                                if let value = result.estimatedValueRange {
                                    InsightChip(text: value, tint: AppTheme.accentSecondary)
                                }
                            }
                        }
                    }
                }
                .buttonStyle(.plain)
            }

            if let errorMessage {
                GlassCard {
                    Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.red)
                }
            }
        }
        .navigationTitle("Analyze")
        .navigationBarTitleDisplayMode(.inline)
        .onChange(of: selectedItem) { _, newValue in
            guard let newValue else { return }
            Task {
                do {
                    if let data = try await newValue.loadTransferable(type: Data.self) {
                        selectedImageData = data
                        if let uiImage = UIImage(data: data) {
                            previewImage = Image(uiImage: uiImage)
                        }
                    }
                } catch {
                    errorMessage = error.localizedDescription
                }
            }
        }
        .safeAreaInset(edge: .bottom) {
            VStack(spacing: 12) {
                if isRunning {
                    ProgressView("Analyzing artwork...")
                        .progressViewStyle(.circular)
                        .font(.subheadline.weight(.medium))
                }

                Button(isRunning ? "Analyzing..." : "Run analysis") {
                    Task { await runAnalysis() }
                }
                .buttonStyle(WorthifyPrimaryButtonStyle())
                .disabled(isRunning || selectedImageData == nil)
            }
            .padding(.horizontal, 20)
            .padding(.top, 10)
            .padding(.bottom, 8)
            .background(.ultraThinMaterial)
        }
    }

    private func runAnalysis() async {
        guard let selectedImageData else { return }

        isRunning = true
        defer { isRunning = false }

        do {
            let imageURL = try await environment.uploadService.uploadImage(data: selectedImageData)
            result = try await environment.detectionService.analyze(imageURL: imageURL)
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
