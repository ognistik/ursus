public struct UrsusUpdateCheckResult: Sendable, Equatable {
    public let message: String
    public let exitCode: Int32

    public init(message: String, exitCode: Int32) {
        self.message = message
        self.exitCode = exitCode
    }
}

@MainActor
public protocol UrsusUpdateChecking: AnyObject, Sendable {
    func startScheduledUpdateChecks(context: String)
    func runScheduledUpdateChecksIfDue(context: String) async
    func checkForUpdatesFromCLI() async -> UrsusUpdateCheckResult
}
