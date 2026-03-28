import AppKit
import BearApplication
import Combine
import Foundation

@MainActor
final class BearMCPAppModel: ObservableObject {
    let runsHeadlessCallbackHost: Bool

    @Published private(set) var dashboard = BearAppSupport.loadDashboardSnapshot()
    @Published private(set) var lastIncomingCallbackURL: URL?

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
        dashboard = BearAppSupport.loadDashboardSnapshot()
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
}

extension Notification.Name {
    static let bearMCPDidReceiveIncomingCallbackURL = Notification.Name("bear-mcp.did-receive-incoming-callback-url")
}
