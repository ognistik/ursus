import AppKit
import Foundation

private let callbackScheme = "bearmcphelper"
private let defaultTimeoutSeconds: TimeInterval = 8

@main
struct BearSelectedNoteHelperEntry {
    @MainActor
    static func main() {
        let app = NSApplication.shared
        let delegate = BearSelectedNoteHelperAppDelegate()
        app.setActivationPolicy(.prohibited)
        app.delegate = delegate
        withExtendedLifetime(delegate) {
            app.run()
        }
        Foundation.exit(delegate.exitCode)
    }
}

@MainActor
final class BearSelectedNoteHelperAppDelegate: NSObject, NSApplicationDelegate {
    private let stdout = FileHandle.standardOutput
    private let stderr = FileHandle.standardError
    fileprivate private(set) var exitCode: Int32 = 1
    private var completed = false
    private var expectedStateToken: String?
    private var responseFileURL: URL?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSAppleEventManager.shared().setEventHandler(
            self,
            andSelector: #selector(handleURLAppleEvent(_:withReplyEvent:)),
            forEventClass: AEEventClass(kInternetEventClass),
            andEventID: AEEventID(kAEGetURL)
        )

        do {
            let invocation = try parseInvocation(arguments: CommandLine.arguments)
            expectedStateToken = invocation.stateToken
            responseFileURL = invocation.responseFileURL
            try scheduleTimeout(seconds: invocation.timeoutSeconds)
            try openBearURL(invocation.requestURL, activateApp: invocation.activateApp)
        } catch {
            finishWithError(message: error.localizedDescription)
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        NSAppleEventManager.shared().removeEventHandler(
            forEventClass: AEEventClass(kInternetEventClass),
            andEventID: AEEventID(kAEGetURL)
        )
    }

    @objc
    private func handleURLAppleEvent(_ event: NSAppleEventDescriptor, withReplyEvent replyEvent: NSAppleEventDescriptor) {
        guard !completed else {
            return
        }

        guard
            let rawURL = event.paramDescriptor(forKeyword: AEKeyword(keyDirectObject))?.stringValue,
            let url = URL(string: rawURL),
            let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        else {
            finishWithError(message: "Selected-note helper received a malformed callback URL.")
            return
        }

        let action = components.path.split(separator: "/").last.map(String.init) ?? ""
        let payload = dictionary(from: components.queryItems ?? [])

        if let expectedStateToken, payload["state"] != expectedStateToken {
            finishWithError(message: "Selected-note helper received a callback for a different request.")
            return
        }

        switch action {
        case "handle-success":
            guard payload["identifier"] != nil || payload["id"] != nil else {
                finishWithError(message: "Selected-note helper callback did not include a note identifier.")
                return
            }
            finishSuccessfully(payload: payload)
        case "handle-error":
            let message = payload["errorMessage"] ?? payload["error"] ?? "Bear did not return the selected note."
            finishWithPayload(["errorMessage": message], to: stderr, exitCode: 1)
        default:
            finishWithError(message: "Selected-note helper received an unrecognized callback path.")
        }
    }

    private func parseInvocation(arguments: [String]) throws -> Invocation {
        let defaults = UserDefaults.standard
        let fallbackArguments = argumentDictionary(arguments: arguments)
        var requestURLString = defaults.string(forKey: "url") ?? fallbackArguments["url"]
        var activateApp = defaults.object(forKey: "activateApp") != nil
            ? defaults.bool(forKey: "activateApp")
            : normalizedBool(fallbackArguments["activateApp"] ?? "NO")
        var timeoutSeconds = defaultTimeoutSeconds
        var responseFileURL: URL?
        let stateToken = UUID().uuidString.replacingOccurrences(of: "-", with: "")

        if let timeoutString = defaults.string(forKey: "timeoutSeconds") ?? fallbackArguments["timeoutSeconds"] {
            guard let parsed = TimeInterval(timeoutString), parsed > 0 else {
                throw HelperError.invalidInvocation("Invalid `-timeoutSeconds` value `\(timeoutString)`.")
            }
            timeoutSeconds = parsed
        }

        if let responseFilePath = defaults.string(forKey: "responseFile") ?? fallbackArguments["responseFile"] {
            responseFileURL = URL(fileURLWithPath: NSString(string: responseFilePath).expandingTildeInPath)
        }

        guard let requestURLString else {
            throw HelperError.invalidInvocation("Missing required `-url` argument.")
        }

        guard let requestURL = URL(string: requestURLString) else {
            throw HelperError.invalidInvocation("Invalid Bear URL `\(requestURLString)`.")
        }

        return Invocation(
            requestURL: try requestURLWithCallbacks(requestURL, stateToken: stateToken),
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

    private func openBearURL(_ url: URL, activateApp: Bool) throws {
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = activateApp

        NSWorkspace.shared.open(url, configuration: configuration) { [weak self] _, error in
            if let error {
                Task { @MainActor in
                    self?.finishWithError(message: "Bear did not accept the selected-note helper request. \(error.localizedDescription)")
                }
            }
        }
    }

    private func scheduleTimeout(seconds: TimeInterval) throws {
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds) { [weak self] in
            Task { @MainActor in
                guard let self, !self.completed else {
                    return
                }
                self.finishWithError(message: "Selected-note helper timed out while waiting for Bear to call back.")
            }
        }
    }

    private func finishSuccessfully(payload: [String: String]) {
        finishWithPayload(payload, to: stdout, exitCode: 0)
    }

    private func finishWithError(message: String) {
        finishWithPayload(["errorMessage": message], to: stderr, exitCode: 1)
    }

    private func finishWithPayload(_ payload: [String: String], to handle: FileHandle, exitCode: Int32) {
        guard !completed else {
            return
        }

        completed = true
        self.exitCode = exitCode

        let data: Data
        do {
            data = try JSONSerialization.data(withJSONObject: payload, options: [.prettyPrinted, .sortedKeys])
        } catch {
            let fallback = "{\"errorMessage\":\"Failed to encode selected-note helper response.\"}\n"
            handle.write(Data(fallback.utf8))
            NSApp.terminate(nil)
            return
        }

        var text = String(decoding: data, as: UTF8.self)
        text.append("\n")
        if let responseFileURL {
            try? data.write(to: responseFileURL, options: .atomic)
        }
        handle.write(Data(text.utf8))
        NSApp.terminate(nil)
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
