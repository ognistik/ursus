import BearCLIRuntime
import Foundation

if let cliArguments = UrsusCLIRuntime.cliArgumentsForEmbeddedApp(from: CommandLine.arguments) {
    let exitCode = await UrsusCLIRuntime.run(arguments: cliArguments)
    Foundation.exit(exitCode)
}

UrsusApp.main()
