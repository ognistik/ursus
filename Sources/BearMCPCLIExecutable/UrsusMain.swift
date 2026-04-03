import BearCLIRuntime
import Foundation

@main
enum UrsusMain {
    static func main() async {
        let exitCode = await UrsusCLIRuntime.run(arguments: Array(CommandLine.arguments.dropFirst()))
        Foundation.exit(exitCode)
    }
}
