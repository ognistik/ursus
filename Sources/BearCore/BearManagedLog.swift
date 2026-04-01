import Foundation

public enum BearManagedLog {
    public static let maxFileSizeBytes = 1_048_576
    public static let maxArchivedFiles = 1

    public static func rotateForManagedAppendIfNeeded(
        incomingBytes: Int,
        fileManager: FileManager = .default,
        logURL: URL,
        logsDirectoryURL: URL
    ) throws {
        try fileManager.createDirectory(at: logsDirectoryURL, withIntermediateDirectories: true)
        try pruneArchivedLogs(fileManager: fileManager, logURL: logURL, logsDirectoryURL: logsDirectoryURL)

        guard fileManager.fileExists(atPath: logURL.path) else {
            return
        }

        let attributes = try fileManager.attributesOfItem(atPath: logURL.path)
        let currentSize = (attributes[.size] as? NSNumber)?.intValue ?? 0
        guard currentSize + incomingBytes > maxFileSizeBytes else {
            return
        }

        let firstArchiveURL = archivedLogURL(index: 1, logURL: logURL, logsDirectoryURL: logsDirectoryURL)
        if fileManager.fileExists(atPath: firstArchiveURL.path) {
            try fileManager.removeItem(at: firstArchiveURL)
        }

        try fileManager.moveItem(at: logURL, to: firstArchiveURL)
        try pruneArchivedLogs(fileManager: fileManager, logURL: logURL, logsDirectoryURL: logsDirectoryURL)
    }

    public static func snapshotAndTruncateIfNeeded(
        fileManager: FileManager = .default,
        logURL: URL,
        logsDirectoryURL: URL
    ) throws {
        try fileManager.createDirectory(at: logsDirectoryURL, withIntermediateDirectories: true)
        try pruneArchivedLogs(fileManager: fileManager, logURL: logURL, logsDirectoryURL: logsDirectoryURL)

        guard fileManager.fileExists(atPath: logURL.path) else {
            return
        }

        let attributes = try fileManager.attributesOfItem(atPath: logURL.path)
        let currentSize = (attributes[.size] as? NSNumber)?.intValue ?? 0
        guard currentSize > maxFileSizeBytes else {
            return
        }

        let firstArchiveURL = archivedLogURL(index: 1, logURL: logURL, logsDirectoryURL: logsDirectoryURL)
        if fileManager.fileExists(atPath: firstArchiveURL.path) {
            try fileManager.removeItem(at: firstArchiveURL)
        }

        try fileManager.copyItem(at: logURL, to: firstArchiveURL)
        try truncate(logURL: logURL)
        try pruneArchivedLogs(fileManager: fileManager, logURL: logURL, logsDirectoryURL: logsDirectoryURL)
    }

    public static func deleteLogFamily(
        fileManager: FileManager = .default,
        logURL: URL,
        logsDirectoryURL: URL
    ) throws {
        if fileManager.fileExists(atPath: logURL.path) {
            try fileManager.removeItem(at: logURL)
        }

        for archivedLogURL in try archivedLogURLs(fileManager: fileManager, logURL: logURL, logsDirectoryURL: logsDirectoryURL) {
            if fileManager.fileExists(atPath: archivedLogURL.path) {
                try fileManager.removeItem(at: archivedLogURL)
            }
        }
    }

    public static func prepareLogFile(
        fileManager: FileManager = .default,
        logURL: URL,
        logsDirectoryURL: URL,
        writer: LogWriter
    ) throws {
        try fileManager.createDirectory(at: logsDirectoryURL, withIntermediateDirectories: true)
        try pruneArchivedLogs(fileManager: fileManager, logURL: logURL, logsDirectoryURL: logsDirectoryURL)

        if !fileManager.fileExists(atPath: logURL.path) {
            try Data().write(to: logURL, options: .atomic)
            return
        }

        switch writer {
        case .managedAppend:
            break
        case .externalProcess:
            try snapshotAndTruncateIfNeeded(fileManager: fileManager, logURL: logURL, logsDirectoryURL: logsDirectoryURL)
        }
    }

    public enum LogWriter {
        case managedAppend
        case externalProcess
    }

    private static func pruneArchivedLogs(
        fileManager: FileManager,
        logURL: URL,
        logsDirectoryURL: URL
    ) throws {
        let archivedURLs = try archivedLogURLs(fileManager: fileManager, logURL: logURL, logsDirectoryURL: logsDirectoryURL)
        let retainedURLs = archivedURLs.prefix(maxArchivedFiles)
        let retainedPaths = Set(retainedURLs.map(\.path))

        for archivedLogURL in archivedURLs where retainedPaths.contains(archivedLogURL.path) == false {
            if fileManager.fileExists(atPath: archivedLogURL.path) {
                try fileManager.removeItem(at: archivedLogURL)
            }
        }
    }

    private static func archivedLogURLs(
        fileManager: FileManager,
        logURL: URL,
        logsDirectoryURL: URL
    ) throws -> [URL] {
        guard fileManager.fileExists(atPath: logsDirectoryURL.path) else {
            return []
        }

        let baseName = logURL.lastPathComponent
        let directoryContents = try fileManager.contentsOfDirectory(
            at: logsDirectoryURL,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        )

        return directoryContents
            .filter { candidate in
                guard candidate.lastPathComponent.hasPrefix(baseName + ".") else {
                    return false
                }
                let suffix = String(candidate.lastPathComponent.dropFirst(baseName.count + 1))
                return Int(suffix) != nil
            }
            .sorted { lhs, rhs in
                archiveIndex(for: lhs, baseName: baseName) < archiveIndex(for: rhs, baseName: baseName)
            }
    }

    private static func archivedLogURL(index: Int, logURL: URL, logsDirectoryURL: URL) -> URL {
        logsDirectoryURL.appendingPathComponent("\(logURL.lastPathComponent).\(index)", isDirectory: false)
    }

    private static func archiveIndex(for url: URL, baseName: String) -> Int {
        let suffix = String(url.lastPathComponent.dropFirst(baseName.count + 1))
        return Int(suffix) ?? .max
    }

    private static func truncate(logURL: URL) throws {
        let handle = try FileHandle(forWritingTo: logURL)
        defer { try? handle.close() }
        try handle.truncate(atOffset: 0)
    }
}
