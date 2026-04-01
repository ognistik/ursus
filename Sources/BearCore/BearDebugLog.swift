import Foundation

public enum BearDebugLog {
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
            try BearManagedLog.rotateForManagedAppendIfNeeded(
                incomingBytes: data.count,
                fileManager: fileManager,
                logURL: logURL,
                logsDirectoryURL: logsDirectoryURL
            )

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
}
