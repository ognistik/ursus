import BearCore
import Foundation

func withTemporaryNoteTemplate<T: Sendable>(_ template: String?, operation: @Sendable () async throws -> T) async throws -> T {
    try await withSharedTemplateFileLock {
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

private func withSharedTemplateFileLock<T: Sendable>(_ operation: @Sendable () async throws -> T) async throws -> T {
    let fileManager = FileManager.default
    let lockURL = fileManager.temporaryDirectory.appendingPathComponent("ursus-tests-template.lock", isDirectory: true)

    while true {
        do {
            try fileManager.createDirectory(at: lockURL, withIntermediateDirectories: false)
            break
        } catch let error as CocoaError where error.code == .fileWriteFileExists {
            try await Task.sleep(for: .milliseconds(10))
        }
    }

    defer { try? fileManager.removeItem(at: lockURL) }
    return try await operation()
}
