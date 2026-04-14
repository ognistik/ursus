import BearApplication
import BearCore
import Foundation
import Testing
@testable import BearCLIRuntime

@Test
func parseNoteNewWithoutExtraFlagsKeepsInteractiveMode() throws {
    let command = try BearCLICommand.parse(arguments: ["note", "new"])

    switch command {
    case .note(.new(let options)):
        #expect(options == nil)
    default:
        Issue.record("Expected 'note new' to parse as .note(.new(nil)).")
    }
}

@Test
func parseNoteAliasNewWithoutExtraFlagsKeepsInteractiveMode() throws {
    let command = try BearCLICommand.parse(arguments: ["n", "new"])

    switch command {
    case .note(.new(let options)):
        #expect(options == nil)
    default:
        Issue.record("Expected 'n new' to parse as .note(.new(nil)).")
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
func parseNoteWithoutSubcommandShowsNoteHelp() throws {
    let command = try BearCLICommand.parse(arguments: ["note"])

    switch command {
    case .note(.help):
        break
    default:
        Issue.record("Expected bare 'note' to parse as note help.")
    }
}

@Test
func parseUpdateWithoutSubcommandShowsUpdateHelp() throws {
    let command = try BearCLICommand.parse(arguments: ["update"])

    switch command {
    case .update(.help):
        break
    default:
        Issue.record("Expected bare 'update' to parse as update help.")
    }
}

@Test
func parseUpdateCheckCommand() throws {
    let command = try BearCLICommand.parse(arguments: ["update", "check"])

    switch command {
    case .update(.check):
        break
    default:
        Issue.record("Expected 'update check' to parse as .update(.check).")
    }
}

@Test
func parseUpdateAliasCheckCommand() throws {
    let command = try BearCLICommand.parse(arguments: ["u", "check"])

    switch command {
    case .update(.check):
        break
    default:
        Issue.record("Expected 'u check' to parse as .update(.check).")
    }
}

@Test
func parseAutoInstallUpdatesCommand() throws {
    let command = try BearCLICommand.parse(arguments: ["update", "auto-install", "on"])

    switch command {
    case .update(.automaticInstall(let option)):
        #expect(option.enabled == true)
    default:
        Issue.record("Expected 'update auto-install on' to parse as .update(.automaticInstall(true)).")
    }
}

@Test
func parseAutoInstallUpdatesRejectsInvalidValue() {
    #expect {
        try BearCLICommand.parse(arguments: ["update", "auto-install", "maybe"])
    } throws: { error in
        guard let bearError = error as? BearError else {
            return false
        }

        switch bearError {
        case .invalidInput(let message):
            return message.contains("update auto-install") && message.contains("on") && message.contains("off")
        default:
            return false
        }
    }
}

@Test
func parseOldCheckForUpdatesCommandIsNotAccepted() {
    do {
        _ = try BearCLICommand.parse(arguments: ["--check-updates"])
        Issue.record("Expected '--check-updates' to be rejected.")
    } catch {
        #expect(String(describing: error).contains("--check-updates"))
    }
}

@Test
func usageTextGroupsCommandsAndScopedHelp() {
    let usage = BearCLICommand.usageText

    #expect(usage.contains("Ursus is a local CLI and MCP server for Bear note workflows."))
    #expect(usage.contains("Core:"))
    #expect(usage.contains("Command Groups:"))
    #expect(usage.contains("Help:"))
    #expect(usage.contains("ursus note --help"))
    #expect(usage.contains("ursus update --help"))
    #expect(usage.contains("Examples:"))
    #expect(usage.contains("ursus update check"))
}

@Test
func noteUsageTextExplainsCommandsFlagsAndExamples() {
    let usage = BearCLICommand.noteUsageText

    #expect(usage.contains("Manage Bear note creation, backups, restore flows, and template application."))
    #expect(usage.contains("ursus note restore snapshot NOTE_ID SNAPSHOT_ID"))
    #expect(usage.contains("`note new` flags:"))
    #expect(usage.contains("--open-note, -on"))
    #expect(usage.contains("Aliases:"))
    #expect(usage.contains("Examples:"))
}

@Test
func updateUsageTextExplainsCommandsAliasesAndValues() {
    let usage = BearCLICommand.updateUsageText

    #expect(usage.contains("Manage Ursus app update checks and automatic install preferences."))
    #expect(usage.contains("ursus update check"))
    #expect(usage.contains("ursus u auto-install on"))
    #expect(usage.contains("Values:"))
    #expect(usage.contains("on"))
    #expect(usage.contains("off"))
}

@Test
func checkForUpdatesWithoutBundledAppProviderReturnsGuidance() async {
    let exitCode = await UrsusCLIRuntime.run(arguments: ["update", "check"])

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
func parseNoteNewExplicitFlagsCollectsOverridesAndAliases() throws {
    let command = try BearCLICommand.parse(
        arguments: [
            "n",
            "new",
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
    case .note(.new(let options)):
        let options = try #require(options)
        #expect(options.title == "Daily Capture")
        #expect(options.tags == ["project-x", "deep work", "ops"])
        #expect(options.replaceTags)
        #expect(options.content == "# Daily Capture\n\nBody")
        #expect(options.openNote)
        #expect(options.newWindow)
    default:
        Issue.record("Expected explicit 'n new' arguments to parse as .note(.new(options)).")
    }
}

@Test
func parseNoteNewExplicitModeDefaultsToClosedAppendBehavior() throws {
    let command = try BearCLICommand.parse(arguments: ["note", "new", "--content", "Body"])

    switch command {
    case .note(.new(let options)):
        let options = try #require(options)
        #expect(options.replaceTags == false)
        #expect(options.openNote == false)
        #expect(options.newWindow == false)
    default:
        Issue.record("Expected explicit 'note new' arguments to parse as .note(.new(options)).")
    }
}

@Test
func parseNoteNewRejectsNewWindowWithoutOpenNote() throws {
    #expect {
        try BearCLICommand.parse(arguments: ["note", "new", "--new-window"])
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
func parseRestoreWithoutArgumentsBuildsLatestSelectedMode() throws {
    let command = try BearCLICommand.parse(arguments: ["note", "restore"])

    switch command {
    case .note(.restoreLatest(let selectors)):
        #expect(selectors.isEmpty)
    default:
        Issue.record("Expected bare 'note restore' to parse as .note(.restoreLatest([])).")
    }
}

@Test
func parseRestoreLatestBuildsSelectorList() throws {
    let command = try BearCLICommand.parse(arguments: ["note", "restore", "latest", "note-1", "Project Notes"])

    switch command {
    case .note(.restoreLatest(let selectors)):
        #expect(selectors == ["note-1", "Project Notes"])
    default:
        Issue.record("Expected 'note restore latest ...' to parse as .note(.restoreLatest(selectors)).")
    }
}

@Test
func parseRestoreSnapshotRequiresPairs() throws {
    #expect {
        try BearCLICommand.parse(arguments: ["note", "restore", "snapshot", "note-1", "snapshot-1", "note-2"])
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
func parseRestoreSnapshotBuildsPairRequests() throws {
    let command = try BearCLICommand.parse(arguments: [
        "note",
        "restore",
        "snapshot",
        "note-1", "snapshot-1",
        "note-2", "snapshot-2",
    ])

    switch command {
    case .note(.restoreSnapshot(let requests)):
        #expect(requests.count == 2)
        #expect(requests[0].noteID == "note-1")
        #expect(requests[0].snapshotID == "snapshot-1")
        #expect(requests[1].noteID == "note-2")
        #expect(requests[1].snapshotID == "snapshot-2")
    default:
        Issue.record("Expected 'note restore snapshot ...' to parse as snapshot restore requests.")
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
