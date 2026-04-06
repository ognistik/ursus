import BearApplication
import BearCore
import Foundation
import Testing
@testable import BearCLIRuntime

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
func parseNewNoteExplicitFlagsCollectsOverridesAndAliases() throws {
    let command = try BearCLICommand.parse(
        arguments: [
            "--new-note",
            "-t", "Daily Capture",
            "-g", "project-x, deep work",
            "--tags", "ops",
            "-rt",
            "-c", "# Daily Capture\n\nBody",
            "-on",
            "-nw",
        ]
    )

    switch command {
    case .newNote(let options):
        let options = try #require(options)
        #expect(options.title == "Daily Capture")
        #expect(options.tags == ["project-x", "deep work", "ops"])
        #expect(options.replaceTags)
        #expect(options.content == "# Daily Capture\n\nBody")
        #expect(options.openNote)
        #expect(options.newWindow)
    default:
        Issue.record("Expected explicit '--new-note' arguments to parse as .newNote(options).")
    }
}

@Test
func parseNewNoteExplicitModeDefaultsToClosedAppendBehavior() throws {
    let command = try BearCLICommand.parse(arguments: ["--new-note", "--content", "Body"])

    switch command {
    case .newNote(let options):
        let options = try #require(options)
        #expect(options.replaceTags == false)
        #expect(options.openNote == false)
        #expect(options.newWindow == false)
    default:
        Issue.record("Expected explicit '--new-note' arguments to parse as .newNote(options).")
    }
}

@Test
func parseNewNoteRejectsNewWindowWithoutOpenNote() throws {
    #expect {
        try BearCLICommand.parse(arguments: ["--new-note", "--new-window"])
    } throws: { error in
        guard let bearError = error as? BearError else {
            return false
        }

        switch bearError {
        case .invalidInput(let message):
            return message.contains("--new-window") && message.contains("--open-note")
        default:
            return false
        }
    }
}

@Test
func parseRestoreNoteRequiresEvenPairs() throws {
    #expect {
        try BearCLICommand.parse(arguments: ["--restore-note", "note-1", "snapshot-1", "note-2"])
    } throws: { error in
        guard let bearError = error as? BearError else {
            return false
        }

        switch bearError {
        case .invalidInput(let message):
            return message.contains("NOTE_ID SNAPSHOT_ID")
        default:
            return false
        }
    }
}

@Test
func parseRestoreNoteBuildsPairRequests() throws {
    let command = try BearCLICommand.parse(arguments: [
        "--restore-note",
        "note-1", "snapshot-1",
        "note-2", "snapshot-2",
    ])

    switch command {
    case .restoreNote(let requests):
        #expect(requests.count == 2)
        #expect(requests[0].noteID == "note-1")
        #expect(requests[0].snapshotID == "snapshot-1")
        #expect(requests[1].noteID == "note-2")
        #expect(requests[1].snapshotID == "snapshot-2")
    default:
        Issue.record("Expected '--restore-note' arguments to parse as restore requests.")
    }
}

@Test
func renderBridgeStatusIncludesLaunchAgentAndHealthDetails() {
    let rendered = UrsusCLIRuntime.renderBridgeStatus(
        BearAppBridgeSnapshot(
            enabled: true,
            host: "127.0.0.1",
            port: 6190,
            endpointURL: "http://127.0.0.1:6190/mcp",
            currentSelectedNoteTokenConfigured: true,
            loadedSelectedNoteTokenConfigured: true,
            currentRuntimeConfigurationGeneration: 3,
            loadedRuntimeConfigurationGeneration: 2,
            currentRuntimeConfigurationFingerprint: "current-fingerprint",
            loadedRuntimeConfigurationFingerprint: "loaded-fingerprint",
            currentBridgeImplementationMarker: "current-impl",
            loadedBridgeImplementationMarker: "loaded-impl",
            launcherPath: "/tmp/ursus",
            launchAgentLabel: "com.aft.ursus",
            plistPath: "/tmp/com.aft.ursus.plist",
            standardOutputLogPath: "/tmp/bridge.stdout.log",
            standardErrorLogPath: "/tmp/bridge.stderr.log",
            installed: true,
            loaded: true,
            plistMatchesExpected: true,
            endpointTransportReachable: true,
            endpointProtocolCompatible: false,
            endpointProbeDetail: "A TCP connection succeeded, but the MCP initialize probe returned HTTP 404.",
            status: .failed,
            statusTitle: "Protocol check failed",
            statusDetail: "The bridge is reachable over TCP but failed the MCP initialize probe."
        )
    )

    #expect(rendered.contains("Status: Protocol check failed"))
    #expect(rendered.contains("LaunchAgent installed: yes"))
    #expect(rendered.contains("LaunchAgent loaded: yes"))
    #expect(rendered.contains("Health: tcp-ok, initialize-failed"))
    #expect(rendered.contains("Stderr log: /tmp/bridge.stderr.log"))
}

@Test
func embeddedAppArgumentsStripHiddenSentinel() {
    let arguments = UrsusCLIRuntime.cliArgumentsForEmbeddedApp(
        from: ["/Applications/Ursus.app/Contents/MacOS/Ursus", "--ursus-cli", "bridge", "status"]
    )

    #expect(arguments == ["bridge", "status"])
}
