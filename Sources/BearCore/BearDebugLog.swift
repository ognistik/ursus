import Foundation

public enum BearDebugLog {
    public static func append(_ message: String, fileManager: FileManager = .default) {
        do {
            try fileManager.createDirectory(at: BearPaths.configDirectoryURL, withIntermediateDirectories: true)
            let timestamp = ISO8601DateFormatter().string(from: Date())
            let line = "[\(timestamp)] \(message)\n"
            let data = Data(line.utf8)

            if fileManager.fileExists(atPath: BearPaths.debugLogURL.path) {
                let handle = try FileHandle(forWritingTo: BearPaths.debugLogURL)
                defer { try? handle.close() }
                try handle.seekToEnd()
                try handle.write(contentsOf: data)
            } else {
                try data.write(to: BearPaths.debugLogURL, options: .atomic)
            }
        } catch {
            // Best-effort debug logging only.
        }
    }
}
