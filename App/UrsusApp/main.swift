import BearCLIRuntime
import Foundation

if let cliArguments = UrsusCLIRuntime.cliArgumentsForEmbeddedApp(from: CommandLine.arguments) {
    let updateChecker = await UrsusCommandLineUpdateChecker()
    let exitCode = await UrsusCLIRuntime.run(arguments: cliArguments, updateChecker: updateChecker)
    Foundation.exit(exitCode)
}

UrsusApp.main()
