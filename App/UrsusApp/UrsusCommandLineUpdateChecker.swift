import BearCLIRuntime
import Foundation
import Sparkle

@MainActor
final class UrsusCommandLineUpdateChecker: NSObject, UrsusUpdateChecking, SPUUpdaterDelegate {
    private var scheduledUpdaterController: SPUStandardUpdaterController?
    private var shortLivedScheduledUpdaterController: SPUStandardUpdaterController?
    private var manualUpdaterController: SPUStandardUpdaterController?
    private weak var shortLivedScheduledUpdater: SPUUpdater?
    private weak var manualUpdater: SPUUpdater?
    private var shortLivedScheduledContinuation: CheckedContinuation<Void, Never>?
    private var manualContinuation: CheckedContinuation<UrsusUpdateCheckResult, Never>?

    func startScheduledUpdateChecks(context: String) {
        guard scheduledUpdaterController == nil else {
            return
        }

        guard UrsusSparkleConfiguration(bundle: .main).isConfigured else {
            return
        }

        let updaterController = SPUStandardUpdaterController(
            startingUpdater: false,
            updaterDelegate: nil,
            userDriverDelegate: nil
        )
        scheduledUpdaterController = updaterController
        updaterController.startUpdater()
    }

    func runScheduledUpdateChecksIfDue(context: String) async {
        guard UrsusSparkleConfiguration(bundle: .main).isConfigured else {
            return
        }

        guard shortLivedScheduledContinuation == nil else {
            return
        }

        let updaterController = SPUStandardUpdaterController(
            startingUpdater: false,
            updaterDelegate: self,
            userDriverDelegate: nil
        )
        shortLivedScheduledUpdaterController = updaterController
        shortLivedScheduledUpdater = updaterController.updater

        await withCheckedContinuation { continuation in
            shortLivedScheduledContinuation = continuation
            updaterController.startUpdater()
        }
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
            userDriverDelegate: nil
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

        return await withCheckedContinuation { continuation in
            manualContinuation = continuation
            updaterController.checkForUpdates(nil)
        }
    }

    func updater(_ updater: SPUUpdater, willScheduleUpdateCheckAfterDelay delay: TimeInterval) {
        guard updater === shortLivedScheduledUpdater else {
            return
        }

        finishShortLivedScheduledCheck()
    }

    func updaterWillNotScheduleUpdateCheck(_ updater: SPUUpdater) {
        guard updater === shortLivedScheduledUpdater else {
            return
        }

        finishShortLivedScheduledCheck()
    }

    func updater(
        _ updater: SPUUpdater,
        didFinishUpdateCycleFor updateCheck: SPUUpdateCheck,
        error: (any Error)?
    ) {
        if updater === shortLivedScheduledUpdater {
            finishShortLivedScheduledCheck()
            return
        }

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

    func updater(_ updater: SPUUpdater, didAbortWithError error: any Error) {
        guard updater === shortLivedScheduledUpdater else {
            return
        }

        finishShortLivedScheduledCheck()
    }

    private func finishShortLivedScheduledCheck() {
        shortLivedScheduledContinuation?.resume()
        shortLivedScheduledContinuation = nil
        shortLivedScheduledUpdaterController = nil
        shortLivedScheduledUpdater = nil
    }
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
