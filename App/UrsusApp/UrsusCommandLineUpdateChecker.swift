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
        await UrsusCommandLineUpdateRequest.openForegroundAppForManualCheck()
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
        reply(.dismiss)
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
enum UrsusCommandLineUpdateRequest {
    static let foregroundLaunchArgument = "--ursus-foreground-check-updates"

    private static let pendingDefaultsKey = "UrsusPendingCommandLineUpdateCheckRequestedAt"
    private static let pendingRequestMaxAge: TimeInterval = 300

    static func openForegroundAppForManualCheck() async -> UrsusUpdateCheckResult {
        guard UrsusSparkleConfiguration(bundle: .main).isConfigured else {
            return UrsusUpdateCheckResult(
                message: "Sparkle updates are not configured for this Ursus build.",
                exitCode: 1
            )
        }

        UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: pendingDefaultsKey)
        UserDefaults.standard.synchronize()

        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        configuration.arguments = [foregroundLaunchArgument]
        configuration.createsNewApplicationInstance = shouldCreateNewApplicationInstance()

        return await withCheckedContinuation { continuation in
            NSWorkspace.shared.openApplication(
                at: Bundle.main.bundleURL,
                configuration: configuration
            ) { _, error in
                if let error {
                    UserDefaults.standard.removeObject(forKey: pendingDefaultsKey)
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
                        message: "Opened Ursus to check for updates.",
                        exitCode: 0
                    )
                )
            }
        }
    }

    static func consumePendingForegroundCheckRequest(now: Date = Date()) -> Bool {
        let defaults = UserDefaults.standard
        let launchedForUpdateCheck = CommandLine.arguments.contains(foregroundLaunchArgument)
        let requestTimestamp = defaults.object(forKey: pendingDefaultsKey) as? Double

        if requestTimestamp != nil {
            defaults.removeObject(forKey: pendingDefaultsKey)
        }

        guard let requestTimestamp else {
            return launchedForUpdateCheck
        }

        return launchedForUpdateCheck || now.timeIntervalSince1970 - requestTimestamp <= pendingRequestMaxAge
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
