import Darwin
import Foundation

public enum BearParentProcessMonitor {
    public static func waitForParentExit(
        originalParentPID: Int32,
        pollInterval: Duration = .seconds(2),
        currentParentPID: @escaping @Sendable () -> Int32 = { getppid() },
        isProcessAlive: @escaping @Sendable (Int32) -> Bool = { pid in
            processExists(pid: pid)
        },
        sleep: @escaping @Sendable (Duration) async -> Void = { duration in
            try? await Task.sleep(for: duration)
        }
    ) async {
        guard originalParentPID > 0 else { return }

        while !Task.isCancelled {
            if currentParentPID() != originalParentPID || !isProcessAlive(originalParentPID) {
                return
            }

            await sleep(pollInterval)
        }
    }

    public static func processExists(pid: Int32) -> Bool {
        guard pid > 0 else { return false }
        if kill(pid, 0) == 0 {
            return true
        }

        return errno == EPERM
    }
}
