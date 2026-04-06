import BearCore
import Foundation

enum BearCLICommand {
    struct NewNoteOptions: Hashable {
        let title: String?
        let tags: [String]?
        let replaceTags: Bool
        let content: String?
        let openNote: Bool
        let newWindow: Bool
    }

    struct RestoreNoteRequest: Hashable {
        let noteID: String
        let snapshotID: String
    }

    enum BridgeSubcommand: Hashable {
        case serve
        case status
        case printURL
        case help
    }

    case mcp
    case bridge(BridgeSubcommand)
    case doctor
    case paths
    case newNote(NewNoteOptions?)
    case backupNote([String])
    case restoreNote([RestoreNoteRequest])
    case applyTemplate([String])
    case help

    static func parse(arguments: [String]) throws -> BearCLICommand {
        guard let command = arguments.first else {
            return .mcp
        }

        let remainingArguments = Array(arguments.dropFirst())

        switch command {
        case "mcp":
            try assertNoExtraArguments(remainingArguments, for: "mcp")
            return .mcp
        case "bridge":
            return try parseBridgeCommand(remainingArguments)
        case "doctor":
            try assertNoExtraArguments(remainingArguments, for: "doctor")
            return .doctor
        case "paths":
            try assertNoExtraArguments(remainingArguments, for: "paths")
            return .paths
        case "--new-note":
            return .newNote(try parseNewNoteOptions(remainingArguments))
        case "--backup-note":
            return .backupNote(remainingArguments)
        case "--restore-note":
            return .restoreNote(try parseRestoreNoteRequests(remainingArguments))
        case "--apply-template":
            return .applyTemplate(remainingArguments)
        case "--help", "-h", "help":
            return .help
        default:
            throw BearError.invalidInput("Unknown command '\(command)'.\n\n\(usageText)")
        }
    }

    static var usageText: String {
        """
        Usage:
          ursus
          ursus mcp
          ursus bridge serve
          ursus bridge status
          ursus bridge print-url
          ursus doctor
          ursus paths
          ursus --new-note
          ursus --new-note [--title TEXT] [--content TEXT] [--tags TAGS] [--replace-tags] [--open-note] [--new-window]
          ursus --backup-note [note-id-or-title ...]
          ursus --restore-note [NOTE_ID SNAPSHOT_ID ...]
          ursus --apply-template [note-id-or-title ...]

        Notes:
          No command defaults to `mcp`.
          `bridge serve` starts the optional localhost HTTP MCP bridge with the configured host and port.
          `bridge status` prints saved bridge config plus LaunchAgent and health-check details.
          `bridge print-url` prints the configured localhost MCP URL.
          `--new-note` with no extra flags preserves the current interactive editing-note flow.
          In explicit `--new-note` mode, omitted `--tags` follows the create-adds-inbox-tags default: it uses configured inbox tags when enabled and stays empty when disabled. Omitted open/window flags leave the note closed, and `--replace-tags` switches from append to replace.
          `--title` also accepts `-t`, `--content` accepts `-c`, `--tags` accepts `-g`, `--replace-tags` accepts `-rt`, `--open-note` accepts `-on`, and `--new-window` accepts `-nw`.
          `--tags` accepts a comma-separated list and may be passed more than once.
          `--new-window` requires `--open-note`.
          `--backup-note`, `--restore-note`, and `--apply-template` use the selected Bear note when no note ids or titles are passed.
          Bare `--restore-note` restores the selected Bear note from its most recent backup snapshot.
          Passed `--restore-note` arguments must be exact note-id/snapshot-id pairs.
          Passed note arguments resolve as exact note id first, then exact case-insensitive title.
          Quote titles with spaces, for example: ursus --apply-template "Project Notes"
        """
    }

    static var bridgeUsageText: String {
        """
        Usage:
          ursus bridge serve
          ursus bridge status
          ursus bridge print-url

        Notes:
          `serve` starts the optional localhost HTTP MCP bridge using the configured host and port.
          `status` reports saved bridge config plus LaunchAgent and health-check details.
          `print-url` prints the configured MCP endpoint URL.
        """
    }

    private static func assertNoExtraArguments(_ arguments: [String], for command: String) throws {
        guard arguments.isEmpty else {
            throw BearError.invalidInput("Command '\(command)' does not accept extra arguments.\n\n\(usageText)")
        }
    }

    private static func parseBridgeCommand(_ arguments: [String]) throws -> BearCLICommand {
        guard let subcommand = arguments.first else {
            return .bridge(.help)
        }

        let remainingArguments = Array(arguments.dropFirst())

        switch subcommand {
        case "serve":
            try assertNoExtraArguments(remainingArguments, for: "bridge serve")
            return .bridge(.serve)
        case "status":
            try assertNoExtraArguments(remainingArguments, for: "bridge status")
            return .bridge(.status)
        case "print-url":
            try assertNoExtraArguments(remainingArguments, for: "bridge print-url")
            return .bridge(.printURL)
        case "--help", "-h", "help":
            try assertNoExtraArguments(remainingArguments, for: "bridge help")
            return .bridge(.help)
        default:
            throw BearError.invalidInput("Unknown bridge subcommand '\(subcommand)'.\n\n\(bridgeUsageText)")
        }
    }

    private static func parseNewNoteOptions(_ arguments: [String]) throws -> NewNoteOptions? {
        guard arguments.isEmpty == false else {
            return nil
        }

        var index = 0
        var title: String?
        var tags: [String]?
        var replaceTags = false
        var content: String?
        var openNote = false
        var openNoteExplicitlySet = false
        var newWindow = false
        var newWindowExplicitlySet = false

        while index < arguments.count {
            let argument = arguments[index]

            switch argument {
            case "--title", "-t":
                title = try parseSingularValueFlag(
                    name: "--title",
                    currentValue: title,
                    arguments: arguments,
                    index: &index
                )
            case "--content", "-c":
                content = try parseSingularValueFlag(
                    name: "--content",
                    currentValue: content,
                    arguments: arguments,
                    index: &index
                )
            case "--tags", "-g":
                let rawValue = try parseRequiredFlagValue(name: "--tags", arguments: arguments, index: &index)
                let parsedTags = parseTags(rawValue)
                if tags != nil {
                    tags?.append(contentsOf: parsedTags)
                } else {
                    tags = parsedTags
                }
            case "--replace-tags", "-rt":
                guard replaceTags == false else {
                    throw BearError.invalidInput("Flag '--replace-tags' may only be passed once.\n\n\(usageText)")
                }
                replaceTags = true
            case "--open-note", "-on":
                guard openNoteExplicitlySet == false else {
                    throw BearError.invalidInput("Flag '--open-note' may only be passed once.\n\n\(usageText)")
                }
                openNote = true
                openNoteExplicitlySet = true
            case "--new-window", "-nw":
                guard newWindowExplicitlySet == false else {
                    throw BearError.invalidInput("Flag '--new-window' may only be passed once.\n\n\(usageText)")
                }
                newWindow = true
                newWindowExplicitlySet = true
            default:
                throw BearError.invalidInput("Unknown flag '\(argument)' for '--new-note'.\n\n\(usageText)")
            }

            index += 1
        }

        guard openNote || newWindow == false else {
            throw BearError.invalidInput("Flag '--new-window' requires '--open-note'.\n\n\(usageText)")
        }

        return NewNoteOptions(
            title: title,
            tags: tags,
            replaceTags: replaceTags,
            content: content,
            openNote: openNote,
            newWindow: newWindow
        )
    }

    private static func parseRestoreNoteRequests(_ arguments: [String]) throws -> [RestoreNoteRequest] {
        guard arguments.isEmpty == false else {
            return []
        }

        guard arguments.count.isMultiple(of: 2) else {
            throw BearError.invalidInput("Command '--restore-note' requires an even number of arguments as NOTE_ID SNAPSHOT_ID pairs.\n\n\(usageText)")
        }

        var requests: [RestoreNoteRequest] = []
        requests.reserveCapacity(arguments.count / 2)

        var index = 0
        while index < arguments.count {
            let noteID = arguments[index].trimmingCharacters(in: .whitespacesAndNewlines)
            let snapshotID = arguments[index + 1].trimmingCharacters(in: .whitespacesAndNewlines)

            guard noteID.isEmpty == false, snapshotID.isEmpty == false else {
                throw BearError.invalidInput("Command '--restore-note' requires non-empty NOTE_ID SNAPSHOT_ID pairs.\n\n\(usageText)")
            }

            requests.append(RestoreNoteRequest(noteID: noteID, snapshotID: snapshotID))
            index += 2
        }

        return requests
    }

    private static func parseSingularValueFlag(
        name: String,
        currentValue: String?,
        arguments: [String],
        index: inout Int
    ) throws -> String {
        guard currentValue == nil else {
            throw BearError.invalidInput("Flag '\(name)' may only be passed once.\n\n\(usageText)")
        }
        return try parseRequiredFlagValue(name: name, arguments: arguments, index: &index)
    }

    private static func parseRequiredFlagValue(
        name: String,
        arguments: [String],
        index: inout Int
    ) throws -> String {
        let nextIndex = index + 1
        guard nextIndex < arguments.count else {
            throw BearError.invalidInput("Flag '\(name)' requires a value.\n\n\(usageText)")
        }
        index = nextIndex
        return arguments[nextIndex]
    }

    private static func parseTags(_ rawValue: String) -> [String] {
        rawValue
            .split(separator: ",", omittingEmptySubsequences: false)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }
}
