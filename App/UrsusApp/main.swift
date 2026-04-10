import AppKit
import BearCLIRuntime
import Foundation

if let cliArguments = UrsusCLIRuntime.cliArgumentsForEmbeddedApp(from: CommandLine.arguments) {
    if cliArguments.isEmpty || cliArguments == ["mcp"] || cliArguments == ["bridge", "serve"] {
        NSApplication.shared.setActivationPolicy(.prohibited)
    }
    let updateChecker = await UrsusCommandLineUpdateChecker()
    let exitCode = await UrsusCLIRuntime.run(arguments: cliArguments, updateChecker: updateChecker)
    Foundation.exit(exitCode)
}

UrsusApp.main()
