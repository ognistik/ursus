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
func parseBridgePauseCommand() throws {
    let command = try BearCLICommand.parse(arguments: ["bridge", "pause"])

    switch command {
    case .bridge(.pause):
        break
    default:
        Issue.record("Expected 'bridge pause' to parse as the bridge pause subcommand.")
    }
}

@Test
func parseBridgeResumeCommand() throws {
    let command = try BearCLICommand.parse(arguments: ["bridge", "resume"])

    switch command {
    case .bridge(.resume):
        break
    default:
        Issue.record("Expected 'bridge resume' to parse as the bridge resume subcommand.")
    }
}

@Test
func parseBridgeRemoveCommand() throws {
    let command = try BearCLICommand.parse(arguments: ["bridge", "remove"])

    switch command {
    case .bridge(.remove):
        break
    default:
        Issue.record("Expected 'bridge remove' to parse as the bridge remove subcommand.")
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
func parseCheckForUpdatesCommand() throws {
    let command = try BearCLICommand.parse(arguments: ["--check-updates"])

    switch command {
    case .checkForUpdates:
        break
    default:
        Issue.record("Expected '--check-updates' to parse as .checkForUpdates.")
    }
}

@Test
func parseOldCheckForUpdatesCommandIsNotAccepted() {
    do {
        _ = try BearCLICommand.parse(arguments: ["--check-for-updates"])
        Issue.record("Expected '--check-for-updates' to be rejected.")
    } catch {
        #expect(String(describing: error).contains("--check-for-updates"))
    }
}

@Test
func usageTextGroupsCommandsOptionsAndExamples() {
    let usage = BearCLICommand.usageText

    #expect(usage.contains("Ursus is a local CLI and MCP server for Bear note workflows."))
    #expect(usage.contains("Commands:"))
    #expect(usage.contains("`--new-note` options:"))
    #expect(usage.contains("Examples:"))
    #expect(usage.contains("Create a tagged note and open it in Bear."))
    #expect(usage.contains("ursus --check-updates"))
}

@Test
func checkForUpdatesWithoutBundledAppProviderReturnsGuidance() async {
    let exitCode = await UrsusCLIRuntime.run(arguments: ["--check-updates"])

    #expect(exitCode == 1)
}

@Test
func bridgeUsageTextExplainsBridgeCommandsAndExamples() {
    let usage = BearCLICommand.bridgeUsageText

    #expect(usage.contains("Manage the optional localhost HTTP MCP bridge."))
    #expect(usage.contains("ursus bridge <command>"))
    #expect(usage.contains("ursus bridge pause"))
    #expect(usage.contains("Examples:"))
    #expect(usage.contains("Confirm that the installed bridge is loaded and responding."))
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
func parseRestoreNoteWithoutArgumentsBuildsEmptyRequestList() throws {
    let command = try BearCLICommand.parse(arguments: ["--restore-note"])

    switch command {
    case .restoreNote(let requests):
        #expect(requests.isEmpty)
    default:
        Issue.record("Expected bare '--restore-note' to parse as .restoreNote([]).")
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
            authMode: .open,
            auth: BearBridgeAuthStoreSnapshot(
                storagePath: "/tmp/bridge-auth.sqlite",
                storageReady: true,
                registeredClientCount: 2,
                activeGrantCount: 1,
                pendingAuthorizationRequestCount: 0,
                activeAuthorizationCodeCount: 0,
                activeRefreshTokenCount: 1,
                activeAccessTokenCount: 1,
                revocationCount: 0
            ),
            endpointURL: "http://127.0.0.1:6190/mcp",
            currentSelectedNoteTokenConfigured: true,
            loadedSelectedNoteTokenConfigured: true,
            currentRuntimeConfigurationGeneration: 3,
            loadedRuntimeConfigurationGeneration: 2,
            currentRuntimeConfigurationFingerprint: "current-fingerprint",
            loadedRuntimeConfigurationFingerprint: "loaded-fingerprint",
            currentBridgeSurfaceMarker: "current-surface",
            loadedBridgeSurfaceMarker: "loaded-surface",
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
func renderBridgeActionReceiptIncludesStatusPlistAndOptionalURL() {
    let rendered = UrsusCLIRuntime.renderBridgeActionReceipt(
        BearBridgeLaunchAgentActionReceipt(
            status: .paused,
            plistPath: "/tmp/com.aft.ursus.plist",
            endpointURL: "http://127.0.0.1:6190/mcp"
        ),
        action: "pause"
    )

    #expect(rendered.contains("Bridge action: pause"))
    #expect(rendered.contains("Result: paused"))
    #expect(rendered.contains("LaunchAgent plist: /tmp/com.aft.ursus.plist"))
    #expect(rendered.contains("URL: http://127.0.0.1:6190/mcp"))
}

@Test
func embeddedAppArgumentsStripHiddenSentinel() {
    let arguments = UrsusCLIRuntime.cliArgumentsForEmbeddedApp(
        from: ["/Applications/Ursus.app/Contents/MacOS/Ursus", "--ursus-cli", "bridge", "status"]
    )

    #expect(arguments == ["bridge", "status"])
}

#if DEBUG
@Test
func parseHiddenDebugDonationCommands() throws {
    let trigger = try BearCLICommand.parse(arguments: ["--debug-donation-trigger"])
    let reset = try BearCLICommand.parse(arguments: ["--debug-donation-reset"])
    let status = try BearCLICommand.parse(arguments: ["--debug-donation-status"])

    switch trigger {
    case .debugDonation(.trigger):
        break
    default:
        Issue.record("Expected '--debug-donation-trigger' to parse as the hidden debug donation trigger command.")
    }

    switch reset {
    case .debugDonation(.reset):
        break
    default:
        Issue.record("Expected '--debug-donation-reset' to parse as the hidden debug donation reset command.")
    }

    switch status {
    case .debugDonation(.status):
        break
    default:
        Issue.record("Expected '--debug-donation-status' to parse as the hidden debug donation status command.")
    }
}
#endif
