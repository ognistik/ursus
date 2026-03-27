import BearCore
import Foundation

enum BearSelectedNoteHelperRunner {
    static func resolveSelectedNoteID(
        helperPath: String,
        bearURL: URL,
        timeout: Duration
    ) async throws -> String {
        let executableURL = try BearSelectedNoteHelperLocator.executableURL(forConfiguredPath: helperPath)
        let result = try await runHelper(
            executableURL: executableURL,
            arguments: [
                "-url", bearURL.absoluteString,
                "-activateApp", "NO",
            ],
            timeout: timeout
        )

        if result.exitCode == 0 {
            let payload = try parseJSONPayload(result.stdoutData)
            if let identifier = payload["identifier"] ?? payload["id"], !identifier.isEmpty {
                return identifier
            }

            throw BearError.xCallback("Selected-note helper completed without returning a note identifier.")
        }

        let payload = try? parseJSONPayload(result.stderrData)
        let message = payload?["errorMessage"]
            ?? payload?["error"]
            ?? payload?["internal_error"]
            ?? "Selected-note helper failed with exit code \(result.exitCode)."
        throw BearError.xCallback(message)
    }

    private static func runHelper(
        executableURL: URL,
        arguments: [String],
        timeout: Duration
    ) async throws -> HelperInvocationResult {
        let process = Process()
        process.executableURL = executableURL
        process.arguments = arguments

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        let completion = HelperProcessCompletion(process: process)

        return try await withCheckedThrowingContinuation { continuation in
            process.terminationHandler = { process in
                let stdoutData = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
                let stderrData = stderrPipe.fileHandleForReading.readDataToEndOfFile()
                completion.finish(
                    continuation: continuation,
                    result: .success(
                        HelperInvocationResult(
                            exitCode: process.terminationStatus,
                            stdoutData: stdoutData,
                            stderrData: stderrData
                        )
                    )
                )
            }

            do {
                try process.run()
            } catch {
                completion.finish(
                    continuation: continuation,
                    result: .failure(
                        BearError.configuration(
                            "Failed to launch selected-note helper at `\(executableURL.path)`. \(error.localizedDescription)"
                        )
                    )
                )
                return
            }

            Task {
                try await Task.sleep(for: timeout)
                completion.finish(
                    continuation: continuation,
                    result: .failure(BearError.xCallback("Timed out while waiting for the selected-note helper to return a result."))
                )
            }
        }
    }

    private static func parseJSONPayload(_ data: Data) throws -> [String: String] {
        guard !data.isEmpty else {
            return [:]
        }

        let object = try JSONSerialization.jsonObject(with: data)
        guard let dictionary = object as? [String: Any] else {
            throw BearError.xCallback("Selected-note helper returned an unexpected payload.")
        }

        var parsed: [String: String] = [:]
        for (key, value) in dictionary {
            switch value {
            case let string as String:
                parsed[key] = string
            case is NSNull:
                parsed[key] = ""
            default:
                parsed[key] = String(describing: value)
            }
        }
        return parsed
    }
}

private struct HelperInvocationResult: Sendable {
    let exitCode: Int32
    let stdoutData: Data
    let stderrData: Data
}

private final class HelperProcessCompletion: @unchecked Sendable {
    private let process: Process
    private let lock = NSLock()
    private var completed = false

    init(process: Process) {
        self.process = process
    }

    func finish(
        continuation: CheckedContinuation<HelperInvocationResult, Error>,
        result: Result<HelperInvocationResult, Error>
    ) {
        lock.lock()
        guard !completed else {
            lock.unlock()
            return
        }
        completed = true
        lock.unlock()

        if process.isRunning {
            process.terminate()
        }

        continuation.resume(with: result)
    }
}
