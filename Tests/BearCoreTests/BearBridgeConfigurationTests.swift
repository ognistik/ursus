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
