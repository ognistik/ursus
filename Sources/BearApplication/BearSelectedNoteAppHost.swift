import AppKit
import BearXCallback
import Foundation

public enum BearMCPAppLaunchMode: Sendable {
    case dashboard
    case selectedNoteCallbackHost
}

@MainActor
public final class BearSelectedNoteAppHost {
    public let launchMode: BearMCPAppLaunchMode

    private let callbackHostFactory: (@escaping @MainActor @Sendable () -> Void) -> BearSelectedNoteCallbackHost
    private var callbackHost: BearSelectedNoteCallbackHost?

    public init(
        arguments: [String] = CommandLine.arguments,
        userDefaults: UserDefaults = .standard,
        callbackHostFactory: @escaping (@escaping @MainActor @Sendable () -> Void) -> BearSelectedNoteCallbackHost = {
            completion in
            BearSelectedNoteCallbackHost(
                callbackScheme: BearSelectedNoteCallbackHost.appCallbackScheme,
                terminator: {
                    Task { @MainActor in
                        completion()
                    }
                }
            )
        }
    ) {
        self.callbackHostFactory = callbackHostFactory

        if Self.shouldRunHeadless(arguments: arguments, userDefaults: userDefaults) {
            launchMode = .selectedNoteCallbackHost
            callbackHost = makeHeadlessCallbackHost()
        } else {
            launchMode = .dashboard
            callbackHost = nil
        }
    }

    public var runsHeadless: Bool {
        launchMode == .selectedNoteCallbackHost
    }

    nonisolated public static func shouldRunHeadless(
        arguments: [String] = CommandLine.arguments,
        userDefaults: UserDefaults = .standard
    ) -> Bool {
        if userDefaults.string(forKey: "url") != nil {
            return true
        }

        return argumentDictionary(arguments: arguments)["url"] != nil
    }

    public func configureApplication(_ application: NSApplication = .shared) {
        guard runsHeadless else {
            return
        }

        application.setActivationPolicy(.prohibited)
    }

    public func start(
        arguments: [String] = CommandLine.arguments,
        userDefaults: UserDefaults = .standard
    ) {
        callbackHost?.start(arguments: arguments, userDefaults: userDefaults)
    }

    @discardableResult
    public func handleIncomingURL(_ url: URL) -> Bool {
        if BearSelectedNoteAppRequest.matches(url) {
            do {
                let request = try BearSelectedNoteAppRequest(url: url)
                startCallbackHostIfNeeded(with: request)
            } catch {
                writeFailureResponse(for: url, message: error.localizedDescription)
            }
            return true
        }

        guard let callbackHost else {
            return false
        }

        callbackHost.handleCallbackURL(url)
        return true
    }

    private func startCallbackHostIfNeeded(with request: BearSelectedNoteAppRequest) {
        guard launchMode == .dashboard else {
            callbackHost?.start(arguments: request.commandLineArguments)
            return
        }

        guard callbackHost == nil else {
            writeFailureResponse(
                for: request,
                message: "Selected-note callback host is already resolving another request."
            )
            return
        }

        let host = makeDashboardCallbackHost()
        callbackHost = host
        host.start(arguments: request.commandLineArguments)
    }

    private func makeHeadlessCallbackHost() -> BearSelectedNoteCallbackHost {
        callbackHostFactory {
            NSApp.terminate(nil)
        }
    }

    private func makeDashboardCallbackHost() -> BearSelectedNoteCallbackHost {
        callbackHostFactory { [weak self] in
            self?.callbackHost = nil
        }
    }

    private func writeFailureResponse(for url: URL, message: String) {
        guard let request = try? BearSelectedNoteAppRequest(url: url) else {
            return
        }

        writeFailureResponse(for: request, message: message)
    }

    private func writeFailureResponse(for request: BearSelectedNoteAppRequest, message: String) {
        guard let responseFileURL = request.responseFileURL else {
            return
        }

        let data = (try? JSONSerialization.data(
            withJSONObject: ["errorMessage": message],
            options: [.prettyPrinted, .sortedKeys]
        )) ?? Data("{\"errorMessage\":\"\(message)\"}\n".utf8)
        try? data.write(to: responseFileURL, options: .atomic)
    }

    nonisolated private static func argumentDictionary(arguments: [String]) -> [String: String] {
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
}
