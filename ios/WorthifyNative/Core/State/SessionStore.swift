import Foundation

@MainActor
final class SessionStore: ObservableObject {
    private static let restoreTimeoutNanoseconds: UInt64 = 3_000_000_000

    private enum RestoreResult {
        case session(AppSession?)
        case timedOut
    }

    enum State: Equatable {
        case restoring
        case signedOut
        case signedIn(AppSession)
    }

    @Published private(set) var state: State = .restoring
    @Published var startupAlertMessage: String?

    private let authService: AuthServicing

    init(authService: AuthServicing) {
        self.authService = authService
    }

    func restore() async {
        state = .restoring
        startupAlertMessage = nil
        let authService = self.authService
        let result = await withTaskGroup(of: RestoreResult.self) { group in
            group.addTask {
                .session(await authService.restoreSession())
            }
            group.addTask {
                try? await Task.sleep(nanoseconds: Self.restoreTimeoutNanoseconds)
                return .timedOut
            }

            let result = await group.next() ?? nil
            group.cancelAll()
            return result
        }

        switch result {
        case let .session(session):
            if let session {
                state = .signedIn(session)
            } else {
                state = .signedOut
            }
        case .timedOut:
            startupAlertMessage = "Session restore timed out. Continuing to the sign-in screen."
            state = .signedOut
        case nil:
            state = .signedOut
        }
    }

    func clearStartupAlert() {
        startupAlertMessage = nil
    }

    func setStartupAlert(_ message: String) {
        startupAlertMessage = message
    }

    func setSignedIn(_ session: AppSession) {
        startupAlertMessage = nil
        state = .signedIn(session)
    }

    func signOut() async {
        await authService.signOut()
        state = .signedOut
    }
}
