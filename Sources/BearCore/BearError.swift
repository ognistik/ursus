import Foundation

public enum BearError: LocalizedError {
    case configuration(String)
    case database(String)
    case invalidInput(String)
    case notFound(String)
    case ambiguous(String)
    case mutationConflict(String)
    case xCallback(String)
    case unsupported(String)

    public var errorDescription: String? {
        switch self {
        case let .configuration(message),
            let .database(message),
            let .invalidInput(message),
            let .notFound(message),
            let .ambiguous(message),
            let .mutationConflict(message),
            let .xCallback(message),
            let .unsupported(message):
            return message
        }
    }
}
