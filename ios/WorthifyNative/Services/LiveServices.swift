import CryptoKit
import Foundation
import UserNotifications

final class SupabaseAuthService: AuthServicing {
    var currentSession: AppSession?

    private let config: AppConfig
    private let urlSession: URLSession
    private let storage: UserDefaults
    private let sessionStorageKey = "worthify.session"

    init(
        config: AppConfig,
        urlSession: URLSession = .shared,
        storage: UserDefaults = .standard
    ) {
        self.config = config
        self.urlSession = urlSession
        self.storage = storage
        self.currentSession = loadPersistedSession()
    }

    func restoreSession() async -> AppSession? {
        guard let persisted = loadPersistedSession() else {
            currentSession = nil
            return nil
        }

        if persisted.expiresAt > Date().addingTimeInterval(60) {
            currentSession = persisted
            return persisted
        }

        do {
            let refreshed = try await refreshSession(using: persisted.refreshToken)
            currentSession = refreshed
            persist(refreshed)
            return refreshed
        } catch {
            clearPersistedSession()
            currentSession = nil
            return nil
        }
    }

    func validSession() async throws -> AppSession {
        if let currentSession, !currentSession.isExpired {
            return currentSession
        }

        if let restored = await restoreSession() {
            return restored
        }

        throw AppError.message("Your session has expired. Sign in again.")
    }

    func signInWithEmailOTP(email: String) async throws {
        let request = OTPRequest(email: email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(), createUser: false)

        _ = try await send(
            url: config.authBaseURL.appendingPathComponent("otp"),
            method: "POST",
            bearerToken: nil,
            body: request,
            responseType: EmptyResponse.self
        )
    }

    func verifyEmailOTP(email: String, code: String) async throws -> AppSession {
        let request = VerifyOTPRequest(
            email: email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
            token: code.trimmingCharacters(in: .whitespacesAndNewlines),
            type: "email"
        )

        let response: SessionResponse = try await send(
            url: config.authBaseURL.appendingPathComponent("verify"),
            method: "POST",
            bearerToken: nil,
            body: request,
            responseType: SessionResponse.self
        )

        let session = response.sessionValue
        currentSession = session
        persist(session)
        return session
    }

    func signOut() async {
        currentSession = nil
        clearPersistedSession()
    }

    private func refreshSession(using refreshToken: String) async throws -> AppSession {
        let url = config.authBaseURL.appendingPathComponent("token").appending(queryItems: [
            URLQueryItem(name: "grant_type", value: "refresh_token")
        ])
        let response: SessionResponse = try await send(
            url: url,
            method: "POST",
            bearerToken: nil,
            body: RefreshTokenRequest(refreshToken: refreshToken),
            responseType: SessionResponse.self
        )
        return response.sessionValue
    }

    private func loadPersistedSession() -> AppSession? {
        guard let data = storage.data(forKey: sessionStorageKey) else {
            return nil
        }
        return try? JSONDecoder().decode(AppSession.self, from: data)
    }

    private func persist(_ session: AppSession) {
        guard let data = try? JSONEncoder().encode(session) else { return }
        storage.set(data, forKey: sessionStorageKey)
    }

    private func clearPersistedSession() {
        storage.removeObject(forKey: sessionStorageKey)
    }

    private func send<Response: Decodable, Body: Encodable>(
        url: URL,
        method: String,
        bearerToken: String?,
        body: Body?,
        responseType: Response.Type
    ) async throws -> Response {
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(config.supabaseAnonKey, forHTTPHeaderField: "apikey")
        if let bearerToken {
            request.setValue("Bearer \(bearerToken)", forHTTPHeaderField: "Authorization")
        }
        if let body {
            request.httpBody = try JSONEncoder().encode(body)
        }

        let (data, response) = try await urlSession.data(for: request)
        try validate(response: response, data: data)

        if Response.self == EmptyResponse.self {
            return EmptyResponse() as! Response
        }

        return try JSONDecoder.supabase.decode(Response.self, from: data)
    }

    private func validate(response: URLResponse, data: Data) throws {
        guard let httpResponse = response as? HTTPURLResponse else {
            throw AppError.message("Invalid server response.")
        }

        guard (200..<300).contains(httpResponse.statusCode) else {
            throw parseError(data: data)
        }
    }

    private func parseError(data: Data) -> Error {
        if let authError = try? JSONDecoder.supabase.decode(SupabaseErrorResponse.self, from: data) {
            return AppError.message(authError.message ?? authError.errorDescription ?? "Authentication request failed.")
        }
        return AppError.message(String(decoding: data, as: UTF8.self))
    }
}

final class CloudinaryImageUploadService: ImageUploadServicing {
    private let config: AppConfig
    private let urlSession: URLSession

    init(config: AppConfig, urlSession: URLSession = .shared) {
        self.config = config
        self.urlSession = urlSession
    }

    func uploadImage(data: Data) async throws -> URL {
        guard !config.cloudinaryCloudName.isEmpty,
              !config.cloudinaryAPIKey.isEmpty,
              !config.cloudinaryAPISecret.isEmpty else {
            throw AppError.invalidConfiguration("Cloudinary credentials are missing.")
        }

        let timestamp = String(Int(Date().timeIntervalSince1970))
        let signature = Insecure.SHA1.hash(
            data: Data("timestamp=\(timestamp)\(config.cloudinaryAPISecret)".utf8)
        ).map { String(format: "%02x", $0) }.joined()

        let boundary = "Boundary-\(UUID().uuidString)"
        let body = MultipartFormData(boundary: boundary)
            .adding(name: "timestamp", value: timestamp)
            .adding(name: "api_key", value: config.cloudinaryAPIKey)
            .adding(name: "signature", value: signature)
            .addingFile(name: "file", filename: "worthify-upload.jpg", mimeType: "image/jpeg", data: data)
            .build()

        let url = URL(string: "https://api.cloudinary.com/v1_1/\(config.cloudinaryCloudName)/image/upload")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.httpBody = body

        let (responseData, response) = try await urlSession.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse, (200..<300).contains(httpResponse.statusCode) else {
            throw AppError.message("Cloudinary upload failed.")
        }

        let uploadResponse = try JSONDecoder.supabase.decode(CloudinaryUploadResponse.self, from: responseData)
        guard let secureURL = URL(string: uploadResponse.secureURL) else {
            throw AppError.message("Cloudinary returned an invalid URL.")
        }
        return secureURL
    }
}

final class ArtworkDetectionService: DetectionServicing {
    private let config: AppConfig
    private let urlSession: URLSession

    init(config: AppConfig, urlSession: URLSession = .shared) {
        self.config = config
        self.urlSession = urlSession
    }

    func analyze(imageURL: URL) async throws -> ArtworkAnalysis {
        guard !config.artworkEndpoint.isEmpty else {
            throw AppError.invalidConfiguration("ARTWORK_ENDPOINT is missing.")
        }

        let endpointURL = URL(string: config.artworkEndpoint)!
        var request = URLRequest(url: endpointURL)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let host = endpointURL.host, host.contains("ngrok") {
            request.setValue("true", forHTTPHeaderField: "ngrok-skip-browser-warning")
        }
        request.httpBody = try JSONEncoder().encode(["image_url": imageURL.absoluteString])

        let (data, response) = try await urlSession.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse, (200..<300).contains(httpResponse.statusCode) else {
            throw AppError.message(String(decoding: data, as: UTF8.self))
        }

        var analysis = try JSONDecoder.supabase.decode(ArtworkAnalysis.self, from: data)
        analysis = ArtworkAnalysis(
            id: analysis.id,
            identifiedArtist: analysis.identifiedArtist,
            artworkTitle: analysis.artworkTitle,
            yearEstimate: analysis.yearEstimate,
            style: analysis.style,
            mediumGuess: analysis.mediumGuess,
            isOriginalOrPrint: analysis.isOriginalOrPrint,
            confidenceLevel: analysis.confidenceLevel,
            estimatedValueRange: analysis.estimatedValueRange,
            valueReasoning: analysis.valueReasoning,
            comparableExamplesSummary: analysis.comparableExamplesSummary,
            disclaimer: analysis.disclaimer,
            sourceImageURL: imageURL
        )
        return analysis
    }
}

final class SupabaseCollectionService: CollectionServicing {
    private let config: AppConfig
    private let authService: AuthServicing
    private let urlSession: URLSession

    init(config: AppConfig, authService: AuthServicing, urlSession: URLSession = .shared) {
        self.config = config
        self.authService = authService
        self.urlSession = urlSession
    }

    func fetchRecentItems() async throws -> [SavedArtwork] {
        let session = try await authService.validSession()
        let url = config.restBaseURL.appendingPathComponent("artwork_identifications").appending(queryItems: [
            URLQueryItem(name: "select", value: "id,user_id,image_url,identified_artist,artwork_title,estimated_value_range,confidence_level,created_at"),
            URLQueryItem(name: "user_id", value: "eq.\(session.userID)"),
            URLQueryItem(name: "order", value: "created_at.desc"),
            URLQueryItem(name: "limit", value: "50")
        ])

        return try await fetchArray(url: url, session: session, type: SavedArtwork.self)
    }

    func saveAnalysis(_ analysis: ArtworkAnalysis, sourceImageURL: URL) async throws {
        let session = try await authService.validSession()
        let url = config.restBaseURL.appendingPathComponent("artwork_identifications")
        let body = SaveArtworkRequest(
            userID: session.userID,
            imageURL: sourceImageURL.absoluteString,
            identifiedArtist: analysis.identifiedArtist,
            artworkTitle: analysis.artworkTitle,
            yearEstimate: analysis.yearEstimate,
            style: analysis.style,
            mediumGuess: analysis.mediumGuess,
            isOriginalOrPrint: analysis.isOriginalOrPrint,
            confidenceLevel: analysis.confidenceLevel,
            estimatedValueRange: analysis.estimatedValueRange,
            valueReasoning: analysis.valueReasoning,
            comparableExamplesSummary: analysis.comparableExamplesSummary,
            disclaimer: analysis.disclaimer,
            isSaved: true
        )

        _ = try await send(url: url, method: "POST", session: session, body: body, responseType: EmptyResponse.self, preferRepresentation: "return=minimal")
    }

    private func fetchArray<Response: Decodable>(url: URL, session: AppSession, type: Response.Type) async throws -> [Response] {
        let response: [Response] = try await send(url: url, method: "GET", session: session, body: Optional<Data>.none, responseType: [Response].self)
        return response
    }

    private func send<Response: Decodable, Body: Encodable>(
        url: URL,
        method: String,
        session: AppSession,
        body: Body?,
        responseType: Response.Type,
        preferRepresentation: String? = nil
    ) async throws -> Response {
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue(config.supabaseAnonKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(session.accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let preferRepresentation {
            request.setValue(preferRepresentation, forHTTPHeaderField: "Prefer")
        }
        if let body {
            request.httpBody = try JSONEncoder().encode(body)
        }

        let (data, response) = try await urlSession.data(for: request)
        try validate(response: response, data: data)

        if Response.self == EmptyResponse.self {
            return EmptyResponse() as! Response
        }

        if data.isEmpty {
            throw AppError.message("Server returned an empty response.")
        }

        return try JSONDecoder.supabase.decode(Response.self, from: data)
    }

    private func validate(response: URLResponse, data: Data) throws {
        guard let httpResponse = response as? HTTPURLResponse else {
            throw AppError.message("Invalid server response.")
        }
        guard (200..<300).contains(httpResponse.statusCode) else {
            if let error = try? JSONDecoder.supabase.decode(SupabaseErrorResponse.self, from: data) {
                throw AppError.message(error.message ?? error.errorDescription ?? "Request failed.")
            }
            throw AppError.message(String(decoding: data, as: UTF8.self))
        }
    }
}

final class SupabaseFavoritesService: FavoritesServicing {
    private let collectionService: SupabaseCollectionService

    init(config: AppConfig, authService: AuthServicing, urlSession: URLSession = .shared) {
        self.collectionService = SupabaseCollectionService(config: config, authService: authService, urlSession: urlSession)
    }

    func fetchFavorites() async throws -> [SavedArtwork] {
        try await collectionService.fetchRecentItems()
    }
}

actor LocalCollectionStore {
    private var items: [SavedArtwork] = []

    func recentItems() -> [SavedArtwork] {
        items.sorted { $0.createdAt > $1.createdAt }
    }

    func save(_ item: SavedArtwork) {
        items.insert(item, at: 0)
    }
}

final class LocalCollectionService: CollectionServicing {
    private let store: LocalCollectionStore
    private let localUserID: String

    init(
        store: LocalCollectionStore = LocalCollectionStore(),
        localUserID: String = "local-device"
    ) {
        self.store = store
        self.localUserID = localUserID
    }

    func fetchRecentItems() async throws -> [SavedArtwork] {
        await store.recentItems()
    }

    func saveAnalysis(_ analysis: ArtworkAnalysis, sourceImageURL: URL) async throws {
        let item = SavedArtwork(
            id: UUID(),
            userID: localUserID,
            imageURL: sourceImageURL.absoluteString,
            identifiedArtist: analysis.identifiedArtist,
            artworkTitle: analysis.artworkTitle,
            estimatedValueRange: analysis.estimatedValueRange,
            confidenceLevel: analysis.confidenceLevel,
            createdAt: Date()
        )
        await store.save(item)
    }
}

final class LocalFavoritesService: FavoritesServicing {
    private let collectionService: CollectionServicing

    init(collectionService: CollectionServicing) {
        self.collectionService = collectionService
    }

    func fetchFavorites() async throws -> [SavedArtwork] {
        try await collectionService.fetchRecentItems()
    }
}

final class SupabaseSubscriptionService: SubscriptionServicing {
    private let config: AppConfig
    private let authService: AuthServicing
    private let urlSession: URLSession

    init(config: AppConfig, authService: AuthServicing, urlSession: URLSession = .shared) {
        self.config = config
        self.authService = authService
        self.urlSession = urlSession
    }

    func fetchSnapshot() async throws -> SubscriptionSnapshot {
        guard let profile = try await fetchProfile() else {
            return .inactive
        }

        return SubscriptionSnapshot(
            isActive: profile.subscriptionStatus == "active",
            isTrial: false,
            productIdentifier: profile.subscriptionProductID,
            availableCredits: profile.availableCredits ?? 0
        )
    }

    func fetchProfile() async throws -> UserProfile? {
        let session = try await authService.validSession()
        let url = config.restBaseURL.appendingPathComponent("users").appending(queryItems: [
            URLQueryItem(name: "select", value: "id,email,full_name,avatar_url,subscription_status,subscription_product_id,paid_credits_remaining"),
            URLQueryItem(name: "id", value: "eq.\(session.userID)"),
            URLQueryItem(name: "limit", value: "1")
        ])

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue(config.supabaseAnonKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(session.accessToken)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await urlSession.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse, (200..<300).contains(httpResponse.statusCode) else {
            throw AppError.message(String(decoding: data, as: UTF8.self))
        }

        let profiles = try JSONDecoder.supabase.decode([UserProfile].self, from: data)
        return profiles.first
    }
}

struct NativeNotificationService: NotificationServicing {
    func registerForPushIfNeeded() async {
        _ = try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge, .sound])
    }
}

struct AppGroupShareBridge: ShareBridgeServicing {
    private let config: AppConfig

    init(config: AppConfig) {
        self.config = config
    }

    func syncConfiguration() async {
        guard !config.appGroupID.isEmpty,
              let defaults = UserDefaults(suiteName: config.appGroupID) else {
            return
        }

        defaults.set(config.searchAPIKey, forKey: "SerpApiKey")
        defaults.set(config.detectAndSearchEndpoint, forKey: "DetectorEndpoint")
        defaults.set(config.apifyAPIToken, forKey: "ApifyApiToken")
        defaults.set(config.supabaseURL, forKey: "SupabaseUrl")
        defaults.set(config.supabaseAnonKey, forKey: "SupabaseAnonKey")
    }
}

private struct OTPRequest: Encodable {
    let email: String
    let createUser: Bool

    enum CodingKeys: String, CodingKey {
        case email
        case createUser = "create_user"
    }
}

private struct VerifyOTPRequest: Encodable {
    let email: String
    let token: String
    let type: String
}

private struct RefreshTokenRequest: Encodable {
    let refreshToken: String

    enum CodingKeys: String, CodingKey {
        case refreshToken = "refresh_token"
    }
}

private struct SessionResponse: Codable {
    let accessToken: String
    let refreshToken: String
    let expiresIn: Int
    let user: SessionUser

    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case refreshToken = "refresh_token"
        case expiresIn = "expires_in"
        case user
    }

    var sessionValue: AppSession {
        AppSession(
            userID: user.id,
            email: user.email,
            isAnonymous: user.isAnonymous,
            accessToken: accessToken,
            refreshToken: refreshToken,
            expiresAt: Date().addingTimeInterval(TimeInterval(expiresIn))
        )
    }
}

private struct SessionUser: Codable {
    let id: String
    let email: String?
    let isAnonymous: Bool

    enum CodingKeys: String, CodingKey {
        case id
        case email
        case isAnonymous = "is_anonymous"
    }
}

private struct SaveArtworkRequest: Encodable {
    let userID: String
    let imageURL: String
    let identifiedArtist: String?
    let artworkTitle: String?
    let yearEstimate: String?
    let style: String?
    let mediumGuess: String?
    let isOriginalOrPrint: String?
    let confidenceLevel: String
    let estimatedValueRange: String?
    let valueReasoning: String?
    let comparableExamplesSummary: String?
    let disclaimer: String
    let isSaved: Bool

    enum CodingKeys: String, CodingKey {
        case userID = "user_id"
        case imageURL = "image_url"
        case identifiedArtist = "identified_artist"
        case artworkTitle = "artwork_title"
        case yearEstimate = "year_estimate"
        case style
        case mediumGuess = "medium_guess"
        case isOriginalOrPrint = "is_original_or_print"
        case confidenceLevel = "confidence_level"
        case estimatedValueRange = "estimated_value_range"
        case valueReasoning = "value_reasoning"
        case comparableExamplesSummary = "comparable_examples_summary"
        case disclaimer
        case isSaved = "is_saved"
    }
}

private struct CloudinaryUploadResponse: Decodable {
    let secureURL: String

    enum CodingKeys: String, CodingKey {
        case secureURL = "secure_url"
    }
}

private struct SupabaseErrorResponse: Decodable {
    let message: String?
    let error: String?
    let errorDescription: String?

    enum CodingKeys: String, CodingKey {
        case message
        case error
        case errorDescription = "error_description"
    }
}

private struct EmptyResponse: Codable {}

private struct MultipartFormData {
    private let boundary: String
    private var data = Data()

    init(boundary: String) {
        self.boundary = boundary
    }

    func adding(name: String, value: String) -> MultipartFormData {
        var copy = self
        copy.data.append("--\(boundary)\r\n".data(using: .utf8)!)
        copy.data.append("Content-Disposition: form-data; name=\"\(name)\"\r\n\r\n".data(using: .utf8)!)
        copy.data.append("\(value)\r\n".data(using: .utf8)!)
        return copy
    }

    func addingFile(name: String, filename: String, mimeType: String, data fileData: Data) -> MultipartFormData {
        var copy = self
        copy.data.append("--\(boundary)\r\n".data(using: .utf8)!)
        copy.data.append("Content-Disposition: form-data; name=\"\(name)\"; filename=\"\(filename)\"\r\n".data(using: .utf8)!)
        copy.data.append("Content-Type: \(mimeType)\r\n\r\n".data(using: .utf8)!)
        copy.data.append(fileData)
        copy.data.append("\r\n".data(using: .utf8)!)
        return copy
    }

    func build() -> Data {
        var copy = data
        copy.append("--\(boundary)--\r\n".data(using: .utf8)!)
        return copy
    }
}

private extension JSONDecoder {
    static var supabase: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}

private extension URL {
    func appending(queryItems: [URLQueryItem]) -> URL {
        guard var components = URLComponents(url: self, resolvingAgainstBaseURL: false) else {
            return self
        }
        var existing = components.queryItems ?? []
        existing.append(contentsOf: queryItems)
        components.queryItems = existing
        return components.url ?? self
    }
}
