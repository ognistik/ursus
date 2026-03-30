import AppKit
import BearCore
import Foundation

public enum BearSelectedNoteCallbackOutputChannel {
    case stdout
    case stderr
}

@MainActor
public final class BearSelectedNoteCallbackHost {
    nonisolated public static let helperCallbackScheme = "bearmcphelper"
    nonisolated public static let defaultCallbackScheme = helperCallbackScheme
    nonisolated public static let defaultTimeoutSeconds: TimeInterval = 8

    public private(set) var exitCode: Int32 = 1

    private let callbackScheme: String
    private let defaultTimeoutSeconds: TimeInterval
    private let outputWriter: (Data, BearSelectedNoteCallbackOutputChannel) -> Void
    private let responseFileWriter: (Data, URL) throws -> Void
    private let requestURLAuthorizer: ((URL) throws -> URL)?
    private let urlOpener: (URL, Bool, @escaping @Sendable (Error?) -> Void) -> Void
    private let terminator: () -> Void

    private var completed = false
    private var expectedStateToken: String?
    private var responseFileURL: URL?

    public init(
        callbackScheme: String = BearSelectedNoteCallbackHost.defaultCallbackScheme,
        defaultTimeoutSeconds: TimeInterval = BearSelectedNoteCallbackHost.defaultTimeoutSeconds,
        outputWriter: ((Data, BearSelectedNoteCallbackOutputChannel) -> Void)? = nil,
        responseFileWriter: ((Data, URL) throws -> Void)? = nil,
        requestURLAuthorizer: ((URL) throws -> URL)? = nil,
        urlOpener: ((URL, Bool, @escaping @Sendable (Error?) -> Void) -> Void)? = nil,
        terminator: (() -> Void)? = nil
    ) {
        self.callbackScheme = callbackScheme
        self.defaultTimeoutSeconds = defaultTimeoutSeconds
        self.outputWriter = outputWriter ?? Self.defaultOutputWriter
        self.responseFileWriter = responseFileWriter ?? Self.defaultResponseFileWriter
        self.requestURLAuthorizer = requestURLAuthorizer
        self.urlOpener = urlOpener ?? Self.defaultOpenBearURL
        self.terminator = terminator ?? { NSApp.terminate(nil) }
    }

    public func start(arguments: [String], userDefaults: UserDefaults = .standard) {
        do {
            let invocation = try parseInvocation(arguments: arguments, userDefaults: userDefaults)
            expectedStateToken = invocation.stateToken
            responseFileURL = invocation.responseFileURL
            scheduleTimeout(seconds: invocation.timeoutSeconds)
            openBearURL(invocation.requestURL, activateApp: invocation.activateApp)
        } catch {
            finishWithError(message: error.localizedDescription)
        }
    }

    public func handleAppleEvent(_ event: NSAppleEventDescriptor) {
        guard !completed else {
            return
        }

        guard
            let rawURL = event.paramDescriptor(forKeyword: AEKeyword(keyDirectObject))?.stringValue,
            let url = URL(string: rawURL)
        else {
            finishWithError(message: "Selected-note callback host received a malformed callback URL.")
            return
        }

        handleCallbackURL(url)
    }

    public func handleCallbackURL(_ url: URL) {
        guard !completed else {
            return
        }

        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            finishWithError(message: "Selected-note callback host received a malformed callback URL.")
            return
        }

        let action = components.path.split(separator: "/").last.map(String.init) ?? ""
        let payload = dictionary(from: components.queryItems ?? [])

        if let expectedStateToken, payload["state"] != expectedStateToken {
            finishWithError(message: "Selected-note callback host received a callback for a different request.")
            return
        }

        switch action {
        case "handle-success":
            guard payload["identifier"] != nil || payload["id"] != nil else {
                finishWithError(message: "Selected-note callback host did not receive a note identifier.")
                return
            }
            finishSuccessfully(payload: payload)
        case "handle-error":
            let message = payload["errorMessage"] ?? payload["error"] ?? "Bear did not return the selected note."
            finishWithPayload(["errorMessage": message], to: .stderr, exitCode: 1)
        default:
            finishWithError(message: "Selected-note callback host received an unrecognized callback path.")
        }
    }

    private func parseInvocation(arguments: [String], userDefaults: UserDefaults) throws -> Invocation {
        let fallbackArguments = argumentDictionary(arguments: arguments)
        let requestURLString = userDefaults.string(forKey: "url") ?? fallbackArguments["url"]
        let activateApp = userDefaults.object(forKey: "activateApp") != nil
            ? userDefaults.bool(forKey: "activateApp")
            : normalizedBool(fallbackArguments["activateApp"] ?? "NO")
        var timeoutSeconds = defaultTimeoutSeconds
        var responseFileURL: URL?
        let stateToken = UUID().uuidString.replacingOccurrences(of: "-", with: "")

        if let timeoutString = userDefaults.string(forKey: "timeoutSeconds") ?? fallbackArguments["timeoutSeconds"] {
            guard let parsed = TimeInterval(timeoutString), parsed > 0 else {
                throw HelperError.invalidInvocation("Invalid `-timeoutSeconds` value `\(timeoutString)`.")
            }
            timeoutSeconds = parsed
        }

        if let responseFilePath = userDefaults.string(forKey: "responseFile") ?? fallbackArguments["responseFile"] {
            responseFileURL = URL(fileURLWithPath: NSString(string: responseFilePath).expandingTildeInPath)
        }

        guard let requestURLString else {
            throw HelperError.invalidInvocation("Missing required `-url` argument.")
        }

        guard let requestURL = URL(string: requestURLString) else {
            throw HelperError.invalidInvocation("Invalid Bear URL `\(requestURLString)`.")
        }

        let authorizedRequestURL: URL
        do {
            authorizedRequestURL = try requestURLAuthorizer?(requestURL) ?? requestURL
        } catch {
            throw HelperError.invalidInvocation(error.localizedDescription)
        }

        return Invocation(
            requestURL: try requestURLWithCallbacks(authorizedRequestURL, stateToken: stateToken),
            activateApp: activateApp,
            timeoutSeconds: timeoutSeconds,
            stateToken: stateToken,
            responseFileURL: responseFileURL
        )
    }

    private func argumentDictionary(arguments: [String]) -> [String: String] {
        var result: [String: String] = [:]
        var index = 1

        while index < arguments.count {
            let argument = arguments[index]
            guard argument.hasPrefix("-") else {
                index += 1
                continue
            }

            let key = String(argument.drop(while: { $0 == "-" }))
            let nextIndex = index + 1
            guard nextIndex < arguments.count else {
                break
            }

            result[key] = arguments[nextIndex]
            index += 2
        }

        return result
    }

    private func requestURLWithCallbacks(_ url: URL, stateToken: String) throws -> URL {
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            throw HelperError.invalidInvocation("Invalid Bear URL.")
        }

        var items = (components.queryItems ?? []).filter { item in
            item.name != "x-success" && item.name != "x-error"
        }
        items.append(URLQueryItem(name: "x-success", value: "\(callbackScheme)://x-callback-url/handle-success?state=\(stateToken)"))
        items.append(URLQueryItem(name: "x-error", value: "\(callbackScheme)://x-callback-url/handle-error?state=\(stateToken)"))
        components.queryItems = items

        guard let resolvedURL = components.url else {
            throw HelperError.invalidInvocation("Failed to prepare Bear callback URL.")
        }

        return resolvedURL
    }

    private func openBearURL(_ url: URL, activateApp: Bool) {
        urlOpener(url, activateApp) { [weak self] error in
            guard let error else {
                return
            }

            Task { @MainActor in
                self?.finishWithError(message: "Bear did not accept the selected-note callback request. \(error.localizedDescription)")
            }
        }
    }

    private func scheduleTimeout(seconds: TimeInterval) {
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds) { [weak self] in
            Task { @MainActor in
                guard let self, !self.completed else {
                    return
                }
                self.finishWithError(message: "Selected-note callback host timed out while waiting for Bear to call back.")
            }
        }
    }

    private func finishSuccessfully(payload: [String: String]) {
        finishWithPayload(payload, to: .stdout, exitCode: 0)
    }

    private func finishWithError(message: String) {
        finishWithPayload(["errorMessage": message], to: .stderr, exitCode: 1)
    }

    private func finishWithPayload(
        _ payload: [String: String],
        to channel: BearSelectedNoteCallbackOutputChannel,
        exitCode: Int32
    ) {
        guard !completed else {
            return
        }

        completed = true
        self.exitCode = exitCode

        let data: Data
        do {
            data = try JSONSerialization.data(withJSONObject: payload, options: [.prettyPrinted, .sortedKeys])
        } catch {
            outputWriter(Data("{\"errorMessage\":\"Failed to encode selected-note callback response.\"}\n".utf8), channel)
            terminator()
            return
        }

        if let responseFileURL {
            try? responseFileWriter(data, responseFileURL)
        }

        var text = String(decoding: data, as: UTF8.self)
        text.append("\n")
        outputWriter(Data(text.utf8), channel)
        terminator()
    }

    private func dictionary(from queryItems: [URLQueryItem]) -> [String: String] {
        var result: [String: String] = [:]
        for item in queryItems {
            result[item.name] = item.value ?? ""
        }
        return result
    }

    private func normalizedBool(_ value: String) -> Bool {
        switch value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "yes", "true", "1":
            return true
        default:
            return false
        }
    }

    private static func defaultOutputWriter(_ data: Data, channel: BearSelectedNoteCallbackOutputChannel) {
        switch channel {
        case .stdout:
            FileHandle.standardOutput.write(data)
        case .stderr:
            FileHandle.standardError.write(data)
        }
    }

    private static func defaultResponseFileWriter(_ data: Data, url: URL) throws {
        try data.write(to: url, options: .atomic)
    }

    private static func defaultOpenBearURL(
        _ url: URL,
        activateApp: Bool,
        completion: @escaping @Sendable (Error?) -> Void
    ) {
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = activateApp

        NSWorkspace.shared.open(url, configuration: configuration) { _, error in
            completion(error)
        }
    }
}

private struct Invocation {
    let requestURL: URL
    let activateApp: Bool
    let timeoutSeconds: TimeInterval
    let stateToken: String
    let responseFileURL: URL?
}

private enum HelperError: LocalizedError {
    case invalidInvocation(String)

    var errorDescription: String? {
        switch self {
        case .invalidInvocation(let message):
            return message
        }
    }
}
