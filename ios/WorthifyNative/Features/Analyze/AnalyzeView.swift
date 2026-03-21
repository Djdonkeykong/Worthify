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
        WorthifyScreen {
            VStack(alignment: .leading, spacing: 16) {
                Text("Upload a photo of your artwork.")
                    .font(.title2.weight(.semibold))

                Text("Choose a clear image, then run the estimate.")
                    .font(.body)
                    .foregroundStyle(.secondary)

                ZStack {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(Color(uiColor: .secondarySystemGroupedBackground))
                        .frame(height: 280)

                    if let previewImage {
                        previewImage
                            .resizable()
                            .scaledToFill()
                            .frame(maxWidth: .infinity)
                            .frame(height: 280)
                            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    } else {
                        VStack(spacing: 8) {
                            Image(systemName: "photo.badge.plus")
                                .font(.title2)
                                .foregroundStyle(.secondary)
                            Text("No image selected")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                PhotosPicker(selection: $selectedItem, matching: .images) {
                    Label(
                        selectedImageData == nil ? "Choose Image" : "Change Image",
                        systemImage: "photo.fill.on.rectangle.fill"
                    )
                }
                .buttonStyle(WorthifySecondaryButtonStyle())

                if isRunning {
                    ProgressView("Analyzing artwork...")
                        .font(.subheadline.weight(.medium))
                }

                Button(isRunning ? "Analyzing..." : "Run Analysis") {
                    Task { await runAnalysis() }
                }
                .buttonStyle(WorthifyPrimaryButtonStyle())
                .disabled(isRunning || selectedImageData == nil)

                if let result {
                    NavigationLink {
                        ResultsView(result: result)
                    } label: {
                        HStack(spacing: 8) {
                            Text("Open Result")
                            Image(systemName: "chevron.right")
                                .font(.footnote.weight(.semibold))
                        }
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
