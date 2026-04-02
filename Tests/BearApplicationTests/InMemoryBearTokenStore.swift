import BearCore
import Foundation

final class InMemoryBearTokenStore: @unchecked Sendable, BearTokenStore {
    private let lock = NSLock()
    private var storedToken: String?
    private let error: Error?

    init(token: String? = nil, error: Error? = nil) {
        self.storedToken = token
        self.error = error
    }

    func readToken() throws -> String? {
        if let error {
            throw error
        }

        lock.lock()
        defer { lock.unlock() }
        return storedToken
    }

    func saveToken(_ token: String) throws {
        if let error {
            throw error
        }

        lock.lock()
        storedToken = token
        lock.unlock()
    }

    func deleteToken() throws {
        if let error {
            throw error
        }

        lock.lock()
        storedToken = nil
        lock.unlock()
    }
}
