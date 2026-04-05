import Foundation

public struct BearConfiguration: Codable, Hashable, Sendable {
    public enum TagsMergeMode: String, Codable, Hashable, Sendable {
        case append
        case replace
    }

    public enum InsertDefault: String, Codable, Hashable, Sendable {
        case top
        case bottom

        public var asInsertPosition: InsertPosition {
            switch self {
            case .top:
                return .top
            case .bottom:
                return .bottom
            }
        }
    }

    public var databasePath: String
    public var inboxTags: [String]
    public var defaultInsertPosition: InsertDefault
    public var templateManagementEnabled: Bool
    public var createOpensNoteByDefault: Bool
    public var openUsesNewWindowByDefault: Bool
    public var createAddsInboxTagsByDefault: Bool
    public var tagsMergeMode: TagsMergeMode
    public var defaultDiscoveryLimit: Int
    public var defaultSnippetLength: Int
    public var backupRetentionDays: Int
    public var disabledTools: [BearToolName]
    public var runtimeConfigurationGeneration: Int
    public var bridge: BearBridgeConfiguration

    public init(
        databasePath: String,
        inboxTags: [String],
        defaultInsertPosition: InsertDefault,
        templateManagementEnabled: Bool,
        createOpensNoteByDefault: Bool,
        openUsesNewWindowByDefault: Bool,
        createAddsInboxTagsByDefault: Bool,
        tagsMergeMode: TagsMergeMode,
        defaultDiscoveryLimit: Int,
        defaultSnippetLength: Int,
        backupRetentionDays: Int,
        disabledTools: [BearToolName] = [],
        runtimeConfigurationGeneration: Int = 0,
        bridge: BearBridgeConfiguration = .default
    ) {
        self.databasePath = databasePath
        self.inboxTags = inboxTags
        self.defaultInsertPosition = defaultInsertPosition
        self.templateManagementEnabled = templateManagementEnabled
        self.createOpensNoteByDefault = createOpensNoteByDefault
        self.openUsesNewWindowByDefault = openUsesNewWindowByDefault
        self.createAddsInboxTagsByDefault = createAddsInboxTagsByDefault
        self.tagsMergeMode = tagsMergeMode
        self.defaultDiscoveryLimit = max(1, defaultDiscoveryLimit)
        self.defaultSnippetLength = max(1, defaultSnippetLength)
        self.backupRetentionDays = max(0, backupRetentionDays)
        self.disabledTools = Self.normalizedDisabledTools(disabledTools)
        self.runtimeConfigurationGeneration = max(0, runtimeConfigurationGeneration)
        self.bridge = bridge
    }

    public static var `default`: BearConfiguration {
        BearConfiguration(
            databasePath: BearPaths.defaultBearDatabaseURL.path,
            inboxTags: ["0-inbox"],
            defaultInsertPosition: .bottom,
            templateManagementEnabled: true,
            createOpensNoteByDefault: true,
            openUsesNewWindowByDefault: true,
            createAddsInboxTagsByDefault: true,
            tagsMergeMode: .append,
            defaultDiscoveryLimit: 20,
            defaultSnippetLength: 280,
            backupRetentionDays: 30,
            disabledTools: [],
            bridge: .default
        )
    }

    public func updatingDisabledTools(_ disabledTools: [BearToolName]) -> BearConfiguration {
        BearConfiguration(
            databasePath: databasePath,
            inboxTags: inboxTags,
            defaultInsertPosition: defaultInsertPosition,
            templateManagementEnabled: templateManagementEnabled,
            createOpensNoteByDefault: createOpensNoteByDefault,
            openUsesNewWindowByDefault: openUsesNewWindowByDefault,
            createAddsInboxTagsByDefault: createAddsInboxTagsByDefault,
            tagsMergeMode: tagsMergeMode,
            defaultDiscoveryLimit: defaultDiscoveryLimit,
            defaultSnippetLength: defaultSnippetLength,
            backupRetentionDays: backupRetentionDays,
            disabledTools: disabledTools,
            runtimeConfigurationGeneration: runtimeConfigurationGeneration,
            bridge: bridge
        )
    }

    public func updatingBridge(_ bridge: BearBridgeConfiguration) -> BearConfiguration {
        BearConfiguration(
            databasePath: databasePath,
            inboxTags: inboxTags,
            defaultInsertPosition: defaultInsertPosition,
            templateManagementEnabled: templateManagementEnabled,
            createOpensNoteByDefault: createOpensNoteByDefault,
            openUsesNewWindowByDefault: openUsesNewWindowByDefault,
            createAddsInboxTagsByDefault: createAddsInboxTagsByDefault,
            tagsMergeMode: tagsMergeMode,
            defaultDiscoveryLimit: defaultDiscoveryLimit,
            defaultSnippetLength: defaultSnippetLength,
            backupRetentionDays: backupRetentionDays,
            disabledTools: disabledTools,
            runtimeConfigurationGeneration: runtimeConfigurationGeneration,
            bridge: bridge
        )
    }

    public func updatingRuntimeConfigurationGeneration(_ generation: Int) -> BearConfiguration {
        BearConfiguration(
            databasePath: databasePath,
            inboxTags: inboxTags,
            defaultInsertPosition: defaultInsertPosition,
            templateManagementEnabled: templateManagementEnabled,
            createOpensNoteByDefault: createOpensNoteByDefault,
            openUsesNewWindowByDefault: openUsesNewWindowByDefault,
            createAddsInboxTagsByDefault: createAddsInboxTagsByDefault,
            tagsMergeMode: tagsMergeMode,
            defaultDiscoveryLimit: defaultDiscoveryLimit,
            defaultSnippetLength: defaultSnippetLength,
            backupRetentionDays: backupRetentionDays,
            disabledTools: disabledTools,
            runtimeConfigurationGeneration: generation,
            bridge: bridge
        )
    }

    public func runtimeConfigurationMatches(_ other: BearConfiguration) -> Bool {
        databasePath == other.databasePath
            && inboxTags == other.inboxTags
            && defaultInsertPosition == other.defaultInsertPosition
            && templateManagementEnabled == other.templateManagementEnabled
            && createOpensNoteByDefault == other.createOpensNoteByDefault
            && openUsesNewWindowByDefault == other.openUsesNewWindowByDefault
            && createAddsInboxTagsByDefault == other.createAddsInboxTagsByDefault
            && tagsMergeMode == other.tagsMergeMode
            && defaultDiscoveryLimit == other.defaultDiscoveryLimit
            && defaultSnippetLength == other.defaultSnippetLength
            && backupRetentionDays == other.backupRetentionDays
            && disabledTools == other.disabledTools
            && bridge == other.bridge
    }

    public var runtimeConfigurationFingerprint: String {
        let normalized = updatingRuntimeConfigurationGeneration(0)
        guard let data = try? BearJSON.makeEncoder().encode(normalized) else {
            return ""
        }

        return String(decoding: data, as: UTF8.self)
    }

    public func isToolEnabled(_ tool: BearToolName) -> Bool {
        !disabledTools.contains(tool)
    }

    private enum CodingKeys: String, CodingKey {
        case databasePath
        case inboxTags
        case defaultInsertPosition
        case templateManagementEnabled
        case createOpensNoteByDefault
        case openUsesNewWindowByDefault
        case createAddsInboxTagsByDefault
        case tagsMergeMode
        case defaultDiscoveryLimit
        case defaultSnippetLength
        case backupRetentionDays
        case disabledTools
        case runtimeConfigurationGeneration
        case bridge
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        databasePath = try container.decodeIfPresent(String.self, forKey: .databasePath) ?? BearPaths.defaultBearDatabaseURL.path
        inboxTags = try container.decodeIfPresent([String].self, forKey: .inboxTags) ?? ["0-inbox"]
        defaultInsertPosition = try container.decodeIfPresent(InsertDefault.self, forKey: .defaultInsertPosition) ?? .bottom
        templateManagementEnabled = try container.decodeIfPresent(Bool.self, forKey: .templateManagementEnabled) ?? true
        createOpensNoteByDefault = try container.decodeIfPresent(Bool.self, forKey: .createOpensNoteByDefault) ?? true
        openUsesNewWindowByDefault = try container.decodeIfPresent(Bool.self, forKey: .openUsesNewWindowByDefault) ?? true
        createAddsInboxTagsByDefault = try container.decodeIfPresent(Bool.self, forKey: .createAddsInboxTagsByDefault) ?? true
        tagsMergeMode = try container.decodeIfPresent(TagsMergeMode.self, forKey: .tagsMergeMode) ?? .append
        defaultDiscoveryLimit = max(1, try container.decodeIfPresent(Int.self, forKey: .defaultDiscoveryLimit) ?? 20)
        defaultSnippetLength = max(1, try container.decodeIfPresent(Int.self, forKey: .defaultSnippetLength) ?? 280)
        backupRetentionDays = max(0, try container.decodeIfPresent(Int.self, forKey: .backupRetentionDays) ?? 30)
        disabledTools = Self.normalizedDisabledTools(try container.decodeIfPresent([BearToolName].self, forKey: .disabledTools) ?? [])
        runtimeConfigurationGeneration = max(0, try container.decodeIfPresent(Int.self, forKey: .runtimeConfigurationGeneration) ?? 0)
        bridge = try container.decodeIfPresent(BearBridgeConfiguration.self, forKey: .bridge) ?? .default
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(databasePath, forKey: .databasePath)
        try container.encode(inboxTags, forKey: .inboxTags)
        try container.encode(defaultInsertPosition, forKey: .defaultInsertPosition)
        try container.encode(templateManagementEnabled, forKey: .templateManagementEnabled)
        try container.encode(createOpensNoteByDefault, forKey: .createOpensNoteByDefault)
        try container.encode(openUsesNewWindowByDefault, forKey: .openUsesNewWindowByDefault)
        try container.encode(createAddsInboxTagsByDefault, forKey: .createAddsInboxTagsByDefault)
        try container.encode(tagsMergeMode, forKey: .tagsMergeMode)
        try container.encode(defaultDiscoveryLimit, forKey: .defaultDiscoveryLimit)
        try container.encode(defaultSnippetLength, forKey: .defaultSnippetLength)
        try container.encode(backupRetentionDays, forKey: .backupRetentionDays)
        try container.encode(disabledTools, forKey: .disabledTools)
        try container.encode(runtimeConfigurationGeneration, forKey: .runtimeConfigurationGeneration)
        try container.encode(bridge, forKey: .bridge)
    }

    public static func load(from url: URL = BearPaths.configFileURL) throws -> BearConfiguration {
        let decoder = JSONDecoder()
        decoder.outputFormattingIfAvailable()

        let data = try Data(contentsOf: url)
        return try decoder.decode(BearConfiguration.self, from: data)
    }
}

private extension JSONDecoder {
    func outputFormattingIfAvailable() {
        // Intentionally empty. Keeps a symmetric helper shape with JSONEncoder setup.
    }
}

extension BearConfiguration {
    public static func normalizedDisabledTools(_ value: [BearToolName]) -> [BearToolName] {
        Array(Set(value)).sorted { $0.rawValue < $1.rawValue }
    }
}
