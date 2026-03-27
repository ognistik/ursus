import BearCore
import Foundation

private let sharedTemplateFileLock = AsyncLock()

func withTemporaryNoteTemplate<T: Sendable>(_ template: String?, operation: @Sendable () async throws -> T) async throws -> T {
    try await sharedTemplateFileLock.withLock {
        let templateURL = BearPaths.noteTemplateURL
        let fileManager = FileManager.default
        let originalTemplate = fileManager.fileExists(atPath: templateURL.path) ? try String(contentsOf: templateURL) : nil

        try fileManager.createDirectory(at: BearPaths.configDirectoryURL, withIntermediateDirectories: true)
        if let template {
            try template.write(to: templateURL, atomically: true, encoding: .utf8)
        } else if fileManager.fileExists(atPath: templateURL.path) {
            try fileManager.removeItem(at: templateURL)
        }
        defer {
            if let originalTemplate {
                try? originalTemplate.write(to: templateURL, atomically: true, encoding: .utf8)
            } else {
                try? fileManager.removeItem(at: templateURL)
            }
        }

        return try await operation()
    }
}

private actor AsyncLock {
    private var locked = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func withLock<T: Sendable>(_ operation: @Sendable () async throws -> T) async rethrows -> T {
        await acquire()
        defer { release() }
        return try await operation()
    }

    private func acquire() async {
        guard locked else {
            locked = true
            return
        }

        await withCheckedContinuation { continuation in
            waiters.append(continuation)
        }
    }

    private func release() {
        guard !waiters.isEmpty else {
            locked = false
            return
        }

        let continuation = waiters.removeFirst()
        continuation.resume()
    }
}
