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
    public var openNoteInEditModeByDefault: Bool
    public var createOpensNoteByDefault: Bool
    public var openUsesNewWindowByDefault: Bool
    public var createAddsInboxTagsByDefault: Bool
    public var tagsMergeMode: TagsMergeMode
    public var defaultDiscoveryLimit: Int
    public var maxDiscoveryLimit: Int
    public var defaultSnippetLength: Int
    public var maxSnippetLength: Int
    public var backupRetentionDays: Int
    public var disabledTools: [BearToolName]
    public var token: String?
    public var bridge: BearBridgeConfiguration

    public init(
        databasePath: String,
        inboxTags: [String],
        defaultInsertPosition: InsertDefault,
        templateManagementEnabled: Bool,
        openNoteInEditModeByDefault: Bool,
        createOpensNoteByDefault: Bool,
        openUsesNewWindowByDefault: Bool,
        createAddsInboxTagsByDefault: Bool,
        tagsMergeMode: TagsMergeMode,
        defaultDiscoveryLimit: Int,
        maxDiscoveryLimit: Int,
        defaultSnippetLength: Int,
        maxSnippetLength: Int,
        backupRetentionDays: Int,
        disabledTools: [BearToolName] = [],
        token: String? = nil,
        bridge: BearBridgeConfiguration = .default
    ) {
        self.databasePath = databasePath
        self.inboxTags = inboxTags
        self.defaultInsertPosition = defaultInsertPosition
        self.templateManagementEnabled = templateManagementEnabled
        self.openNoteInEditModeByDefault = openNoteInEditModeByDefault
        self.createOpensNoteByDefault = createOpensNoteByDefault
        self.openUsesNewWindowByDefault = openUsesNewWindowByDefault
        self.createAddsInboxTagsByDefault = createAddsInboxTagsByDefault
        self.tagsMergeMode = tagsMergeMode
        self.defaultDiscoveryLimit = defaultDiscoveryLimit
        self.maxDiscoveryLimit = maxDiscoveryLimit
        self.defaultSnippetLength = defaultSnippetLength
        self.maxSnippetLength = maxSnippetLength
        self.backupRetentionDays = max(0, backupRetentionDays)
        self.disabledTools = Self.normalizedDisabledTools(disabledTools)
        self.token = Self.normalizedToken(token)
        self.bridge = bridge
    }

    public static var `default`: BearConfiguration {
        BearConfiguration(
            databasePath: BearPaths.defaultBearDatabaseURL.path,
            inboxTags: ["0-inbox"],
            defaultInsertPosition: .bottom,
            templateManagementEnabled: true,
            openNoteInEditModeByDefault: true,
            createOpensNoteByDefault: true,
            openUsesNewWindowByDefault: true,
            createAddsInboxTagsByDefault: true,
            tagsMergeMode: .append,
            defaultDiscoveryLimit: 20,
            maxDiscoveryLimit: 100,
            defaultSnippetLength: 280,
            maxSnippetLength: 1_000,
            backupRetentionDays: 30,
            disabledTools: [],
            token: nil,
            bridge: .default
        )
    }

    public func updatingToken(_ token: String?) -> BearConfiguration {
        BearConfiguration(
            databasePath: databasePath,
            inboxTags: inboxTags,
            defaultInsertPosition: defaultInsertPosition,
            templateManagementEnabled: templateManagementEnabled,
            openNoteInEditModeByDefault: openNoteInEditModeByDefault,
            createOpensNoteByDefault: createOpensNoteByDefault,
            openUsesNewWindowByDefault: openUsesNewWindowByDefault,
            createAddsInboxTagsByDefault: createAddsInboxTagsByDefault,
            tagsMergeMode: tagsMergeMode,
            defaultDiscoveryLimit: defaultDiscoveryLimit,
            maxDiscoveryLimit: maxDiscoveryLimit,
            defaultSnippetLength: defaultSnippetLength,
            maxSnippetLength: maxSnippetLength,
            backupRetentionDays: backupRetentionDays,
            disabledTools: disabledTools,
            token: token,
            bridge: bridge
        )
    }

    public func updatingDisabledTools(_ disabledTools: [BearToolName]) -> BearConfiguration {
        BearConfiguration(
            databasePath: databasePath,
            inboxTags: inboxTags,
            defaultInsertPosition: defaultInsertPosition,
            templateManagementEnabled: templateManagementEnabled,
            openNoteInEditModeByDefault: openNoteInEditModeByDefault,
            createOpensNoteByDefault: createOpensNoteByDefault,
            openUsesNewWindowByDefault: openUsesNewWindowByDefault,
            createAddsInboxTagsByDefault: createAddsInboxTagsByDefault,
            tagsMergeMode: tagsMergeMode,
            defaultDiscoveryLimit: defaultDiscoveryLimit,
            maxDiscoveryLimit: maxDiscoveryLimit,
            defaultSnippetLength: defaultSnippetLength,
            maxSnippetLength: maxSnippetLength,
            backupRetentionDays: backupRetentionDays,
            disabledTools: disabledTools,
            token: token,
            bridge: bridge
        )
    }

    public func updatingBridge(_ bridge: BearBridgeConfiguration) -> BearConfiguration {
        BearConfiguration(
            databasePath: databasePath,
            inboxTags: inboxTags,
            defaultInsertPosition: defaultInsertPosition,
            templateManagementEnabled: templateManagementEnabled,
            openNoteInEditModeByDefault: openNoteInEditModeByDefault,
            createOpensNoteByDefault: createOpensNoteByDefault,
            openUsesNewWindowByDefault: openUsesNewWindowByDefault,
            createAddsInboxTagsByDefault: createAddsInboxTagsByDefault,
            tagsMergeMode: tagsMergeMode,
            defaultDiscoveryLimit: defaultDiscoveryLimit,
            maxDiscoveryLimit: maxDiscoveryLimit,
            defaultSnippetLength: defaultSnippetLength,
            maxSnippetLength: maxSnippetLength,
            backupRetentionDays: backupRetentionDays,
            disabledTools: disabledTools,
            token: token,
            bridge: bridge
        )
    }

    public func isToolEnabled(_ tool: BearToolName) -> Bool {
        !disabledTools.contains(tool)
    }

    private enum CodingKeys: String, CodingKey {
        case databasePath
        case inboxTags
        case defaultInsertPosition
        case templateManagementEnabled
        case openNoteInEditModeByDefault
        case createOpensNoteByDefault
        case openUsesNewWindowByDefault
        case createAddsInboxTagsByDefault
        case tagsMergeMode
        case defaultDiscoveryLimit
        case maxDiscoveryLimit
        case defaultSnippetLength
        case maxSnippetLength
        case backupRetentionDays
        case disabledTools
        case token
        case bridge
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        databasePath = try container.decodeIfPresent(String.self, forKey: .databasePath) ?? BearPaths.defaultBearDatabaseURL.path
        inboxTags = try container.decodeIfPresent([String].self, forKey: .inboxTags) ?? ["0-inbox"]
        defaultInsertPosition = try container.decodeIfPresent(InsertDefault.self, forKey: .defaultInsertPosition) ?? .bottom
        templateManagementEnabled = try container.decodeIfPresent(Bool.self, forKey: .templateManagementEnabled) ?? true
        openNoteInEditModeByDefault = try container.decodeIfPresent(Bool.self, forKey: .openNoteInEditModeByDefault) ?? true
        createOpensNoteByDefault = try container.decodeIfPresent(Bool.self, forKey: .createOpensNoteByDefault) ?? true
        openUsesNewWindowByDefault = try container.decodeIfPresent(Bool.self, forKey: .openUsesNewWindowByDefault) ?? true
        createAddsInboxTagsByDefault = try container.decodeIfPresent(Bool.self, forKey: .createAddsInboxTagsByDefault) ?? true
        tagsMergeMode = try container.decodeIfPresent(TagsMergeMode.self, forKey: .tagsMergeMode) ?? .append
        defaultDiscoveryLimit = try container.decodeIfPresent(Int.self, forKey: .defaultDiscoveryLimit) ?? 20
        maxDiscoveryLimit = try container.decodeIfPresent(Int.self, forKey: .maxDiscoveryLimit) ?? 100
        defaultSnippetLength = try container.decodeIfPresent(Int.self, forKey: .defaultSnippetLength) ?? 280
        maxSnippetLength = try container.decodeIfPresent(Int.self, forKey: .maxSnippetLength) ?? 1_000
        backupRetentionDays = max(0, try container.decodeIfPresent(Int.self, forKey: .backupRetentionDays) ?? 30)
        disabledTools = Self.normalizedDisabledTools(try container.decodeIfPresent([BearToolName].self, forKey: .disabledTools) ?? [])
        token = Self.normalizedToken(try container.decodeIfPresent(String.self, forKey: .token))
        bridge = try container.decodeIfPresent(BearBridgeConfiguration.self, forKey: .bridge) ?? .default
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(databasePath, forKey: .databasePath)
        try container.encode(inboxTags, forKey: .inboxTags)
        try container.encode(defaultInsertPosition, forKey: .defaultInsertPosition)
        try container.encode(templateManagementEnabled, forKey: .templateManagementEnabled)
        try container.encode(openNoteInEditModeByDefault, forKey: .openNoteInEditModeByDefault)
        try container.encode(createOpensNoteByDefault, forKey: .createOpensNoteByDefault)
        try container.encode(openUsesNewWindowByDefault, forKey: .openUsesNewWindowByDefault)
        try container.encode(createAddsInboxTagsByDefault, forKey: .createAddsInboxTagsByDefault)
        try container.encode(tagsMergeMode, forKey: .tagsMergeMode)
        try container.encode(defaultDiscoveryLimit, forKey: .defaultDiscoveryLimit)
        try container.encode(maxDiscoveryLimit, forKey: .maxDiscoveryLimit)
        try container.encode(defaultSnippetLength, forKey: .defaultSnippetLength)
        try container.encode(maxSnippetLength, forKey: .maxSnippetLength)
        try container.encode(backupRetentionDays, forKey: .backupRetentionDays)
        try container.encode(disabledTools, forKey: .disabledTools)
        if let token {
            try container.encode(token, forKey: .token)
        }
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
    static func normalizedToken(_ value: String?) -> String? {
        guard let value else {
            return nil
        }

        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    public static func normalizedDisabledTools(_ value: [BearToolName]) -> [BearToolName] {
        Array(Set(value)).sorted { $0.rawValue < $1.rawValue }
    }
}
