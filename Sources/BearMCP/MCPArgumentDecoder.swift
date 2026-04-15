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

    static func optionalString(_ object: [String: Value], _ key: String) -> String? {
        object[key]?.stringValue
    }

    static func int(_ arguments: [String: Value]?, _ key: String, default defaultValue: Int) -> Int {
        arguments?[key]?.intValue ?? defaultValue
    }

    static func optionalInt(_ arguments: [String: Value]?, _ key: String) -> Int? {
        arguments?[key]?.intValue
    }

    static func optionalInt(_ object: [String: Value], _ key: String) -> Int? {
        object[key]?.intValue
    }

    static func bool(_ arguments: [String: Value]?, _ key: String, default defaultValue: Bool) -> Bool {
        arguments?[key]?.boolValue ?? defaultValue
    }

    static func stringArray(_ arguments: [String: Value]?, _ key: String, default defaultValue: [String] = []) -> [String] {
        arguments?[key]?.arrayValue?.compactMap(\.stringValue) ?? defaultValue
    }

    static func stringArray(_ object: [String: Value], _ key: String, default defaultValue: [String] = []) -> [String] {
        object[key]?.arrayValue?.compactMap(\.stringValue) ?? defaultValue
    }

    static func objectArray(_ arguments: [String: Value]?, _ key: String) -> [[String: Value]] {
        arguments?[key]?.arrayValue?.compactMap(\.objectValue) ?? []
    }

    static func location(_ arguments: [String: Value]?, _ key: String = "location") throws -> BearNoteLocation {
        guard let raw = optionalString(arguments, key) else {
            return .notes
        }
        guard let location = BearNoteLocation(rawValue: raw) else {
            throw BearError.invalidInput("Invalid location '\(raw)'. Expected 'notes' or 'archive'.")
        }
        return location
    }

    static func location(_ object: [String: Value], _ key: String = "location") throws -> BearNoteLocation {
        guard let raw = optionalString(object, key) else {
            return .notes
        }
        guard let location = BearNoteLocation(rawValue: raw) else {
            throw BearError.invalidInput("Invalid location '\(raw)'. Expected 'notes' or 'archive'.")
        }
        return location
    }

    static func findTextMode(_ object: [String: Value], _ key: String = "text_mode") throws -> FindTextMode {
        guard let raw = optionalString(object, key) else {
            return .substring
        }
        guard let mode = FindTextMode(rawValue: raw) else {
            throw BearError.invalidInput("Invalid text mode '\(raw)'.")
        }
        return mode
    }

    static func findTagMatchMode(_ object: [String: Value], key: String) throws -> FindTagMatchMode {
        guard let raw = optionalString(object, key) else {
            return .any
        }
        guard let mode = FindTagMatchMode(rawValue: raw) else {
            throw BearError.invalidInput("Invalid tag match mode '\(raw)'.")
        }
        return mode
    }

    static func optionalFindTagMatchMode(_ object: [String: Value], key: String) throws -> FindTagMatchMode? {
        guard let raw = optionalString(object, key) else {
            return nil
        }
        guard let mode = FindTagMatchMode(rawValue: raw) else {
            throw BearError.invalidInput("Invalid tag match mode '\(raw)'.")
        }
        return mode
    }

    static func optionalFindDateField(_ object: [String: Value], key: String) throws -> FindDateField? {
        guard let raw = optionalString(object, key) else {
            return nil
        }
        guard let field = FindDateField(rawValue: raw) else {
            throw BearError.invalidInput("Invalid date field '\(raw)'.")
        }
        return field
    }

    static func findSearchFields(_ object: [String: Value], key: String = "search_fields") throws -> [FindSearchField] {
        let rawFields = stringArray(object, key)
        return try rawFields.map { raw in
            guard let field = FindSearchField(rawValue: raw) else {
                throw BearError.invalidInput("Invalid search field '\(raw)'.")
            }
            return field
        }
    }

    static func replaceContentKind(_ object: [String: Value], _ key: String = "kind") throws -> ReplaceContentKind {
        guard let raw = object[key]?.stringValue else {
            throw BearError.invalidInput("Missing required string argument '\(key)'.")
        }
        guard let kind = ReplaceContentKind(rawValue: raw) else {
            throw BearError.invalidInput("Invalid replace content kind '\(raw)'.")
        }
        return kind
    }

    static func replaceStringOccurrence(_ object: [String: Value], _ key: String = "occurrence") throws -> ReplaceStringOccurrence? {
        guard let raw = object[key]?.stringValue else {
            return nil
        }
        guard let occurrence = ReplaceStringOccurrence(rawValue: raw) else {
            throw BearError.invalidInput("Invalid replace occurrence '\(raw)'.")
        }
        return occurrence
    }

    static func optionalBool(_ object: [String: Value], _ key: String) throws -> Bool? {
        guard let value = object[key] else {
            return nil
        }
        guard let raw = value.boolValue else {
            throw BearError.invalidInput("Invalid boolean '\(key)'. Expected true or false.")
        }
        return raw
    }

    static func optionalBool(_ arguments: [String: Value]?, _ key: String) throws -> Bool? {
        guard let value = arguments?[key] else {
            return nil
        }
        guard let raw = value.boolValue else {
            throw BearError.invalidInput("Invalid boolean '\(key)'. Expected true or false.")
        }
        return raw
    }

    static func openNotePresentation(_ object: [String: Value], defaultNewWindow: Bool) throws -> BearPresentationOptions {
        let newWindowOverride = try optionalBool(object, "new_window")

        return BearPresentationOptions(
            openNote: true,
            newWindow: newWindowOverride ?? defaultNewWindow,
            newWindowOverride: newWindowOverride,
            showWindow: true,
            edit: true
        )
    }

    static func optionalPosition(_ object: [String: Value], key: String = "position") throws -> InsertPosition? {
        guard let raw = object[key]?.stringValue else {
            return nil
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

    static func position(_ object: [String: Value], default defaultValue: InsertPosition) throws -> InsertPosition {
        try optionalPosition(object) ?? defaultValue
    }

    static func relativeTextTarget(_ object: [String: Value], key: String = "target") throws -> RelativeTextTarget? {
        guard let targetObject = object[key]?.objectValue else {
            return nil
        }

        guard let text = targetObject["text"]?.stringValue, !text.isEmpty else {
            throw BearError.invalidInput("Target objects require a non-empty string `text`.")
        }

        let targetKind: RelativeTargetKind
        if let rawTargetKind = targetObject["target_kind"]?.stringValue {
            guard let decoded = RelativeTargetKind(rawValue: rawTargetKind) else {
                throw BearError.invalidInput("Invalid target kind '\(rawTargetKind)'. Expected 'heading' or 'string'.")
            }
            targetKind = decoded
        } else {
            targetKind = .string
        }

        guard let rawPlacement = targetObject["placement"]?.stringValue else {
            throw BearError.invalidInput("Target objects require a `placement` of 'before' or 'after'.")
        }
        guard let placement = RelativeTargetPlacement(rawValue: rawPlacement) else {
            throw BearError.invalidInput("Invalid target placement '\(rawPlacement)'. Expected 'before' or 'after'.")
        }

        return RelativeTextTarget(text: text, targetKind: targetKind, placement: placement)
    }

    static func position(_ object: [String: Value], default defaultValue: InsertPosition, key: String) throws -> InsertPosition {
        try optionalPosition(object, key: key) ?? defaultValue
    }
}
