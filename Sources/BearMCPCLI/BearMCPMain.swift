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
struct BearMCPMain {
    static func main() async {
        LoggingSystem.bootstrap(StreamLogHandler.standardError)
        let logger = Logger(label: "bear-mcp")

        do {
            let command = try BearCLICommand.parse(arguments: Array(CommandLine.arguments.dropFirst()))

            switch command {
            case .help:
                print(BearCLICommand.usageText)
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
            case .newNote:
                let runtime = try makeRuntimeServices(logger: logger)
                let receipt = try await runtime.service.createInteractiveNote()
                print(renderNewNoteReceipt(receipt))
            case .deleteNote(let selectors):
                let runtime = try makeRuntimeServices(logger: logger)
                let receipts = try await runtime.service.trashNoteTargets(
                    selectors.isEmpty ? [.selected] : selectors.map(NoteTarget.selector)
                )
                print(renderMutationReceipts(receipts, action: "trash"))
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
            fputs("bear-mcp failed: \(message)\n", stderr)
            Foundation.exit(1)
        }
    }

    private static func runMCP(logger: Logger, processLock: BearProcessLock) async throws {
        logger.info("bear-mcp acquired process lock at \(processLock.lockURL.path)")
        let runtime = try makeRuntimeServices(logger: logger)
        let configuration = runtime.configuration
        let service = runtime.service

        let server = await BearMCPServer(
            service: service,
            configuration: configuration,
            selectedNoteTokenConfigured: BearSelectedNoteTokenResolver.configured(configuration: configuration)
        ).makeServer()
        try await server.start(transport: StdioTransport())
        let originalParentPID = getppid()
        let shutdownReason = await waitForShutdownTrigger(server: server, originalParentPID: originalParentPID)

        switch shutdownReason {
        case .serverCompleted:
            logger.info("bear-mcp stdio transport closed; shutting down server.")
        case .parentExited:
            logger.info("bear-mcp parent process exited; shutting down orphaned stdio server.")
        }

        await server.stop()
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

    private static func renderApplyTemplateReceipts(_ receipts: [ApplyTemplateReceipt]) -> String {
        receipts.map { receipt in
            let title = receipt.title ?? "Untitled"
            return "\(label(for: receipt.status, action: "apply-template")): \(title) (\(receipt.noteID))"
        }.joined(separator: "\n")
    }

    private static func label(for status: String, action: String) -> String {
        switch (action, status) {
        case ("create", "created"):
            return "Created note"
        case ("create", "submitted"):
            return "Submitted note"
        case ("trash", "trashed"):
            return "Trashed note"
        case ("trash", "already_trashed"):
            return "Note already trashed"
        case ("trash", "submitted"):
            return "Submitted trash request"
        case ("apply-template", "applied"):
            return "Applied template"
        case ("apply-template", "unchanged"):
            return "Template already current"
        default:
            return status.replacingOccurrences(of: "_", with: " ").capitalized
        }
    }
}
