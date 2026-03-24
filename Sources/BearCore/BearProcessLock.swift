import Darwin
import Foundation

public final class BearProcessLock: @unchecked Sendable {
    private let fileDescriptor: Int32

    private init(fileDescriptor: Int32) {
        self.fileDescriptor = fileDescriptor
    }

    deinit {
        flock(fileDescriptor, LOCK_UN)
        close(fileDescriptor)
    }

    public static func acquire() throws -> BearProcessLock {
        try FileManager.default.createDirectory(at: BearPaths.configDirectoryURL, withIntermediateDirectories: true)

        let path = BearPaths.processLockURL.path
        let fileDescriptor = open(path, O_CREAT | O_RDWR, S_IRUSR | S_IWUSR)
        guard fileDescriptor >= 0 else {
            throw BearError.configuration("Unable to open Bear MCP process lock at \(path).")
        }

        guard flock(fileDescriptor, LOCK_EX | LOCK_NB) == 0 else {
            close(fileDescriptor)
            throw BearError.configuration("bear-mcp is already running. Stop the existing MCP server before starting another instance.")
        }

        let pidString = "\(getpid())\n"
        ftruncate(fileDescriptor, 0)
        _ = pidString.withCString { pointer in
            write(fileDescriptor, pointer, strlen(pointer))
        }

        return BearProcessLock(fileDescriptor: fileDescriptor)
    }
}
