import Foundation

public enum BearDebugLog {
    private static let maxFileSizeBytes = 1_048_576
    private static let maxArchivedFiles = 3

    public static func append(
        _ message: String,
        fileManager: FileManager = .default,
        logURL: URL = BearPaths.debugLogURL,
        logsDirectoryURL: URL = BearPaths.logsDirectoryURL
    ) {
        do {
            try fileManager.createDirectory(at: logsDirectoryURL, withIntermediateDirectories: true)
            let timestamp = ISO8601DateFormatter().string(from: Date())
            let line = "[\(timestamp)] \(message)\n"
            let data = Data(line.utf8)
            try rotateIfNeeded(for: data.count, fileManager: fileManager, logURL: logURL, logsDirectoryURL: logsDirectoryURL)

            if fileManager.fileExists(atPath: logURL.path) {
                let handle = try FileHandle(forWritingTo: logURL)
                defer { try? handle.close() }
                try handle.seekToEnd()
                try handle.write(contentsOf: data)
            } else {
                try data.write(to: logURL, options: .atomic)
            }
        } catch {
            // Best-effort debug logging only.
        }
    }

    private static func rotateIfNeeded(
        for incomingBytes: Int,
        fileManager: FileManager,
        logURL: URL,
        logsDirectoryURL: URL
    ) throws {
        guard fileManager.fileExists(atPath: logURL.path) else {
            return
        }

        let attributes = try fileManager.attributesOfItem(atPath: logURL.path)
        let currentSize = (attributes[.size] as? NSNumber)?.intValue ?? 0
        guard currentSize + incomingBytes > maxFileSizeBytes else {
            return
        }

        let oldestArchiveURL = archivedLogURL(index: maxArchivedFiles, logsDirectoryURL: logsDirectoryURL)
        if fileManager.fileExists(atPath: oldestArchiveURL.path) {
            try fileManager.removeItem(at: oldestArchiveURL)
        }

        if maxArchivedFiles > 1 {
            for index in stride(from: maxArchivedFiles - 1, through: 1, by: -1) {
                let sourceURL = archivedLogURL(index: index, logsDirectoryURL: logsDirectoryURL)
                let destinationURL = archivedLogURL(index: index + 1, logsDirectoryURL: logsDirectoryURL)
                if fileManager.fileExists(atPath: sourceURL.path) {
                    if fileManager.fileExists(atPath: destinationURL.path) {
                        try fileManager.removeItem(at: destinationURL)
                    }
                    try fileManager.moveItem(at: sourceURL, to: destinationURL)
                }
            }
        }

        let firstArchiveURL = archivedLogURL(index: 1, logsDirectoryURL: logsDirectoryURL)
        if fileManager.fileExists(atPath: firstArchiveURL.path) {
            try fileManager.removeItem(at: firstArchiveURL)
        }
        try fileManager.moveItem(at: logURL, to: firstArchiveURL)
    }

    private static func archivedLogURL(index: Int, logsDirectoryURL: URL) -> URL {
        logsDirectoryURL.appendingPathComponent("debug.log.\(index)", isDirectory: false)
    }
}
