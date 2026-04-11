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

    struct AutomaticUpdatesOption: Hashable {
        let enabled: Bool
    }

    enum BridgeSubcommand: Hashable {
        case serve
        case status
        case printURL
        case pause
        case resume
        case remove
        case help
    }

#if DEBUG
    enum DebugDonationSubcommand: Hashable {
        case trigger
        case reset
        case status
    }
#endif

    case mcp
    case bridge(BridgeSubcommand)
    case doctor
    case paths
    case newNote(NewNoteOptions?)
    case backupNote([String])
    case restoreNote([RestoreNoteRequest])
    case applyTemplate([String])
    case checkForUpdates
    case automaticUpdateInstalls(AutomaticUpdatesOption)
#if DEBUG
    case debugDonation(DebugDonationSubcommand)
#endif
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
        case "--check-updates":
            try assertNoExtraArguments(remainingArguments, for: "--check-updates")
            return .checkForUpdates
        case "--auto-install-updates":
            return .automaticUpdateInstalls(try parseAutomaticUpdatesOption(remainingArguments, flag: command))
#if DEBUG
        case "--debug-donation-trigger":
            try assertNoExtraArguments(remainingArguments, for: "--debug-donation-trigger")
            return .debugDonation(.trigger)
        case "--debug-donation-reset":
            try assertNoExtraArguments(remainingArguments, for: "--debug-donation-reset")
            return .debugDonation(.reset)
        case "--debug-donation-status":
            try assertNoExtraArguments(remainingArguments, for: "--debug-donation-status")
            return .debugDonation(.status)
#endif
        case "--help", "-h", "help":
            return .help
        default:
            throw BearError.invalidInput("Unknown command '\(command)'.\n\n\(usageText)")
        }
    }

    static var usageText: String {
        """
        Ursus is a local CLI and MCP server for Bear note workflows.

        Usage:
          ursus [command]

        If you run `ursus` with no command, it starts the stdio MCP server.

        Core:
          ursus
              Start the stdio MCP server.
          ursus mcp
              Start the stdio MCP server explicitly.
          ursus doctor
              Check the local Ursus setup and print diagnostics.
          ursus paths
              Print important Ursus file paths.

        Bridge:
          ursus bridge serve
              Start the optional localhost HTTP MCP bridge.
          ursus bridge status
              Show bridge configuration, LaunchAgent state, and health checks.
          ursus bridge print-url
              Print the bridge MCP endpoint URL.
          ursus bridge pause
              Stop the installed bridge LaunchAgent without removing it.
          ursus bridge resume
              Start the installed bridge LaunchAgent again.
          ursus bridge remove
              Stop and uninstall the bridge LaunchAgent.

        Notes:
          ursus --new-note
              Create a new Bear note using the selected note tags.
          ursus --new-note [--title TEXT] [--content TEXT] [--tags TAGS] [--replace-tags] [--open-note] [--new-window]
              Create a new note with explicit options.

        Backups And Templates:
          ursus --backup-note [note-id-or-title ...]
              Save backup snapshotss. Wait a few seconds before running if currently editing to ensure changes are saved.
          ursus --restore-note [NOTE_ID SNAPSHOT_ID ...]
              Restore notes from saved backups.
          ursus --apply-template [note-id-or-title ...]
              Apply the configured note template to one or more notes.

        Updates:
          ursus --check-updates
              Check for Ursus app updates through Sparkle without opening the main window.
          ursus --auto-install-updates true|false
              Enable or disable Sparkle automatic update installs. Setting `true` also enables automatic update checks.

        `--new-note` options:
          --title, -t TEXT
              Set the note title.
          --content, -c TEXT
              Set the note body content.
          --tags, -g TAGS
              Add tags as a comma-separated list. You can pass this more than once.
          --replace-tags, -rt
              Replace tags instead of appending them.
          --open-note, -on
              Open the new note in Bear after creating it.
          --new-window, -nw
              Open the new note in a new Bear window. Requires `--open-note`.

        `--auto-install-updates` values:
          true
              Enable automatic update installs and automatic update checks.
          false
              Disable automatic update installs without changing automatic update checks.

        Note targeting:
          For `--backup-note`, `--restore-note`, and `--apply-template`, no arguments means "use the currently selected Bear note".
          Bare `--restore-note` restores the selected note from its most recent backup snapshot.
          Passed note selectors resolve as exact note id first, then exact case-insensitive title.
          Passed `--restore-note` arguments must be exact `NOTE_ID SNAPSHOT_ID` pairs.
          In explicit `--new-note` mode, omitted `--tags` follows the create-adds-inbox-tags default.
          In explicit `--new-note` mode, omitted open/window flags leave the note closed.

        Examples:
          ursus
              Start the stdio MCP server for a desktop host such as Codex or Claude Desktop.
          ursus bridge status
              Check whether the optional localhost bridge is installed and healthy.
          ursus --new-note --title "Daily Note" --tags work,journal --open-note
              Create a tagged note and open it in Bear.
          ursus --backup-note
              Back up the currently selected Bear note.
          ursus --apply-template "Project Notes"
              Apply the current template to the note titled "Project Notes".
          ursus --check-updates
              Check for a Sparkle app update from the command line.
          ursus --auto-install-updates true
              Turn on Sparkle automatic installs from the command line.

        Tip:
          Quote titles with spaces, for example: ursus --apply-template "Project Notes"
        """
    }

    static var bridgeUsageText: String {
        """
        Manage the optional localhost HTTP MCP bridge.

        Usage:
          ursus bridge <command>

        Commands:
          ursus bridge serve
              Start the localhost HTTP MCP bridge using the saved host and port.
          ursus bridge status
              Show bridge configuration, LaunchAgent state, and health checks.
          ursus bridge print-url
              Print the saved MCP endpoint URL.
          ursus bridge pause
              Stop the installed bridge LaunchAgent without removing it.
          ursus bridge resume
              Start the installed bridge LaunchAgent again.
          ursus bridge remove
              Stop and uninstall the bridge LaunchAgent.

        Examples:
          ursus bridge serve
              Run the bridge directly in the current terminal.
          ursus bridge status
              Confirm that the installed bridge is loaded and responding.
          ursus bridge pause
              Recover from a stuck bridge process that keeps relaunching.
        """
    }

    private static func assertNoExtraArguments(_ arguments: [String], for command: String) throws {
        guard arguments.isEmpty else {
            throw BearError.invalidInput("Command '\(command)' does not accept extra arguments.\n\n\(usageText)")
        }
    }

    private static func parseAutomaticUpdatesOption(
        _ arguments: [String],
        flag: String
    ) throws -> AutomaticUpdatesOption {
        guard arguments.count == 1 else {
            throw BearError.invalidInput("Command '\(flag)' requires exactly one value: `true` or `false`.\n\n\(usageText)")
        }

        let rawValue = arguments[0].trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        switch rawValue {
        case "true":
            return AutomaticUpdatesOption(enabled: true)
        case "false":
            return AutomaticUpdatesOption(enabled: false)
        default:
            throw BearError.invalidInput("Command '\(flag)' requires `true` or `false`, but received '\(arguments[0])'.\n\n\(usageText)")
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
        case "pause":
            try assertNoExtraArguments(remainingArguments, for: "bridge pause")
            return .bridge(.pause)
        case "resume":
            try assertNoExtraArguments(remainingArguments, for: "bridge resume")
            return .bridge(.resume)
        case "remove":
            try assertNoExtraArguments(remainingArguments, for: "bridge remove")
            return .bridge(.remove)
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
