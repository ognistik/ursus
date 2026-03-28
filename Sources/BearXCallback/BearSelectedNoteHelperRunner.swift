import AppKit
import BearCore
import Foundation

enum BearSelectedNoteHelperRunner {
    static func resolveSelectedNoteID(
        bearURL: URL,
        timeout: Duration
    ) async throws -> String {
        if let appBundleURL = BearMCPAppLocator.installedAppBundleURL() {
            if await isApplicationRunning(appBundleURL: appBundleURL) {
                BearDebugLog.append(
                    "xcallback.resolve-selected-note host=app reason=preferred-app-running reuseExistingInstance=true appPath=\(appBundleURL.path)"
                )
                return try await resolveSelectedNoteIDInRunningApp(
                    appBundleURL: appBundleURL,
                    bearURL: bearURL,
                    timeout: timeout
                )
            }

            BearDebugLog.append(
                "xcallback.resolve-selected-note host=app appPath=\(appBundleURL.path)"
            )
            return try await resolveSelectedNoteID(
                appBundleURL: appBundleURL,
                appName: BearMCPAppLocator.appName,
                bearURL: bearURL,
                timeout: timeout,
                terminateRunningInstancesBeforeLaunch: false
            )
        }

        if let helperBundleURL = BearSelectedNoteHelperLocator.installedAppBundleURL() {
            BearDebugLog.append(
                "xcallback.resolve-selected-note host=helper reason=preferred-app-missing helperPath=\(helperBundleURL.path)"
            )
            return try await resolveSelectedNoteID(
                appBundleURL: helperBundleURL,
                appName: BearSelectedNoteHelperLocator.appName,
                bearURL: bearURL,
                timeout: timeout,
                terminateRunningInstancesBeforeLaunch: true
            )
        }

        throw BearError.configuration(
            "Selected-note targeting requires `\(BearMCPAppLocator.appName)` to be installed in `/Applications` or `~/Applications`. During Phase 3 verification, `\(BearSelectedNoteHelperLocator.appName)` can still be installed there as a legacy fallback."
        )
    }

    static func resolveSelectedNoteID(
        appBundleURL: URL,
        appName: String = BearMCPAppLocator.appName,
        bearURL: URL,
        timeout: Duration,
        terminateRunningInstancesBeforeLaunch: Bool = false
    ) async throws -> String {
        let responseFileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: false)
            .appendingPathExtension("json")
        defer {
            try? FileManager.default.removeItem(at: responseFileURL)
        }

        try await runOpenCommand(
            appBundleURL: appBundleURL,
            appName: appName,
            bearURL: bearURL,
            responseFileURL: responseFileURL,
            terminateRunningInstancesBeforeLaunch: terminateRunningInstancesBeforeLaunch
        )

        let result = try await waitForResponseFile(responseFileURL, timeout: timeout)
        let payload = try parseJSONPayload(result)

        if let identifier = payload["identifier"] ?? payload["id"], !identifier.isEmpty {
            return identifier
        }

        let message = payload["errorMessage"]
            ?? payload["error"]
            ?? payload["internal_error"]
            ?? "Selected-note callback host failed without returning a note identifier."
        throw BearError.xCallback(message)
    }

    static func resolveSelectedNoteID(
        executableURL: URL,
        bearURL: URL,
        timeout: Duration
    ) async throws -> String {
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

    private static func runOpenCommand(
        appBundleURL: URL,
        appName: String,
        bearURL: URL,
        responseFileURL: URL,
        terminateRunningInstancesBeforeLaunch: Bool
    ) async throws {
        if terminateRunningInstancesBeforeLaunch {
            await MainActor.run {
                terminateRunningInstances(appBundleURL: appBundleURL)
            }
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/open", isDirectory: false)
        process.arguments = [
            "-a", appBundleURL.path,
            "--args",
            "-url", bearURL.absoluteString,
            "-activateApp", "NO",
            "-responseFile", responseFileURL.path,
        ]

        try await withCheckedThrowingContinuation { continuation in
            let completion = ProcessLaunchCompletion()
            process.terminationHandler = { process in
                if process.terminationStatus == 0 {
                    completion.finish(continuation: continuation, result: .success(()))
                } else {
                    completion.finish(
                        continuation: continuation,
                        result: .failure(
                            BearError.configuration(
                                "Failed to launch `\(appName)` through Launch Services."
                            )
                        )
                    )
                }
            }

            do {
                try process.run()
            } catch {
                completion.finish(
                    continuation: continuation,
                    result: .failure(
                        BearError.configuration(
                            "Failed to launch `\(appName)`. \(error.localizedDescription)"
                        )
                    )
                )
            }
        }
    }

    private static func resolveSelectedNoteIDInRunningApp(
        appBundleURL: URL,
        bearURL: URL,
        timeout: Duration
    ) async throws -> String {
        let responseFileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: false)
            .appendingPathExtension("json")
        defer {
            try? FileManager.default.removeItem(at: responseFileURL)
        }

        let appRequest = BearSelectedNoteAppRequest(
            requestURL: bearURL,
            activateApp: false,
            responseFileURL: responseFileURL
        )

        try await runRunningAppOpenCommand(
            appBundleURL: appBundleURL,
            appRequest: appRequest
        )

        let result = try await waitForResponseFile(responseFileURL, timeout: timeout)
        let payload = try parseJSONPayload(result)

        if let identifier = payload["identifier"] ?? payload["id"], !identifier.isEmpty {
            return identifier
        }

        let message = payload["errorMessage"]
            ?? payload["error"]
            ?? payload["internal_error"]
            ?? "Selected-note callback host failed without returning a note identifier."
        throw BearError.xCallback(message)
    }

    private static func runRunningAppOpenCommand(
        appBundleURL: URL,
        appRequest: BearSelectedNoteAppRequest
    ) async throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/open", isDirectory: false)
        process.arguments = [
            "-g",
            "-a", appBundleURL.path,
            appRequest.url.absoluteString,
        ]

        try await withCheckedThrowingContinuation { continuation in
            let completion = ProcessLaunchCompletion()
            process.terminationHandler = { process in
                if process.terminationStatus == 0 {
                    completion.finish(continuation: continuation, result: .success(()))
                } else {
                    completion.finish(
                        continuation: continuation,
                        result: .failure(
                            BearError.configuration(
                                "Failed to send the selected-note callback request to the running `\(BearMCPAppLocator.appName)` instance."
                            )
                        )
                    )
                }
            }

            do {
                try process.run()
            } catch {
                completion.finish(
                    continuation: continuation,
                    result: .failure(
                        BearError.configuration(
                            "Failed to contact the running `\(BearMCPAppLocator.appName)` instance. \(error.localizedDescription)"
                        )
                    )
                )
            }
        }
    }

    @MainActor
    private static func isApplicationRunning(appBundleURL: URL) -> Bool {
        guard let bundle = Bundle(url: appBundleURL),
              let bundleIdentifier = bundle.bundleIdentifier
        else {
            return false
        }

        return !NSRunningApplication.runningApplications(withBundleIdentifier: bundleIdentifier).isEmpty
    }

    @MainActor
    private static func terminateRunningInstances(appBundleURL: URL) {
        guard let bundle = Bundle(url: appBundleURL),
              let bundleIdentifier = bundle.bundleIdentifier
        else {
            return
        }

        let runningApps = NSRunningApplication.runningApplications(withBundleIdentifier: bundleIdentifier)
        guard !runningApps.isEmpty else {
            return
        }

        for app in runningApps {
            if !app.terminate() {
                app.forceTerminate()
            }
        }
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

    private static func waitForResponseFile(
        _ responseFileURL: URL,
        timeout: Duration
    ) async throws -> Data {
        let clock = ContinuousClock()
        let deadline = clock.now + timeout

        while clock.now < deadline {
            if let data = try? Data(contentsOf: responseFileURL), !data.isEmpty {
                return data
            }

            try await Task.sleep(for: .milliseconds(100))
        }

        throw BearError.xCallback("Timed out while waiting for the selected-note callback host to return a result.")
    }

    private static func parseJSONPayload(_ data: Data) throws -> [String: String] {
        guard !data.isEmpty else {
            return [:]
        }

        let object = try JSONSerialization.jsonObject(with: data)
        guard let dictionary = object as? [String: Any] else {
            throw BearError.xCallback("Selected-note callback host returned an unexpected payload.")
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

private final class ProcessLaunchCompletion: @unchecked Sendable {
    private let lock = NSLock()
    private var completed = false

    func finish(
        continuation: CheckedContinuation<Void, Error>,
        result: Result<Void, Error>
    ) {
        lock.lock()
        guard !completed else {
            lock.unlock()
            return
        }
        completed = true
        lock.unlock()

        continuation.resume(with: result)
    }
}
