import AppKit
import Combine
import Foundation
import Sparkle
import SwiftUI

@MainActor
final class UrsusUpdaterController: ObservableObject {
    @Published private(set) var canCheckForUpdates = false
    @Published private(set) var automaticallyChecksForUpdates = false
    @Published private(set) var isConfigured = false

    private let updaterController: SPUStandardUpdaterController
    private var cancellables: Set<AnyCancellable> = []

    init(bundle: Bundle = .main) {
        let configuration = SparkleConfiguration(bundle: bundle)
        self.isConfigured = configuration.isConfigured
        self.automaticallyChecksForUpdates = configuration.defaultAutomaticChecks
        self.updaterController = SPUStandardUpdaterController(
            startingUpdater: false,
            updaterDelegate: nil,
            userDriverDelegate: nil
        )

        guard configuration.isConfigured else {
            return
        }

        bindUpdaterState()
        updaterController.startUpdater()
        canCheckForUpdates = updaterController.updater.canCheckForUpdates
        automaticallyChecksForUpdates = updaterController.updater.automaticallyChecksForUpdates
    }

    var configurationNote: String? {
        guard !isConfigured else {
            return nil
        }

        return "App updates will start working once `SUFeedURL` and `SUPublicEDKey` point at the real Sparkle release feed."
    }

    func checkForUpdates() {
        guard isConfigured else {
            return
        }

        updaterController.checkForUpdates(nil)
    }

    func checkForUpdatesFromCommandLineRequest() async {
        guard isConfigured else {
            return
        }

        for _ in 0..<20 where !updaterController.updater.canCheckForUpdates {
            try? await Task.sleep(nanoseconds: 100_000_000)
        }

        guard updaterController.updater.canCheckForUpdates else {
            return
        }

        bringAppToFront()
        updaterController.checkForUpdates(nil)
    }

    func setAutomaticallyChecksForUpdates(_ newValue: Bool) {
        automaticallyChecksForUpdates = newValue

        guard isConfigured else {
            return
        }

        updaterController.updater.automaticallyChecksForUpdates = newValue
    }
}

private extension UrsusUpdaterController {
    func bindUpdaterState() {
        let updater = updaterController.updater

        updater.publisher(for: \.canCheckForUpdates)
            .receive(on: RunLoop.main)
            .assign(to: &$canCheckForUpdates)

        updater.publisher(for: \.automaticallyChecksForUpdates)
            .receive(on: RunLoop.main)
            .assign(to: &$automaticallyChecksForUpdates)
    }

    func bringAppToFront() {
        let app = NSApplication.shared

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

private struct SparkleConfiguration {
    private static let placeholderFeedURL = "https://example.com/ursus/appcast.xml"
    private static let placeholderPublicKey = "REPLACE_WITH_SPARKLE_PUBLIC_ED_KEY"

    let feedURL: String?
    let publicEDKey: String?
    let defaultAutomaticChecks: Bool

    init(bundle: Bundle) {
        self.feedURL = bundle.object(forInfoDictionaryKey: "SUFeedURL") as? String
        self.publicEDKey = bundle.object(forInfoDictionaryKey: "SUPublicEDKey") as? String
        self.defaultAutomaticChecks = bundle.object(forInfoDictionaryKey: "SUEnableAutomaticChecks") as? Bool ?? false
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

struct UrsusCheckForUpdatesCommand: View {
    @ObservedObject var updaterController: UrsusUpdaterController

    var body: some View {
        Button("Check for Updates…") {
            updaterController.checkForUpdates()
        }
        .disabled(!updaterController.isConfigured || !updaterController.canCheckForUpdates)
    }
}
