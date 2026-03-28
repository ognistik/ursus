import AppKit
import BearApplication
import Combine
import Foundation

@MainActor
final class BearMCPAppModel: ObservableObject {
    let runsHeadlessCallbackHost: Bool

    @Published private(set) var dashboard = BearAppSupport.loadDashboardSnapshot()
    @Published private(set) var lastIncomingCallbackURL: URL?
    @Published var tokenDraft = ""
    @Published var revealsStoredToken = false
    @Published private(set) var tokenStatusMessage: String?
    @Published private(set) var tokenStatusError: String?
    @Published private(set) var storedSelectedNoteToken: String?

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

        refreshStoredSelectedNoteToken()
    }

    func reload() {
        dashboard = BearAppSupport.loadDashboardSnapshot()
        refreshStoredSelectedNoteToken()
    }

    func saveSelectedNoteToken() {
        do {
            try BearAppSupport.saveSelectedNoteToken(tokenDraft)
            tokenDraft = ""
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

    func reveal(path: String) {
        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)])
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

    private func refreshStoredSelectedNoteToken() {
        do {
            storedSelectedNoteToken = try BearAppSupport.loadResolvedSelectedNoteToken()?.value
            tokenStatusError = nil
        } catch {
            storedSelectedNoteToken = nil
            tokenStatusError = localizedMessage(for: error)
        }
    }

    private func localizedMessage(for error: Error) -> String {
        (error as? LocalizedError)?.errorDescription ?? String(describing: error)
    }
}

extension Notification.Name {
    static let bearMCPDidReceiveIncomingCallbackURL = Notification.Name("bear-mcp.did-receive-incoming-callback-url")
}
