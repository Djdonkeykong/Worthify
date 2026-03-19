import Foundation

@MainActor
final class SessionStore: ObservableObject {
    enum State: Equatable {
        case restoring
        case signedOut
        case signedIn(AppSession)
    }

    @Published private(set) var state: State = .restoring

    private let authService: AuthServicing

    init(authService: AuthServicing) {
        self.authService = authService
    }

    func restore() async {
        state = .restoring
        if let session = await authService.restoreSession() {
            state = .signedIn(session)
        } else {
            state = .signedOut
        }
    }

    func setSignedIn(_ session: AppSession) {
        state = .signedIn(session)
    }

    func signOut() async {
        await authService.signOut()
        state = .signedOut
    }
}
