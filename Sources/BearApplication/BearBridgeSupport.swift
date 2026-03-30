import BearCore
import Darwin
import Foundation

public struct BearProcessExecutionResult: Hashable, Sendable {
    public let exitCode: Int32
    public let stdout: String
    public let stderr: String

    public init(exitCode: Int32, stdout: String, stderr: String) {
        self.exitCode = exitCode
        self.stdout = stdout
        self.stderr = stderr
    }

    public var combinedOutput: String {
        [stdout, stderr]
            .filter { !$0.isEmpty }
            .joined(separator: "\n")
    }
}

public typealias BearLaunchctlCommandRunner = @Sendable (_ arguments: [String]) throws -> BearProcessExecutionResult

public enum BearLaunchctl {
    public static func run(arguments: [String]) throws -> BearProcessExecutionResult {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/launchctl", isDirectory: false)
        process.arguments = arguments

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        try process.run()
        process.waitUntilExit()

        let stdoutData = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
        let stderrData = stderrPipe.fileHandleForReading.readDataToEndOfFile()

        return BearProcessExecutionResult(
            exitCode: process.terminationStatus,
            stdout: String(decoding: stdoutData, as: UTF8.self),
            stderr: String(decoding: stderrData, as: UTF8.self)
        )
    }
}

public struct BearAppBridgeSnapshot: Codable, Hashable, Sendable {
    public let enabled: Bool
    public let host: String
    public let port: Int
    public let endpointURL: String
    public let launcherPath: String
    public let launchAgentLabel: String
    public let plistPath: String
    public let standardOutputLogPath: String
    public let standardErrorLogPath: String
    public let installed: Bool
    public let loaded: Bool
    public let plistMatchesExpected: Bool
    public let status: BearDoctorCheckStatus
    public let statusTitle: String
    public let statusDetail: String
}

public enum BearBridgeLaunchAgentInstallStatus: String, Codable, Hashable, Sendable {
    case installed
    case refreshed
}

public struct BearBridgeLaunchAgentInstallReceipt: Codable, Hashable, Sendable {
    public let status: BearBridgeLaunchAgentInstallStatus
    public let plistPath: String
    public let endpointURL: String
    public let launcherPath: String
    public let standardOutputLogPath: String
    public let standardErrorLogPath: String
}

public enum BearBridgeLaunchAgentActionStatus: String, Codable, Hashable, Sendable {
    case removed
    case paused
    case resumed
    case unchanged
}

public struct BearBridgeLaunchAgentActionReceipt: Codable, Hashable, Sendable {
    public let status: BearBridgeLaunchAgentActionStatus
    public let plistPath: String
    public let endpointURL: String?
}

public extension BearAppSupport {
    static func installBridgeLaunchAgent(
        fromAppBundleURL appBundleURL: URL,
        fileManager: FileManager = .default,
        configDirectoryURL: URL = BearPaths.configDirectoryURL,
        configFileURL: URL = BearPaths.configFileURL,
        templateURL: URL = BearPaths.noteTemplateURL,
        launcherURL: URL = BearBridgeLaunchAgent.launcherURL,
        launchAgentPlistURL: URL = BearBridgeLaunchAgent.plistURL,
        standardOutputURL: URL = BearBridgeLaunchAgent.standardOutputURL,
        standardErrorURL: URL = BearBridgeLaunchAgent.standardErrorURL,
        launchctlRunner: BearLaunchctlCommandRunner = BearLaunchctl.run,
        bundledCLIExecutableURLResolver: (URL, FileManager) throws -> URL = BearMCPCLILocator.bundledExecutableURL
    ) throws -> BearBridgeLaunchAgentInstallReceipt {
        _ = try reconcilePublicLauncherIfNeeded(
            fromAppBundleURL: appBundleURL,
            fileManager: fileManager,
            destinationURL: launcherURL,
            bundledCLIExecutableURLResolver: bundledCLIExecutableURLResolver
        )

        let configuration = try BearRuntimeBootstrap.loadConfiguration(
            fileManager: fileManager,
            configDirectoryURL: configDirectoryURL,
            configFileURL: configFileURL,
            templateURL: templateURL
        )

        let selectedPort = try selectedBridgePort(
            forInstallFrom: configuration.bridge,
            fileManager: fileManager,
            launchAgentPlistURL: launchAgentPlistURL
        )
        let validatedBridge = try BearBridgeConfiguration(
            enabled: true,
            host: configuration.bridge.host,
            port: selectedPort
        ).validated()
        let updatedConfiguration = configuration.updatingBridge(validatedBridge)

        try BearRuntimeBootstrap.saveConfiguration(
            updatedConfiguration,
            fileManager: fileManager,
            configDirectoryURL: configDirectoryURL,
            configFileURL: configFileURL,
            templateURL: templateURL
        )

        let existedBeforeInstall = fileManager.fileExists(atPath: launchAgentPlistURL.path)
        try prepareBridgeArtifacts(
            fileManager: fileManager,
            launchAgentPlistURL: launchAgentPlistURL,
            standardOutputURL: standardOutputURL,
            standardErrorURL: standardErrorURL
        )

        let expectedPlist = BearBridgeLaunchAgent.expectedPlist(
            launcherURL: launcherURL,
            standardOutputURL: standardOutputURL,
            standardErrorURL: standardErrorURL
        )
        try expectedPlist.xmlData().write(to: launchAgentPlistURL, options: .atomic)
        try? fileManager.setAttributes([.posixPermissions: 0o644], ofItemAtPath: launchAgentPlistURL.path)

        try unloadBridgeLaunchAgentIfPresent(
            launchAgentPlistURL: launchAgentPlistURL,
            launchctlRunner: launchctlRunner
        )
        try runLaunchctl(
            ["bootstrap", launchdUserDomain(), launchAgentPlistURL.path],
            launchctlRunner: launchctlRunner,
            failureMessage: "Failed to start the Bear MCP bridge LaunchAgent."
        )

        return BearBridgeLaunchAgentInstallReceipt(
            status: existedBeforeInstall ? .refreshed : .installed,
            plistPath: launchAgentPlistURL.path,
            endpointURL: try validatedBridge.endpointURLString(),
            launcherPath: launcherURL.path,
            standardOutputLogPath: standardOutputURL.path,
            standardErrorLogPath: standardErrorURL.path
        )
    }

    static func removeBridgeLaunchAgent(
        fileManager: FileManager = .default,
        configDirectoryURL: URL = BearPaths.configDirectoryURL,
        configFileURL: URL = BearPaths.configFileURL,
        templateURL: URL = BearPaths.noteTemplateURL,
        launchAgentPlistURL: URL = BearBridgeLaunchAgent.plistURL,
        launchctlRunner: BearLaunchctlCommandRunner = BearLaunchctl.run
    ) throws -> BearBridgeLaunchAgentActionReceipt {
        let configuration = try BearRuntimeBootstrap.loadConfiguration(
            fileManager: fileManager,
            configDirectoryURL: configDirectoryURL,
            configFileURL: configFileURL,
            templateURL: templateURL
        )

        try unloadBridgeLaunchAgentIfPresent(
            launchAgentPlistURL: launchAgentPlistURL,
            launchctlRunner: launchctlRunner
        )

        let hadPlist = fileManager.fileExists(atPath: launchAgentPlistURL.path)
        if hadPlist {
            try fileManager.removeItem(at: launchAgentPlistURL)
        }

        if configuration.bridge.enabled {
            let disabledBridge = try BearBridgeConfiguration(
                enabled: false,
                host: configuration.bridge.host,
                port: configuration.bridge.port
            ).validated()
            try BearRuntimeBootstrap.saveConfiguration(
                configuration.updatingBridge(disabledBridge),
                fileManager: fileManager,
                configDirectoryURL: configDirectoryURL,
                configFileURL: configFileURL,
                templateURL: templateURL
            )
        }

        return BearBridgeLaunchAgentActionReceipt(
            status: hadPlist || configuration.bridge.enabled ? .removed : .unchanged,
            plistPath: launchAgentPlistURL.path,
            endpointURL: nil
        )
    }

    static func pauseBridgeLaunchAgent(
        fileManager: FileManager = .default,
        configDirectoryURL: URL = BearPaths.configDirectoryURL,
        configFileURL: URL = BearPaths.configFileURL,
        templateURL: URL = BearPaths.noteTemplateURL,
        launchAgentPlistURL: URL = BearBridgeLaunchAgent.plistURL,
        launchctlRunner: BearLaunchctlCommandRunner = BearLaunchctl.run
    ) throws -> BearBridgeLaunchAgentActionReceipt {
        let configuration = try BearRuntimeBootstrap.loadConfiguration(
            fileManager: fileManager,
            configDirectoryURL: configDirectoryURL,
            configFileURL: configFileURL,
            templateURL: templateURL
        )
        let bridge = try configuration.bridge.validated()

        guard fileManager.fileExists(atPath: launchAgentPlistURL.path) else {
            throw BearError.configuration("Install the Bear MCP bridge before trying to pause it.")
        }

        let loaded = try queryLaunchAgentLoaded(launchctlRunner: launchctlRunner)
        if loaded {
            try unloadBridgeLaunchAgentIfPresent(
                launchAgentPlistURL: launchAgentPlistURL,
                launchctlRunner: launchctlRunner
            )
        }

        return BearBridgeLaunchAgentActionReceipt(
            status: loaded ? .paused : .unchanged,
            plistPath: launchAgentPlistURL.path,
            endpointURL: try bridge.endpointURLString()
        )
    }

    static func resumeBridgeLaunchAgent(
        fileManager: FileManager = .default,
        configDirectoryURL: URL = BearPaths.configDirectoryURL,
        configFileURL: URL = BearPaths.configFileURL,
        templateURL: URL = BearPaths.noteTemplateURL,
        launcherURL: URL = BearBridgeLaunchAgent.launcherURL,
        launchAgentPlistURL: URL = BearBridgeLaunchAgent.plistURL,
        standardOutputURL: URL = BearBridgeLaunchAgent.standardOutputURL,
        standardErrorURL: URL = BearBridgeLaunchAgent.standardErrorURL,
        launchctlRunner: BearLaunchctlCommandRunner = BearLaunchctl.run
    ) throws -> BearBridgeLaunchAgentActionReceipt {
        let configuration = try BearRuntimeBootstrap.loadConfiguration(
            fileManager: fileManager,
            configDirectoryURL: configDirectoryURL,
            configFileURL: configFileURL,
            templateURL: templateURL
        )
        let bridge = try configuration.bridge.validated()

        guard bridge.enabled else {
            throw BearError.configuration("Install the Bear MCP bridge before trying to resume it.")
        }

        guard fileManager.fileExists(atPath: launchAgentPlistURL.path) else {
            throw BearError.configuration("The Bear MCP bridge LaunchAgent is not installed. Install it again from the app.")
        }

        let expectedPlist = BearBridgeLaunchAgent.expectedPlist(
            launcherURL: launcherURL,
            standardOutputURL: standardOutputURL,
            standardErrorURL: standardErrorURL
        )
        guard try BearBridgeLaunchAgentPlist.load(from: launchAgentPlistURL) == expectedPlist else {
            throw BearError.configuration("The Bear MCP bridge LaunchAgent needs repair before it can be resumed.")
        }

        let loaded = try queryLaunchAgentLoaded(launchctlRunner: launchctlRunner)
        if !loaded {
            try runLaunchctl(
                ["bootstrap", launchdUserDomain(), launchAgentPlistURL.path],
                launchctlRunner: launchctlRunner,
                failureMessage: "Failed to resume the Bear MCP bridge LaunchAgent."
            )
        }

        return BearBridgeLaunchAgentActionReceipt(
            status: loaded ? .unchanged : .resumed,
            plistPath: launchAgentPlistURL.path,
            endpointURL: try bridge.endpointURLString()
        )
    }

    static func bridgeSnapshot(
        configuration: BearConfiguration,
        fileManager: FileManager = .default,
        launcherURL: URL = BearBridgeLaunchAgent.launcherURL,
        launchAgentPlistURL: URL = BearBridgeLaunchAgent.plistURL,
        standardOutputURL: URL = BearBridgeLaunchAgent.standardOutputURL,
        standardErrorURL: URL = BearBridgeLaunchAgent.standardErrorURL,
        launchctlRunner: BearLaunchctlCommandRunner = BearLaunchctl.run
    ) -> BearAppBridgeSnapshot {
        let installed = fileManager.fileExists(atPath: launchAgentPlistURL.path)
        let bridge: BearBridgeConfiguration
        let endpointURL: String

        do {
            bridge = try configuration.bridge.validated()
            endpointURL = try bridge.endpointURLString()
        } catch {
            return BearAppBridgeSnapshot(
                enabled: configuration.bridge.enabled,
                host: configuration.bridge.host,
                port: configuration.bridge.port,
                endpointURL: "invalid bridge URL",
                launcherPath: launcherURL.path,
                launchAgentLabel: BearBridgeLaunchAgent.label,
                plistPath: launchAgentPlistURL.path,
                standardOutputLogPath: standardOutputURL.path,
                standardErrorLogPath: standardErrorURL.path,
                installed: installed,
                loaded: false,
                plistMatchesExpected: false,
                status: .invalid,
                statusTitle: "Invalid configuration",
                statusDetail: bridgeLocalizedMessage(for: error)
            )
        }

        let expectedPlist = BearBridgeLaunchAgent.expectedPlist(
            launcherURL: launcherURL,
            standardOutputURL: standardOutputURL,
            standardErrorURL: standardErrorURL
        )
        let plistMatchesExpected = installed && ((try? BearBridgeLaunchAgentPlist.load(from: launchAgentPlistURL)) == expectedPlist)

        let loaded: Bool
        let loadError: String?
        do {
            loaded = installed && plistMatchesExpected
                ? (try queryLaunchAgentLoaded(launchctlRunner: launchctlRunner))
                : false
            loadError = nil
        } catch {
            loaded = false
            loadError = bridgeLocalizedMessage(for: error)
        }

        let state = bridgeState(
            configuration: bridge,
            launcherURL: launcherURL,
            launchAgentPlistURL: launchAgentPlistURL,
            launchAgentInstalled: installed,
            plistMatchesExpected: plistMatchesExpected,
            launchAgentLoaded: loaded,
            loadError: loadError,
            endpointURL: endpointURL,
            fileManager: fileManager
        )

        return BearAppBridgeSnapshot(
            enabled: bridge.enabled,
            host: bridge.host,
            port: bridge.port,
            endpointURL: endpointURL,
            launcherPath: launcherURL.path,
            launchAgentLabel: BearBridgeLaunchAgent.label,
            plistPath: launchAgentPlistURL.path,
            standardOutputLogPath: standardOutputURL.path,
            standardErrorLogPath: standardErrorURL.path,
            installed: installed,
            loaded: loaded,
            plistMatchesExpected: plistMatchesExpected,
            status: state.status,
            statusTitle: state.title,
            statusDetail: state.detail
        )
    }
}

private extension BearAppSupport {
    static func selectedBridgePort(
        forInstallFrom bridge: BearBridgeConfiguration,
        fileManager: FileManager,
        launchAgentPlistURL: URL
    ) throws -> Int {
        let shouldReuseSavedPort = bridge.enabled
            || bridge.port != BearBridgeConfiguration.preferredPort
            || fileManager.fileExists(atPath: launchAgentPlistURL.path)

        return try BearBridgePortAllocator.selectPort(
            configuredPort: shouldReuseSavedPort ? bridge.port : nil,
            host: bridge.host
        )
    }

    static func prepareBridgeArtifacts(
        fileManager: FileManager,
        launchAgentPlistURL: URL,
        standardOutputURL: URL,
        standardErrorURL: URL
    ) throws {
        try fileManager.createDirectory(
            at: launchAgentPlistURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try fileManager.createDirectory(
            at: standardOutputURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )

        if !fileManager.fileExists(atPath: standardOutputURL.path) {
            try Data().write(to: standardOutputURL, options: .atomic)
        }
        if !fileManager.fileExists(atPath: standardErrorURL.path) {
            try Data().write(to: standardErrorURL, options: .atomic)
        }
    }

    static func unloadBridgeLaunchAgentIfPresent(
        launchAgentPlistURL: URL,
        launchctlRunner: BearLaunchctlCommandRunner
    ) throws {
        let result = try launchctlRunner(["bootout", launchdUserDomain(), launchAgentPlistURL.path])
        guard result.exitCode == 0 || launchctlResultLooksMissing(result) else {
            throw BearError.configuration(
                "Failed to stop the Bear MCP bridge LaunchAgent. \(launchctlMessage(from: result))"
            )
        }
    }

    static func queryLaunchAgentLoaded(
        launchctlRunner: BearLaunchctlCommandRunner
    ) throws -> Bool {
        let result = try launchctlRunner(["print", BearBridgeLaunchAgent.serviceTarget()])
        if result.exitCode == 0 {
            return true
        }
        if launchctlResultLooksMissing(result) {
            return false
        }

        throw BearError.configuration(
            "Failed to inspect the Bear MCP bridge LaunchAgent. \(launchctlMessage(from: result))"
        )
    }

    static func runLaunchctl(
        _ arguments: [String],
        launchctlRunner: BearLaunchctlCommandRunner,
        failureMessage: String
    ) throws {
        let result = try launchctlRunner(arguments)
        guard result.exitCode == 0 else {
            throw BearError.configuration("\(failureMessage) \(launchctlMessage(from: result))")
        }
    }

    static func bridgeState(
        configuration: BearBridgeConfiguration,
        launcherURL: URL,
        launchAgentPlistURL: URL,
        launchAgentInstalled: Bool,
        plistMatchesExpected: Bool,
        launchAgentLoaded: Bool,
        loadError: String?,
        endpointURL: String,
        fileManager: FileManager
    ) -> (status: BearDoctorCheckStatus, title: String, detail: String) {
        if !configuration.enabled && !launchAgentInstalled {
            return (
                .missing,
                "Not installed",
                "Install the optional Remote MCP Bridge when you need a localhost HTTP MCP URL for apps that cannot launch local stdio MCP servers."
            )
        }

        if !configuration.enabled && launchAgentInstalled {
            return (
                .invalid,
                "Needs cleanup",
                "The bridge is disabled in config, but a LaunchAgent still exists at \(launchAgentPlistURL.path). Remove it or reinstall it from this app."
            )
        }

        guard fileManager.isExecutableFile(atPath: launcherURL.path) else {
            return (
                .invalid,
                "Launcher unavailable",
                "The bridge depends on the stable launcher at \(launcherURL.path). Repair that launcher first, then reinstall the bridge."
            )
        }

        guard launchAgentInstalled else {
            return (
                .missing,
                "Missing LaunchAgent",
                "The bridge is enabled in config, but its LaunchAgent plist is missing. Install or repair it from this app."
            )
        }

        guard plistMatchesExpected else {
            return (
                .invalid,
                "Needs repair",
                "The bridge LaunchAgent plist does not match the expected `bear-mcp bridge serve` command or log paths. Repair it from this app."
            )
        }

        if let loadError {
            return (
                .failed,
                "Status unavailable",
                loadError
            )
        }

        if launchAgentLoaded {
            return (
                .ok,
                "Running",
                "The Bear MCP bridge LaunchAgent is loaded and should be serving \(endpointURL)."
            )
        }

        return (
            .notConfigured,
            "Paused",
            "The bridge LaunchAgent is installed but currently unloaded. Resume it to serve \(endpointURL) again."
        )
    }

    static func launchdUserDomain() -> String {
        "gui/\(getuid())"
    }

    static func launchctlResultLooksMissing(_ result: BearProcessExecutionResult) -> Bool {
        let output = result.combinedOutput.lowercased()
        return output.contains("could not find service")
            || output.contains("service not found")
            || output.contains("no such process")
            || output.contains("not loaded")
            || output.contains("could not find specified service")
    }

    static func launchctlMessage(from result: BearProcessExecutionResult) -> String {
        let trimmed = result.combinedOutput.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            return "launchctl exited with status \(result.exitCode)."
        }

        return trimmed
    }

    static func bridgeLocalizedMessage(for error: Error) -> String {
        (error as? LocalizedError)?.errorDescription ?? String(describing: error)
    }
}
