import BearCore
import Foundation

enum BearCLICommand {
    case mcp
    case updateConfig
    case doctor
    case paths
    case newNote
    case deleteNote([String])
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
        case "--update-config":
            try assertNoExtraArguments(remainingArguments, for: "--update-config")
            return .updateConfig
        case "doctor":
            try assertNoExtraArguments(remainingArguments, for: "doctor")
            return .doctor
        case "paths":
            try assertNoExtraArguments(remainingArguments, for: "paths")
            return .paths
        case "--new-note":
            try assertNoExtraArguments(remainingArguments, for: "--new-note")
            return .newNote
        case "--delete-note":
            return .deleteNote(remainingArguments)
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
          bear-mcp doctor
          bear-mcp paths
          bear-mcp --update-config
          bear-mcp --new-note
          bear-mcp --delete-note [note-id-or-title ...]
          bear-mcp --apply-template [note-id-or-title ...]

        Notes:
          No command defaults to `mcp`.
          `--delete-note` and `--apply-template` use the selected Bear note when no note ids or titles are passed.
          Passed note arguments resolve as exact note id first, then exact case-insensitive title.
          Quote titles with spaces, for example: bear-mcp --apply-template "Project Notes"
        """
    }

    private static func assertNoExtraArguments(_ arguments: [String], for command: String) throws {
        guard arguments.isEmpty else {
            throw BearError.invalidInput("Command '\(command)' does not accept extra arguments.\n\n\(usageText)")
        }
    }
}
