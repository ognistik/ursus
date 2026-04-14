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

    enum NoteSubcommand: Hashable {
        case new(NewNoteOptions?)
        case backup([String])
        case restoreLatest([String])
        case restoreSnapshot([RestoreNoteRequest])
        case applyTemplate([String])
        case help
    }

    enum UpdateSubcommand: Hashable {
        case check
        case automaticInstall(AutomaticUpdatesOption)
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
    case note(NoteSubcommand)
    case update(UpdateSubcommand)
    case doctor
    case paths
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
        case "note", "n":
            return try parseNoteCommand(remainingArguments)
        case "update", "u":
            return try parseUpdateCommand(remainingArguments)
        case "doctor":
            try assertNoExtraArguments(remainingArguments, for: "doctor")
            return .doctor
        case "paths":
            try assertNoExtraArguments(remainingArguments, for: "paths")
            return .paths
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
        case "--help", "-h":
            try assertNoExtraArguments(remainingArguments, for: command)
            return .help
        default:
            throw BearError.invalidInput("Unknown command '\(command)'.\n\n\(usageText)")
        }
    }

    static var usageText: String {
        """
        Ursus is a local CLI and MCP server for Bear note workflows.

        Usage:
          ursus
          ursus <command>

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

        Command Groups:
          ursus note
          ursus n
              Create notes, manage backups, restore snapshots, and apply templates.
          ursus update
          ursus u
              Check for Ursus app updates and configure automatic installs.
          ursus bridge
              Manage the optional localhost HTTP MCP bridge.

        Help:
          ursus --help
          ursus -h
              Show this overview.
          ursus note --help
              Show note commands, note restore modes, and note creation flags.
          ursus update --help
              Show update commands and values.
          ursus bridge --help
              Show bridge commands.

        Examples:
          ursus
              Start the stdio MCP server for a desktop host such as Codex or Claude Desktop.
          ursus note new --title "Daily Note" --tags work,journal --open-note
              Create a tagged note and open it in Bear.
          ursus note backup
              Back up the currently selected Bear note.
          ursus note restore snapshot abc123 snap001
              Restore a specific note backup snapshot.
          ursus update check
              Check for a Sparkle app update from the command line.
          ursus bridge status
              Check whether the optional localhost bridge is installed and healthy.
        """
    }

    static var noteUsageText: String {
        """
        Manage Bear note creation, backups, restore flows, and template application.

        Usage:
          ursus note <command> [arguments]
          ursus n <command> [arguments]

        Commands:
          ursus note new [--title TEXT] [--content TEXT] [--tags TAGS] [--replace-tags] [--open-note] [--new-window]
              Create a new Bear note.
          ursus note backup [note-id-or-title ...]
              Save backup snapshots for one or more notes.
          ursus note restore
              Restore the selected Bear note from its most recent backup.
          ursus note restore latest [note-id-or-title ...]
              Restore the latest backup for the selected note or for each passed note target.
          ursus note restore snapshot NOTE_ID SNAPSHOT_ID [NOTE_ID SNAPSHOT_ID ...]
              Restore exact note and snapshot pairs.
          ursus note apply-template [note-id-or-title ...]
              Apply the configured note template to one or more notes.

        Aliases:
          ursus n new ...
          ursus n backup ...
          ursus n restore ...
          ursus n apply-template ...

        `note new` flags:
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

        Behavior:
          `ursus note new` with no modifiers preserves the interactive selected-note-aware flow.
          In explicit `ursus note new` mode, omitted `--tags` follows the create-adds-inbox-tags default.
          `--new-window` requires `--open-note`.
          `ursus note backup`, `ursus note restore`, and `ursus note apply-template` use the selected Bear note when no targets are passed.
          `ursus note restore snapshot` requires exact `NOTE_ID SNAPSHOT_ID` pairs.
          Passed note selectors resolve as exact note id first, then exact case-insensitive title.

        Examples:
          ursus note new
              Create a note using the interactive selected-note-aware flow.
          ursus n new -t "Meeting Notes" -g work,meeting -on
              Create a tagged note and open it in Bear.
          ursus note backup "Project Notes"
              Save a manual backup for a specific note.
          ursus note restore
              Restore the selected note from its latest backup.
          ursus note restore latest "Project Notes"
              Restore the latest backup for a specific note.
          ursus note restore snapshot abc123 snap001 def456 snap002
              Restore exact snapshot pairs in one command.
          ursus note apply-template
              Apply the configured template to the selected note.

        Tip:
          Quote titles with spaces, for example: ursus note apply-template "Project Notes"
        """
    }

    static var updateUsageText: String {
        """
        Manage Ursus app update checks and automatic install preferences.

        Usage:
          ursus update <command>
          ursus u <command>

        Commands:
          ursus update check
              Check for Ursus app updates through Sparkle without opening the main window.
          ursus update auto-install on
              Enable Sparkle automatic update installs and automatic update checks.
          ursus update auto-install off
              Disable Sparkle automatic update installs without changing automatic update checks.

        Aliases:
          ursus u check
          ursus u auto-install on
          ursus u auto-install off

        Values:
          on
              Enable automatic installs.
          off
              Disable automatic installs.

        Examples:
          ursus update check
              Check for a Sparkle app update from the command line.
          ursus u auto-install on
              Turn on Sparkle automatic installs from the command line.
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

        Help:
          ursus bridge --help
              Show this bridge help.

        Examples:
          ursus bridge serve
              Run the bridge directly in the current terminal.
          ursus bridge status
              Confirm that the installed bridge is loaded and responding.
          ursus bridge pause
              Recover from a stuck bridge process that keeps relaunching.
        """
    }

    private static func assertNoExtraArguments(
        _ arguments: [String],
        for command: String,
        usageText: String = usageText
    ) throws {
        guard arguments.isEmpty else {
            throw BearError.invalidInput("Command '\(command)' does not accept extra arguments.\n\n\(usageText)")
        }
    }

    private static func parseAutomaticUpdatesOption(
        _ arguments: [String],
        command: String,
        usageText: String = updateUsageText
    ) throws -> AutomaticUpdatesOption {
        guard arguments.count == 1 else {
            throw BearError.invalidInput("Command '\(command)' requires exactly one value: `on` or `off`.\n\n\(usageText)")
        }

        let rawValue = arguments[0].trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        switch rawValue {
        case "on":
            return AutomaticUpdatesOption(enabled: true)
        case "off":
            return AutomaticUpdatesOption(enabled: false)
        default:
            throw BearError.invalidInput("Command '\(command)' requires `on` or `off`, but received '\(arguments[0])'.\n\n\(usageText)")
        }
    }

    private static func parseBridgeCommand(_ arguments: [String]) throws -> BearCLICommand {
        guard let subcommand = arguments.first else {
            return .bridge(.help)
        }

        let remainingArguments = Array(arguments.dropFirst())

        switch subcommand {
        case "serve":
            if isScopedHelpRequest(remainingArguments) {
                return .bridge(.help)
            }
            try assertNoExtraArguments(remainingArguments, for: "bridge serve", usageText: bridgeUsageText)
            return .bridge(.serve)
        case "status":
            if isScopedHelpRequest(remainingArguments) {
                return .bridge(.help)
            }
            try assertNoExtraArguments(remainingArguments, for: "bridge status", usageText: bridgeUsageText)
            return .bridge(.status)
        case "print-url":
            if isScopedHelpRequest(remainingArguments) {
                return .bridge(.help)
            }
            try assertNoExtraArguments(remainingArguments, for: "bridge print-url", usageText: bridgeUsageText)
            return .bridge(.printURL)
        case "pause":
            if isScopedHelpRequest(remainingArguments) {
                return .bridge(.help)
            }
            try assertNoExtraArguments(remainingArguments, for: "bridge pause", usageText: bridgeUsageText)
            return .bridge(.pause)
        case "resume":
            if isScopedHelpRequest(remainingArguments) {
                return .bridge(.help)
            }
            try assertNoExtraArguments(remainingArguments, for: "bridge resume", usageText: bridgeUsageText)
            return .bridge(.resume)
        case "remove":
            if isScopedHelpRequest(remainingArguments) {
                return .bridge(.help)
            }
            try assertNoExtraArguments(remainingArguments, for: "bridge remove", usageText: bridgeUsageText)
            return .bridge(.remove)
        case "--help", "-h":
            try assertNoExtraArguments(remainingArguments, for: "bridge --help", usageText: bridgeUsageText)
            return .bridge(.help)
        default:
            throw BearError.invalidInput("Unknown bridge subcommand '\(subcommand)'.\n\n\(bridgeUsageText)")
        }
    }

    private static func parseNoteCommand(_ arguments: [String]) throws -> BearCLICommand {
        guard let subcommand = arguments.first else {
            return .note(.help)
        }

        let remainingArguments = Array(arguments.dropFirst())

        switch subcommand {
        case "new":
            if isScopedHelpRequest(remainingArguments) {
                return .note(.help)
            }
            return .note(.new(try parseNewNoteOptions(remainingArguments, usageText: noteUsageText)))
        case "backup":
            if isScopedHelpRequest(remainingArguments) {
                return .note(.help)
            }
            return .note(.backup(remainingArguments))
        case "restore":
            return try parseRestoreNoteCommand(remainingArguments)
        case "apply-template":
            if isScopedHelpRequest(remainingArguments) {
                return .note(.help)
            }
            return .note(.applyTemplate(remainingArguments))
        case "--help", "-h":
            try assertNoExtraArguments(remainingArguments, for: "note --help", usageText: noteUsageText)
            return .note(.help)
        default:
            throw BearError.invalidInput("Unknown note subcommand '\(subcommand)'.\n\n\(noteUsageText)")
        }
    }

    private static func parseRestoreNoteCommand(_ arguments: [String]) throws -> BearCLICommand {
        guard let mode = arguments.first else {
            return .note(.restoreLatest([]))
        }

        let remainingArguments = Array(arguments.dropFirst())

        switch mode {
        case "latest":
            if isScopedHelpRequest(remainingArguments) {
                return .note(.help)
            }
            return .note(.restoreLatest(remainingArguments))
        case "snapshot":
            if isScopedHelpRequest(remainingArguments) {
                return .note(.help)
            }
            return .note(
                .restoreSnapshot(
                    try parseRestoreNoteRequests(
                        remainingArguments,
                        command: "note restore snapshot",
                        usageText: noteUsageText
                    )
                )
            )
        case "--help", "-h":
            try assertNoExtraArguments(remainingArguments, for: "note restore --help", usageText: noteUsageText)
            return .note(.help)
        default:
            throw BearError.invalidInput(
                "Unknown restore mode '\(mode)'. Use `latest` or `snapshot`.\n\n\(noteUsageText)"
            )
        }
    }

    private static func parseUpdateCommand(_ arguments: [String]) throws -> BearCLICommand {
        guard let subcommand = arguments.first else {
            return .update(.help)
        }

        let remainingArguments = Array(arguments.dropFirst())

        switch subcommand {
        case "check":
            if isScopedHelpRequest(remainingArguments) {
                return .update(.help)
            }
            try assertNoExtraArguments(remainingArguments, for: "update check", usageText: updateUsageText)
            return .update(.check)
        case "auto-install":
            if isScopedHelpRequest(remainingArguments) {
                return .update(.help)
            }
            return .update(
                .automaticInstall(
                    try parseAutomaticUpdatesOption(
                        remainingArguments,
                        command: "update auto-install",
                        usageText: updateUsageText
                    )
                )
            )
        case "--help", "-h":
            try assertNoExtraArguments(remainingArguments, for: "update --help", usageText: updateUsageText)
            return .update(.help)
        default:
            throw BearError.invalidInput("Unknown update subcommand '\(subcommand)'.\n\n\(updateUsageText)")
        }
    }

    private static func parseNewNoteOptions(
        _ arguments: [String],
        usageText: String = noteUsageText
    ) throws -> NewNoteOptions? {
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
                    index: &index,
                    usageText: usageText
                )
            case "--content", "-c":
                content = try parseSingularValueFlag(
                    name: "--content",
                    currentValue: content,
                    arguments: arguments,
                    index: &index,
                    usageText: usageText
                )
            case "--tags", "-g":
                let rawValue = try parseRequiredFlagValue(
                    name: "--tags",
                    arguments: arguments,
                    index: &index,
                    usageText: usageText
                )
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
                throw BearError.invalidInput("Unknown flag '\(argument)' for 'note new'.\n\n\(usageText)")
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

    private static func parseRestoreNoteRequests(
        _ arguments: [String],
        command: String,
        usageText: String = noteUsageText
    ) throws -> [RestoreNoteRequest] {
        guard arguments.isEmpty == false else {
            throw BearError.invalidInput("Command '\(command)' requires at least one NOTE_ID SNAPSHOT_ID pair.\n\n\(usageText)")
        }

        guard arguments.count.isMultiple(of: 2) else {
            throw BearError.invalidInput("Command '\(command)' requires an even number of arguments as NOTE_ID SNAPSHOT_ID pairs.\n\n\(usageText)")
        }

        var requests: [RestoreNoteRequest] = []
        requests.reserveCapacity(arguments.count / 2)

        var index = 0
        while index < arguments.count {
            let noteID = arguments[index].trimmingCharacters(in: .whitespacesAndNewlines)
            let snapshotID = arguments[index + 1].trimmingCharacters(in: .whitespacesAndNewlines)

            guard noteID.isEmpty == false, snapshotID.isEmpty == false else {
                throw BearError.invalidInput("Command '\(command)' requires non-empty NOTE_ID SNAPSHOT_ID pairs.\n\n\(usageText)")
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
        index: inout Int,
        usageText: String
    ) throws -> String {
        guard currentValue == nil else {
            throw BearError.invalidInput("Flag '\(name)' may only be passed once.\n\n\(usageText)")
        }
        return try parseRequiredFlagValue(name: name, arguments: arguments, index: &index, usageText: usageText)
    }

    private static func parseRequiredFlagValue(
        name: String,
        arguments: [String],
        index: inout Int,
        usageText: String
    ) throws -> String {
        let nextIndex = index + 1
        guard nextIndex < arguments.count else {
            throw BearError.invalidInput("Flag '\(name)' requires a value.\n\n\(usageText)")
        }
        index = nextIndex
        return arguments[nextIndex]
    }

    private static func isScopedHelpRequest(_ arguments: [String]) -> Bool {
        arguments.count == 1 && isHelpFlag(arguments[0])
    }

    private static func isHelpFlag(_ argument: String) -> Bool {
        argument == "--help" || argument == "-h"
    }

    private static func parseTags(_ rawValue: String) -> [String] {
        rawValue
            .split(separator: ",", omittingEmptySubsequences: false)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }
}
