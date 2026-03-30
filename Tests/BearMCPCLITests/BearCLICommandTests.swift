import BearCore
import Foundation
import Testing
@testable import BearMCPCLI

@Test
func parseNewNoteWithoutExtraFlagsKeepsInteractiveMode() throws {
    let command = try BearCLICommand.parse(arguments: ["--new-note"])

    switch command {
    case .newNote(let options):
        #expect(options == nil)
    default:
        Issue.record("Expected '--new-note' to parse as .newNote(nil).")
    }
}

@Test
func parseBridgeServeCommand() throws {
    let command = try BearCLICommand.parse(arguments: ["bridge", "serve"])

    switch command {
    case .bridge(.serve):
        break
    default:
        Issue.record("Expected 'bridge serve' to parse as the bridge serve subcommand.")
    }
}

@Test
func parseBridgeWithoutSubcommandShowsBridgeHelp() throws {
    let command = try BearCLICommand.parse(arguments: ["bridge"])

    switch command {
    case .bridge(.help):
        break
    default:
        Issue.record("Expected bare 'bridge' to parse as bridge help.")
    }
}

@Test
func parseNewNoteExplicitFlagsCollectsOverrides() throws {
    let command = try BearCLICommand.parse(
        arguments: [
            "--new-note",
            "--title", "Daily Capture",
            "--tags", "project-x, deep work",
            "--tags", "ops",
            "--tag-merge-mode", "replace",
            "--content", "# Daily Capture\n\nBody",
            "--open-note", "no",
            "--new-window", "false",
        ]
    )

    switch command {
    case .newNote(let options):
        let options = try #require(options)
        #expect(options.title == "Daily Capture")
        #expect(options.tags == ["project-x", "deep work", "ops"])
        #expect(options.tagMergeMode == .replace)
        #expect(options.content == "# Daily Capture\n\nBody")
        #expect(options.openNote == false)
        #expect(options.newWindow == false)
    default:
        Issue.record("Expected explicit '--new-note' arguments to parse as .newNote(options).")
    }
}

@Test
func parseNewNoteTreatsExplicitAppendAsExplicitMode() throws {
    let command = try BearCLICommand.parse(arguments: ["--new-note", "--tag-merge-mode", "append"])

    switch command {
    case .newNote(let options):
        let options = try #require(options)
        #expect(options.tagMergeMode == .append)
    default:
        Issue.record("Expected '--tag-merge-mode append' to stay in explicit mode.")
    }
}

@Test
func parseNewNoteRejectsInvalidBooleanValues() throws {
    #expect {
        try BearCLICommand.parse(arguments: ["--new-note", "--open-note", "maybe"])
    } throws: { error in
        guard let bearError = error as? BearError else {
            return false
        }

        switch bearError {
        case .invalidInput(let message):
            return message.contains("--open-note")
        default:
            return false
        }
    }
}
