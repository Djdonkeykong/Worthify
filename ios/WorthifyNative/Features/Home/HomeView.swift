import SwiftUI
import UIKit

struct HomeView: View {
    @EnvironmentObject private var environment: AppEnvironment
    @State private var showSourceSheet = false
    @State private var showPhotoLibraryPicker = false
    @State private var showCameraPicker = false
    @State private var navigateToAnalyze = false
    @State private var selectedImageData: Data?
    @State private var pickerErrorMessage: String?
    @State private var latestSavedItem: SavedArtwork?

    var body: some View {
        WorthifyScreen {
            VStack(spacing: 28) {
                previewArtwork
                    .frame(maxWidth: .infinity)
                    .frame(height: 320)

                Text("Scan your first artwork\nwith Worthify")
                    .font(.system(size: 56, weight: .bold))
                    .lineSpacing(-2)
                    .multilineTextAlignment(.center)

                Button {
                    selectedImageData = nil
                    showSourceSheet = true
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 34, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 176, height: 84)
                        .background(Color(red: 1, green: 0, blue: 0.35), in: Capsule())
                }
                .buttonStyle(.plain)
            }
            .frame(maxWidth: .infinity)
            .padding(.top, 36)
        }
        .toolbar(.hidden, for: .navigationBar)
        .task { await loadLatestArtwork() }
        .refreshable { await loadLatestArtwork() }
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
        if let imageURL = latestSavedItem?.remoteImageURL {
            AsyncImage(url: imageURL) { phase in
                switch phase {
                case let .success(image):
                    image
                        .resizable()
                        .scaledToFit()
                case .failure:
                    placeholderArtwork
                case .empty:
                    placeholderArtwork
                @unknown default:
                    placeholderArtwork
                }
            }
        } else {
            placeholderArtwork
        }
    }

    private var placeholderArtwork: some View {
        Image("home-placeholder")
            .resizable()
            .scaledToFit()
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

    private var isGuestMode: Bool {
        environment.config.bypassAuth && signedInSession == nil
    }

    private var signedInSession: AppSession? {
        if case let .signedIn(session) = environment.sessionStore.state {
            return session
        }
        return nil
    }

    private func loadLatestArtwork() async {
        guard !isGuestMode else {
            latestSavedItem = nil
            return
        }

        do {
            latestSavedItem = (try await environment.collectionService.fetchRecentItems()).first
        } catch {
            latestSavedItem = nil
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
                sourceButton(title: "Snap", systemImage: "camera.fill") {
                    dismiss()
                    onTakePhoto()
                }

                sourceButton(title: "Upload", systemImage: "arrow.up.fill") {
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

    private func sourceButton(title: String, systemImage: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 12) {
                Image(systemName: systemImage)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(Color(red: 1, green: 0, blue: 0.35))
                    .frame(width: 46, height: 46)
                    .background(Color(red: 1, green: 0, blue: 0.35).opacity(0.12), in: RoundedRectangle(cornerRadius: 12, style: .continuous))

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
