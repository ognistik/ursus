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
            case "doctor":
                print(BearRuntimeBootstrap.doctorReport(logger: logger))
            case "paths":
                print(
                    [
                        BearPaths.configFileURL.path,
                        BearPaths.noteTemplateURL.path,
                        BearPaths.processLockURL.path,
                        BearPaths.debugLogURL.path,
                        BearPaths.defaultBearDatabaseURL.path,
                    ].joined(separator: "\n")
                )
            case "mcp":
                let processLock = try BearProcessLock.acquire()
                try await runMCP(logger: logger, processLock: processLock)
            default:
                fputs("Unknown command '\(command)'. Use 'mcp', 'doctor', or 'paths'.\n", stderr)
                Foundation.exit(1)
            }
        } catch {
            let message = (error as? LocalizedError)?.errorDescription ?? String(describing: error)
            fputs("bear-mcp failed: \(message)\n", stderr)
            Foundation.exit(1)
        }
    }

    private static func runMCP(logger: Logger, processLock _: BearProcessLock) async throws {
        let configuration = try BearRuntimeBootstrap.loadConfiguration()
        let databaseReader = try BearDatabaseReader(
            databaseURL: URL(fileURLWithPath: configuration.databasePath),
            activeScopeTags: configuration.activeTags
        )
        let writeTransport = BearXCallbackTransport(readStore: databaseReader)
        let service = BearService(
            configuration: configuration,
            readStore: databaseReader,
            writeTransport: writeTransport,
            logger: logger
        )

        let server = await BearMCPServer(service: service, configuration: configuration).makeServer()
        try await server.start(transport: StdioTransport())

        while !Task.isCancelled {
            if getppid() == 1 {
                logger.info("bear-mcp parent process exited; shutting down orphaned stdio server.")
                return
            }
            try await Task.sleep(for: .seconds(2))
        }
    }
}
