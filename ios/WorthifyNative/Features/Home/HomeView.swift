import SwiftUI
import UIKit

struct HomeView: View {
    @State private var showSourceSheet = false
    @State private var showPhotoLibraryPicker = false
    @State private var showCameraPicker = false
    @State private var navigateToAnalyze = false
    @State private var selectedImageData: Data?
    @State private var pickerErrorMessage: String?
    @State private var didSchedulePickerWarmup = false

    var body: some View {
        ZStack {
            AppBackdrop()

            VStack(spacing: 20) {
                previewArtwork
                    .frame(maxWidth: .infinity)
                    .frame(height: 220)

                Text("Scan your first artwork\nwith Worthify")
                    .font(.system(size: 28, weight: .bold))
                    .lineSpacing(2)
                    .multilineTextAlignment(.center)

                Button {
                    AppHaptics.mediumImpact()
                    selectedImageData = nil
                    showSourceSheet = true
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(AppTheme.primaryActionForeground)
                        .frame(width: 88, height: 52)
                        .background(AppTheme.primaryActionBackground, in: Capsule())
                }
                .buttonStyle(.plain)
            }
            .frame(maxWidth: .infinity)
            .frame(maxHeight: .infinity, alignment: .center)
            .padding(.horizontal, 20)
        }
        .toolbar(.hidden, for: .navigationBar)
        .onAppear {
            schedulePhotoLibraryPickerWarmupIfNeeded()
        }
        .navigationDestination(isPresented: $navigateToAnalyze) {
            AnalyzeView(prefilledImageData: selectedImageData)
        }
        .sheet(isPresented: $showSourceSheet) {
            UploadSourceSheet(
                onTakePhoto: { presentSourcePicker(.camera) },
                onUploadPhoto: { presentSourcePicker(.photoLibrary) }
            )
            .presentationDetents([.height(285)])
            .presentationDragIndicator(.hidden)
        }
        .sheet(isPresented: $showPhotoLibraryPicker) {
            ImagePicker(sourceType: .photoLibrary, onImagePicked: handlePickedImage)
                .ignoresSafeArea()
        }
        .sheet(isPresented: $showCameraPicker) {
            ImagePicker(sourceType: .camera, onImagePicked: handlePickedImage)
                .ignoresSafeArea()
        }
        .alert("Unable to continue", isPresented: isPickerErrorPresented) {
            Button("OK", role: .cancel) {
                pickerErrorMessage = nil
            }
        } message: {
            Text(pickerErrorMessage ?? "Unknown source error.")
        }
    }

    private var isPickerErrorPresented: Binding<Bool> {
        Binding(
            get: { pickerErrorMessage != nil },
            set: { if !$0 { pickerErrorMessage = nil } }
        )
    }

    @ViewBuilder
    private var previewArtwork: some View {
        placeholderArtwork
    }

    private var placeholderArtwork: some View {
        Image("HomePlaceholder")
            .resizable()
            .scaledToFit()
            .frame(maxHeight: 220)
    }

    private func presentSourcePicker(_ sourceType: UIImagePickerController.SourceType) {
        showSourceSheet = false

        if sourceType == .camera, !UIImagePickerController.isSourceTypeAvailable(.camera) {
            pickerErrorMessage = "Camera is not available on this device."
            return
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            switch sourceType {
            case .camera:
                showCameraPicker = true
            case .photoLibrary:
                showPhotoLibraryPicker = true
            default:
                break
            }
        }
    }

    private func handlePickedImage(_ image: UIImage) {
        guard let imageData = image.jpegData(compressionQuality: 0.92) ?? image.pngData() else {
            pickerErrorMessage = "Could not load the selected image."
            return
        }

        selectedImageData = imageData
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            navigateToAnalyze = true
        }
    }

    private func schedulePhotoLibraryPickerWarmupIfNeeded() {
        guard !didSchedulePickerWarmup else { return }
        didSchedulePickerWarmup = true

        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 450_000_000)
            ImagePickerWarmup.prewarmPhotoLibraryPicker()
        }
    }
}

private struct UploadSourceSheet: View {
    let onTakePhoto: () -> Void
    let onUploadPhoto: () -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Capsule()
                .fill(Color(uiColor: .tertiaryLabel))
                .frame(width: 44, height: 5)
                .frame(maxWidth: .infinity)
                .opacity(0.35)
                .padding(.top, 8)

            HStack {
                Text("Pick your source")
                    .font(.title.weight(.bold))

                Spacer()

                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .frame(width: 38, height: 38)
                        .background(Color(uiColor: .tertiarySystemFill), in: Circle())
                }
                .buttonStyle(.plain)
            }

            Text("Choose your starting point")
                .font(.body)
                .foregroundStyle(.secondary)

            HStack(spacing: 12) {
                sourceButton(title: "Snap", iconAsset: "ImportSnapSymbol") {
                    dismiss()
                    onTakePhoto()
                }

                sourceButton(title: "Upload", iconAsset: "ImportUploadSymbol") {
                    dismiss()
                    onUploadPhoto()
                }
            }
            .frame(maxWidth: .infinity)

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 18)
        .padding(.bottom, 16)
    }

    private func sourceButton(title: String, iconAsset: String, action: @escaping () -> Void) -> some View {
        Button {
            AppHaptics.mediumImpact()
            action()
        } label: {
            VStack(spacing: 12) {
                Image(iconAsset)
                    .renderingMode(.template)
                    .resizable()
                    .scaledToFit()
                    .foregroundStyle(AppTheme.primaryActionBackground)
                    .frame(width: 22, height: 22)
                    .frame(width: 46, height: 46)
                    .background(Color(uiColor: .tertiarySystemFill), in: RoundedRectangle(cornerRadius: 12, style: .continuous))

                Text(title)
                    .font(.headline)
                    .foregroundStyle(.primary)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 128)
            .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}

private struct ImagePicker: UIViewControllerRepresentable {
    let sourceType: UIImagePickerController.SourceType
    let onImagePicked: (UIImage) -> Void
    @Environment(\.dismiss) private var dismiss

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = sourceType
        picker.delegate = context.coordinator
        picker.allowsEditing = false
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    final class Coordinator: NSObject, UINavigationControllerDelegate, UIImagePickerControllerDelegate {
        private let parent: ImagePicker

        init(parent: ImagePicker) {
            self.parent = parent
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            parent.dismiss()
        }

        func imagePickerController(
            _ picker: UIImagePickerController,
            didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]
        ) {
            parent.dismiss()

            if let image = info[.originalImage] as? UIImage {
                DispatchQueue.main.async {
                    self.parent.onImagePicked(image)
                }
            }
        }
    }
}

private enum ImagePickerWarmup {
    private static var didPrewarmPhotoLibraryPicker = false

    @MainActor
    static func prewarmPhotoLibraryPicker() {
        guard !didPrewarmPhotoLibraryPicker else { return }
        didPrewarmPhotoLibraryPicker = true
        guard UIImagePickerController.isSourceTypeAvailable(.photoLibrary) else { return }

        let picker = UIImagePickerController()
        picker.sourceType = .photoLibrary
        _ = picker.view
    }
}
