import BearApplication
import BearCore
import BearDB
import BearMCP
import BearXCallback
import Darwin
import Foundation
import Logging
import MCP

@main
struct UrsusMain {
    static func main() async {
        LoggingSystem.bootstrap(StreamLogHandler.standardError)
        let logger = Logger(label: "ursus")

        do {
            let command = try BearCLICommand.parse(arguments: Array(CommandLine.arguments.dropFirst()))

            switch command {
            case .help:
                print(BearCLICommand.usageText)
            case .bridge(.help):
                print(BearCLICommand.bridgeUsageText)
            case .doctor:
                print(BearRuntimeBootstrap.doctorReport(logger: logger))
            case .paths:
                print(
                    [
                        BearPaths.configFileURL.path,
                        BearPaths.noteTemplateURL.path,
                        BearPaths.publicCLIExecutableURL.path,
                        BearPaths.backupsIndexURL.path,
                        BearPaths.processLockURL.path,
                        BearPaths.debugLogURL.path,
                        BearPaths.defaultBearDatabaseURL.path,
                    ].joined(separator: "\n")
                )
            case .bridge(.status):
                let configuration = try BearRuntimeBootstrap.loadConfiguration()
                let snapshot = BearAppSupport.bridgeSnapshot(configuration: configuration)
                print(renderBridgeStatus(snapshot))
            case .bridge(.printURL):
                let configuration = try BearRuntimeBootstrap.loadConfiguration()
                print(try configuration.bridge.endpointURLString())
            case .bridge(.serve):
                try await runBridge(logger: logger)
            case .newNote(let options):
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
            case .backupNote(let selectors):
                let runtime = try makeRuntimeServices(logger: logger)
                let summaries = try await runtime.service.backupNoteTargets(
                    selectors.isEmpty ? [.selected] : selectors.map(NoteTarget.selector)
                )
                print(renderBackupSummaries(summaries))
            case .restoreNote(let requests):
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
            case .applyTemplate(let selectors):
                let runtime = try makeRuntimeServices(logger: logger)
                let receipts = try await runtime.service.applyTemplateToTargets(
                    selectors.isEmpty ? [.selected] : selectors.map(NoteTarget.selector)
                )
                print(renderApplyTemplateReceipts(receipts))
            case .mcp:
                let processLock = try BearProcessLock.acquire()
                try await runMCP(logger: logger, processLock: processLock)
            }
        } catch {
            let message = (error as? LocalizedError)?.errorDescription ?? String(describing: error)
            fputs("ursus failed: \(message)\n", stderr)
            Foundation.exit(1)
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
            selectedNoteTokenConfigured: BearSelectedNoteTokenResolver.configured(configuration: configuration)
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

        if !bridge.enabled {
            logger.info("ursus bridge serve is starting while bridge.enabled=false; direct CLI bridge runs are still allowed.")
        }

        let application = BearBridgeHTTPApplication(
            configuration: .init(
                host: bridge.host,
                port: bridge.port,
                endpoint: bridge.endpointPath
            ),
            serverFactory: {
                await UrsusMCPServer(
                    service: runtime.service,
                    configuration: runtime.configuration,
                    selectedNoteTokenConfigured: BearSelectedNoteTokenResolver.configured(configuration: runtime.configuration)
                ).makeServer()
            },
            logger: logger
        )

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
        let databaseReader = try BearDatabaseReader(
            databaseURL: URL(fileURLWithPath: configuration.databasePath)
        )
        let writeTransport = BearXCallbackTransport(readStore: databaseReader)
        let backupStore = BearBackupFileStore(retentionDays: configuration.backupRetentionDays)
        let service = BearService(
            configuration: configuration,
            readStore: databaseReader,
            writeTransport: writeTransport,
            backupStore: backupStore,
            logger: logger
        )

        return RuntimeServices(configuration: configuration, service: service)
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

    private struct RuntimeServices {
        let configuration: BearConfiguration
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
                "title=\(shellQuoted(summary.title))",
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
        return [
            "Bridge \(status)",
            "Host: \(bridge.host)",
            "Port: \(bridge.port)",
            "URL: \(bridge.endpointURL)",
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
