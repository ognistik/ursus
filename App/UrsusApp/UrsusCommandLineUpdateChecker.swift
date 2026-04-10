import AppKit
import BearCLIRuntime
import Foundation
import Sparkle

@MainActor
final class UrsusCommandLineUpdateChecker: NSObject, UrsusUpdateChecking, SPUUpdaterDelegate, SPUStandardUserDriverDelegate {
    private var scheduledUpdater: SPUUpdater?
    private var scheduledUserDriver: UrsusBackgroundUpdateUserDriver?
    private var manualUpdaterController: SPUStandardUpdaterController?
    private weak var manualUpdater: SPUUpdater?
    private var manualContinuation: CheckedContinuation<UrsusUpdateCheckResult, Never>?

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
        guard UrsusSparkleConfiguration(bundle: .main).isConfigured else {
            return UrsusUpdateCheckResult(
                message: "Sparkle updates are not configured for this Ursus build.",
                exitCode: 1
            )
        }

        guard manualContinuation == nil else {
            return UrsusUpdateCheckResult(
                message: "A Sparkle update check is already running.",
                exitCode: 1
            )
        }

        let updaterController = SPUStandardUpdaterController(
            startingUpdater: false,
            updaterDelegate: self,
            userDriverDelegate: self
        )
        manualUpdaterController = updaterController
        manualUpdater = updaterController.updater
        updaterController.startUpdater()

        guard updaterController.updater.canCheckForUpdates else {
            manualUpdaterController = nil
            return UrsusUpdateCheckResult(
                message: "Sparkle cannot start a new update check right now.",
                exitCode: 1
            )
        }

        bringUpdateUIToFront()

        return await withCheckedContinuation { continuation in
            manualContinuation = continuation
            updaterController.checkForUpdates(nil)
        }
    }

    func updater(
        _ updater: SPUUpdater,
        didFinishUpdateCycleFor updateCheck: SPUUpdateCheck,
        error: (any Error)?
    ) {
        guard updater === manualUpdater else {
            return
        }

        let result: UrsusUpdateCheckResult
        if let error {
            result = UrsusUpdateCheckResult(
                message: "Sparkle update check finished with an error: \(error.localizedDescription)",
                exitCode: 1
            )
        } else {
            result = UrsusUpdateCheckResult(
                message: "Sparkle update check finished.",
                exitCode: 0
            )
        }

        manualContinuation?.resume(returning: result)
        manualContinuation = nil
        manualUpdaterController = nil
        manualUpdater = nil
    }

    nonisolated func standardUserDriverWillShowModalAlert() {
        Task { @MainActor in
            bringUpdateUIToFront()
        }
    }

    nonisolated func standardUserDriverDidShowModalAlert() {
        Task { @MainActor in
            bringUpdateUIToFront()
        }
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
private func bringUpdateUIToFront() {
    let app = NSApplication.shared

    if app.activationPolicy() != .regular {
        app.setActivationPolicy(.regular)
    }

    if app.isHidden {
        app.unhide(nil)
    }

    if #available(macOS 14, *) {
        app.activate()
    } else {
        NSRunningApplication.current.activate(options: [.activateIgnoringOtherApps])
    }
}
