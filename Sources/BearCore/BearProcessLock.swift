import Darwin
import Foundation

public final class BearProcessLock: @unchecked Sendable {
    private let fileDescriptor: Int32
    public let lockURL: URL

    private init(fileDescriptor: Int32, lockURL: URL) {
        self.fileDescriptor = fileDescriptor
        self.lockURL = lockURL
    }

    deinit {
        flock(fileDescriptor, LOCK_UN)
        close(fileDescriptor)
    }

    public static func acquire() throws -> BearProcessLock {
        var unusableMessages: [String] = []

        for lockURL in BearPaths.processLockCandidateURLs {
            do {
                return try acquire(at: lockURL)
            } catch let error as LockAcquisitionError {
                switch error {
                case .alreadyRunning:
                    continue
                case .unusable(let message):
                    unusableMessages.append(message)
                }
            } catch {
                unusableMessages.append(error.localizedDescription)
            }
        }

        let processSpecificLockURL = BearPaths.processSpecificFallbackLockURL(processID: getpid())
        do {
            return try acquire(at: processSpecificLockURL)
        } catch let error as LockAcquisitionError {
            switch error {
            case .alreadyRunning:
                unusableMessages.append(
                    "Could not acquire process-specific lock at \(processSpecificLockURL.path) because it is already in use."
                )
            case .unusable(let message):
                unusableMessages.append(message)
            }
        } catch {
            unusableMessages.append(error.localizedDescription)
        }

        let reason = unusableMessages.joined(separator: " ")
        throw BearError.configuration("Unable to acquire Bear MCP process lock. \(reason)")
    }

    private static func acquire(at lockURL: URL) throws -> BearProcessLock {
        let fileManager = FileManager.default
        let lockDirectoryURL = lockURL.deletingLastPathComponent()

        do {
            try fileManager.createDirectory(at: lockDirectoryURL, withIntermediateDirectories: true)
        } catch {
            throw LockAcquisitionError.unusable(
                "Could not create lock directory at \(lockDirectoryURL.path): \(error.localizedDescription)."
            )
        }

        let path = lockURL.path
        let fileDescriptor = open(path, O_CREAT | O_RDWR, S_IRUSR | S_IWUSR)
        guard fileDescriptor >= 0 else {
            throw LockAcquisitionError.unusable("Could not open lock file at \(path): \(posixErrorDescription()).")
        }

        guard flock(fileDescriptor, LOCK_EX | LOCK_NB) == 0 else {
            let errorCode = errno
            close(fileDescriptor)

            if errorCode == EWOULDBLOCK || errorCode == EAGAIN {
                throw LockAcquisitionError.alreadyRunning
            }

            throw LockAcquisitionError.unusable("Could not lock \(path): \(String(cString: strerror(errorCode))).")
        }

        let pidString = "\(getpid())\n"
        ftruncate(fileDescriptor, 0)
        _ = pidString.withCString { pointer in
            write(fileDescriptor, pointer, strlen(pointer))
        }

        return BearProcessLock(fileDescriptor: fileDescriptor, lockURL: lockURL)
    }

    private static func posixErrorDescription() -> String {
        String(cString: strerror(errno))
    }

    private enum LockAcquisitionError: Error {
        case alreadyRunning
        case unusable(String)
    }
}
