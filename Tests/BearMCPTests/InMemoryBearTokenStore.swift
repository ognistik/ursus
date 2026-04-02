import BearCore
import Foundation

final class InMemoryBearTokenStore: @unchecked Sendable, BearTokenStore {
    private let lock = NSLock()
    private var storedToken: String?

    init(token: String? = nil) {
        self.storedToken = token
    }

    func readToken() throws -> String? {
        lock.lock()
        defer { lock.unlock() }
        return storedToken
    }

    func saveToken(_ token: String) throws {
        lock.lock()
        storedToken = token
        lock.unlock()
    }

    func deleteToken() throws {
        lock.lock()
        storedToken = nil
        lock.unlock()
    }
}
