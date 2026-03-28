import AppKit
import BearApplication
import BearCore
import Combine
import Foundation

@MainActor
final class BearMCPAppModel: ObservableObject {
    let runsHeadlessCallbackHost: Bool

    @Published private(set) var dashboard = BearAppSupport.loadDashboardSnapshot(
        currentAppBundleURL: Bundle.main.bundleURL
    )
    @Published private(set) var lastIncomingCallbackURL: URL?
    @Published var tokenDraft = ""
    @Published var revealsStoredToken = false
    @Published private(set) var tokenStatusMessage: String?
    @Published private(set) var tokenStatusError: String?
    @Published private(set) var cliStatusMessage: String?
    @Published private(set) var cliStatusError: String?
    @Published private(set) var hostSetupStatusMessage: String?
    @Published private(set) var hostSetupStatusError: String?
    @Published private(set) var storedSelectedNoteToken: String?
    @Published private(set) var storedTokenHasBeenExplicitlyLoaded = false

    private var cancellables: Set<AnyCancellable> = []

    init(
        runsHeadlessCallbackHost: Bool = BearSelectedNoteAppHost.shouldRunHeadless()
    ) {
        self.runsHeadlessCallbackHost = runsHeadlessCallbackHost

        NotificationCenter.default.publisher(for: .bearMCPDidReceiveIncomingCallbackURL)
            .compactMap { $0.object as? URL }
            .sink { [weak self] url in
                self?.recordIncomingCallback(url)
            }
            .store(in: &cancellables)

    }

    func reload() {
        dashboard = BearAppSupport.loadDashboardSnapshot(
            currentAppBundleURL: Bundle.main.bundleURL
        )
    }

    func saveSelectedNoteToken() {
        do {
            try BearAppSupport.saveSelectedNoteToken(tokenDraft)
            tokenDraft = ""
            storedSelectedNoteToken = nil
            storedTokenHasBeenExplicitlyLoaded = false
            revealsStoredToken = false
            tokenStatusMessage = "Token saved in Keychain. Any legacy config copy was cleaned up."
            tokenStatusError = nil
            reload()
        } catch {
            tokenStatusMessage = nil
            tokenStatusError = localizedMessage(for: error)
        }
    }

    func importSelectedNoteTokenFromConfig() {
        do {
            let imported = try BearAppSupport.importSelectedNoteTokenFromConfig()
            storedSelectedNoteToken = nil
            storedTokenHasBeenExplicitlyLoaded = false
            revealsStoredToken = false
            tokenStatusMessage = imported
                ? "Token imported into Keychain and removed from config.json."
                : "No legacy config token was found to import."
            tokenStatusError = nil
            reload()
        } catch {
            tokenStatusMessage = nil
            tokenStatusError = localizedMessage(for: error)
        }
    }

    func removeSelectedNoteToken() {
        do {
            try BearAppSupport.removeSelectedNoteToken()
            tokenDraft = ""
            storedSelectedNoteToken = nil
            storedTokenHasBeenExplicitlyLoaded = false
            revealsStoredToken = false
            tokenStatusMessage = "Token removed. Keychain and any legacy config copy are now cleared."
            tokenStatusError = nil
            reload()
        } catch {
            tokenStatusMessage = nil
            tokenStatusError = localizedMessage(for: error)
        }
    }

    func recordIncomingCallback(_ url: URL) {
        lastIncomingCallbackURL = url
    }

    func installBundledCLI() {
        do {
            let receipt = try BearAppSupport.installBundledCLI(fromAppBundleURL: Bundle.main.bundleURL)
            cliStatusMessage = "CLI installed at \(receipt.destinationPath). MCP hosts should use that path."
            cliStatusError = nil
            reload()
        } catch {
            cliStatusMessage = nil
            cliStatusError = localizedMessage(for: error)
        }
    }

    func reveal(path: String) {
        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)])
    }

    func copyInstalledCLIPath() {
        let path = installedCLIPath
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(path, forType: .string)
        cliStatusMessage = "Copied CLI path: \(path)"
        cliStatusError = nil
    }

    func copyHostSetupSnippet(_ setup: BearHostAppSetupSnapshot) {
        guard let snippet = setup.snippet else {
            hostSetupStatusMessage = nil
            hostSetupStatusError = "No local snippet is available for \(setup.appName)."
            return
        }

        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(snippet, forType: .string)
        hostSetupStatusMessage = "Copied \(setup.appName) setup snippet."
        hostSetupStatusError = nil
    }

    func copyHostConfigPath(_ setup: BearHostAppSetupSnapshot) {
        guard let configPath = setup.configPath else {
            hostSetupStatusMessage = nil
            hostSetupStatusError = "No local config path is tracked for \(setup.appName)."
            return
        }

        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(configPath, forType: .string)
        hostSetupStatusMessage = "Copied \(setup.appName) config path: \(configPath)"
        hostSetupStatusError = nil
    }

    func loadStoredSelectedNoteToken() {
        do {
            storedSelectedNoteToken = try BearAppSupport.loadResolvedSelectedNoteToken()?.value
            storedTokenHasBeenExplicitlyLoaded = true
            tokenStatusError = nil
        } catch {
            storedSelectedNoteToken = nil
            storedTokenHasBeenExplicitlyLoaded = false
            tokenStatusError = localizedMessage(for: error)
        }
    }

    var appDisplayName: String {
        if let value = Bundle.main.object(forInfoDictionaryKey: "CFBundleName") as? String, !value.isEmpty {
            return value
        }

        return "Bear MCP"
    }

    var bundleIdentifier: String {
        Bundle.main.bundleIdentifier ?? "unknown"
    }

    var versionDescription: String {
        let shortVersion = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.0.0"
        let buildVersion = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "0"
        return "\(shortVersion) (\(buildVersion))"
    }

    var callbackSchemes: [String] {
        guard let urlTypes = Bundle.main.object(forInfoDictionaryKey: "CFBundleURLTypes") as? [[String: Any]] else {
            return []
        }

        return urlTypes
            .flatMap { $0["CFBundleURLSchemes"] as? [String] ?? [] }
            .sorted()
    }

    var maskedStoredSelectedNoteToken: String? {
        guard let storedSelectedNoteToken else {
            return nil
        }

        return String(repeating: "*", count: max(8, storedSelectedNoteToken.count))
    }

    var currentBundledCLIPath: String? {
        try? BearMCPCLILocator.bundledExecutableURL(forAppBundleURL: Bundle.main.bundleURL).path
    }

    var installedCLIPath: String {
        dashboard.settings?.appManagedCLIPath ?? BearMCPCLILocator.appManagedInstallURL.path
    }

    private func localizedMessage(for error: Error) -> String {
        (error as? LocalizedError)?.errorDescription ?? String(describing: error)
    }
}

extension Notification.Name {
    static let bearMCPDidReceiveIncomingCallbackURL = Notification.Name("bear-mcp.did-receive-incoming-callback-url")
}
