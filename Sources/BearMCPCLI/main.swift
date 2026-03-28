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
            let command = CommandLine.arguments.dropFirst().first ?? "mcp"

            switch command {
            case "--update-config":
                _ = try BearRuntimeBootstrap.updateConfigurationFile()
                print("Updated config: \(BearPaths.configFileURL.path)")
            case "doctor":
                print(BearRuntimeBootstrap.doctorReport(logger: logger))
            case "paths":
                print(
                    [
                        BearPaths.configFileURL.path,
                        BearPaths.noteTemplateURL.path,
                        BearPaths.backupsIndexURL.path,
                        BearPaths.processLockURL.path,
                        BearPaths.debugLogURL.path,
                        BearPaths.defaultBearDatabaseURL.path,
                    ].joined(separator: "\n")
                )
            case "mcp":
                let processLock = try BearProcessLock.acquire()
                try await runMCP(logger: logger, processLock: processLock)
            default:
                fputs("Unknown command '\(command)'. Use 'mcp', '--update-config', 'doctor', or 'paths'.\n", stderr)
                Foundation.exit(1)
            }
        } catch {
            let message = (error as? LocalizedError)?.errorDescription ?? String(describing: error)
            fputs("bear-mcp failed: \(message)\n", stderr)
            Foundation.exit(1)
        }
    }

    private static func runMCP(logger: Logger, processLock: BearProcessLock) async throws {
        logger.info("bear-mcp acquired process lock at \(processLock.lockURL.path)")
        let configuration = try BearRuntimeBootstrap.loadConfiguration()
        let tokenStore = BearKeychainSelectedNoteTokenStore()
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
            tokenStore: tokenStore,
            logger: logger
        )

        let server = await BearMCPServer(
            service: service,
            configuration: configuration,
            selectedNoteTokenConfigured: BearSelectedNoteTokenResolver.configuredHint(configuration: configuration)
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
}
