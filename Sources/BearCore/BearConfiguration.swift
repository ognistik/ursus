import Foundation

public struct BearConfiguration: Codable, Hashable, Sendable {
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

    public enum CreateRequestTagsMode: String, Codable, Hashable, Sendable {
        case append
        case replace

        public init(from decoder: Decoder) throws {
            let container = try decoder.singleValueContainer()
            let raw = try container.decode(String.self)
            switch raw {
            case "append", "append_active":
                self = .append
            case "replace", "replace_active":
                self = .replace
            default:
                throw DecodingError.dataCorruptedError(in: container, debugDescription: "Invalid createRequestTagsMode '\(raw)'.")
            }
        }

        public func encode(to encoder: Encoder) throws {
            var container = encoder.singleValueContainer()
            try container.encode(rawValue)
        }
    }

    public var databasePath: String
    public var activeTags: [String]
    public var defaultInsertPosition: InsertDefault
    public var templateManagementEnabled: Bool
    public var openNoteInEditModeByDefault: Bool
    public var createOpensNoteByDefault: Bool
    public var openUsesNewWindowByDefault: Bool
    public var createAddsActiveTagsByDefault: Bool
    public var createRequestTagsMode: CreateRequestTagsMode
    public var defaultDiscoveryLimit: Int
    public var maxDiscoveryLimit: Int
    public var defaultSnippetLength: Int
    public var maxSnippetLength: Int

    public init(
        databasePath: String,
        activeTags: [String],
        defaultInsertPosition: InsertDefault,
        templateManagementEnabled: Bool,
        openNoteInEditModeByDefault: Bool,
        createOpensNoteByDefault: Bool,
        openUsesNewWindowByDefault: Bool,
        createAddsActiveTagsByDefault: Bool,
        createRequestTagsMode: CreateRequestTagsMode,
        defaultDiscoveryLimit: Int,
        maxDiscoveryLimit: Int,
        defaultSnippetLength: Int,
        maxSnippetLength: Int
    ) {
        self.databasePath = databasePath
        self.activeTags = activeTags
        self.defaultInsertPosition = defaultInsertPosition
        self.templateManagementEnabled = templateManagementEnabled
        self.openNoteInEditModeByDefault = openNoteInEditModeByDefault
        self.createOpensNoteByDefault = createOpensNoteByDefault
        self.openUsesNewWindowByDefault = openUsesNewWindowByDefault
        self.createAddsActiveTagsByDefault = createAddsActiveTagsByDefault
        self.createRequestTagsMode = createRequestTagsMode
        self.defaultDiscoveryLimit = defaultDiscoveryLimit
        self.maxDiscoveryLimit = maxDiscoveryLimit
        self.defaultSnippetLength = defaultSnippetLength
        self.maxSnippetLength = maxSnippetLength
    }

    public static var `default`: BearConfiguration {
        BearConfiguration(
            databasePath: BearPaths.defaultBearDatabaseURL.path,
            activeTags: ["0-inbox"],
            defaultInsertPosition: .bottom,
            templateManagementEnabled: true,
            openNoteInEditModeByDefault: true,
            createOpensNoteByDefault: true,
            openUsesNewWindowByDefault: true,
            createAddsActiveTagsByDefault: true,
            createRequestTagsMode: .append,
            defaultDiscoveryLimit: 20,
            maxDiscoveryLimit: 100,
            defaultSnippetLength: 280,
            maxSnippetLength: 1_000
        )
    }

    private enum CodingKeys: String, CodingKey {
        case databasePath
        case activeTags
        case defaultInsertPosition
        case templateManagementEnabled
        case openNoteInEditModeByDefault
        case createOpensNoteByDefault
        case openUsesNewWindowByDefault
        case createAddsActiveTagsByDefault
        case createRequestTagsMode
        case defaultDiscoveryLimit
        case maxDiscoveryLimit
        case defaultSnippetLength
        case maxSnippetLength
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        databasePath = try container.decodeIfPresent(String.self, forKey: .databasePath) ?? BearPaths.defaultBearDatabaseURL.path
        activeTags = try container.decodeIfPresent([String].self, forKey: .activeTags) ?? ["0-inbox"]
        defaultInsertPosition = try container.decodeIfPresent(InsertDefault.self, forKey: .defaultInsertPosition) ?? .bottom
        templateManagementEnabled = try container.decodeIfPresent(Bool.self, forKey: .templateManagementEnabled) ?? true
        openNoteInEditModeByDefault = try container.decodeIfPresent(Bool.self, forKey: .openNoteInEditModeByDefault) ?? true
        createOpensNoteByDefault = try container.decodeIfPresent(Bool.self, forKey: .createOpensNoteByDefault) ?? true
        openUsesNewWindowByDefault = try container.decodeIfPresent(Bool.self, forKey: .openUsesNewWindowByDefault) ?? true
        createAddsActiveTagsByDefault = try container.decodeIfPresent(Bool.self, forKey: .createAddsActiveTagsByDefault) ?? true
        createRequestTagsMode = try container.decodeIfPresent(CreateRequestTagsMode.self, forKey: .createRequestTagsMode) ?? .append
        defaultDiscoveryLimit = try container.decodeIfPresent(Int.self, forKey: .defaultDiscoveryLimit) ?? 20
        maxDiscoveryLimit = try container.decodeIfPresent(Int.self, forKey: .maxDiscoveryLimit) ?? 100
        defaultSnippetLength = try container.decodeIfPresent(Int.self, forKey: .defaultSnippetLength) ?? 280
        maxSnippetLength = try container.decodeIfPresent(Int.self, forKey: .maxSnippetLength) ?? 1_000
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
