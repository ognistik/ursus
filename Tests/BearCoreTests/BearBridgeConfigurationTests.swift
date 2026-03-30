import BearCore
import Foundation
import Testing

@Test
func bridgeConfigurationDefaultsToLocalhostWithStableURL() throws {
    let bridge = BearBridgeConfiguration.default

    #expect(bridge.enabled == false)
    #expect(bridge.host == "127.0.0.1")
    #expect(bridge.port == 6190)
    #expect(try bridge.endpointURLString() == "http://127.0.0.1:6190/mcp")
}

@Test
func configurationDecodesLegacyJSONWithoutBridgeBlock() throws {
    let json = """
    {
      "databasePath": "/tmp/database.sqlite",
      "inboxTags": ["0-inbox"]
    }
    """

    let configuration = try BearJSON.makeDecoder().decode(
        BearConfiguration.self,
        from: Data(json.utf8)
    )

    #expect(configuration.bridge == .default)
}

@Test
func bridgePortAllocatorPrefersConfiguredPortAndScansDeterministically() throws {
    let preferred = try BearBridgePortAllocator.selectPort(
        configuredPort: nil,
        preferredPort: 6190,
        searchRange: 6190...6193,
        availabilityProbe: { _, port in port != 6190 && port == 6191 }
    )

    #expect(preferred == 6191)

    let configured = try BearBridgePortAllocator.selectPort(
        configuredPort: 6205,
        preferredPort: 6190,
        searchRange: 6190...6193,
        availabilityProbe: { _, _ in false }
    )

    #expect(configured == 6205)
}

@Test
func bridgeLaunchAgentExpectedPlistUsesStableLauncherAndLogs() throws {
    let temporaryDirectory = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    let launcherURL = temporaryDirectory.appendingPathComponent("bear-mcp", isDirectory: false)
    let stdoutURL = temporaryDirectory.appendingPathComponent("bridge.stdout.log", isDirectory: false)
    let stderrURL = temporaryDirectory.appendingPathComponent("bridge.stderr.log", isDirectory: false)
    let plistURL = temporaryDirectory.appendingPathComponent("com.aft.bear-mcp.plist", isDirectory: false)

    defer {
        try? FileManager.default.removeItem(at: temporaryDirectory)
    }

    let expected = BearBridgeLaunchAgent.expectedPlist(
        launcherURL: launcherURL,
        standardOutputURL: stdoutURL,
        standardErrorURL: stderrURL
    )

    try FileManager.default.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)
    try expected.xmlData().write(to: plistURL, options: .atomic)

    let decoded = try BearBridgeLaunchAgentPlist.load(from: plistURL)

    #expect(decoded == expected)
    #expect(decoded.label == "com.aft.bear-mcp")
    #expect(decoded.programArguments == [launcherURL.path, "bridge", "serve"])
    #expect(decoded.standardOutPath == stdoutURL.path)
    #expect(decoded.standardErrorPath == stderrURL.path)
}
