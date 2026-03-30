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

    private let headerHeight: CGFloat = 360

    init(prefilledImageData: Data? = nil) {
        _selectedImageData = State(initialValue: prefilledImageData)
        if
            let prefilledImageData,
            let uiImage = UIImage(data: prefilledImageData)
        {
            _previewImage = State(initialValue: Image(uiImage: uiImage))
        } else {
            _previewImage = State(initialValue: nil)
        }
    }

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                AppBackdrop()

                ScrollView(.vertical, showsIndicators: false) {
                    VStack(spacing: 0) {
                        StretchyPreviewHeader(
                            image: previewImage,
                            baseHeight: headerHeight + proxy.safeAreaInsets.top
                        )

                        VStack(alignment: .leading, spacing: 12) {
                            Text("Analyze")
                                .font(.footnote.weight(.semibold))
                                .foregroundStyle(.secondary)
                                .textCase(.uppercase)

                            GlassCard {
                                SectionHeading(
                                    previewImage == nil ? "Choose a photo" : "Ready to analyze",
                                    subtitle: previewImage == nil
                                        ? "Upload an artwork image to begin."
                                        : "Review the image, then run the analysis when it looks right."
                                )

                                VStack(alignment: .leading, spacing: 8) {
                                    guidanceRow(systemImage: "viewfinder", text: "Shoot straight-on and fill the frame with the artwork.")
                                    guidanceRow(systemImage: "sun.max", text: "Avoid glare, shadows, and reflective glass when possible.")
                                    guidanceRow(systemImage: "signature", text: "If the result is weak, retake details like signatures or labels.")
                                }

                                if let errorMessage {
                                    Text(errorMessage)
                                        .font(.footnote.weight(.medium))
                                        .foregroundStyle(.red)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                }

                                HStack(spacing: 12) {
                                    PhotosPicker(selection: $selectedItem, matching: .images) {
                                        actionTile(
                                            title: previewImage == nil ? "Upload photo" : "Change photo",
                                            systemImage: "photo.on.rectangle.angled",
                                            isPrimary: false,
                                            isDisabled: false
                                        )
                                    }
                                    .buttonStyle(.plain)

                                    Button {
                                        Task { await runAnalysis() }
                                    } label: {
                                        actionTile(
                                            title: isRunning ? "Analyzing" : "Analyze",
                                            systemImage: isRunning ? "hourglass" : "magnifyingglass",
                                            isPrimary: true,
                                            isDisabled: isRunning || selectedImageData == nil
                                        )
                                    }
                                    .buttonStyle(.plain)
                                    .disabled(isRunning || selectedImageData == nil)
                                }
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.top, 18)
                        .padding(.bottom, 32)
                    }
                }
                .coordinateSpace(name: "analyze-scroll")
                .ignoresSafeArea(edges: .top)

                if isRunning {
                    analysisOverlay
                }
            }
        }
        .navigationTitle("Analyze")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.hidden, for: .navigationBar)
        .navigationDestination(item: $result) { analysis in
            ResultsView(result: analysis)
        }
        .onChange(of: selectedItem) { _, newValue in
            guard let newValue else { return }
            Task {
                do {
                    if let data = try await newValue.loadTransferable(type: Data.self) {
                        selectedImageData = data
                        result = nil
                        errorMessage = nil
                        if let uiImage = UIImage(data: data) {
                            previewImage = Image(uiImage: uiImage)
                        }
                    }
                } catch {
                    errorMessage = error.localizedDescription
                }
            }
        }
    }

    private func guidanceRow(systemImage: String, text: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: systemImage)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
                .frame(width: 18, alignment: .center)

            Text(text)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func actionTile(title: String, systemImage: String, isPrimary: Bool, isDisabled: Bool) -> some View {
        let backgroundColor = isPrimary
            ? AppTheme.primaryActionBackground
            : Color(uiColor: .tertiarySystemFill)
        let foregroundColor = isPrimary
            ? AppTheme.primaryActionForeground
            : AppTheme.secondaryActionForeground

        return VStack(spacing: 10) {
            Image(systemName: systemImage)
                .font(.system(size: 20, weight: .semibold))

            Text(title)
                .font(.subheadline.weight(.semibold))
                .multilineTextAlignment(.center)
        }
        .foregroundStyle(isDisabled ? .secondary : foregroundColor)
        .frame(maxWidth: .infinity)
        .frame(height: 112)
        .background(
            (isDisabled ? Color(uiColor: .quaternarySystemFill) : backgroundColor),
            in: RoundedRectangle(cornerRadius: 18, style: .continuous)
        )
    }

    private var analysisOverlay: some View {
        ZStack {
            Color.black.opacity(0.78)
                .ignoresSafeArea()

            VStack(spacing: 24) {
                ProgressView()
                    .tint(.white)
                    .controlSize(.large)

                Text("Analyzing artwork...")
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(.white)
            }
        }
        .transition(.opacity)
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

private struct StretchyPreviewHeader: View {
    let image: Image?
    let baseHeight: CGFloat

    var body: some View {
        GeometryReader { proxy in
            let minY = proxy.frame(in: .named("analyze-scroll")).minY
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
                .overlay(alignment: .top) {
                    LinearGradient(
                        colors: [Color.black.opacity(0.16), Color.clear],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    .frame(height: 140)
                }
        }
        .frame(height: baseHeight)
    }

    private var headerImage: some View {
        Group {
            if let image {
                image
                    .resizable()
                    .scaledToFill()
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

            VStack(spacing: 10) {
                Image(systemName: "photo")
                    .font(.system(size: 34, weight: .medium))
                    .foregroundStyle(.secondary)

                Text("Choose an artwork to begin")
                    .font(.headline)
                    .foregroundStyle(.secondary)
            }
        }
    }
}
