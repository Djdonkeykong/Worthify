import Combine
import Foundation

@MainActor
final class AppEnvironment: ObservableObject {
    let config: AppConfig
    let authService: AuthServicing
    let uploadService: ImageUploadServicing
    let detectionService: DetectionServicing
    let collectionService: CollectionServicing
    let favoritesService: FavoritesServicing
    let subscriptionService: SubscriptionServicing
    let notificationService: NotificationServicing
    let shareBridge: ShareBridgeServicing

    @Published var sessionStore: SessionStore
    @Published var router: AppRouter
    private var cancellables = Set<AnyCancellable>()

    init(
        config: AppConfig,
        authService: AuthServicing,
        uploadService: ImageUploadServicing,
        detectionService: DetectionServicing,
        collectionService: CollectionServicing,
        favoritesService: FavoritesServicing,
        subscriptionService: SubscriptionServicing,
        notificationService: NotificationServicing,
        shareBridge: ShareBridgeServicing,
        sessionStore: SessionStore,
        router: AppRouter
    ) {
        self.config = config
        self.authService = authService
        self.uploadService = uploadService
        self.detectionService = detectionService
        self.collectionService = collectionService
        self.favoritesService = favoritesService
        self.subscriptionService = subscriptionService
        self.notificationService = notificationService
        self.shareBridge = shareBridge
        self.sessionStore = sessionStore
        self.router = router

        // Forward nested observable changes so views reading
        // environment.router/environment.sessionStore actually update.
        sessionStore.objectWillChange
            .sink { [weak self] _ in
                self?.objectWillChange.send()
            }
            .store(in: &cancellables)

        router.objectWillChange
            .sink { [weak self] _ in
                self?.objectWillChange.send()
            }
            .store(in: &cancellables)
    }

    static func bootstrap() -> AppEnvironment {
        let config = AppConfig.load()
        let authService = SupabaseAuthService(config: config)
        let uploadService = CloudinaryImageUploadService(config: config)
        let detectionService = ArtworkDetectionService(config: config)
        let collectionService: CollectionServicing
        let favoritesService: FavoritesServicing
        if config.bypassAuth {
            let localCollectionService = LocalCollectionService()
            collectionService = localCollectionService
            favoritesService = LocalFavoritesService(collectionService: localCollectionService)
        } else {
            let supabaseCollectionService = SupabaseCollectionService(config: config, authService: authService)
            collectionService = supabaseCollectionService
            favoritesService = SupabaseFavoritesService(config: config, authService: authService)
        }
        let subscriptionService = SupabaseSubscriptionService(config: config, authService: authService)
        let notificationService = NativeNotificationService()
        let shareBridge = AppGroupShareBridge(config: config)
        let sessionStore = SessionStore(authService: authService)
        let router = AppRouter()

        return AppEnvironment(
            config: config,
            authService: authService,
            uploadService: uploadService,
            detectionService: detectionService,
            collectionService: collectionService,
            favoritesService: favoritesService,
            subscriptionService: subscriptionService,
            notificationService: notificationService,
            shareBridge: shareBridge,
            sessionStore: sessionStore,
            router: router
        )
    }
}
