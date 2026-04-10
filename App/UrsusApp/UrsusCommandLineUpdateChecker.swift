import AppKit
import BearCLIRuntime
import Foundation
import Sparkle

@MainActor
final class UrsusCommandLineUpdateChecker: NSObject, UrsusUpdateChecking {
    private var scheduledUpdater: SPUUpdater?
    private var scheduledUserDriver: UrsusBackgroundUpdateUserDriver?

    func startScheduledUpdateChecks(context: String) {
        guard scheduledUpdater == nil else {
            return
        }

        guard UrsusSparkleConfiguration(bundle: .main).isConfigured else {
            return
        }

        let userDriver = UrsusBackgroundUpdateUserDriver()
        let updater = SPUUpdater(
            hostBundle: .main,
            applicationBundle: .main,
            userDriver: userDriver,
            delegate: nil
        )
        do {
            try updater.start()
        } catch {
            scheduledUserDriver = nil
            scheduledUpdater = nil
            return
        }
        scheduledUserDriver = userDriver
        scheduledUpdater = updater
    }

    func checkForUpdatesFromCLI() async -> UrsusUpdateCheckResult {
        await UrsusCommandLineUpdateRequest.openSparkleUpdateUI(
            mode: .manual,
            successMessage: "Opened Ursus to check for updates."
        )
    }

    func setAutomaticallyDownloadsUpdatesFromCLI(_ enabled: Bool) async -> UrsusUpdateCheckResult {
        guard UrsusSparkleConfiguration(bundle: .main).isConfigured else {
            return UrsusUpdateCheckResult(
                message: "Sparkle updates are not configured for this Ursus build.",
                exitCode: 1
            )
        }

        let updaterController = SPUStandardUpdaterController(
            startingUpdater: false,
            updaterDelegate: nil,
            userDriverDelegate: nil
        )
        updaterController.startUpdater()

        let updater = updaterController.updater

        for _ in 0..<20 where !updater.canCheckForUpdates {
            try? await Task.sleep(nanoseconds: 100_000_000)
        }

        if enabled {
            updater.automaticallyChecksForUpdates = true
        }

        guard !enabled || updater.allowsAutomaticUpdates else {
            return UrsusUpdateCheckResult(
                message: "Ursus could not enable automatic update installs because Sparkle does not currently allow that option.",
                exitCode: 1
            )
        }

        updater.automaticallyDownloadsUpdates = enabled

        return UrsusUpdateCheckResult(
            message: enabled
                ? "Automatic update installs are now enabled. Ursus will also check for updates automatically."
                : "Automatic update installs are now disabled.",
            exitCode: 0
        )
    }
}

@MainActor
private final class UrsusBackgroundUpdateUserDriver: NSObject, SPUUserDriver {
    private let permissionResponse = SUUpdatePermissionResponse(
        automaticUpdateChecks: true,
        sendSystemProfile: false
    )

    func show(
        _ request: SPUUpdatePermissionRequest,
        reply: @escaping (SUUpdatePermissionResponse) -> Void
    ) {
        reply(permissionResponse)
    }

    func showUserInitiatedUpdateCheck(cancellation: @escaping () -> Void) {}

    func showUpdateFound(
        with appcastItem: SUAppcastItem,
        state: SPUUserUpdateState,
        reply: @escaping (SPUUserUpdateChoice) -> Void
    ) {
        Task { @MainActor in
            _ = await UrsusCommandLineUpdateRequest.openSparkleUpdateUI(
                mode: .updateAvailable,
                successMessage: "Opened Ursus to show an available update."
            )
            reply(.dismiss)
        }
    }

    func showUpdateReleaseNotes(with downloadData: SPUDownloadData) {}

    func showUpdateReleaseNotesFailedToDownloadWithError(_ error: any Error) {}

    func showUpdateNotFoundWithError(
        _ error: any Error,
        acknowledgement: @escaping () -> Void
    ) {
        acknowledgement()
    }

    func showUpdaterError(
        _ error: any Error,
        acknowledgement: @escaping () -> Void
    ) {
        acknowledgement()
    }

    func showDownloadInitiated(cancellation: @escaping () -> Void) {}

    func showDownloadDidReceiveExpectedContentLength(_ expectedContentLength: UInt64) {}

    func showDownloadDidReceiveData(ofLength length: UInt64) {}

    func showDownloadDidStartExtractingUpdate() {}

    func showExtractionReceivedProgress(_ progress: Double) {}

    func showReadyToInstallAndRelaunch() async -> SPUUserUpdateChoice {
        .dismiss
    }

    func showInstallingUpdate(
        withApplicationTerminated applicationTerminated: Bool,
        retryTerminatingApplication: @escaping () -> Void
    ) {}

    func showUpdateInstalledAndRelaunched(
        _ relaunched: Bool,
        acknowledgement: @escaping () -> Void
    ) {
        acknowledgement()
    }

    func dismissUpdateInstallation() {}
}

private struct UrsusSparkleConfiguration {
    private static let placeholderFeedURL = "https://example.com/ursus/appcast.xml"
    private static let placeholderPublicKey = "REPLACE_WITH_SPARKLE_PUBLIC_ED_KEY"

    let feedURL: String?
    let publicEDKey: String?

    init(bundle: Bundle) {
        self.feedURL = bundle.object(forInfoDictionaryKey: "SUFeedURL") as? String
        self.publicEDKey = bundle.object(forInfoDictionaryKey: "SUPublicEDKey") as? String
    }

    var isConfigured: Bool {
        guard
            let feedURL = normalized(feedURL),
            let publicEDKey = normalized(publicEDKey)
        else {
            return false
        }

        return feedURL != Self.placeholderFeedURL && publicEDKey != Self.placeholderPublicKey
    }

    private func normalized(_ value: String?) -> String? {
        guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else {
            return nil
        }

        return trimmed
    }
}

@MainActor
enum UrsusSparkleUpdateUIMode: String {
    case manual
    case updateAvailable
}

@MainActor
enum UrsusCommandLineUpdateRequest {
    static let pendingRequestNotification = Notification.Name("UrsusSparkleUpdateUIRequest")
    static let updateUILaunchArgument = "--ursus-sparkle-update-ui"
    private static let updateAvailableLaunchArgument = "--ursus-sparkle-update-available"

    private static let pendingDefaultsKey = "UrsusPendingSparkleUpdateUIRequestedAt"
    private static let pendingModeDefaultsKey = "UrsusPendingSparkleUpdateUIMode"
    private static let pendingRequestMaxAge: TimeInterval = 300

    static func updateUIMode(from processArguments: [String]) -> UrsusSparkleUpdateUIMode? {
        guard processArguments.dropFirst().contains(updateUILaunchArgument) else {
            return nil
        }

        if processArguments.dropFirst().contains(updateAvailableLaunchArgument) {
            return .updateAvailable
        }

        return .manual
    }

    static func openSparkleUpdateUI(
        mode: UrsusSparkleUpdateUIMode,
        successMessage: String
    ) async -> UrsusUpdateCheckResult {
        guard UrsusSparkleConfiguration(bundle: .main).isConfigured else {
            return UrsusUpdateCheckResult(
                message: "Sparkle updates are not configured for this Ursus build.",
                exitCode: 1
            )
        }

        UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: pendingDefaultsKey)
        UserDefaults.standard.set(mode.rawValue, forKey: pendingModeDefaultsKey)
        UserDefaults.standard.synchronize()

        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        configuration.arguments = launchArguments(for: mode)
        configuration.createsNewApplicationInstance = shouldCreateNewApplicationInstance()

        return await withCheckedContinuation { continuation in
            NSWorkspace.shared.openApplication(
                at: Bundle.main.bundleURL,
                configuration: configuration
            ) { _, error in
                if let error {
                    UserDefaults.standard.removeObject(forKey: pendingDefaultsKey)
                    UserDefaults.standard.removeObject(forKey: pendingModeDefaultsKey)
                    continuation.resume(
                        returning: UrsusUpdateCheckResult(
                            message: "Ursus could not open its update UI: \(error.localizedDescription)",
                            exitCode: 1
                        )
                    )
                    return
                }

                continuation.resume(
                    returning: UrsusUpdateCheckResult(
                        message: successMessage,
                        exitCode: 0
                    )
                )
            }
        }
    }

    static func consumePendingForegroundCheckRequest(now: Date = Date()) -> UrsusSparkleUpdateUIMode? {
        let defaults = UserDefaults.standard
        let launchedMode = updateUIMode(from: CommandLine.arguments)
        let requestTimestamp = defaults.object(forKey: pendingDefaultsKey) as? Double
        let pendingMode = (defaults.string(forKey: pendingModeDefaultsKey))
            .flatMap(UrsusSparkleUpdateUIMode.init(rawValue:))

        clearPendingRequest()

        guard let requestTimestamp else {
            return launchedMode
        }

        if let launchedMode {
            return launchedMode
        }

        guard now.timeIntervalSince1970 - requestTimestamp <= pendingRequestMaxAge else {
            return nil
        }

        return pendingMode ?? .manual
    }

    static func clearPendingRequest() {
        let defaults = UserDefaults.standard
        defaults.removeObject(forKey: pendingDefaultsKey)
        defaults.removeObject(forKey: pendingModeDefaultsKey)
    }

    private static func launchArguments(for mode: UrsusSparkleUpdateUIMode) -> [String] {
        switch mode {
        case .manual:
            return [updateUILaunchArgument]
        case .updateAvailable:
            return [updateUILaunchArgument, updateAvailableLaunchArgument]
        }
    }

    private static func shouldCreateNewApplicationInstance() -> Bool {
        guard let bundleIdentifier = Bundle.main.bundleIdentifier else {
            return false
        }

        return !NSRunningApplication.runningApplications(withBundleIdentifier: bundleIdentifier)
            .contains { runningApplication in
                runningApplication.processIdentifier != getpid()
                    && runningApplication.activationPolicy == .regular
            }
    }
}

@MainActor
enum UrsusSparkleUpdateUIRunner {
    static func run(mode: UrsusSparkleUpdateUIMode) -> Int32 {
        guard UrsusSparkleConfiguration(bundle: .main).isConfigured else {
            fputs("Sparkle updates are not configured for this Ursus build.\n", stderr)
            return 1
        }

        UrsusCommandLineUpdateRequest.clearPendingRequest()

        let app = NSApplication.shared
        let delegate = UrsusSparkleUpdateUIAppDelegate(mode: mode)
        app.delegate = delegate
        app.setActivationPolicy(.regular)
        app.unhide(nil)
        activate(app)

        app.run()
        return delegate.exitCode
    }

    static func activate(_ app: NSApplication = .shared) {
        if app.activationPolicy() != .regular {
            app.setActivationPolicy(.regular)
        }

        app.unhide(nil)

        if let keyWindow = app.keyWindow {
            keyWindow.makeKeyAndOrderFront(nil)
        } else if let visibleWindow = app.windows.first(where: { $0.isVisible }) {
            visibleWindow.makeKeyAndOrderFront(nil)
        }

        if #available(macOS 14, *) {
            app.activate()
        } else {
            NSRunningApplication.current.activate(options: [.activateIgnoringOtherApps])
        }
    }
}

@MainActor
private final class UrsusSparkleUpdateUIAppDelegate: NSObject, NSApplicationDelegate, SPUUpdaterDelegate, SPUStandardUserDriverDelegate {
    private let mode: UrsusSparkleUpdateUIMode
    private var updaterController: SPUStandardUpdaterController?
    private var didStartCheck = false
    private var didRequestTermination = false

    private(set) var exitCode: Int32 = 0

    init(mode: UrsusSparkleUpdateUIMode) {
        self.mode = mode
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        let updaterController = SPUStandardUpdaterController(
            startingUpdater: false,
            updaterDelegate: self,
            userDriverDelegate: self
        )
        self.updaterController = updaterController
        updaterController.startUpdater()

        Task { @MainActor in
            await startUpdateCheckWhenReady()
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    func updater(
        _ updater: SPUUpdater,
        didFinishUpdateCycleFor updateCheck: SPUUpdateCheck,
        error: (any Error)?
    ) {
        if error != nil {
            exitCode = 1
        }

        scheduleTermination()
    }

    nonisolated func standardUserDriverWillShowModalAlert() {
        Task { @MainActor in
            UrsusSparkleUpdateUIRunner.activate()
        }
    }

    nonisolated func standardUserDriverDidShowModalAlert() {
        Task { @MainActor in
            UrsusSparkleUpdateUIRunner.activate()
        }
    }

    nonisolated func standardUserDriverWillHandleShowingUpdate(
        _ handleShowingUpdate: Bool,
        for update: SUAppcastItem,
        state: SPUUserUpdateState
    ) {
        Task { @MainActor in
            UrsusSparkleUpdateUIRunner.activate()
        }
    }

    private func startUpdateCheckWhenReady() async {
        guard !didStartCheck else {
            return
        }
        didStartCheck = true

        guard let updaterController else {
            exitCode = 1
            scheduleTermination()
            return
        }

        for _ in 0..<30 where !updaterController.updater.canCheckForUpdates {
            try? await Task.sleep(nanoseconds: 100_000_000)
        }

        guard updaterController.updater.canCheckForUpdates else {
            exitCode = 1
            scheduleTermination()
            return
        }

        UrsusSparkleUpdateUIRunner.activate()

        switch mode {
        case .manual, .updateAvailable:
            updaterController.checkForUpdates(nil)
        }
    }

    private func scheduleTermination() {
        guard !didRequestTermination else {
            return
        }
        didRequestTermination = true

        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 250_000_000)
            NSApplication.shared.terminate(nil)
        }
    }
}
