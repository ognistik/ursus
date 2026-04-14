import BearApplication
import BearCore
import BearDB
import BearMCP
import BearXCallback
import Darwin
import Foundation
import Logging
import MCP

public enum UrsusCLIRuntime {
    public static let embeddedInvocationFlag = "--ursus-cli"

    public static func bridgeSurfaceMarker(
        configuration: BearConfiguration,
        selectedNoteTokenConfigured: Bool
    ) -> String {
        UrsusMCPServer.bridgeSurfaceMarker(
            configuration: configuration,
            selectedNoteTokenConfigured: selectedNoteTokenConfigured
        )
    }

    public static func cliArgumentsForEmbeddedApp(from processArguments: [String]) -> [String]? {
        guard processArguments.dropFirst().first == embeddedInvocationFlag else {
            return nil
        }

        return Array(processArguments.dropFirst(2))
    }

    public static func run(
        arguments: [String],
        updateChecker: (any UrsusUpdateChecking)? = nil
    ) async -> Int32 {
        LoggingSystem.bootstrap(StreamLogHandler.standardError)
        let logger = Logger(label: "ursus")

        do {
            let command = try BearCLICommand.parse(arguments: arguments)
            switch command {
            case .mcp:
                await updateChecker?.startScheduledUpdateChecks(context: "stdio MCP")
            case .bridge(.serve):
                await updateChecker?.startScheduledUpdateChecks(context: "HTTP bridge")
            default:
                break
            }

            switch command {
            case .help:
                print(BearCLICommand.usageText)
            case .bridge(.help):
                print(BearCLICommand.bridgeUsageText)
            case .note(.help):
                print(BearCLICommand.noteUsageText)
            case .update(.help):
                print(BearCLICommand.updateUsageText)
            case .doctor:
                print(
                    BearRuntimeBootstrap.doctorReport(
                        logger: logger,
                        bridgeSurfaceMarkerProvider: bridgeSurfaceMarker
                    )
                )
            case .paths:
                print(
                    [
                        BearPaths.configFileURL.path,
                        BearPaths.noteTemplateURL.path,
                        BearPaths.publicCLIExecutableURL.path,
                        BearPaths.backupsMetadataURL.path,
                        BearPaths.bridgeAuthDatabaseURL.path,
                        BearPaths.runtimeStateDatabaseURL.path,
                        BearPaths.processLockURL.path,
                        BearPaths.debugLogURL.path,
                        BearPaths.defaultBearDatabaseURL.path,
                    ].joined(separator: "\n")
                )
            case .bridge(.status):
                let configuration = try BearRuntimeBootstrap.loadConfiguration()
                let selectedNoteTokenConfigured = BearSelectedNoteTokenResolver.configured()
                let snapshot = BearAppSupport.bridgeSnapshot(
                    configuration: configuration,
                    selectedNoteTokenConfigured: selectedNoteTokenConfigured,
                    currentBridgeSurfaceMarker: bridgeSurfaceMarker(
                        configuration: configuration,
                        selectedNoteTokenConfigured: selectedNoteTokenConfigured
                    )
                )
                print(renderBridgeStatus(snapshot))
            case .bridge(.printURL):
                let configuration = try BearRuntimeBootstrap.loadConfiguration()
                print(try configuration.bridge.endpointURLString())
            case .bridge(.pause):
                let receipt = try BearAppSupport.pauseBridgeLaunchAgent()
                print(renderBridgeActionReceipt(receipt, action: "pause"))
            case .bridge(.resume):
                let receipt = try BearAppSupport.resumeBridgeLaunchAgent()
                print(renderBridgeActionReceipt(receipt, action: "resume"))
            case .bridge(.remove):
                let receipt = try BearAppSupport.removeBridgeLaunchAgent()
                print(renderBridgeActionReceipt(receipt, action: "remove"))
            case .bridge(.serve):
                try await runBridge(logger: logger)
            case .note(.new(let options)):
                let runtime = try makeRuntimeServices(logger: logger)
                let receipt: MutationReceipt
                if let options {
                    receipt = try await runtime.service.createCLINewNote(
                        title: options.title,
                        content: options.content,
                        tags: options.tags,
                        tagMergeMode: options.replaceTags ? .replace : .append,
                        openNote: options.openNote,
                        newWindow: options.newWindow
                    )
                } else {
                    receipt = try await runtime.service.createInteractiveNote()
                }
                print(renderNewNoteReceipt(receipt))
            case .note(.backup(let selectors)):
                let runtime = try makeRuntimeServices(logger: logger)
                let summaries = try await runtime.service.backupNoteTargets(
                    selectors.isEmpty ? [.selected] : selectors.map(NoteTarget.selector)
                )
                print(renderBackupSummaries(summaries))
            case .note(.restoreLatest(let selectors)):
                let runtime = try makeRuntimeServices(logger: logger)
                let receipts = try await runtime.service.restoreLatestBackupsForTargets(
                    selectors.isEmpty ? [.selected] : selectors.map(NoteTarget.selector)
                )
                print(renderRestoreBackupReceipts(receipts))
            case .note(.restoreSnapshot(let requests)):
                let runtime = try makeRuntimeServices(logger: logger)
                let receipts = try await runtime.service.restoreCLIBackups(
                    requests.map {
                        RestoreBackupRequest(
                            noteID: $0.noteID,
                            snapshotID: $0.snapshotID,
                            presentation: BearPresentationOptions()
                        )
                    }
                )
                print(renderRestoreBackupReceipts(receipts))
            case .note(.applyTemplate(let selectors)):
                let runtime = try makeRuntimeServices(logger: logger)
                let receipts = try await runtime.service.applyTemplateToTargets(
                    selectors.isEmpty ? [.selected] : selectors.map(NoteTarget.selector)
                )
                print(renderApplyTemplateReceipts(receipts))
            case .update(.check):
                guard let updateChecker else {
                    print("Sparkle update checks are available from the bundled Ursus.app launcher. Run `~/.local/bin/ursus update check` after opening Ursus.app once to install or repair the launcher.")
                    return 1
                }

                let result = await updateChecker.checkForUpdatesFromCLI()
                print(result.message)
                return result.exitCode
            case .update(.automaticInstall(let option)):
                guard let updateChecker else {
                    print("Sparkle automatic install settings are available from the bundled Ursus.app launcher. Run `~/.local/bin/ursus update auto-install \(option.enabled ? "on" : "off")` after opening Ursus.app once to install or repair the launcher.")
                    return 1
                }

                let result = await updateChecker.setAutomaticallyDownloadsUpdatesFromCLI(option.enabled)
                print(result.message)
                return result.exitCode
#if DEBUG
            case .debugDonation(let subcommand):
                let store = BearRuntimeStateStore()
                let snapshot: BearDonationPromptSnapshot

                switch subcommand {
                case .trigger:
                    snapshot = try await store.debugMarkDonationPromptEligible()
                case .reset:
                    snapshot = try await store.debugResetDonationPromptState()
                case .status:
                    snapshot = try await store.loadDonationPromptSnapshot()
                }

                print(renderDonationPromptSnapshot(snapshot))
#endif
            case .mcp:
                let processLock = try BearProcessLock.acquire()
                try await runMCP(logger: logger, processLock: processLock)
            }

            return 0
        } catch {
            let message = (error as? LocalizedError)?.errorDescription ?? String(describing: error)
            fputs("ursus failed: \(message)\n", stderr)
            return 1
        }
    }

    private static func runMCP(logger: Logger, processLock: BearProcessLock) async throws {
        logger.info("ursus acquired process lock at \(processLock.lockURL.path)")
        let runtime = try makeRuntimeServices(logger: logger)
        let configuration = runtime.configuration
        let service = runtime.service

        let server = await UrsusMCPServer(
            service: service,
            configuration: configuration,
            selectedNoteTokenConfigured: BearSelectedNoteTokenResolver.configured(tokenStore: runtime.tokenStore)
        ).makeServer()
        try await server.start(transport: StdioTransport())
        let originalParentPID = getppid()
        let shutdownReason = await waitForShutdownTrigger(server: server, originalParentPID: originalParentPID)

        switch shutdownReason {
        case .serverCompleted:
            logger.info("ursus stdio transport closed; shutting down server.")
        case .parentExited:
            logger.info("ursus parent process exited; shutting down orphaned stdio server.")
        }

        await server.stop()
    }

    private static func runBridge(logger: Logger) async throws {
        let runtime = try makeRuntimeServices(logger: logger)
        let bridge = try runtime.configuration.bridge.validated()
        let selectedNoteTokenConfigured = BearSelectedNoteTokenResolver.configured(tokenStore: runtime.tokenStore)
        let currentBridgeSurfaceMarker = bridgeSurfaceMarker(
            configuration: runtime.configuration,
            selectedNoteTokenConfigured: selectedNoteTokenConfigured
        )
        defer {
            try? BearAppSupport.clearBridgeRuntimeState()
        }

        if !bridge.enabled {
            logger.info("ursus bridge serve is starting while bridge.enabled=false; direct CLI bridge runs are still allowed.")
        }

        if bridge.authMode.requiresOAuth {
            _ = try BearBridgeAuthStore.prepareStorage()
        }

        try maintainBridgeLogs()

        let application = BearBridgeHTTPApplication(
            configuration: .init(
                host: bridge.host,
                port: bridge.port,
                endpoint: bridge.endpointPath,
                authMode: bridge.authMode
            ),
            serverFactory: {
                await UrsusMCPServer(
                    service: runtime.service,
                    configuration: runtime.configuration,
                    selectedNoteTokenConfigured: selectedNoteTokenConfigured
                ).makeServer()
            },
            readyHandler: {
                try BearAppSupport.recordBridgeLoadedRuntimeState(
                    selectedNoteTokenConfigured: selectedNoteTokenConfigured,
                    runtimeConfigurationGeneration: runtime.configuration.runtimeConfigurationGeneration,
                    runtimeConfigurationFingerprint: runtime.configuration.runtimeConfigurationFingerprint,
                    bridgeSurfaceMarker: currentBridgeSurfaceMarker
                )
            },
            logger: logger
        )
        let logMaintenanceTask = Task {
            await maintainBridgeLogsUntilCancelled(logger: logger)
        }
        defer {
            logMaintenanceTask.cancel()
        }

        try await withThrowingTaskGroup(of: BridgeShutdownReason.self) { group in
            group.addTask {
                try await application.start()
                return .serverCompleted
            }

            group.addTask {
                let signal = await BearTerminationSignalMonitor.waitForTerminationSignal()
                return .signal(signal)
            }

            let firstReason = try await group.next() ?? .serverCompleted

            switch firstReason {
            case .serverCompleted:
                logger.info("ursus bridge server stopped.")
            case .signal(let signal):
                logger.info("ursus bridge received signal \(signal); shutting down.")
                await application.stop()
                _ = try await group.next()
            }

            group.cancelAll()
        }
    }

    private static func makeRuntimeServices(logger: Logger) throws -> RuntimeServices {
        let configuration = try BearRuntimeBootstrap.loadConfiguration()
        let tokenStore = BearKeychainTokenStore.selectedNoteDefault
        let databaseReader = try BearDatabaseReader(
            databaseURL: BearPaths.defaultBearDatabaseURL
        )
        let writeTransport = BearXCallbackTransport(readStore: databaseReader)
        let backupStore = BearBackupFileStore(retentionDays: configuration.backupRetentionDays)
        let backupAvailabilityReader = BearBackupAvailabilityReader(retentionDays: configuration.backupRetentionDays)
        let backupPresenceLookup: (@Sendable ([String]) throws -> Set<String>)? = configuration.isToolEnabled(.listBackups) && backupAvailabilityReader.isEnabled
            ? { @Sendable noteIDs in
                try backupAvailabilityReader.noteIDsWithBackups(noteIDs)
            }
            : nil
        let service = BearService(
            configuration: configuration,
            tokenStore: tokenStore,
            readStore: databaseReader,
            writeTransport: writeTransport,
            backupStore: backupStore,
            backupPresenceLookup: backupPresenceLookup,
            logger: logger
        )

        return RuntimeServices(
            configuration: configuration,
            tokenStore: tokenStore,
            service: service
        )
    }

    private static func waitForShutdownTrigger(server: Server, originalParentPID: Int32) async -> ShutdownReason {
        await withTaskGroup(of: ShutdownReason.self, returning: ShutdownReason.self) { group in
            group.addTask {
                await server.waitUntilCompleted()
                return .serverCompleted
            }

            group.addTask {
                await BearParentProcessMonitor.waitForParentExit(originalParentPID: originalParentPID)
                return .parentExited
            }

            let reason = await group.next() ?? .serverCompleted
            group.cancelAll()
            return reason
        }
    }

    private enum ShutdownReason {
        case serverCompleted
        case parentExited
    }

    private enum BridgeShutdownReason {
        case serverCompleted
        case signal(Int32)
    }

    private static func maintainBridgeLogs(fileManager: FileManager = .default) throws {
        try BearManagedLog.prepareLogFile(
            fileManager: fileManager,
            logURL: BearBridgeLaunchAgent.standardOutputURL,
            logsDirectoryURL: BearPaths.logsDirectoryURL,
            writer: .externalProcess
        )
        try BearManagedLog.prepareLogFile(
            fileManager: fileManager,
            logURL: BearBridgeLaunchAgent.standardErrorURL,
            logsDirectoryURL: BearPaths.logsDirectoryURL,
            writer: .externalProcess
        )
    }

    private static func maintainBridgeLogsUntilCancelled(
        logger: Logger,
        fileManager: FileManager = .default,
        intervalNanoseconds: UInt64 = 30_000_000_000
    ) async {
        while !Task.isCancelled {
            do {
                try maintainBridgeLogs(fileManager: fileManager)
            } catch {
                logger.warning("ursus bridge log maintenance failed: \(String(describing: error))")
            }

            do {
                try await Task.sleep(nanoseconds: intervalNanoseconds)
            } catch {
                return
            }
        }
    }

    private struct RuntimeServices {
        let configuration: BearConfiguration
        let tokenStore: any BearTokenStore
        let service: BearService
    }

    private static func renderNewNoteReceipt(_ receipt: MutationReceipt) -> String {
        let title = receipt.title ?? "Untitled"
        if let noteID = receipt.noteID {
            return "\(label(for: receipt.status, action: "create")): \(title) (\(noteID))"
        }
        return "\(label(for: receipt.status, action: "create")): \(title)"
    }

    private static func renderMutationReceipts(_ receipts: [MutationReceipt], action: String) -> String {
        receipts.map { receipt in
            let title = receipt.title ?? "Untitled"
            if let noteID = receipt.noteID {
                return "\(label(for: receipt.status, action: action)): \(title) (\(noteID))"
            }
            return "\(label(for: receipt.status, action: action)): \(title)"
        }.joined(separator: "\n")
    }

    private static func renderBackupSummaries(_ summaries: [BearBackupSummary]) -> String {
        summaries.map { summary in
            [
                "status=backed_up",
                "note_id=\(summary.noteID)",
                "snapshot_id=\(summary.snapshotID)",
            ].joined(separator: " ")
        }.joined(separator: "\n")
    }

    private static func renderRestoreBackupReceipts(_ receipts: [RestoreBackupReceipt]) -> String {
        receipts.map { receipt in
            [
                "status=\(receipt.status)",
                "note_id=\(receipt.noteID)",
                "snapshot_id=\(receipt.snapshotID)",
                "title=\(shellQuoted(receipt.title ?? "Untitled"))",
            ].joined(separator: " ")
        }.joined(separator: "\n")
    }

    private static func renderApplyTemplateReceipts(_ receipts: [ApplyTemplateReceipt]) -> String {
        receipts.map { receipt in
            let title = receipt.title ?? "Untitled"
            return "\(label(for: receipt.status, action: "apply-template")): \(title) (\(receipt.noteID))"
        }.joined(separator: "\n")
    }

    static func renderBridgeStatus(_ bridge: BearAppBridgeSnapshot) -> String {
        let status = bridge.enabled ? "enabled" : "disabled"
        let launchAgentInstalled = bridge.installed ? "yes" : "no"
        let launchAgentLoaded = bridge.loaded ? "yes" : "no"
        let plistMatchesExpected = bridge.plistMatchesExpected ? "yes" : "no"
        let transportHealth = bridge.endpointTransportReachable ? "tcp-ok" : "tcp-failed"
        let protocolHealth = bridge.endpointProtocolCompatible ? "initialize-ok" : "initialize-failed"
        let authMode = bridge.requiresOAuth ? "oauth-required" : "open"
        return [
            "Bridge \(status)",
            "Host: \(bridge.host)",
            "Port: \(bridge.port)",
            "URL: \(bridge.endpointURL)",
            "Auth mode: \(authMode)",
            "Auth storage: \(bridge.auth.storageReady ? "ready" : "not-initialized")",
            "Auth counts: clients=\(bridge.auth.registeredClientCount) grants=\(bridge.auth.activeGrantCount) pending_requests=\(bridge.auth.pendingAuthorizationRequestCount)",
            "Status: \(bridge.statusTitle)",
            "Detail: \(bridge.statusDetail)",
            "LaunchAgent installed: \(launchAgentInstalled)",
            "LaunchAgent loaded: \(launchAgentLoaded)",
            "LaunchAgent matches expected command: \(plistMatchesExpected)",
            "Health: \(transportHealth), \(protocolHealth)",
            "Launcher: \(bridge.launcherPath)",
            "LaunchAgent plist: \(bridge.plistPath)",
            "Stdout log: \(bridge.standardOutputLogPath)",
            "Stderr log: \(bridge.standardErrorLogPath)",
        ].joined(separator: "\n")
    }

    static func renderBridgeActionReceipt(
        _ receipt: BearBridgeLaunchAgentActionReceipt,
        action: String
    ) -> String {
        var lines = [
            "Bridge action: \(action)",
            "Result: \(receipt.status.rawValue)",
            "LaunchAgent plist: \(receipt.plistPath)",
        ]
        if let endpointURL = receipt.endpointURL {
            lines.append("URL: \(endpointURL)")
        }
        return lines.joined(separator: "\n")
    }

    static func renderDonationPromptSnapshot(_ snapshot: BearDonationPromptSnapshot) -> String {
        let suppression = snapshot.permanentSuppressionReason?.rawValue ?? "none"
        return [
            "runtime_state_path=\(BearPaths.runtimeStateDatabaseURL.path)",
            "successful_operation_count=\(snapshot.totalSuccessfulOperationCount)",
            "next_prompt_operation_count=\(snapshot.nextPromptOperationCount)",
            "permanent_suppression_reason=\(suppression)",
            "prompt_eligible=\(snapshot.isPromptEligible ? "yes" : "no")",
            "support_affordance=\(snapshot.shouldShowSupportAffordance ? "yes" : "no")",
        ].joined(separator: "\n")
    }

    private static func label(for status: String, action: String) -> String {
        switch (action, status) {
        case ("create", "created"):
            return "Created note"
        case ("create", "submitted"):
            return "Submitted note"
        case ("apply-template", "applied"):
            return "Applied template"
        case ("apply-template", "unchanged"):
            return "Template already current"
        default:
            return status.replacingOccurrences(of: "_", with: " ").capitalized
        }
    }

    private static func shellQuoted(_ text: String) -> String {
        let escaped = text
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        return "\"\(escaped)\""
    }
}
