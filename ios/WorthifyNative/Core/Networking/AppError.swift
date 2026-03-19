import Foundation

enum AppError: LocalizedError {
    case notImplemented(String)
    case invalidConfiguration(String)
    case message(String)

    var errorDescription: String? {
        switch self {
        case let .notImplemented(message):
            return "Not implemented: \(message)"
        case let .invalidConfiguration(message):
            return "Invalid configuration: \(message)"
        case let .message(message):
            return message
        }
    }
}
