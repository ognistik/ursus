import BearCore
import Foundation

enum BearCLICommand {
    struct NewNoteOptions: Hashable {
        let title: String?
        let tags: [String]?
        let tagMergeMode: BearConfiguration.TagsMergeMode
        let content: String?
        let openNote: Bool?
        let newWindow: Bool?
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
    case deleteNote([String])
    case archiveNote([String])
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
        case "--delete-note":
            return .deleteNote(remainingArguments)
        case "--archive-note":
            return .archiveNote(remainingArguments)
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
          bear-mcp
          bear-mcp mcp
          bear-mcp bridge serve
          bear-mcp bridge status
          bear-mcp bridge print-url
          bear-mcp doctor
          bear-mcp paths
          bear-mcp --new-note
          bear-mcp --new-note [--title TEXT] [--content TEXT] [--tags TAGS] [--tag-merge-mode append|replace] [--open-note yes|no] [--new-window yes|no]
          bear-mcp --delete-note [note-id-or-title ...]
          bear-mcp --archive-note [note-id-or-title ...]
          bear-mcp --apply-template [note-id-or-title ...]

        Notes:
          No command defaults to `mcp`.
          `bridge serve` starts the optional localhost HTTP MCP bridge with the configured host and port.
          `bridge status` prints saved bridge config plus LaunchAgent and health-check details.
          `bridge print-url` prints the configured localhost MCP URL.
          `--new-note` with no extra flags preserves the current interactive editing-note flow.
          In explicit `--new-note` mode, omitted `--tags` defaults to configured inbox tags and `--tag-merge-mode` defaults to `append`.
          `--tags` accepts a comma-separated list and may be passed more than once.
          `--delete-note`, `--archive-note`, and `--apply-template` use the selected Bear note when no note ids or titles are passed.
          Passed note arguments resolve as exact note id first, then exact case-insensitive title.
          Quote titles with spaces, for example: bear-mcp --apply-template "Project Notes"
        """
    }

    static var bridgeUsageText: String {
        """
        Usage:
          bear-mcp bridge serve
          bear-mcp bridge status
          bear-mcp bridge print-url

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
        guard !arguments.isEmpty else {
            return nil
        }

        var index = 0
        var title: String?
        var tags: [String]?
        var tagMergeMode: BearConfiguration.TagsMergeMode = .append
        var tagMergeModeExplicitlySet = false
        var content: String?
        var openNote: Bool?
        var newWindow: Bool?

        while index < arguments.count {
            let argument = arguments[index]

            switch argument {
            case "--title":
                title = try parseSingularValueFlag(
                    name: "--title",
                    currentValue: title,
                    arguments: arguments,
                    index: &index
                )
            case "--content":
                content = try parseSingularValueFlag(
                    name: "--content",
                    currentValue: content,
                    arguments: arguments,
                    index: &index
                )
            case "--tags":
                let rawValue = try parseRequiredFlagValue(name: "--tags", arguments: arguments, index: &index)
                let parsedTags = parseTags(rawValue)
                if tags != nil {
                    tags?.append(contentsOf: parsedTags)
                } else {
                    tags = parsedTags
                }
            case "--tag-merge-mode":
                let rawValue = try parseRequiredFlagValue(name: "--tag-merge-mode", arguments: arguments, index: &index)
                guard !tagMergeModeExplicitlySet else {
                    throw BearError.invalidInput("Flag '--tag-merge-mode' may only be passed once.\n\n\(usageText)")
                }
                guard let parsedMode = BearConfiguration.TagsMergeMode(rawValue: rawValue.lowercased()) else {
                    throw BearError.invalidInput("Flag '--tag-merge-mode' must be 'append' or 'replace'.\n\n\(usageText)")
                }
                tagMergeMode = parsedMode
                tagMergeModeExplicitlySet = true
            case "--open-note":
                let rawValue = try parseRequiredFlagValue(name: "--open-note", arguments: arguments, index: &index)
                guard openNote == nil else {
                    throw BearError.invalidInput("Flag '--open-note' may only be passed once.\n\n\(usageText)")
                }
                openNote = try parseBoolFlagValue(rawValue, for: "--open-note")
            case "--new-window":
                let rawValue = try parseRequiredFlagValue(name: "--new-window", arguments: arguments, index: &index)
                guard newWindow == nil else {
                    throw BearError.invalidInput("Flag '--new-window' may only be passed once.\n\n\(usageText)")
                }
                newWindow = try parseBoolFlagValue(rawValue, for: "--new-window")
            default:
                throw BearError.invalidInput("Unknown flag '\(argument)' for '--new-note'.\n\n\(usageText)")
            }

            index += 1
        }

        let options = NewNoteOptions(
            title: title,
            tags: tags,
            tagMergeMode: tagMergeMode,
            content: content,
            openNote: openNote,
            newWindow: newWindow
        )

        return options
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

    private static func parseBoolFlagValue(_ rawValue: String, for flagName: String) throws -> Bool {
        switch rawValue.lowercased() {
        case "yes", "true", "1":
            return true
        case "no", "false", "0":
            return false
        default:
            throw BearError.invalidInput("Flag '\(flagName)' must be yes/no, true/false, or 1/0.\n\n\(usageText)")
        }
    }

    private static func parseTags(_ rawValue: String) -> [String] {
        rawValue
            .split(separator: ",", omittingEmptySubsequences: false)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }
}
