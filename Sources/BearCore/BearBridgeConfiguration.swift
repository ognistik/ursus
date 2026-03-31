import Darwin
import Foundation

public struct BearBridgeConfiguration: Codable, Hashable, Sendable {
    public static let defaultHost = "127.0.0.1"
    public static let defaultEndpointPath = "/mcp"
    public static let preferredPort = 6190

    public var enabled: Bool
    public var host: String
    public var port: Int

    public init(
        enabled: Bool = false,
        host: String = BearBridgeConfiguration.defaultHost,
        port: Int = BearBridgeConfiguration.preferredPort
    ) {
        self.enabled = enabled
        self.host = host.trimmingCharacters(in: .whitespacesAndNewlines)
        self.port = port
    }

    public static var `default`: BearBridgeConfiguration {
        BearBridgeConfiguration()
    }

    public var endpointPath: String {
        Self.defaultEndpointPath
    }

    public func validated() throws -> BearBridgeConfiguration {
        let normalizedHost = host.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedHost.isEmpty else {
            throw BearError.invalidInput("Bridge host cannot be empty.")
        }

        guard Self.isSupportedHost(normalizedHost) else {
            throw BearError.invalidInput("Bridge host must be `localhost` or an IPv4 loopback address such as `127.0.0.1`.")
        }

        try BearBridgePortAllocator.validate(port: port)
        return BearBridgeConfiguration(enabled: enabled, host: normalizedHost, port: port)
    }

    public func endpointURL() throws -> URL {
        let validatedConfiguration = try validated()
        var components = URLComponents()
        components.scheme = "http"
        components.host = validatedConfiguration.host
        components.port = validatedConfiguration.port
        components.path = validatedConfiguration.endpointPath

        guard let url = components.url else {
            throw BearError.invalidInput("Bridge endpoint could not be formatted from the current host and port.")
        }

        return url
    }

    public func endpointURLString() throws -> String {
        try endpointURL().absoluteString
    }

    public static func isSupportedHost(_ host: String) -> Bool {
        let normalizedHost = host.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !normalizedHost.isEmpty else {
            return false
        }

        if normalizedHost == "localhost" {
            return true
        }

        let octets = normalizedHost.split(separator: ".", omittingEmptySubsequences: false)
        guard octets.count == 4 else {
            return false
        }

        guard let firstOctet = Int(octets[0]), firstOctet == 127 else {
            return false
        }

        for octet in octets {
            guard let value = Int(octet), (0...255).contains(value) else {
                return false
            }
        }

        return true
    }
}

public enum BearBridgePortAllocator {
    public typealias AvailabilityProbe = @Sendable (_ host: String, _ port: Int) -> Bool

    public static let defaultSearchRange = BearBridgeConfiguration.preferredPort...(BearBridgeConfiguration.preferredPort + 20)

    public static func selectPort(
        configuredPort: Int?,
        host: String = BearBridgeConfiguration.defaultHost,
        preferredPort: Int = BearBridgeConfiguration.preferredPort,
        searchRange: ClosedRange<Int> = defaultSearchRange,
        availabilityProbe: AvailabilityProbe = isPortAvailable
    ) throws -> Int {
        if let configuredPort {
            try validate(port: configuredPort)
            return configuredPort
        }

        try validate(port: preferredPort)

        if availabilityProbe(host, preferredPort) {
            return preferredPort
        }

        for port in searchRange where port != preferredPort {
            try validate(port: port)
            if availabilityProbe(host, port) {
                return port
            }
        }

        throw BearError.configuration(
            "No available bridge port was found between \(searchRange.lowerBound) and \(searchRange.upperBound)."
        )
    }

    public static func validate(port: Int) throws {
        guard (1024...65535).contains(port) else {
            throw BearError.invalidInput("Bridge port must be between 1024 and 65535.")
        }
    }

    public static func isPortAvailable(host: String, port: Int) -> Bool {
        let socketHandle = socket(AF_INET, SOCK_STREAM, 0)
        guard socketHandle >= 0 else {
            return false
        }
        defer { close(socketHandle) }

        var value: Int32 = 1
        guard setsockopt(socketHandle, SOL_SOCKET, SO_REUSEADDR, &value, socklen_t(MemoryLayout<Int32>.size)) == 0 else {
            return false
        }

        let normalizedHost = host == "localhost" ? BearBridgeConfiguration.defaultHost : host

        var address = sockaddr_in()
        address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        address.sin_family = sa_family_t(AF_INET)
        address.sin_port = in_port_t(UInt16(port).bigEndian)

        let conversionResult = normalizedHost.withCString { hostPointer in
            inet_pton(AF_INET, hostPointer, &address.sin_addr)
        }
        guard conversionResult == 1 else {
            return false
        }

        return withUnsafePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockaddrPointer in
                bind(socketHandle, sockaddrPointer, socklen_t(MemoryLayout<sockaddr_in>.size)) == 0
            }
        }
    }
}

public enum BearBridgeLaunchAgent {
    public static let label = "com.aft.bear-mcp"
    public static let standardOutputFileName = "bridge.stdout.log"
    public static let standardErrorFileName = "bridge.stderr.log"

    public static var launchAgentsDirectoryURL: URL {
        URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true)
            .appendingPathComponent("Library", isDirectory: true)
            .appendingPathComponent("LaunchAgents", isDirectory: true)
    }

    public static var plistURL: URL {
        launchAgentsDirectoryURL.appendingPathComponent("\(label).plist", isDirectory: false)
    }

    public static var standardOutputURL: URL {
        BearPaths.logsDirectoryURL.appendingPathComponent(standardOutputFileName, isDirectory: false)
    }

    public static var standardErrorURL: URL {
        BearPaths.logsDirectoryURL.appendingPathComponent(standardErrorFileName, isDirectory: false)
    }

    public static var launcherURL: URL {
        BearPaths.publicCLIExecutableURL
    }

    public static func serviceTarget(userIdentifier: uid_t = getuid()) -> String {
        "gui/\(userIdentifier)/\(label)"
    }

    public static func expectedPlist(
        launcherURL: URL = launcherURL,
        standardOutputURL: URL = standardOutputURL,
        standardErrorURL: URL = standardErrorURL
    ) -> BearBridgeLaunchAgentPlist {
        BearBridgeLaunchAgentPlist(
            label: label,
            programArguments: [launcherURL.path, "bridge", "serve"],
            runAtLoad: true,
            keepAlive: true,
            standardOutPath: standardOutputURL.path,
            standardErrorPath: standardErrorURL.path
        )
    }
}

public struct BearBridgeLaunchAgentPlist: Codable, Hashable, Sendable {
    public let label: String
    public let programArguments: [String]
    public let runAtLoad: Bool
    public let keepAlive: Bool
    public let standardOutPath: String
    public let standardErrorPath: String

    public init(
        label: String,
        programArguments: [String],
        runAtLoad: Bool,
        keepAlive: Bool,
        standardOutPath: String,
        standardErrorPath: String
    ) {
        self.label = label
        self.programArguments = programArguments
        self.runAtLoad = runAtLoad
        self.keepAlive = keepAlive
        self.standardOutPath = standardOutPath
        self.standardErrorPath = standardErrorPath
    }

    public func xmlData() throws -> Data {
        let encoder = PropertyListEncoder()
        encoder.outputFormat = .xml
        return try encoder.encode(self)
    }

    public static func load(from url: URL) throws -> BearBridgeLaunchAgentPlist {
        let data = try Data(contentsOf: url)
        return try PropertyListDecoder().decode(BearBridgeLaunchAgentPlist.self, from: data)
    }

    private enum CodingKeys: String, CodingKey {
        case label = "Label"
        case programArguments = "ProgramArguments"
        case runAtLoad = "RunAtLoad"
        case keepAlive = "KeepAlive"
        case standardOutPath = "StandardOutPath"
        case standardErrorPath = "StandardErrorPath"
    }
}
