import Foundation

protocol AuthServicing {
    var currentSession: AppSession? { get }
    func restoreSession() async -> AppSession?
    func validSession() async throws -> AppSession
    func signInWithEmailOTP(email: String) async throws
    func verifyEmailOTP(email: String, code: String) async throws -> AppSession
    func signOut() async
}

protocol ImageUploadServicing {
    func uploadImage(data: Data) async throws -> URL
}

protocol DetectionServicing {
    func analyze(imageURL: URL) async throws -> ArtworkAnalysis
}

protocol CollectionServicing {
    func fetchRecentItems() async throws -> [SavedArtwork]
    func saveAnalysis(_ analysis: ArtworkAnalysis, sourceImageURL: URL) async throws
}

protocol FavoritesServicing {
    func fetchFavorites() async throws -> [SavedArtwork]
}

protocol SubscriptionServicing {
    func fetchSnapshot() async throws -> SubscriptionSnapshot
    func fetchProfile() async throws -> UserProfile?
}

protocol NotificationServicing {
    func registerForPushIfNeeded() async
}

protocol ShareBridgeServicing {
    func syncConfiguration() async
}
