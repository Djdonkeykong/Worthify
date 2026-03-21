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
                AppBackdrop()

                VStack(spacing: 14) {
                    HStack(spacing: 12) {
                        PhotosPicker(selection: $selectedItem, matching: .images) {
                            Label(
                                selectedImageData == nil ? "Choose Image" : "Change Image",
                                systemImage: "photo.fill.on.rectangle.fill"
                            )
                        }
                        .buttonStyle(WorthifySecondaryButtonStyle())

                        Button("Run Analysis") {
                            Task { await runAnalysis() }
                        }
                        .buttonStyle(WorthifyPrimaryButtonStyle())
                        .disabled(isRunning || selectedImageData == nil)
                    }
                    .padding(.top, 8)

                    ZStack {
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .fill(Color(uiColor: .secondarySystemGroupedBackground))

                        if let previewImage {
                            previewImage
                                .resizable()
                                .scaledToFill()
                        } else {
                            VStack(spacing: 10) {
                                Image(systemName: "photo.badge.plus")
                                    .font(.title2)
                                    .foregroundStyle(.secondary)
                                Text("No image selected")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: imageHeight(for: proxy.size))
                    .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))

                    if let result {
                        NavigationLink {
                            ResultsView(result: result)
                        } label: {
                            Text("Open Result")
                                .font(.headline)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 14)
                                .background(Color(uiColor: .tertiarySystemFill), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                        }
                        .buttonStyle(.plain)
                    }

                    if let errorMessage {
                        Text(errorMessage)
                            .font(.subheadline)
                            .foregroundStyle(.red)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }

                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 12)

                if isRunning {
                    analysisOverlay
                }
            }
        }
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
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

    private func imageHeight(for size: CGSize) -> CGFloat {
        let target = size.height * 0.64
        return max(360, min(target, 620))
    }

    private var analysisOverlay: some View {
        ZStack {
            Color.black.opacity(0.62)
                .ignoresSafeArea()

            VStack(spacing: 14) {
                ProgressView()
                    .progressViewStyle(.circular)
                    .tint(.white)
                    .scaleEffect(1.2)

                Text("Analyzing artwork...")
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(.white)
            }
            .padding(.horizontal, 28)
            .padding(.vertical, 24)
            .background(Color.black.opacity(0.22), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
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
