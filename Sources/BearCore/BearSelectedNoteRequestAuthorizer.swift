import Foundation

public enum BearSelectedNoteRequestAuthorizer {
    public static func prepareManagedRequestURL(
        _ requestURL: URL,
        fileManager: FileManager = .default,
        configFileURL: URL = BearPaths.configFileURL,
        tokenStore: any BearSelectedNoteTokenStore = BearKeychainSelectedNoteTokenStore()
    ) throws -> URL {
        guard requiresManagedSelectedNoteTokenInjection(requestURL) else {
            return requestURL
        }

        let configuration: BearConfiguration
        if fileManager.fileExists(atPath: configFileURL.path) {
            configuration = try BearConfiguration.load(from: configFileURL)
        } else {
            configuration = .default
        }

        guard let token = try BearSelectedNoteTokenResolver.resolve(
            configuration: configuration,
            tokenStore: tokenStore
        )?.value else {
            throw BearError.invalidInput("Selected-note targeting requires a configured Bear API token.")
        }

        guard var components = URLComponents(url: requestURL, resolvingAgainstBaseURL: false) else {
            throw BearError.invalidInput("Invalid Bear selected-note request URL.")
        }

        var queryItems = components.queryItems ?? []
        queryItems.append(URLQueryItem(name: "token", value: token))
        components.queryItems = queryItems

        guard let resolvedURL = components.url else {
            throw BearError.invalidInput("Failed to prepare the Bear selected-note request URL.")
        }

        return resolvedURL
    }

    private static func requiresManagedSelectedNoteTokenInjection(_ requestURL: URL) -> Bool {
        guard
            let components = URLComponents(url: requestURL, resolvingAgainstBaseURL: false),
            components.scheme == "bear",
            components.host == "x-callback-url",
            components.path == "/open-note"
        else {
            return false
        }

        let queryItems = components.queryItems ?? []
        let selectedRequested = queryItems.contains {
            $0.name == "selected" && normalizedYesNo($0.value) == true
        }
        let tokenPresent = queryItems.contains { $0.name == "token" && !($0.value ?? "").isEmpty }

        return selectedRequested && !tokenPresent
    }

    private static func normalizedYesNo(_ value: String?) -> Bool {
        switch value?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "yes", "true", "1":
            return true
        default:
            return false
        }
    }
}
