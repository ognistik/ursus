import BearCore
import Foundation
import MCP

enum MCPArgumentDecoder {
    static func string(_ arguments: [String: Value]?, _ key: String) throws -> String {
        guard let value = arguments?[key]?.stringValue, !value.isEmpty else {
            throw BearError.invalidInput("Missing required string argument '\(key)'.")
        }
        return value
    }

    static func optionalString(_ arguments: [String: Value]?, _ key: String) -> String? {
        arguments?[key]?.stringValue
    }

    static func int(_ arguments: [String: Value]?, _ key: String, default defaultValue: Int) -> Int {
        arguments?[key]?.intValue ?? defaultValue
    }

    static func bool(_ arguments: [String: Value]?, _ key: String, default defaultValue: Bool) -> Bool {
        arguments?[key]?.boolValue ?? defaultValue
    }

    static func stringArray(_ arguments: [String: Value]?, _ key: String, default defaultValue: [String] = []) -> [String] {
        arguments?[key]?.arrayValue?.compactMap(\.stringValue) ?? defaultValue
    }

    static func objectArray(_ arguments: [String: Value]?, _ key: String) -> [[String: Value]] {
        arguments?[key]?.arrayValue?.compactMap(\.objectValue) ?? []
    }

    static func scope(_ arguments: [String: Value]?, _ key: String = "scope") throws -> BearScope {
        guard let raw = optionalString(arguments, key) else {
            return .all
        }
        guard let scope = BearScope(rawValue: raw) else {
            throw BearError.invalidInput("Invalid scope '\(raw)'. Expected 'all' or 'active'.")
        }
        return scope
    }

    static func replaceMode(_ object: [String: Value], _ key: String = "mode") throws -> ReplaceMode {
        guard let raw = object[key]?.stringValue else {
            return .exact
        }
        guard let mode = ReplaceMode(rawValue: raw) else {
            throw BearError.invalidInput("Invalid replace mode '\(raw)'.")
        }
        return mode
    }

    static func presentation(_ object: [String: Value], defaults: BearPresentationOptions) -> BearPresentationOptions {
        let openNoteOverride = object["open_note"]?.boolValue
        let newWindowOverride = object["new_window"]?.boolValue

        return BearPresentationOptions(
            openNote: openNoteOverride ?? defaults.openNote,
            openNoteOverride: openNoteOverride,
            newWindow: newWindowOverride ?? defaults.newWindow,
            newWindowOverride: newWindowOverride,
            showWindow: object["show_window"]?.boolValue ?? defaults.showWindow,
            edit: object["edit"]?.boolValue ?? defaults.edit
        )
    }

    static func position(_ object: [String: Value], default defaultValue: InsertPosition) throws -> InsertPosition {
        guard let raw = object["position"]?.stringValue else {
            return defaultValue
        }
        switch raw {
        case "top":
            return .top
        case "bottom":
            return .bottom
        default:
            throw BearError.invalidInput("Invalid insert position '\(raw)'. Expected 'top' or 'bottom'.")
        }
    }
}
