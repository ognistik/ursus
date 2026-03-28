import Foundation

public struct BearSelectedNoteAppRequest: Sendable, Equatable {
    public static let callbackHost = "x-callback-url"
    public static let action = "start-selected-note-host"

    public let requestURL: URL
    public let activateApp: Bool
    public let responseFileURL: URL?
    public let timeoutSeconds: TimeInterval?

    public init(
        requestURL: URL,
        activateApp: Bool,
        responseFileURL: URL? = nil,
        timeoutSeconds: TimeInterval? = nil
    ) {
        self.requestURL = requestURL
        self.activateApp = activateApp
        self.responseFileURL = responseFileURL
        self.timeoutSeconds = timeoutSeconds
    }

    public var url: URL {
        var components = URLComponents()
        components.scheme = BearSelectedNoteCallbackHost.appCallbackScheme
        components.host = Self.callbackHost
        components.path = "/\(Self.action)"
        components.queryItems = queryItems

        return components.url!
    }

    public var commandLineArguments: [String] {
        var arguments = [
            "Bear MCP",
            "-url", requestURL.absoluteString,
            "-activateApp", activateApp ? "YES" : "NO",
        ]

        if let responseFileURL {
            arguments.append(contentsOf: ["-responseFile", responseFileURL.path])
        }

        if let timeoutSeconds {
            arguments.append(contentsOf: ["-timeoutSeconds", String(timeoutSeconds)])
        }

        return arguments
    }

    public static func matches(_ url: URL) -> Bool {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return false
        }

        let action = components.path.split(separator: "/").last.map(String.init)
        return components.scheme == BearSelectedNoteCallbackHost.appCallbackScheme
            && components.host == callbackHost
            && action == Self.action
    }

    public init(url: URL) throws {
        guard Self.matches(url) else {
            throw ParseError.unrecognizedURL
        }

        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            throw ParseError.invalidURL("Malformed app request URL.")
        }

        let queryItems = Self.dictionary(from: components.queryItems ?? [])

        guard let requestURLString = queryItems["url"], !requestURLString.isEmpty else {
            throw ParseError.invalidURL("Missing Bear request URL.")
        }

        guard let requestURL = URL(string: requestURLString) else {
            throw ParseError.invalidURL("Invalid Bear request URL.")
        }

        let activateApp = Self.normalizedBool(queryItems["activateApp"] ?? "NO")
        let responseFileURL: URL? = queryItems["responseFile"].flatMap { value -> URL? in
            guard !value.isEmpty else {
                return nil
            }
            return URL(fileURLWithPath: NSString(string: value).expandingTildeInPath)
        }

        let timeoutSeconds: TimeInterval?
        if let value = queryItems["timeoutSeconds"], !value.isEmpty {
            guard let parsed = TimeInterval(value), parsed > 0 else {
                throw ParseError.invalidURL("Invalid timeout value `\(value)`.")
            }
            timeoutSeconds = parsed
        } else {
            timeoutSeconds = nil
        }

        self.init(
            requestURL: requestURL,
            activateApp: activateApp,
            responseFileURL: responseFileURL,
            timeoutSeconds: timeoutSeconds
        )
    }

    private var queryItems: [URLQueryItem] {
        var items = [
            URLQueryItem(name: "url", value: requestURL.absoluteString),
            URLQueryItem(name: "activateApp", value: activateApp ? "YES" : "NO"),
        ]

        if let responseFileURL {
            items.append(URLQueryItem(name: "responseFile", value: responseFileURL.path))
        }

        if let timeoutSeconds {
            items.append(URLQueryItem(name: "timeoutSeconds", value: String(timeoutSeconds)))
        }

        return items
    }

    private static func dictionary(from queryItems: [URLQueryItem]) -> [String: String] {
        var result: [String: String] = [:]
        for item in queryItems {
            result[item.name] = item.value ?? ""
        }
        return result
    }

    private static func normalizedBool(_ value: String) -> Bool {
        switch value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "yes", "true", "1":
            return true
        default:
            return false
        }
    }

    public enum ParseError: LocalizedError {
        case unrecognizedURL
        case invalidURL(String)

        public var errorDescription: String? {
            switch self {
            case .unrecognizedURL:
                return "The URL does not match the selected-note app request format."
            case .invalidURL(let message):
                return message
            }
        }
    }
}
