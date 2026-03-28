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

    private let callbackHost: BearSelectedNoteCallbackHost?

    public init(
        arguments: [String] = CommandLine.arguments,
        userDefaults: UserDefaults = .standard
    ) {
        if Self.shouldRunHeadless(arguments: arguments, userDefaults: userDefaults) {
            launchMode = .selectedNoteCallbackHost
            callbackHost = BearSelectedNoteCallbackHost(callbackScheme: BearSelectedNoteCallbackHost.appCallbackScheme)
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
        guard let callbackHost else {
            return false
        }

        callbackHost.handleCallbackURL(url)
        return true
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
