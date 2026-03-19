import Foundation

@MainActor
final class SessionStore: ObservableObject {
    private static let restoreTimeoutNanoseconds: UInt64 = 3_000_000_000

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
        let authService = self.authService
        let session = await withTaskGroup(of: AppSession?.self) { group in
            group.addTask {
                await authService.restoreSession()
            }
            group.addTask {
                try? await Task.sleep(nanoseconds: Self.restoreTimeoutNanoseconds)
                return nil
            }

            let result = await group.next() ?? nil
            group.cancelAll()
            return result
        }

        if let session {
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
