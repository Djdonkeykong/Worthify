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
                backgroundLayer(size: proxy.size)

                VStack {
                    Spacer()

                    if let errorMessage {
                        Text(errorMessage)
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 10)
                            .background(Color.black.opacity(0.46), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                            .padding(.horizontal, 20)
                            .padding(.bottom, 12)
                    }

                    HStack(spacing: 14) {
                        PhotosPicker(selection: $selectedItem, matching: .images) {
                            controlButton(
                                symbol: "photo.on.rectangle.angled",
                                isPrimary: false,
                                isDisabled: false
                            )
                        }
                        .buttonStyle(.plain)

                        Button {
                            Task { await runAnalysis() }
                        } label: {
                            controlButton(
                                symbol: isRunning ? "hourglass" : "magnifyingglass",
                                isPrimary: true,
                                isDisabled: isRunning || selectedImageData == nil
                            )
                        }
                        .buttonStyle(.plain)
                        .disabled(isRunning || selectedImageData == nil)
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 24)
                }

                if isRunning {
                    analysisOverlay
                }
            }
        }
        .navigationTitle("Analyze")
        .navigationBarTitleDisplayMode(.inline)
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

    @ViewBuilder
    private func backgroundLayer(size: CGSize) -> some View {
        if let previewImage {
            AppBackdrop()

            VStack {
                previewImage
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: .infinity, maxHeight: imageDisplayHeight(for: size))
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .padding(.horizontal, 8)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(.top, 68)
            .padding(.bottom, 104)
        } else {
            ZStack {
                AppBackdrop()

                VStack(spacing: 12) {
                    Image(systemName: "photo")
                        .font(.system(size: 34, weight: .medium))
                        .foregroundStyle(.secondary)
                    Text("Choose an artwork to begin")
                        .font(.headline)
                        .foregroundStyle(.secondary)
                }
            }
            .ignoresSafeArea()
        }
    }

    private func imageDisplayHeight(for size: CGSize) -> CGFloat {
        let target = size.height * 0.75
        return max(420, min(target, 760))
    }

    private func controlButton(symbol: String, isPrimary: Bool, isDisabled: Bool) -> some View {
        let backgroundColor = isPrimary ? AppTheme.primaryActionBackground : Color.black.opacity(0.40)
        let foregroundColor = AppTheme.primaryActionForeground

        return Image(systemName: symbol)
            .font(.system(size: 22, weight: .semibold))
            .foregroundStyle(isDisabled ? .white.opacity(0.5) : foregroundColor)
            .frame(width: 72, height: 72)
            .background(
                (isDisabled ? Color.black.opacity(0.25) : backgroundColor),
                in: Circle()
            )
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
