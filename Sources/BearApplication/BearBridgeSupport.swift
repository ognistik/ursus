import BearCore
import Dispatch
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
    public let authMode: BearBridgeAuthMode
    public let auth: BearBridgeAuthStoreSnapshot
    public let endpointURL: String
    public let currentSelectedNoteTokenConfigured: Bool
    public let loadedSelectedNoteTokenConfigured: Bool?
    public let currentRuntimeConfigurationGeneration: Int
    public let loadedRuntimeConfigurationGeneration: Int?
    public let currentRuntimeConfigurationFingerprint: String
    public let loadedRuntimeConfigurationFingerprint: String?
    public let currentBridgeSurfaceMarker: String?
    public let loadedBridgeSurfaceMarker: String?
    public let launcherPath: String
    public let launchAgentLabel: String
    public let plistPath: String
    public let standardOutputLogPath: String
    public let standardErrorLogPath: String
    public let installed: Bool
    public let loaded: Bool
    public let plistMatchesExpected: Bool
    public let endpointTransportReachable: Bool
    public let endpointProtocolCompatible: Bool
    public let endpointProbeDetail: String?
    public let status: BearDoctorCheckStatus
    public let statusTitle: String
    public let statusDetail: String

    public init(
        enabled: Bool,
        host: String,
        port: Int,
        authMode: BearBridgeAuthMode,
        auth: BearBridgeAuthStoreSnapshot,
        endpointURL: String,
        currentSelectedNoteTokenConfigured: Bool,
        loadedSelectedNoteTokenConfigured: Bool?,
        currentRuntimeConfigurationGeneration: Int,
        loadedRuntimeConfigurationGeneration: Int?,
        currentRuntimeConfigurationFingerprint: String,
        loadedRuntimeConfigurationFingerprint: String?,
        currentBridgeSurfaceMarker: String?,
        loadedBridgeSurfaceMarker: String?,
        launcherPath: String,
        launchAgentLabel: String,
        plistPath: String,
        standardOutputLogPath: String,
        standardErrorLogPath: String,
        installed: Bool,
        loaded: Bool,
        plistMatchesExpected: Bool,
        endpointTransportReachable: Bool,
        endpointProtocolCompatible: Bool,
        endpointProbeDetail: String?,
        status: BearDoctorCheckStatus,
        statusTitle: String,
        statusDetail: String
    ) {
        self.enabled = enabled
        self.host = host
        self.port = port
        self.authMode = authMode
        self.auth = auth
        self.endpointURL = endpointURL
        self.currentSelectedNoteTokenConfigured = currentSelectedNoteTokenConfigured
        self.loadedSelectedNoteTokenConfigured = loadedSelectedNoteTokenConfigured
        self.currentRuntimeConfigurationGeneration = currentRuntimeConfigurationGeneration
        self.loadedRuntimeConfigurationGeneration = loadedRuntimeConfigurationGeneration
        self.currentRuntimeConfigurationFingerprint = currentRuntimeConfigurationFingerprint
        self.loadedRuntimeConfigurationFingerprint = loadedRuntimeConfigurationFingerprint
        self.currentBridgeSurfaceMarker = currentBridgeSurfaceMarker
        self.loadedBridgeSurfaceMarker = loadedBridgeSurfaceMarker
        self.launcherPath = launcherPath
        self.launchAgentLabel = launchAgentLabel
        self.plistPath = plistPath
        self.standardOutputLogPath = standardOutputLogPath
        self.standardErrorLogPath = standardErrorLogPath
        self.installed = installed
        self.loaded = loaded
        self.plistMatchesExpected = plistMatchesExpected
        self.endpointTransportReachable = endpointTransportReachable
        self.endpointProtocolCompatible = endpointProtocolCompatible
        self.endpointProbeDetail = endpointProbeDetail
        self.status = status
        self.statusTitle = statusTitle
        self.statusDetail = statusDetail
    }

    public var runtimeConfigurationRestartRequired: Bool {
        guard installed,
              loaded,
              status == .ok || status == .configured,
              let loadedRuntimeConfigurationFingerprint
        else {
            return false
        }

        return loadedRuntimeConfigurationFingerprint != currentRuntimeConfigurationFingerprint
    }

    public var surfaceRestartRequired: Bool {
        guard installed,
              loaded,
              status == .ok || status == .configured,
              let loadedBridgeSurfaceMarker,
              let currentBridgeSurfaceMarker
        else {
            return false
        }

        return loadedBridgeSurfaceMarker != currentBridgeSurfaceMarker
    }

    public var restartRequired: Bool {
        runtimeConfigurationRestartRequired || surfaceRestartRequired || selectedNoteTokenRestartRequired
    }

    public var selectedNoteTokenRestartRequired: Bool {
        guard installed,
              loaded,
              status == .ok || status == .configured,
              let loadedSelectedNoteTokenConfigured
        else {
            return false
        }

        return loadedSelectedNoteTokenConfigured != currentSelectedNoteTokenConfigured
    }

    public var requiresOAuth: Bool {
        authMode.requiresOAuth
    }

    public var authModeSummary: String {
        requiresOAuth ? "OAuth required for all bridge requests" : "Open local bridge"
    }

    public var authStateSummary: String {
        if requiresOAuth {
            if auth.storageReady {
                return "OAuth ready. \(auth.compactSummary)."
            }

            return "OAuth enabled. Auth storage will be prepared when the protected bridge starts."
        }

        if auth.hasStoredAuthState {
            return "Stored auth state is retained for the protected bridge. \(auth.compactSummary)."
        }

        return "Auth storage stays idle until bridge OAuth is enabled."
    }
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

public struct BearBridgeEndpointProbeResult: Hashable, Sendable {
    public let reachable: Bool
    public let transportReachable: Bool
    public let protocolCompatible: Bool
    public let authChallengeSeen: Bool
    public let selectedNoteTokenConfigured: Bool?
    public let detail: String?

    public init(
        reachable: Bool,
        transportReachable: Bool? = nil,
        protocolCompatible: Bool? = nil,
        authChallengeSeen: Bool = false,
        selectedNoteTokenConfigured: Bool? = nil,
        detail: String? = nil
    ) {
        self.reachable = reachable
        self.transportReachable = transportReachable ?? reachable
        self.protocolCompatible = protocolCompatible ?? reachable
        self.authChallengeSeen = authChallengeSeen
        self.selectedNoteTokenConfigured = selectedNoteTokenConfigured
        self.detail = detail
    }
}

public typealias BearBridgeEndpointProbe = @Sendable (_ host: String, _ port: Int) -> BearBridgeEndpointProbeResult

private final class BearBridgeURLSessionProbeBox: @unchecked Sendable {
    var data: Data?
    var response: URLResponse?
    var error: Error?
}

private struct BearBridgeRuntimeState: Codable, Hashable, Sendable {
    let loadedSelectedNoteTokenConfigured: Bool?
    let loadedRuntimeConfigurationGeneration: Int
    let loadedRuntimeConfigurationFingerprint: String
    let loadedBridgeSurfaceMarker: String?
    let recordedAt: Date
}

public extension BearAppSupport {
    static func recordBridgeLoadedRuntimeState(
        selectedNoteTokenConfigured: Bool,
        runtimeConfigurationGeneration: Int,
        runtimeConfigurationFingerprint: String,
        bridgeSurfaceMarker: String? = nil,
        fileManager: FileManager = .default,
        runtimeStateURL: URL = BearPaths.bridgeRuntimeStateURL
    ) throws {
        try fileManager.createDirectory(
            at: runtimeStateURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )

        let state = BearBridgeRuntimeState(
            loadedSelectedNoteTokenConfigured: selectedNoteTokenConfigured,
            loadedRuntimeConfigurationGeneration: runtimeConfigurationGeneration,
            loadedRuntimeConfigurationFingerprint: runtimeConfigurationFingerprint,
            loadedBridgeSurfaceMarker: bridgeSurfaceMarker,
            recordedAt: Date()
        )
        let data = try BearJSON.makeEncoder().encode(state)
        try data.write(to: runtimeStateURL, options: .atomic)
        try? fileManager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: runtimeStateURL.path)
    }

    static func clearBridgeRuntimeState(
        fileManager: FileManager = .default,
        runtimeStateURL: URL = BearPaths.bridgeRuntimeStateURL
    ) throws {
        guard fileManager.fileExists(atPath: runtimeStateURL.path) else {
            return
        }

        try fileManager.removeItem(at: runtimeStateURL)
    }

    static func defaultBridgeEndpointProbe(host: String, port: Int) -> BearBridgeEndpointProbeResult {
        probeBridgeEndpoint(host: host, port: port)
    }

    static func bridgeHealthCheckRequest(url: URL, timeout: TimeInterval) -> URLRequest {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = timeout
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.httpBody = bridgeHealthCheckRequestBody()
        return request
    }

    static func bridgeToolsListProbeRequest(
        url: URL,
        timeout: TimeInterval,
        protocolVersion: String
    ) -> URLRequest {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = timeout
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(protocolVersion, forHTTPHeaderField: "MCP-Protocol-Version")
        request.httpBody = bridgeToolsListProbeRequestBody()
        return request
    }

    static func bridgeResponseRequiresOAuth(_ response: HTTPURLResponse) -> Bool {
        guard let challenge = response.value(forHTTPHeaderField: "WWW-Authenticate") else {
            return false
        }

        return challenge.lowercased().contains("bearer")
    }

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
        endpointProbe: BearBridgeEndpointProbe = defaultBridgeEndpointProbe,
        bundledCLIExecutableURLResolver: (URL, FileManager) throws -> URL = UrsusCLILocator.bundledExecutableURL
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
        try? clearBridgeRuntimeState(fileManager: fileManager)

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
        try assertBridgePortAvailable(host: validatedBridge.host, port: validatedBridge.port)
        try runLaunchctl(
            ["bootstrap", launchdUserDomain(), launchAgentPlistURL.path],
            launchctlRunner: launchctlRunner,
            failureMessage: "Failed to start the Ursus bridge LaunchAgent."
        )
        try waitForBridgeEndpoint(
            host: validatedBridge.host,
            port: validatedBridge.port,
            endpointURL: try validatedBridge.endpointURLString(),
            standardErrorURL: standardErrorURL,
            endpointProbe: endpointProbe
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

        try unloadBridgeLaunchAgentIfPresent(
            launchAgentPlistURL: launchAgentPlistURL,
            launchctlRunner: launchctlRunner
        )

        let hadPlist = fileManager.fileExists(atPath: launchAgentPlistURL.path)
        if hadPlist {
            try fileManager.removeItem(at: launchAgentPlistURL)
        }
        try? clearBridgeRuntimeState(fileManager: fileManager)
        try removeBridgeLogArtifacts(
            fileManager: fileManager,
            standardOutputURL: standardOutputURL,
            standardErrorURL: standardErrorURL
        )

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
            throw BearError.configuration("Install the Ursus bridge before trying to pause it.")
        }

        let loaded = try queryLaunchAgentLoaded(launchctlRunner: launchctlRunner)
        if loaded {
            try unloadBridgeLaunchAgentIfPresent(
                launchAgentPlistURL: launchAgentPlistURL,
                launchctlRunner: launchctlRunner
            )
            try? clearBridgeRuntimeState(fileManager: fileManager)
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
        launchctlRunner: BearLaunchctlCommandRunner = BearLaunchctl.run,
        endpointProbe: BearBridgeEndpointProbe = defaultBridgeEndpointProbe
    ) throws -> BearBridgeLaunchAgentActionReceipt {
        let configuration = try BearRuntimeBootstrap.loadConfiguration(
            fileManager: fileManager,
            configDirectoryURL: configDirectoryURL,
            configFileURL: configFileURL,
            templateURL: templateURL
        )
        let bridge = try configuration.bridge.validated()

        guard bridge.enabled else {
            throw BearError.configuration("Install the Ursus bridge before trying to resume it.")
        }

        guard fileManager.fileExists(atPath: launchAgentPlistURL.path) else {
            throw BearError.configuration("The Ursus bridge LaunchAgent is not installed. Install it again from the app.")
        }

        let expectedPlist = BearBridgeLaunchAgent.expectedPlist(
            launcherURL: launcherURL,
            standardOutputURL: standardOutputURL,
            standardErrorURL: standardErrorURL
        )
        guard try BearBridgeLaunchAgentPlist.load(from: launchAgentPlistURL) == expectedPlist else {
            throw BearError.configuration("The Ursus bridge LaunchAgent needs repair before it can be resumed.")
        }

        let loaded = try queryLaunchAgentLoaded(launchctlRunner: launchctlRunner)
        if !loaded {
            try? clearBridgeRuntimeState(fileManager: fileManager)
            try prepareBridgeArtifacts(
                fileManager: fileManager,
                launchAgentPlistURL: launchAgentPlistURL,
                standardOutputURL: standardOutputURL,
                standardErrorURL: standardErrorURL
            )
            try assertBridgePortAvailable(host: bridge.host, port: bridge.port)
            try runLaunchctl(
                ["bootstrap", launchdUserDomain(), launchAgentPlistURL.path],
                launchctlRunner: launchctlRunner,
                failureMessage: "Failed to resume the Ursus bridge LaunchAgent."
            )
            try waitForBridgeEndpoint(
                host: bridge.host,
                port: bridge.port,
                endpointURL: try bridge.endpointURLString(),
                standardErrorURL: standardErrorURL,
                endpointProbe: endpointProbe
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
        selectedNoteTokenConfigured: Bool = BearSelectedNoteTokenResolver.configured(),
        currentBridgeSurfaceMarker: String? = nil,
        fileManager: FileManager = .default,
        launcherURL: URL = BearBridgeLaunchAgent.launcherURL,
        launchAgentPlistURL: URL = BearBridgeLaunchAgent.plistURL,
        standardOutputURL: URL = BearBridgeLaunchAgent.standardOutputURL,
        standardErrorURL: URL = BearBridgeLaunchAgent.standardErrorURL,
        bridgeRuntimeStateURL: URL = BearPaths.bridgeRuntimeStateURL,
        bridgeAuthDatabaseURL: URL = BearPaths.bridgeAuthDatabaseURL,
        launchctlRunner: BearLaunchctlCommandRunner = BearLaunchctl.run,
        endpointProbe: BearBridgeEndpointProbe = defaultBridgeEndpointProbe
    ) -> BearAppBridgeSnapshot {
        let installed = fileManager.fileExists(atPath: launchAgentPlistURL.path)
        let bridgeRuntimeState = loadBridgeRuntimeState(
            fileManager: fileManager,
            runtimeStateURL: bridgeRuntimeStateURL
        )
        let bridge: BearBridgeConfiguration
        let endpointURL: String
        let authSnapshot = (try? BearBridgeAuthStore.loadSnapshot(
            databaseURL: bridgeAuthDatabaseURL,
            fileManager: fileManager,
            prepareIfMissing: configuration.bridge.enabled && configuration.bridge.authMode.requiresOAuth
        )) ?? .empty(storagePath: bridgeAuthDatabaseURL.path)
        let runtimeStateLoadedSelectedNoteTokenConfigured = bridgeRuntimeState?.loadedSelectedNoteTokenConfigured
        let currentRuntimeConfigurationGeneration = configuration.runtimeConfigurationGeneration
        let currentRuntimeConfigurationFingerprint = configuration.runtimeConfigurationFingerprint

        do {
            bridge = try configuration.bridge.validated()
            endpointURL = try bridge.endpointURLString()
        } catch {
            return BearAppBridgeSnapshot(
                enabled: configuration.bridge.enabled,
                host: configuration.bridge.host,
                port: configuration.bridge.port,
                authMode: configuration.bridge.authMode,
                auth: authSnapshot,
                endpointURL: "invalid bridge URL",
                currentSelectedNoteTokenConfigured: selectedNoteTokenConfigured,
                loadedSelectedNoteTokenConfigured: runtimeStateLoadedSelectedNoteTokenConfigured,
                currentRuntimeConfigurationGeneration: currentRuntimeConfigurationGeneration,
                loadedRuntimeConfigurationGeneration: nil,
                currentRuntimeConfigurationFingerprint: currentRuntimeConfigurationFingerprint,
                loadedRuntimeConfigurationFingerprint: nil,
                currentBridgeSurfaceMarker: currentBridgeSurfaceMarker,
                loadedBridgeSurfaceMarker: bridgeRuntimeState?.loadedBridgeSurfaceMarker,
                launcherPath: launcherURL.path,
                launchAgentLabel: BearBridgeLaunchAgent.label,
                plistPath: launchAgentPlistURL.path,
                standardOutputLogPath: standardOutputURL.path,
                standardErrorLogPath: standardErrorURL.path,
                installed: installed,
                loaded: false,
                plistMatchesExpected: false,
                endpointTransportReachable: false,
                endpointProtocolCompatible: false,
                endpointProbeDetail: nil,
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

        let endpointProbeResult = loaded
            ? endpointProbe(bridge.host, bridge.port)
            : BearBridgeEndpointProbeResult(reachable: false, transportReachable: false, protocolCompatible: false)
        let loadedSelectedNoteTokenConfigured = runtimeStateLoadedSelectedNoteTokenConfigured
            ?? endpointProbeResult.selectedNoteTokenConfigured

        let state = bridgeState(
            configuration: bridge,
            launcherURL: launcherURL,
            launchAgentPlistURL: launchAgentPlistURL,
            launchAgentInstalled: installed,
            plistMatchesExpected: plistMatchesExpected,
            launchAgentLoaded: loaded,
            endpointTransportReachable: endpointProbeResult.transportReachable,
            endpointReachable: endpointProbeResult.reachable,
            endpointProtocolCompatible: endpointProbeResult.protocolCompatible,
            endpointAuthChallengeSeen: endpointProbeResult.authChallengeSeen,
            endpointProbeDetail: endpointProbeResult.detail,
            loadError: loadError,
            endpointURL: endpointURL,
            standardOutputURL: standardOutputURL,
            standardErrorURL: standardErrorURL,
            fileManager: fileManager
        )

        return BearAppBridgeSnapshot(
            enabled: bridge.enabled,
            host: bridge.host,
            port: bridge.port,
            authMode: bridge.authMode,
            auth: authSnapshot,
            endpointURL: endpointURL,
            currentSelectedNoteTokenConfigured: selectedNoteTokenConfigured,
            loadedSelectedNoteTokenConfigured: loadedSelectedNoteTokenConfigured,
            currentRuntimeConfigurationGeneration: currentRuntimeConfigurationGeneration,
            loadedRuntimeConfigurationGeneration: bridgeRuntimeState?.loadedRuntimeConfigurationGeneration,
            currentRuntimeConfigurationFingerprint: currentRuntimeConfigurationFingerprint,
            loadedRuntimeConfigurationFingerprint: bridgeRuntimeState?.loadedRuntimeConfigurationFingerprint,
            currentBridgeSurfaceMarker: currentBridgeSurfaceMarker,
            loadedBridgeSurfaceMarker: bridgeRuntimeState?.loadedBridgeSurfaceMarker,
            launcherPath: launcherURL.path,
            launchAgentLabel: BearBridgeLaunchAgent.label,
            plistPath: launchAgentPlistURL.path,
            standardOutputLogPath: standardOutputURL.path,
            standardErrorLogPath: standardErrorURL.path,
            installed: installed,
            loaded: loaded,
            plistMatchesExpected: plistMatchesExpected,
            endpointTransportReachable: endpointProbeResult.transportReachable,
            endpointProtocolCompatible: endpointProbeResult.protocolCompatible,
            endpointProbeDetail: endpointProbeResult.detail,
            status: state.status,
            statusTitle: state.title,
            statusDetail: state.detail
        )
    }
}

private extension BearAppSupport {
    static func loadBridgeRuntimeState(
        fileManager: FileManager,
        runtimeStateURL: URL
    ) -> BearBridgeRuntimeState? {
        guard fileManager.fileExists(atPath: runtimeStateURL.path),
              let data = try? Data(contentsOf: runtimeStateURL)
        else {
            return nil
        }

        return try? BearJSON.makeDecoder().decode(BearBridgeRuntimeState.self, from: data)
    }

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

        try BearManagedLog.prepareLogFile(
            fileManager: fileManager,
            logURL: standardOutputURL,
            logsDirectoryURL: standardOutputURL.deletingLastPathComponent(),
            writer: .externalProcess
        )
        try BearManagedLog.prepareLogFile(
            fileManager: fileManager,
            logURL: standardErrorURL,
            logsDirectoryURL: standardErrorURL.deletingLastPathComponent(),
            writer: .externalProcess
        )
    }

    static func removeBridgeLogArtifacts(
        fileManager: FileManager,
        standardOutputURL: URL,
        standardErrorURL: URL
    ) throws {
        try BearManagedLog.deleteLogFamily(
            fileManager: fileManager,
            logURL: standardOutputURL,
            logsDirectoryURL: standardOutputURL.deletingLastPathComponent()
        )
        try BearManagedLog.deleteLogFamily(
            fileManager: fileManager,
            logURL: standardErrorURL,
            logsDirectoryURL: standardErrorURL.deletingLastPathComponent()
        )
    }

    static func unloadBridgeLaunchAgentIfPresent(
        launchAgentPlistURL: URL,
        launchctlRunner: BearLaunchctlCommandRunner
    ) throws {
        guard try queryLaunchAgentLoaded(launchctlRunner: launchctlRunner) else {
            return
        }

        let result = try launchctlRunner(["bootout", launchdUserDomain(), launchAgentPlistURL.path])
        if result.exitCode == 0 || launchctlResultLooksMissing(result) {
            return
        }

        if launchctlResultLooksBootoutIOError(result),
           (try? queryLaunchAgentLoaded(launchctlRunner: launchctlRunner)) == false
        {
            return
        }

        throw BearError.configuration(
            "Failed to stop the Ursus bridge LaunchAgent. \(launchctlMessage(from: result))"
        )
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
            "Failed to inspect the Ursus bridge LaunchAgent. \(launchctlMessage(from: result))"
        )
    }

    static func assertBridgePortAvailable(host: String, port: Int) throws {
        guard BearBridgePortAllocator.isPortAvailable(host: host, port: port) else {
            throw BearError.configuration(
                "Bridge port \(port) on \(host) is already in use. Choose another port before installing or resuming the bridge."
            )
        }
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

    static func waitForBridgeEndpoint(
        host: String,
        port: Int,
        endpointURL: String,
        standardErrorURL: URL,
        endpointProbe: BearBridgeEndpointProbe,
        timeout: TimeInterval = 8,
        interval: TimeInterval = 0.1
    ) throws {
        let deadline = Date().addingTimeInterval(timeout)
        var lastProbe = BearBridgeEndpointProbeResult(reachable: false)

        repeat {
            lastProbe = endpointProbe(host, port)
            if lastProbe.reachable {
                return
            }

            if Date() >= deadline {
                break
            }

            Thread.sleep(forTimeInterval: interval)
        } while true

        let detail = lastProbe.detail.map { " \($0)" } ?? ""
        throw BearError.configuration(
            "The Ursus bridge LaunchAgent was started, but \(endpointURL) did not become MCP-ready within \(Int(timeout.rounded())) seconds.\(detail) Check \(standardErrorURL.path) for bridge startup errors."
        )
    }

    static func probeBridgeEndpoint(
        host: String,
        port: Int,
        timeout: TimeInterval = 0.25
    ) -> BearBridgeEndpointProbeResult {
        let socketHandle = socket(AF_INET, SOCK_STREAM, 0)
        guard socketHandle >= 0 else {
            return BearBridgeEndpointProbeResult(
                reachable: false,
                detail: String(cString: strerror(errno))
            )
        }
        defer { close(socketHandle) }

        let currentFlags = fcntl(socketHandle, F_GETFL, 0)
        if currentFlags >= 0 {
            _ = fcntl(socketHandle, F_SETFL, currentFlags | O_NONBLOCK)
        }

        let normalizedHost = host == "localhost" ? BearBridgeConfiguration.defaultHost : host
        var address = sockaddr_in()
        address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        address.sin_family = sa_family_t(AF_INET)
        address.sin_port = in_port_t(UInt16(port).bigEndian)

        let conversionResult = normalizedHost.withCString { hostPointer in
            inet_pton(AF_INET, hostPointer, &address.sin_addr)
        }
        guard conversionResult == 1 else {
            return BearBridgeEndpointProbeResult(
                reachable: false,
                detail: "The configured host `\(host)` is not a valid IPv4 address."
            )
        }

        let connectResult = withUnsafePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockaddrPointer in
                connect(socketHandle, sockaddrPointer, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }

        if connectResult == 0 {
            return probeBridgeProtocol(host: normalizedHost, port: port, timeout: timeout)
        }

        if errno != EINPROGRESS {
            return BearBridgeEndpointProbeResult(
                reachable: false,
                transportReachable: false,
                protocolCompatible: false,
                detail: String(cString: strerror(errno))
            )
        }

        var pollDescriptor = pollfd(
            fd: socketHandle,
            events: Int16(POLLOUT),
            revents: 0
        )
        let pollTimeoutMilliseconds = max(1, Int32((timeout * 1_000).rounded()))
        let pollResult = poll(&pollDescriptor, 1, pollTimeoutMilliseconds)
        guard pollResult > 0 else {
            return BearBridgeEndpointProbeResult(
                reachable: false,
                transportReachable: false,
                protocolCompatible: false,
                detail: pollResult == 0 ? "The connection attempt timed out." : String(cString: strerror(errno))
            )
        }

        var socketError: Int32 = 0
        var socketErrorSize = socklen_t(MemoryLayout<Int32>.size)
        let socketOptionResult = getsockopt(
            socketHandle,
            SOL_SOCKET,
            SO_ERROR,
            &socketError,
            &socketErrorSize
        )
        guard socketOptionResult == 0 else {
            return BearBridgeEndpointProbeResult(
                reachable: false,
                transportReachable: false,
                protocolCompatible: false,
                detail: String(cString: strerror(errno))
            )
        }

        guard socketError == 0 else {
            return BearBridgeEndpointProbeResult(
                reachable: false,
                transportReachable: false,
                protocolCompatible: false,
                detail: String(cString: strerror(socketError))
            )
        }

        return probeBridgeProtocol(host: normalizedHost, port: port, timeout: timeout)
    }

    static func bridgeState(
        configuration: BearBridgeConfiguration,
        launcherURL: URL,
        launchAgentPlistURL: URL,
        launchAgentInstalled: Bool,
        plistMatchesExpected: Bool,
        launchAgentLoaded: Bool,
        endpointTransportReachable: Bool,
        endpointReachable: Bool,
        endpointProtocolCompatible: Bool,
        endpointAuthChallengeSeen: Bool,
        endpointProbeDetail: String?,
        loadError: String?,
        endpointURL: String,
        standardOutputURL: URL,
        standardErrorURL: URL,
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
                "The bridge LaunchAgent plist does not match the expected `ursus bridge serve` command or log paths. Repair it from this app."
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
            if configuration.requiresOAuth && endpointAuthChallengeSeen {
                return (
                    .ok,
                    "Running",
                    "The Ursus bridge LaunchAgent is loaded and requiring OAuth for all requests on \(endpointURL)."
                )
            }

            if !configuration.requiresOAuth && endpointAuthChallengeSeen {
                let logHint = recentBridgeLogHint(
                    fileManager: fileManager,
                    standardOutputURL: standardOutputURL,
                    standardErrorURL: standardErrorURL
                )
                return (
                    .failed,
                    "Unexpected auth challenge",
                    "The Ursus bridge LaunchAgent responded with an OAuth challenge even though bridge auth mode is open.\(logHint) Check \(standardErrorURL.path) and \(standardOutputURL.path) for bridge startup errors."
                )
            }

            guard endpointReachable else {
                let detail = endpointProbeDetail ?? "The endpoint did not complete the MCP health probe."
                let logHint = recentBridgeLogHint(
                    fileManager: fileManager,
                    standardOutputURL: standardOutputURL,
                    standardErrorURL: standardErrorURL
                )
                let failureTitle = endpointTransportReachable
                    ? (endpointProtocolCompatible ? "Not reachable" : "Protocol check failed")
                    : "Not reachable"
                return (
                    .failed,
                    failureTitle,
                    "The Ursus bridge LaunchAgent appears loaded, but \(endpointURL) is not healthy yet. \(detail)\(logHint) Check \(standardErrorURL.path) and \(standardOutputURL.path) for startup errors."
                )
            }

            return (
                .ok,
                "Running",
                "The Ursus bridge LaunchAgent is loaded and passed MCP initialize and tools/list probes at \(endpointURL)."
            )
        }

        return (
            .notConfigured,
            "Paused",
            "The bridge LaunchAgent is installed but currently unloaded. Resume it to serve \(endpointURL) again."
        )
    }

    static func probeBridgeProtocol(
        host: String,
        port: Int,
        timeout: TimeInterval
    ) -> BearBridgeEndpointProbeResult {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = timeout
        configuration.timeoutIntervalForResource = timeout
        configuration.waitsForConnectivity = false

        guard let url = try? BearBridgeConfiguration(
            enabled: true,
            host: host,
            port: port
        ).endpointURL() else {
            return BearBridgeEndpointProbeResult(
                reachable: false,
                transportReachable: true,
                protocolCompatible: false,
                detail: "The configured bridge endpoint URL could not be constructed."
            )
        }

        let session = URLSession(configuration: configuration)
        defer {
            session.finishTasksAndInvalidate()
        }

        let initializeProbeResult = performBridgeProbeRequest(
            bridgeHealthCheckRequest(url: url, timeout: timeout),
            timeout: timeout,
            session: session
        )
        if initializeProbeResult.timedOut {
            return BearBridgeEndpointProbeResult(
                reachable: false,
                transportReachable: true,
                protocolCompatible: false,
                detail: "A TCP connection succeeded, but the MCP initialize probe timed out."
            )
        }

        if let responseError = initializeProbeResult.error {
            return BearBridgeEndpointProbeResult(
                reachable: false,
                transportReachable: true,
                protocolCompatible: false,
                detail: "A TCP connection succeeded, but the MCP initialize probe failed: \(bridgeLocalizedMessage(for: responseError))"
            )
        }

        guard let httpResponse = initializeProbeResult.response else {
            return BearBridgeEndpointProbeResult(
                reachable: false,
                transportReachable: true,
                protocolCompatible: false,
                detail: "A TCP connection succeeded, but the bridge did not return an HTTP response."
            )
        }

        if httpResponse.statusCode == 401,
           bridgeResponseRequiresOAuth(httpResponse)
        {
            return BearBridgeEndpointProbeResult(
                reachable: true,
                transportReachable: true,
                protocolCompatible: true,
                authChallengeSeen: true,
                detail: "The bridge is reachable and challenged the MCP request with OAuth."
            )
        }

        guard httpResponse.statusCode == 200 else {
            return BearBridgeEndpointProbeResult(
                reachable: false,
                transportReachable: true,
                protocolCompatible: false,
                detail: "A TCP connection succeeded, but the MCP initialize probe returned HTTP \(httpResponse.statusCode)."
            )
        }

        guard let responseData = initializeProbeResult.data else {
            return BearBridgeEndpointProbeResult(
                reachable: false,
                transportReachable: true,
                protocolCompatible: false,
                detail: "A TCP connection succeeded, but the bridge returned an empty initialize response."
            )
        }

        guard bridgeInitializeResponseLooksHealthy(responseData) else {
            return BearBridgeEndpointProbeResult(
                reachable: false,
                transportReachable: true,
                protocolCompatible: false,
                detail: "A TCP connection succeeded, but the bridge returned an invalid MCP initialize response."
            )
        }

        guard let protocolVersion = bridgeNegotiatedProtocolVersion(from: responseData) else {
            return BearBridgeEndpointProbeResult(
                reachable: false,
                transportReachable: true,
                protocolCompatible: false,
                detail: "A TCP connection succeeded, but the bridge initialize response did not include a negotiated protocol version."
            )
        }

        let toolsListProbeResult = performBridgeProbeRequest(
            bridgeToolsListProbeRequest(
                url: url,
                timeout: timeout,
                protocolVersion: protocolVersion
            ),
            timeout: timeout,
            session: session
        )
        if toolsListProbeResult.timedOut {
            return BearBridgeEndpointProbeResult(
                reachable: false,
                transportReachable: true,
                protocolCompatible: false,
                detail: "A TCP connection succeeded and MCP initialize succeeded, but the MCP tools/list probe timed out."
            )
        }

        if let responseError = toolsListProbeResult.error {
            return BearBridgeEndpointProbeResult(
                reachable: false,
                transportReachable: true,
                protocolCompatible: false,
                detail: "A TCP connection succeeded and MCP initialize succeeded, but the MCP tools/list probe failed: \(bridgeLocalizedMessage(for: responseError))"
            )
        }

        guard let toolsListHTTPResponse = toolsListProbeResult.response else {
            return BearBridgeEndpointProbeResult(
                reachable: false,
                transportReachable: true,
                protocolCompatible: false,
                detail: "A TCP connection succeeded and MCP initialize succeeded, but the bridge did not return an HTTP response to tools/list."
            )
        }

        guard toolsListHTTPResponse.statusCode == 200 else {
            return BearBridgeEndpointProbeResult(
                reachable: false,
                transportReachable: true,
                protocolCompatible: false,
                detail: "A TCP connection succeeded and MCP initialize succeeded, but the MCP tools/list probe returned HTTP \(toolsListHTTPResponse.statusCode)."
            )
        }

        guard let toolsListData = toolsListProbeResult.data else {
            return BearBridgeEndpointProbeResult(
                reachable: false,
                transportReachable: true,
                protocolCompatible: false,
                detail: "A TCP connection succeeded and MCP initialize succeeded, but the bridge returned an empty tools/list response."
            )
        }

        guard bridgeToolsListResponseLooksHealthy(toolsListData) else {
            return BearBridgeEndpointProbeResult(
                reachable: false,
                transportReachable: true,
                protocolCompatible: false,
                detail: "A TCP connection succeeded and MCP initialize succeeded, but the bridge returned an invalid MCP tools/list response."
            )
        }

        return BearBridgeEndpointProbeResult(
            reachable: true,
            transportReachable: true,
            protocolCompatible: true,
            selectedNoteTokenConfigured: bridgeAdvertisedSelectedNoteSupport(from: toolsListData)
        )
    }

    static func bridgeHealthCheckRequestBody() -> Data {
        Data(
            """
            {"jsonrpc":"2.0","id":"bridge-health-check","method":"initialize","params":{"protocolVersion":"2025-03-26","capabilities":{},"clientInfo":{"name":"ursus-health-check","version":"1.0"}}}
            """.utf8
        )
    }

    static func bridgeToolsListProbeRequestBody() -> Data {
        Data(
            """
            {"jsonrpc":"2.0","id":"bridge-health-check-tools-list","method":"tools/list","params":{}}
            """.utf8
        )
    }

    static func bridgeInitializeResponseLooksHealthy(_ data: Data) -> Bool {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              object["jsonrpc"] as? String == "2.0",
              let result = object["result"] as? [String: Any],
              result["protocolVersion"] as? String != nil,
              result["serverInfo"] as? [String: Any] != nil
        else {
            return false
        }

        return true
    }

    static func bridgeNegotiatedProtocolVersion(from data: Data) -> String? {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let result = object["result"] as? [String: Any],
              let protocolVersion = result["protocolVersion"] as? String,
              !protocolVersion.isEmpty
        else {
            return nil
        }

        return protocolVersion
    }

    static func bridgeToolsListResponseLooksHealthy(_ data: Data) -> Bool {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              object["jsonrpc"] as? String == "2.0",
              let result = object["result"] as? [String: Any],
              result["tools"] as? [Any] != nil
        else {
            return false
        }

        return true
    }

    static func bridgeAdvertisedSelectedNoteSupport(from data: Data) -> Bool? {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let result = object["result"] as? [String: Any],
              let tools = result["tools"] as? [[String: Any]]
        else {
            return nil
        }

        let topLevelToolNames: Set<String> = [
            "bear_get_notes",
            "bear_archive_notes",
        ]
        let operationToolNames: Set<String> = [
            "bear_create_backups",
            "bear_list_backups",
            "bear_compare_backup",
            "bear_delete_backups",
            "bear_add_tags",
            "bear_remove_tags",
            "bear_apply_template",
            "bear_insert_text",
            "bear_replace_content",
            "bear_add_files",
            "bear_open_notes",
            "bear_restore_notes",
        ]

        var inspectedKnownTool = false

        for tool in tools {
            guard let name = tool["name"] as? String,
                  let inputSchema = tool["inputSchema"] as? [String: Any],
                  let properties = inputSchema["properties"] as? [String: Any]
            else {
                continue
            }

            if topLevelToolNames.contains(name) {
                inspectedKnownTool = true
                if properties["selected"] != nil {
                    return true
                }
                continue
            }

            if operationToolNames.contains(name),
               let operations = properties["operations"] as? [String: Any],
               let items = operations["items"] as? [String: Any],
               let operationProperties = items["properties"] as? [String: Any]
            {
                inspectedKnownTool = true
                if operationProperties["selected"] != nil {
                    return true
                }
            }
        }

        return inspectedKnownTool ? false : nil
    }

    static func performBridgeProbeRequest(
        _ request: URLRequest,
        timeout: TimeInterval,
        session: URLSession
    ) -> (data: Data?, response: HTTPURLResponse?, error: Error?, timedOut: Bool) {
        let semaphore = DispatchSemaphore(value: 0)
        let probeBox = BearBridgeURLSessionProbeBox()

        let task = session.dataTask(with: request) { data, urlResponse, error in
            probeBox.data = data
            probeBox.response = urlResponse
            probeBox.error = error
            semaphore.signal()
        }
        task.resume()

        let waitResult = semaphore.wait(timeout: .now() + timeout + 0.1)
        if waitResult == .timedOut {
            task.cancel()
            return (nil, nil, nil, true)
        }

        return (probeBox.data, probeBox.response as? HTTPURLResponse, probeBox.error, false)
    }

    static func recentBridgeLogHint(
        fileManager: FileManager,
        standardOutputURL: URL,
        standardErrorURL: URL
    ) -> String {
        if let stderrLine = lastNonEmptyLine(in: standardErrorURL, fileManager: fileManager) {
            return " Recent stderr: \(stderrLine)"
        }

        if let stdoutLine = lastNonEmptyLine(in: standardOutputURL, fileManager: fileManager) {
            return " Recent stdout: \(stdoutLine)"
        }

        return ""
    }

    static func lastNonEmptyLine(
        in url: URL,
        fileManager: FileManager,
        maxCharacters: Int = 240
    ) -> String? {
        guard fileManager.fileExists(atPath: url.path),
              let contents = try? String(contentsOf: url, encoding: .utf8)
        else {
            return nil
        }

        guard let line = contents
            .split(whereSeparator: { $0.isNewline })
            .map({ String($0).trimmingCharacters(in: .whitespacesAndNewlines) })
            .last(where: { !$0.isEmpty })
        else {
            return nil
        }

        if line.count <= maxCharacters {
            return line
        }

        let endIndex = line.index(line.startIndex, offsetBy: maxCharacters)
        return String(line[..<endIndex]) + "..."
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

    static func launchctlResultLooksBootoutIOError(_ result: BearProcessExecutionResult) -> Bool {
        let output = result.combinedOutput.lowercased()
        return output.contains("boot-out failed")
            && output.contains("input/output error")
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

extension BearAppSupport {
    static func testBridgeAdvertisedSelectedNoteSupport(from data: Data) -> Bool? {
        bridgeAdvertisedSelectedNoteSupport(from: data)
    }
}
