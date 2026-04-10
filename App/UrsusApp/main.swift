import BearCLIRuntime
import Foundation

if let cliArguments = UrsusCLIRuntime.cliArgumentsForEmbeddedApp(from: CommandLine.arguments) {
    let updateChecker = await makeEmbeddedUpdateChecker(arguments: cliArguments)
    let exitCode = await UrsusCLIRuntime.run(arguments: cliArguments, updateChecker: updateChecker)
    Foundation.exit(exitCode)
}

UrsusApp.main()

@MainActor
private func makeEmbeddedUpdateChecker(arguments: [String]) async -> UrsusCommandLineUpdateChecker? {
    if arguments.isEmpty {
        return UrsusCommandLineUpdateChecker()
    }

    if arguments.count >= 2, arguments[0] == "bridge", arguments[1] == "serve" {
        return UrsusCommandLineUpdateChecker()
    }

    if arguments.first == "--check-updates" {
        return UrsusCommandLineUpdateChecker()
    }

    return nil
}
