import BearCore
import CryptoKit
import Foundation
import GRDB

public enum BearBridgeAuthTokenKind: String, Codable, Hashable, Sendable {
    case authorizationCode
    case refreshToken
    case accessToken
}

public enum BearBridgeAuthRequestStatus: String, Codable, Hashable, Sendable {
    case pending
    case approved
    case denied
    case completed
    case expired
}

public struct BearBridgeAuthStoreSnapshot: Codable, Hashable, Sendable {
    public let storagePath: String
    public let storageReady: Bool
    public let registeredClientCount: Int
    public let activeGrantCount: Int
    public let pendingAuthorizationRequestCount: Int
    public let activeAuthorizationCodeCount: Int
    public let activeRefreshTokenCount: Int
    public let activeAccessTokenCount: Int
    public let revocationCount: Int

    public init(
        storagePath: String,
        storageReady: Bool,
        registeredClientCount: Int,
        activeGrantCount: Int,
        pendingAuthorizationRequestCount: Int,
        activeAuthorizationCodeCount: Int,
        activeRefreshTokenCount: Int,
        activeAccessTokenCount: Int,
        revocationCount: Int
    ) {
        self.storagePath = storagePath
        self.storageReady = storageReady
        self.registeredClientCount = registeredClientCount
        self.activeGrantCount = activeGrantCount
        self.pendingAuthorizationRequestCount = pendingAuthorizationRequestCount
        self.activeAuthorizationCodeCount = activeAuthorizationCodeCount
        self.activeRefreshTokenCount = activeRefreshTokenCount
        self.activeAccessTokenCount = activeAccessTokenCount
        self.revocationCount = revocationCount
    }

    public var hasStoredAuthState: Bool {
        registeredClientCount > 0
            || activeGrantCount > 0
            || pendingAuthorizationRequestCount > 0
            || activeAuthorizationCodeCount > 0
            || activeRefreshTokenCount > 0
            || activeAccessTokenCount > 0
            || revocationCount > 0
    }

    public var compactSummary: String {
        guard storageReady else {
            return "Auth storage not initialized yet."
        }

        return "\(activeGrantCount) grants, \(pendingAuthorizationRequestCount) pending requests"
    }

    static func empty(storagePath: String, storageReady: Bool = false) -> BearBridgeAuthStoreSnapshot {
        BearBridgeAuthStoreSnapshot(
            storagePath: storagePath,
            storageReady: storageReady,
            registeredClientCount: 0,
            activeGrantCount: 0,
            pendingAuthorizationRequestCount: 0,
            activeAuthorizationCodeCount: 0,
            activeRefreshTokenCount: 0,
            activeAccessTokenCount: 0,
            revocationCount: 0
        )
    }
}

public struct BearBridgePendingAuthorizationRequestSummary: Codable, Hashable, Sendable, Identifiable {
    public let id: String
    public let clientID: String
    public let clientDisplayName: String?
    public let grantID: String?
    public let requestedScope: String
    public let resource: String?
    public let redirectURI: String
    public let state: String?
    public let status: BearBridgeAuthRequestStatus
    public let createdAt: Date
    public let expiresAt: Date
    public let resolvedAt: Date?

    public var clientTitle: String {
        clientDisplayName ?? clientID
    }
}

public struct BearBridgeAuthGrantSummary: Codable, Hashable, Sendable, Identifiable {
    public let id: String
    public let clientID: String
    public let clientDisplayName: String?
    public let scope: String
    public let resource: String?
    public let createdAt: Date
    public let updatedAt: Date

    public var clientTitle: String {
        clientDisplayName ?? clientID
    }
}

public struct BearBridgeAuthReviewSnapshot: Codable, Hashable, Sendable {
    public let storagePath: String
    public let storageReady: Bool
    public let pendingRequests: [BearBridgePendingAuthorizationRequestSummary]
    public let activeGrants: [BearBridgeAuthGrantSummary]

    public init(
        storagePath: String,
        storageReady: Bool,
        pendingRequests: [BearBridgePendingAuthorizationRequestSummary],
        activeGrants: [BearBridgeAuthGrantSummary]
    ) {
        self.storagePath = storagePath
        self.storageReady = storageReady
        self.pendingRequests = pendingRequests
        self.activeGrants = activeGrants
    }

    public var hasStoredAuthState: Bool {
        !pendingRequests.isEmpty || !activeGrants.isEmpty
    }

    public var compactSummary: String {
        "\(activeGrants.count) grants, \(pendingRequests.count) pending requests"
    }

    static func empty(storagePath: String, storageReady: Bool = false) -> BearBridgeAuthReviewSnapshot {
        BearBridgeAuthReviewSnapshot(
            storagePath: storagePath,
            storageReady: storageReady,
            pendingRequests: [],
            activeGrants: []
        )
    }
}

public struct BearBridgeAuthClientDraft: Hashable, Sendable {
    public let displayName: String?
    public let redirectURIs: [String]
    public let metadataJSON: String?

    public init(
        displayName: String? = nil,
        redirectURIs: [String],
        metadataJSON: String? = nil
    ) {
        self.displayName = displayName
        self.redirectURIs = redirectURIs
        self.metadataJSON = metadataJSON
    }
}

public struct BearBridgeAuthClient: Codable, Hashable, Sendable, Identifiable {
    public let id: String
    public let displayName: String?
    public let redirectURIs: [String]
    public let metadataJSON: String
    public let createdAt: Date
    public let updatedAt: Date
}

public struct BearBridgeAuthGrantDraft: Hashable, Sendable {
    public let clientID: String
    public let scope: String
    public let resource: String?
    public let metadataJSON: String?

    public init(
        clientID: String,
        scope: String,
        resource: String? = nil,
        metadataJSON: String? = nil
    ) {
        self.clientID = clientID
        self.scope = scope
        self.resource = resource
        self.metadataJSON = metadataJSON
    }
}

public struct BearBridgeAuthGrant: Codable, Hashable, Sendable, Identifiable {
    public let id: String
    public let clientID: String
    public let scope: String
    public let resource: String?
    public let metadataJSON: String
    public let createdAt: Date
    public let updatedAt: Date
    public let revokedAt: Date?

    public var isActive: Bool {
        revokedAt == nil
    }
}

public struct BearBridgePendingAuthorizationRequestDraft: Hashable, Sendable {
    public let clientID: String
    public let grantID: String?
    public let requestedScope: String
    public let redirectURI: String
    public let state: String?
    public let codeChallenge: String?
    public let codeChallengeMethod: String?
    public let expiresAt: Date
    public let metadataJSON: String?

    public init(
        clientID: String,
        grantID: String? = nil,
        requestedScope: String,
        redirectURI: String,
        state: String? = nil,
        codeChallenge: String? = nil,
        codeChallengeMethod: String? = nil,
        expiresAt: Date,
        metadataJSON: String? = nil
    ) {
        self.clientID = clientID
        self.grantID = grantID
        self.requestedScope = requestedScope
        self.redirectURI = redirectURI
        self.state = state
        self.codeChallenge = codeChallenge
        self.codeChallengeMethod = codeChallengeMethod
        self.expiresAt = expiresAt
        self.metadataJSON = metadataJSON
    }
}

public struct BearBridgePendingAuthorizationRequest: Codable, Hashable, Sendable, Identifiable {
    public let id: String
    public let clientID: String
    public let grantID: String?
    public let requestedScope: String
    public let redirectURI: String
    public let state: String?
    public let codeChallenge: String?
    public let codeChallengeMethod: String?
    public let status: BearBridgeAuthRequestStatus
    public let metadataJSON: String
    public let createdAt: Date
    public let expiresAt: Date
    public let resolvedAt: Date?

    public var isPending: Bool {
        status == .pending && resolvedAt == nil
    }
}

public struct BearBridgeAuthorizationCodeDraft: Hashable, Sendable {
    public let clientID: String
    public let grantID: String?
    public let pendingRequestID: String?
    public let scope: String
    public let redirectURI: String
    public let codeChallenge: String?
    public let codeChallengeMethod: String?
    public let expiresAt: Date

    public init(
        clientID: String,
        grantID: String? = nil,
        pendingRequestID: String? = nil,
        scope: String,
        redirectURI: String,
        codeChallenge: String? = nil,
        codeChallengeMethod: String? = nil,
        expiresAt: Date
    ) {
        self.clientID = clientID
        self.grantID = grantID
        self.pendingRequestID = pendingRequestID
        self.scope = scope
        self.redirectURI = redirectURI
        self.codeChallenge = codeChallenge
        self.codeChallengeMethod = codeChallengeMethod
        self.expiresAt = expiresAt
    }
}

public struct BearBridgeAuthorizationCode: Codable, Hashable, Sendable, Identifiable {
    public let id: String
    public let clientID: String
    public let grantID: String?
    public let pendingRequestID: String?
    public let scope: String
    public let redirectURI: String
    public let codeChallenge: String?
    public let codeChallengeMethod: String?
    public let createdAt: Date
    public let expiresAt: Date
    public let redeemedAt: Date?
    public let revokedAt: Date?

    public var isActive: Bool {
        redeemedAt == nil && revokedAt == nil
    }
}

public struct BearBridgeRefreshTokenDraft: Hashable, Sendable {
    public let clientID: String
    public let grantID: String?
    public let scope: String
    public let expiresAt: Date?
    public let metadataJSON: String?

    public init(
        clientID: String,
        grantID: String? = nil,
        scope: String,
        expiresAt: Date? = nil,
        metadataJSON: String? = nil
    ) {
        self.clientID = clientID
        self.grantID = grantID
        self.scope = scope
        self.expiresAt = expiresAt
        self.metadataJSON = metadataJSON
    }
}

public struct BearBridgeRefreshToken: Codable, Hashable, Sendable, Identifiable {
    public let id: String
    public let clientID: String
    public let grantID: String?
    public let scope: String
    public let metadataJSON: String
    public let createdAt: Date
    public let expiresAt: Date?
    public let rotatedAt: Date?
    public let revokedAt: Date?
    public let replacedByTokenID: String?

    public var isActive: Bool {
        rotatedAt == nil && revokedAt == nil
    }
}

public struct BearBridgeAccessTokenDraft: Hashable, Sendable {
    public let clientID: String
    public let grantID: String?
    public let refreshTokenID: String?
    public let scope: String
    public let expiresAt: Date
    public let metadataJSON: String?

    public init(
        clientID: String,
        grantID: String? = nil,
        refreshTokenID: String? = nil,
        scope: String,
        expiresAt: Date,
        metadataJSON: String? = nil
    ) {
        self.clientID = clientID
        self.grantID = grantID
        self.refreshTokenID = refreshTokenID
        self.scope = scope
        self.expiresAt = expiresAt
        self.metadataJSON = metadataJSON
    }
}

public struct BearBridgeAccessToken: Codable, Hashable, Sendable, Identifiable {
    public let id: String
    public let clientID: String
    public let grantID: String?
    public let refreshTokenID: String?
    public let scope: String
    public let metadataJSON: String
    public let createdAt: Date
    public let expiresAt: Date
    public let revokedAt: Date?

    public var isActive: Bool {
        revokedAt == nil
    }
}

public struct BearBridgeIssuedAuthorizationCode: Hashable, Sendable {
    public let code: String
    public let record: BearBridgeAuthorizationCode
}

public struct BearBridgeIssuedRefreshToken: Hashable, Sendable {
    public let token: String
    public let record: BearBridgeRefreshToken
}

public struct BearBridgeIssuedAccessToken: Hashable, Sendable {
    public let token: String
    public let record: BearBridgeAccessToken
}

public struct BearBridgeAuthRevocation: Codable, Hashable, Sendable, Identifiable {
    public let id: String
    public let tokenKind: BearBridgeAuthTokenKind
    public let clientID: String?
    public let reason: String?
    public let metadataJSON: String
    public let createdAt: Date
}

public actor BearBridgeAuthStore {
    public typealias IdentifierGenerator = @Sendable () -> String
    public typealias SecretGenerator = @Sendable (_ kind: BearBridgeAuthTokenKind) -> String

    private let databaseURL: URL
    private let fileManager: FileManager
    private let now: @Sendable () -> Date
    private let identifierGenerator: IdentifierGenerator
    private let secretGenerator: SecretGenerator
    private var databaseQueue: DatabaseQueue?

    public init(
        databaseURL: URL = BearPaths.bridgeAuthDatabaseURL,
        fileManager: FileManager = .default,
        now: @escaping @Sendable () -> Date = { Date() },
        identifierGenerator: @escaping IdentifierGenerator = { UUID().uuidString.lowercased() },
        secretGenerator: @escaping SecretGenerator = { kind in
            let prefix: String
            switch kind {
            case .authorizationCode:
                prefix = "uc"
            case .refreshToken:
                prefix = "urt"
            case .accessToken:
                prefix = "uat"
            }

            let first = UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased()
            let second = UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased()
            return "\(prefix)_\(first)\(second)"
        }
    ) {
        self.databaseURL = databaseURL
        self.fileManager = fileManager
        self.now = now
        self.identifierGenerator = identifierGenerator
        self.secretGenerator = secretGenerator
    }

    public func snapshot(prepareIfMissing: Bool = true) throws -> BearBridgeAuthStoreSnapshot {
        try Self.loadSnapshot(
            databaseURL: databaseURL,
            fileManager: fileManager,
            now: now,
            prepareIfMissing: prepareIfMissing
        )
    }

    public func reviewSnapshot(prepareIfMissing: Bool = false) throws -> BearBridgeAuthReviewSnapshot {
        try Self.loadReviewSnapshot(
            databaseURL: databaseURL,
            fileManager: fileManager,
            now: now,
            prepareIfMissing: prepareIfMissing
        )
    }

    public func registerClient(_ draft: BearBridgeAuthClientDraft) throws -> BearBridgeAuthClient {
        let dbQueue = try prepareDatabaseQueue()
        let createdAt = now()
        let record = BridgeAuthClientRecord(
            clientID: identifierGenerator(),
            displayName: Self.normalizedOptionalString(draft.displayName),
            redirectURIsJSON: try Self.encodeRedirectURIs(draft.redirectURIs),
            metadataJSON: try Self.normalizedMetadataJSON(draft.metadataJSON),
            createdAt: createdAt,
            updatedAt: createdAt
        )

        try dbQueue.write { db in
            try record.insert(db)
        }

        return try record.makeModel()
    }

    public func client(id: String) throws -> BearBridgeAuthClient? {
        let dbQueue = try prepareDatabaseQueue()
        let record = try dbQueue.read { db in
            try BridgeAuthClientRecord.fetchOne(db, key: id)
        }
        return try record?.makeModel()
    }

    public func createGrant(_ draft: BearBridgeAuthGrantDraft) throws -> BearBridgeAuthGrant {
        let dbQueue = try prepareDatabaseQueue()
        let createdAt = now()
        let record = BridgeAuthGrantRecord(
            grantID: identifierGenerator(),
            clientID: draft.clientID,
            scope: try Self.normalizedRequiredString(draft.scope, label: "Grant scope"),
            resource: Self.normalizedOptionalString(draft.resource),
            metadataJSON: try Self.normalizedMetadataJSON(draft.metadataJSON),
            createdAt: createdAt,
            updatedAt: createdAt,
            revokedAt: nil
        )

        try dbQueue.write { db in
            try record.insert(db)
        }

        return record.makeModel()
    }

    public func grant(id: String) throws -> BearBridgeAuthGrant? {
        let dbQueue = try prepareDatabaseQueue()
        let record = try dbQueue.read { db in
            try BridgeAuthGrantRecord.fetchOne(db, key: id)
        }
        return record?.makeModel()
    }

    public func activeGrant(
        clientID: String,
        scope: String,
        resource: String? = nil
    ) throws -> BearBridgeAuthGrant? {
        let dbQueue = try prepareDatabaseQueue()
        let normalizedScope = try Self.normalizedRequiredString(scope, label: "Grant scope")
        let normalizedResource = Self.normalizedOptionalString(resource)
        let record = try dbQueue.read { db in
            try BridgeAuthGrantRecord.fetchOne(
                db,
                sql: """
                SELECT *
                FROM grants
                WHERE client_id = ?
                    AND scope = ?
                    AND revoked_at IS NULL
                    AND (
                        (resource IS NULL AND ? IS NULL)
                        OR resource = ?
                    )
                ORDER BY created_at ASC
                LIMIT 1
                """,
                arguments: [clientID, normalizedScope, normalizedResource, normalizedResource]
            )
        }
        return record?.makeModel()
    }

    public func ensureGrant(_ draft: BearBridgeAuthGrantDraft) throws -> BearBridgeAuthGrant {
        if let existing = try activeGrant(
            clientID: draft.clientID,
            scope: draft.scope,
            resource: draft.resource
        ) {
            return existing
        }

        return try createGrant(draft)
    }

    public func revokeGrant(id: String) throws -> BearBridgeAuthGrant? {
        let dbQueue = try prepareDatabaseQueue()
        let revokedAt = now()

        return try dbQueue.write { db in
            guard var record = try BridgeAuthGrantRecord.fetchOne(db, key: id) else {
                return nil
            }

            record.revokedAt = revokedAt
            record.updatedAt = revokedAt
            try record.update(db)
            try db.execute(
                sql: """
                UPDATE authorization_codes
                SET revoked_at = COALESCE(revoked_at, ?)
                WHERE grant_id = ?
                """,
                arguments: [revokedAt.timeIntervalSince1970, id]
            )
            try db.execute(
                sql: """
                UPDATE refresh_tokens
                SET revoked_at = COALESCE(revoked_at, ?)
                WHERE grant_id = ?
                """,
                arguments: [revokedAt.timeIntervalSince1970, id]
            )
            try db.execute(
                sql: """
                UPDATE access_tokens
                SET revoked_at = COALESCE(revoked_at, ?)
                WHERE grant_id = ?
                """,
                arguments: [revokedAt.timeIntervalSince1970, id]
            )
            return record.makeModel()
        }
    }

    public func createPendingAuthorizationRequest(
        _ draft: BearBridgePendingAuthorizationRequestDraft
    ) throws -> BearBridgePendingAuthorizationRequest {
        let dbQueue = try prepareDatabaseQueue()
        let record = BridgeAuthPendingRequestRecord(
            requestID: identifierGenerator(),
            clientID: draft.clientID,
            grantID: draft.grantID,
            requestedScope: try Self.normalizedRequiredString(draft.requestedScope, label: "Requested scope"),
            redirectURI: try Self.normalizedRequiredString(draft.redirectURI, label: "Redirect URI"),
            state: Self.normalizedOptionalString(draft.state),
            codeChallenge: Self.normalizedOptionalString(draft.codeChallenge),
            codeChallengeMethod: Self.normalizedOptionalString(draft.codeChallengeMethod),
            status: .pending,
            metadataJSON: try Self.normalizedMetadataJSON(draft.metadataJSON),
            createdAt: now(),
            expiresAt: draft.expiresAt,
            resolvedAt: nil
        )

        try dbQueue.write { db in
            try record.insert(db)
        }

        return record.makeModel()
    }

    public func pendingAuthorizationRequest(id: String) throws -> BearBridgePendingAuthorizationRequest? {
        let dbQueue = try prepareDatabaseQueue()
        let record = try dbQueue.read { db in
            try BridgeAuthPendingRequestRecord.fetchOne(db, key: id)
        }
        return record?.makeModel()
    }

    public func pendingAuthorizationRequestSummaries() throws -> [BearBridgePendingAuthorizationRequestSummary] {
        let dbQueue = try prepareDatabaseQueue()
        return try Self.pendingAuthorizationRequestSummaries(using: dbQueue, now: now())
    }

    public func activeGrantSummaries() throws -> [BearBridgeAuthGrantSummary] {
        let dbQueue = try prepareDatabaseQueue()
        return try Self.activeGrantSummaries(using: dbQueue)
    }

    public func updatePendingAuthorizationRequestStatus(
        id: String,
        status: BearBridgeAuthRequestStatus
    ) throws -> BearBridgePendingAuthorizationRequest? {
        let dbQueue = try prepareDatabaseQueue()
        let resolvedAt = status == .pending ? nil : now()

        return try dbQueue.write { db in
            guard var record = try BridgeAuthPendingRequestRecord.fetchOne(db, key: id) else {
                return nil
            }

            record.status = status
            record.resolvedAt = resolvedAt
            try record.update(db)
            return record.makeModel()
        }
    }

    public func approvePendingAuthorizationRequest(
        id: String
    ) throws -> BearBridgePendingAuthorizationRequest? {
        guard let request = try pendingAuthorizationRequest(id: id) else {
            return nil
        }

        if request.status == .pending, request.expiresAt < now() {
            return try updatePendingAuthorizationRequestStatus(id: id, status: .expired)
        }

        guard request.status == .pending else {
            return request
        }

        let resource = Self.metadataValue(named: "resource", in: request.metadataJSON)
        _ = try ensureGrant(
            BearBridgeAuthGrantDraft(
                clientID: request.clientID,
                scope: request.requestedScope,
                resource: resource,
                metadataJSON: Self.metadataJSONString(
                    [
                        "approved_by": "ursus-app",
                        "resource": resource,
                    ]
                )
            )
        )
        return try updatePendingAuthorizationRequestStatus(id: id, status: .approved)
    }

    public func denyPendingAuthorizationRequest(
        id: String
    ) throws -> BearBridgePendingAuthorizationRequest? {
        guard let request = try pendingAuthorizationRequest(id: id) else {
            return nil
        }

        if request.status == .pending, request.expiresAt < now() {
            return try updatePendingAuthorizationRequestStatus(id: id, status: .expired)
        }

        guard request.status == .pending else {
            return request
        }

        return try updatePendingAuthorizationRequestStatus(id: id, status: .denied)
    }

    public func issueAuthorizationCode(
        _ draft: BearBridgeAuthorizationCodeDraft
    ) throws -> BearBridgeIssuedAuthorizationCode {
        let dbQueue = try prepareDatabaseQueue()
        let secret = secretGenerator(.authorizationCode)
        let record = BridgeAuthAuthorizationCodeRecord(
            codeID: identifierGenerator(),
            clientID: draft.clientID,
            grantID: draft.grantID,
            pendingRequestID: draft.pendingRequestID,
            codeHash: Self.hash(secret),
            scope: try Self.normalizedRequiredString(draft.scope, label: "Authorization code scope"),
            redirectURI: try Self.normalizedRequiredString(draft.redirectURI, label: "Authorization code redirect URI"),
            codeChallenge: Self.normalizedOptionalString(draft.codeChallenge),
            codeChallengeMethod: Self.normalizedOptionalString(draft.codeChallengeMethod),
            createdAt: now(),
            expiresAt: draft.expiresAt,
            redeemedAt: nil,
            revokedAt: nil
        )

        try dbQueue.write { db in
            try record.insert(db)
        }

        return BearBridgeIssuedAuthorizationCode(code: secret, record: record.makeModel())
    }

    public func authorizationCode(for rawCode: String) throws -> BearBridgeAuthorizationCode? {
        let dbQueue = try prepareDatabaseQueue()
        let record = try dbQueue.read { db in
            try BridgeAuthAuthorizationCodeRecord.fetchOne(
                db,
                sql: """
                SELECT *
                FROM authorization_codes
                WHERE code_hash = ?
                    AND redeemed_at IS NULL
                    AND revoked_at IS NULL
                    AND expires_at >= ?
                LIMIT 1
                """,
                arguments: [Self.hash(rawCode), now().timeIntervalSince1970]
            )
        }
        return record?.makeModel()
    }

    public func markAuthorizationCodeRedeemed(id: String) throws -> BearBridgeAuthorizationCode? {
        let dbQueue = try prepareDatabaseQueue()
        let redeemedAt = now()

        return try dbQueue.write { db in
            guard var record = try BridgeAuthAuthorizationCodeRecord.fetchOne(db, key: id) else {
                return nil
            }

            record.redeemedAt = redeemedAt
            try record.update(db)
            return record.makeModel()
        }
    }

    public func issueRefreshToken(_ draft: BearBridgeRefreshTokenDraft) throws -> BearBridgeIssuedRefreshToken {
        let dbQueue = try prepareDatabaseQueue()
        let secret = secretGenerator(.refreshToken)
        let record = BridgeAuthRefreshTokenRecord(
            tokenID: identifierGenerator(),
            clientID: draft.clientID,
            grantID: draft.grantID,
            tokenHash: Self.hash(secret),
            scope: try Self.normalizedRequiredString(draft.scope, label: "Refresh token scope"),
            metadataJSON: try Self.normalizedMetadataJSON(draft.metadataJSON),
            createdAt: now(),
            expiresAt: draft.expiresAt,
            rotatedAt: nil,
            revokedAt: nil,
            replacedByTokenID: nil
        )

        try dbQueue.write { db in
            try record.insert(db)
        }

        return BearBridgeIssuedRefreshToken(token: secret, record: record.makeModel())
    }

    public func refreshToken(for rawToken: String) throws -> BearBridgeRefreshToken? {
        let dbQueue = try prepareDatabaseQueue()
        let nowInterval = now().timeIntervalSince1970
        let record = try dbQueue.read { db in
            try BridgeAuthRefreshTokenRecord.fetchOne(
                db,
                sql: """
                SELECT *
                FROM refresh_tokens
                WHERE token_hash = ?
                    AND rotated_at IS NULL
                    AND revoked_at IS NULL
                    AND (expires_at IS NULL OR expires_at >= ?)
                LIMIT 1
                """,
                arguments: [Self.hash(rawToken), nowInterval]
            )
        }
        return record?.makeModel()
    }

    public func rotateRefreshToken(id: String, replacedByTokenID: String) throws -> BearBridgeRefreshToken? {
        let dbQueue = try prepareDatabaseQueue()
        let rotatedAt = now()

        return try dbQueue.write { db in
            guard var record = try BridgeAuthRefreshTokenRecord.fetchOne(db, key: id) else {
                return nil
            }

            record.rotatedAt = rotatedAt
            record.replacedByTokenID = replacedByTokenID
            try record.update(db)
            return record.makeModel()
        }
    }

    public func issueAccessToken(_ draft: BearBridgeAccessTokenDraft) throws -> BearBridgeIssuedAccessToken {
        let dbQueue = try prepareDatabaseQueue()
        let secret = secretGenerator(.accessToken)
        let record = BridgeAuthAccessTokenRecord(
            tokenID: identifierGenerator(),
            clientID: draft.clientID,
            grantID: draft.grantID,
            refreshTokenID: draft.refreshTokenID,
            tokenHash: Self.hash(secret),
            scope: try Self.normalizedRequiredString(draft.scope, label: "Access token scope"),
            metadataJSON: try Self.normalizedMetadataJSON(draft.metadataJSON),
            createdAt: now(),
            expiresAt: draft.expiresAt,
            revokedAt: nil
        )

        try dbQueue.write { db in
            try record.insert(db)
        }

        return BearBridgeIssuedAccessToken(token: secret, record: record.makeModel())
    }

    public func accessToken(for rawToken: String) throws -> BearBridgeAccessToken? {
        let dbQueue = try prepareDatabaseQueue()
        let record = try dbQueue.read { db in
            try BridgeAuthAccessTokenRecord.fetchOne(
                db,
                sql: """
                SELECT *
                FROM access_tokens
                WHERE token_hash = ?
                    AND revoked_at IS NULL
                    AND expires_at >= ?
                LIMIT 1
                """,
                arguments: [Self.hash(rawToken), now().timeIntervalSince1970]
            )
        }
        return record?.makeModel()
    }

    public func validatedAccessToken(
        rawToken: String,
        resource: String? = nil,
        requiredScopes: [String] = []
    ) throws -> BearBridgeAccessToken? {
        guard let accessToken = try accessToken(for: rawToken) else {
            return nil
        }

        if let normalizedResource = Self.normalizedOptionalString(resource) {
            guard let storedResource = Self.metadataValue(named: "resource", in: accessToken.metadataJSON),
                  storedResource == normalizedResource
            else {
                return nil
            }
        }

        let normalizedRequiredScopes = requiredScopes.compactMap(Self.normalizedOptionalString)
        if !normalizedRequiredScopes.isEmpty {
            let tokenScopes = Set(
                accessToken.scope
                    .split(whereSeparator: \.isWhitespace)
                    .map(String.init)
            )
            guard normalizedRequiredScopes.allSatisfy(tokenScopes.contains) else {
                return nil
            }
        }

        return accessToken
    }

    @discardableResult
    public func revokeAuthorizationCode(rawCode: String, clientID: String? = nil, reason: String? = nil) throws -> BearBridgeAuthRevocation {
        try revokeSecret(rawValue: rawCode, kind: .authorizationCode, clientID: clientID, reason: reason)
    }

    @discardableResult
    public func revokeRefreshToken(rawToken: String, clientID: String? = nil, reason: String? = nil) throws -> BearBridgeAuthRevocation {
        try revokeSecret(rawValue: rawToken, kind: .refreshToken, clientID: clientID, reason: reason)
    }

    @discardableResult
    public func revokeAccessToken(rawToken: String, clientID: String? = nil, reason: String? = nil) throws -> BearBridgeAuthRevocation {
        try revokeSecret(rawValue: rawToken, kind: .accessToken, clientID: clientID, reason: reason)
    }

    nonisolated public static func loadSnapshot(
        databaseURL: URL = BearPaths.bridgeAuthDatabaseURL,
        fileManager: FileManager = .default,
        now: @escaping @Sendable () -> Date = { Date() },
        prepareIfMissing: Bool = false
    ) throws -> BearBridgeAuthStoreSnapshot {
        guard prepareIfMissing || fileManager.fileExists(atPath: databaseURL.path) else {
            return .empty(storagePath: databaseURL.path)
        }

        let dbQueue = try makeDatabaseQueue(
            databaseURL: databaseURL,
            fileManager: fileManager
        )
        let snapshot = try snapshot(using: dbQueue, storagePath: databaseURL.path, now: now())
        return snapshot
    }

    nonisolated public static func loadReviewSnapshot(
        databaseURL: URL = BearPaths.bridgeAuthDatabaseURL,
        fileManager: FileManager = .default,
        now: @escaping @Sendable () -> Date = { Date() },
        prepareIfMissing: Bool = false
    ) throws -> BearBridgeAuthReviewSnapshot {
        guard prepareIfMissing || fileManager.fileExists(atPath: databaseURL.path) else {
            return .empty(storagePath: databaseURL.path)
        }

        let dbQueue = try makeDatabaseQueue(
            databaseURL: databaseURL,
            fileManager: fileManager
        )
        return try reviewSnapshot(
            using: dbQueue,
            storagePath: databaseURL.path,
            now: now()
        )
    }

    @discardableResult
    nonisolated public static func prepareStorage(
        databaseURL: URL = BearPaths.bridgeAuthDatabaseURL,
        fileManager: FileManager = .default,
        now: @escaping @Sendable () -> Date = { Date() }
    ) throws -> BearBridgeAuthStoreSnapshot {
        try loadSnapshot(
            databaseURL: databaseURL,
            fileManager: fileManager,
            now: now,
            prepareIfMissing: true
        )
    }
}

private extension BearBridgeAuthStore {
    func prepareDatabaseQueue() throws -> DatabaseQueue {
        if let databaseQueue {
            return databaseQueue
        }

        let databaseQueue = try Self.makeDatabaseQueue(
            databaseURL: databaseURL,
            fileManager: fileManager
        )
        self.databaseQueue = databaseQueue
        return databaseQueue
    }

    func revokeSecret(
        rawValue: String,
        kind: BearBridgeAuthTokenKind,
        clientID: String?,
        reason: String?
    ) throws -> BearBridgeAuthRevocation {
        let dbQueue = try prepareDatabaseQueue()
        let tokenHash = Self.hash(rawValue)
        let revokedAt = now()
        let revocationRecord = BridgeAuthRevocationRecord(
            revocationID: identifierGenerator(),
            tokenKind: kind,
            tokenHash: tokenHash,
            clientID: Self.normalizedOptionalString(clientID),
            reason: Self.normalizedOptionalString(reason),
            metadataJSON: "{}",
            createdAt: revokedAt
        )

        try dbQueue.write { db in
            switch kind {
            case .authorizationCode:
                try db.execute(
                    sql: """
                    UPDATE authorization_codes
                    SET revoked_at = COALESCE(revoked_at, ?)
                    WHERE code_hash = ?
                    """,
                    arguments: [revokedAt.timeIntervalSince1970, tokenHash]
                )
            case .refreshToken:
                try db.execute(
                    sql: """
                    UPDATE refresh_tokens
                    SET revoked_at = COALESCE(revoked_at, ?)
                    WHERE token_hash = ?
                    """,
                    arguments: [revokedAt.timeIntervalSince1970, tokenHash]
                )
            case .accessToken:
                try db.execute(
                    sql: """
                    UPDATE access_tokens
                    SET revoked_at = COALESCE(revoked_at, ?)
                    WHERE token_hash = ?
                    """,
                    arguments: [revokedAt.timeIntervalSince1970, tokenHash]
                )
            }

            try revocationRecord.insert(db)
        }

        return revocationRecord.makeModel()
    }

    static func snapshot(
        using dbQueue: DatabaseQueue,
        storagePath: String,
        now: Date
    ) throws -> BearBridgeAuthStoreSnapshot {
        let nowInterval = now.timeIntervalSince1970
        let counts = try dbQueue.read { db in
            BridgeAuthCountSnapshot(
                registeredClientCount: try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM clients") ?? 0,
                activeGrantCount: try Int.fetchOne(
                    db,
                    sql: "SELECT COUNT(*) FROM grants WHERE revoked_at IS NULL"
                ) ?? 0,
                pendingAuthorizationRequestCount: try Int.fetchOne(
                    db,
                    sql: """
                    SELECT COUNT(*)
                    FROM pending_authorization_requests
                    WHERE status = ?
                        AND resolved_at IS NULL
                        AND expires_at >= ?
                    """,
                    arguments: [BearBridgeAuthRequestStatus.pending.rawValue, nowInterval]
                ) ?? 0,
                activeAuthorizationCodeCount: try Int.fetchOne(
                    db,
                    sql: """
                    SELECT COUNT(*)
                    FROM authorization_codes
                    WHERE redeemed_at IS NULL
                        AND revoked_at IS NULL
                        AND expires_at >= ?
                    """,
                    arguments: [nowInterval]
                ) ?? 0,
                activeRefreshTokenCount: try Int.fetchOne(
                    db,
                    sql: """
                    SELECT COUNT(*)
                    FROM refresh_tokens
                    WHERE rotated_at IS NULL
                        AND revoked_at IS NULL
                        AND (expires_at IS NULL OR expires_at >= ?)
                    """,
                    arguments: [nowInterval]
                ) ?? 0,
                activeAccessTokenCount: try Int.fetchOne(
                    db,
                    sql: """
                    SELECT COUNT(*)
                    FROM access_tokens
                    WHERE revoked_at IS NULL
                        AND expires_at >= ?
                    """,
                    arguments: [nowInterval]
                ) ?? 0,
                revocationCount: try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM revocations") ?? 0
            )
        }

        return BearBridgeAuthStoreSnapshot(
            storagePath: storagePath,
            storageReady: true,
            registeredClientCount: counts.registeredClientCount,
            activeGrantCount: counts.activeGrantCount,
            pendingAuthorizationRequestCount: counts.pendingAuthorizationRequestCount,
            activeAuthorizationCodeCount: counts.activeAuthorizationCodeCount,
            activeRefreshTokenCount: counts.activeRefreshTokenCount,
            activeAccessTokenCount: counts.activeAccessTokenCount,
            revocationCount: counts.revocationCount
        )
    }

    static func reviewSnapshot(
        using dbQueue: DatabaseQueue,
        storagePath: String,
        now: Date
    ) throws -> BearBridgeAuthReviewSnapshot {
        BearBridgeAuthReviewSnapshot(
            storagePath: storagePath,
            storageReady: true,
            pendingRequests: try pendingAuthorizationRequestSummaries(using: dbQueue, now: now),
            activeGrants: try activeGrantSummaries(using: dbQueue)
        )
    }

    static func pendingAuthorizationRequestSummaries(
        using dbQueue: DatabaseQueue,
        now: Date
    ) throws -> [BearBridgePendingAuthorizationRequestSummary] {
        try dbQueue.read { db in
            try BridgeAuthPendingRequestSummaryRow.fetchAll(
                db,
                sql: """
                SELECT
                    pending_authorization_requests.*,
                    clients.display_name AS client_display_name
                FROM pending_authorization_requests
                JOIN clients ON clients.client_id = pending_authorization_requests.client_id
                WHERE pending_authorization_requests.status = ?
                    AND pending_authorization_requests.resolved_at IS NULL
                    AND pending_authorization_requests.expires_at >= ?
                ORDER BY pending_authorization_requests.created_at ASC
                """,
                arguments: [
                    BearBridgeAuthRequestStatus.pending.rawValue,
                    now.timeIntervalSince1970,
                ]
            )
            .map(\.model)
        }
    }

    static func activeGrantSummaries(
        using dbQueue: DatabaseQueue
    ) throws -> [BearBridgeAuthGrantSummary] {
        try dbQueue.read { db in
            try BridgeAuthGrantSummaryRow.fetchAll(
                db,
                sql: """
                SELECT
                    grants.*,
                    clients.display_name AS client_display_name
                FROM grants
                JOIN clients ON clients.client_id = grants.client_id
                WHERE grants.revoked_at IS NULL
                ORDER BY grants.updated_at DESC, grants.created_at DESC
                """
            )
            .map(\.model)
        }
    }

    static func makeDatabaseQueue(
        databaseURL: URL,
        fileManager: FileManager
    ) throws -> DatabaseQueue {
        try fileManager.createDirectory(
            at: databaseURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )

        var configuration = Configuration()
        configuration.label = "ursus.bridge-auth"
        configuration.prepareDatabase { db in
            try db.execute(sql: "PRAGMA foreign_keys = ON")
        }

        let dbQueue = try DatabaseQueue(path: databaseURL.path, configuration: configuration)
        var migrator = DatabaseMigrator()
        migrator.registerMigration("createBridgeAuthTables") { db in
            try db.create(table: "clients") { table in
                table.column("client_id", .text).notNull().primaryKey()
                table.column("display_name", .text)
                table.column("redirect_uris_json", .text).notNull()
                table.column("metadata_json", .text).notNull()
                table.column("created_at", .double).notNull()
                table.column("updated_at", .double).notNull()
            }

            try db.create(table: "grants") { table in
                table.column("grant_id", .text).notNull().primaryKey()
                table.column("client_id", .text).notNull()
                    .references("clients", column: "client_id", onDelete: .cascade)
                table.column("scope", .text).notNull()
                table.column("resource", .text)
                table.column("metadata_json", .text).notNull()
                table.column("created_at", .double).notNull()
                table.column("updated_at", .double).notNull()
                table.column("revoked_at", .double)
            }
            try db.create(index: "grants_client_idx", on: "grants", columns: ["client_id"])

            try db.create(table: "pending_authorization_requests") { table in
                table.column("request_id", .text).notNull().primaryKey()
                table.column("client_id", .text).notNull()
                    .references("clients", column: "client_id", onDelete: .cascade)
                table.column("grant_id", .text)
                    .references("grants", column: "grant_id", onDelete: .setNull)
                table.column("requested_scope", .text).notNull()
                table.column("redirect_uri", .text).notNull()
                table.column("state", .text)
                table.column("code_challenge", .text)
                table.column("code_challenge_method", .text)
                table.column("status", .text).notNull()
                table.column("metadata_json", .text).notNull()
                table.column("created_at", .double).notNull()
                table.column("expires_at", .double).notNull()
                table.column("resolved_at", .double)
            }
            try db.create(
                index: "pending_authorization_requests_status_idx",
                on: "pending_authorization_requests",
                columns: ["status", "expires_at"]
            )

            try db.create(table: "authorization_codes") { table in
                table.column("code_id", .text).notNull().primaryKey()
                table.column("client_id", .text).notNull()
                    .references("clients", column: "client_id", onDelete: .cascade)
                table.column("grant_id", .text)
                    .references("grants", column: "grant_id", onDelete: .setNull)
                table.column("pending_request_id", .text)
                    .references("pending_authorization_requests", column: "request_id", onDelete: .setNull)
                table.column("code_hash", .text).notNull().unique()
                table.column("scope", .text).notNull()
                table.column("redirect_uri", .text).notNull()
                table.column("code_challenge", .text)
                table.column("code_challenge_method", .text)
                table.column("created_at", .double).notNull()
                table.column("expires_at", .double).notNull()
                table.column("redeemed_at", .double)
                table.column("revoked_at", .double)
            }
            try db.create(index: "authorization_codes_hash_idx", on: "authorization_codes", columns: ["code_hash"])

            try db.create(table: "refresh_tokens") { table in
                table.column("token_id", .text).notNull().primaryKey()
                table.column("client_id", .text).notNull()
                    .references("clients", column: "client_id", onDelete: .cascade)
                table.column("grant_id", .text)
                    .references("grants", column: "grant_id", onDelete: .setNull)
                table.column("token_hash", .text).notNull().unique()
                table.column("scope", .text).notNull()
                table.column("metadata_json", .text).notNull()
                table.column("created_at", .double).notNull()
                table.column("expires_at", .double)
                table.column("rotated_at", .double)
                table.column("revoked_at", .double)
                table.column("replaced_by_token_id", .text)
                    .references("refresh_tokens", column: "token_id", onDelete: .setNull)
            }
            try db.create(index: "refresh_tokens_hash_idx", on: "refresh_tokens", columns: ["token_hash"])

            try db.create(table: "access_tokens") { table in
                table.column("token_id", .text).notNull().primaryKey()
                table.column("client_id", .text).notNull()
                    .references("clients", column: "client_id", onDelete: .cascade)
                table.column("grant_id", .text)
                    .references("grants", column: "grant_id", onDelete: .setNull)
                table.column("refresh_token_id", .text)
                    .references("refresh_tokens", column: "token_id", onDelete: .setNull)
                table.column("token_hash", .text).notNull().unique()
                table.column("scope", .text).notNull()
                table.column("metadata_json", .text).notNull()
                table.column("created_at", .double).notNull()
                table.column("expires_at", .double).notNull()
                table.column("revoked_at", .double)
            }
            try db.create(index: "access_tokens_hash_idx", on: "access_tokens", columns: ["token_hash"])

            try db.create(table: "revocations") { table in
                table.column("revocation_id", .text).notNull().primaryKey()
                table.column("token_kind", .text).notNull()
                table.column("token_hash", .text).notNull()
                table.column("client_id", .text)
                table.column("reason", .text)
                table.column("metadata_json", .text).notNull()
                table.column("created_at", .double).notNull()
            }
            try db.create(index: "revocations_token_hash_idx", on: "revocations", columns: ["token_kind", "token_hash"])
        }
        try migrator.migrate(dbQueue)
        return dbQueue
    }

    static func normalizedMetadataJSON(_ metadataJSON: String?) throws -> String {
        let normalized = metadataJSON?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !normalized.isEmpty else {
            return "{}"
        }

        guard let data = normalized.data(using: .utf8) else {
            throw BearError.invalidInput("Bridge auth metadata must be UTF-8 JSON.")
        }
        _ = try JSONSerialization.jsonObject(with: data)
        return normalized
    }

    static func metadataValue(named name: String, in metadataJSON: String) -> String? {
        guard let data = metadataJSON.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else {
            return nil
        }

        return normalizedOptionalString(object[name] as? String)
    }

    static func metadataJSONString(_ dictionary: [String: String?]) -> String {
        let filtered = dictionary.reduce(into: [String: String]()) { partialResult, entry in
            if let value = normalizedOptionalString(entry.value) {
                partialResult[entry.key] = value
            }
        }

        guard JSONSerialization.isValidJSONObject(filtered),
              let data = try? JSONSerialization.data(withJSONObject: filtered, options: [.sortedKeys]),
              let string = String(data: data, encoding: .utf8)
        else {
            return "{}"
        }

        return string
    }

    static func encodeRedirectURIs(_ redirectURIs: [String]) throws -> String {
        let normalized = redirectURIs
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        guard !normalized.isEmpty else {
            throw BearError.invalidInput("OAuth client registrations need at least one redirect URI.")
        }

        var deduplicated: [String] = []
        var seen = Set<String>()
        for redirectURI in normalized where seen.insert(redirectURI).inserted {
            deduplicated.append(redirectURI)
        }

        let data = try JSONEncoder().encode(deduplicated)
        guard let string = String(data: data, encoding: .utf8) else {
            throw BearError.invalidInput("Failed to encode redirect URIs.")
        }
        return string
    }

    static func normalizedRequiredString(_ value: String, label: String) throws -> String {
        let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else {
            throw BearError.invalidInput("\(label) cannot be empty.")
        }
        return normalized
    }

    static func normalizedOptionalString(_ value: String?) -> String? {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed?.isEmpty == true ? nil : trimmed
    }

    static func defaultIdentifier() -> String {
        UUID().uuidString.lowercased()
    }

    static func defaultSecret(kind: BearBridgeAuthTokenKind) -> String {
        let prefix: String
        switch kind {
        case .authorizationCode:
            prefix = "uc"
        case .refreshToken:
            prefix = "urt"
        case .accessToken:
            prefix = "uat"
        }

        let first = UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased()
        let second = UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased()
        return "\(prefix)_\(first)\(second)"
    }

    static func hash(_ rawValue: String) -> String {
        let digest = SHA256.hash(data: Data(rawValue.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }
}

private struct BridgeAuthCountSnapshot {
    let registeredClientCount: Int
    let activeGrantCount: Int
    let pendingAuthorizationRequestCount: Int
    let activeAuthorizationCodeCount: Int
    let activeRefreshTokenCount: Int
    let activeAccessTokenCount: Int
    let revocationCount: Int
}

private struct BridgeAuthPendingRequestSummaryRow: Decodable, FetchableRecord, Hashable, Sendable {
    let requestID: String
    let clientID: String
    let clientDisplayName: String?
    let grantID: String?
    let requestedScope: String
    let redirectURI: String
    let state: String?
    let status: BearBridgeAuthRequestStatus
    let metadataJSON: String
    let createdAt: Date
    let expiresAt: Date
    let resolvedAt: Date?

    enum CodingKeys: String, CodingKey {
        case requestID = "request_id"
        case clientID = "client_id"
        case clientDisplayName = "client_display_name"
        case grantID = "grant_id"
        case requestedScope = "requested_scope"
        case redirectURI = "redirect_uri"
        case state
        case status
        case metadataJSON = "metadata_json"
        case createdAt = "created_at"
        case expiresAt = "expires_at"
        case resolvedAt = "resolved_at"
    }

    var model: BearBridgePendingAuthorizationRequestSummary {
        BearBridgePendingAuthorizationRequestSummary(
            id: requestID,
            clientID: clientID,
            clientDisplayName: clientDisplayName,
            grantID: grantID,
            requestedScope: requestedScope,
            resource: BearBridgeAuthStore.metadataValue(named: "resource", in: metadataJSON),
            redirectURI: redirectURI,
            state: state,
            status: status,
            createdAt: createdAt,
            expiresAt: expiresAt,
            resolvedAt: resolvedAt
        )
    }
}

private struct BridgeAuthGrantSummaryRow: Decodable, FetchableRecord, Hashable, Sendable {
    let grantID: String
    let clientID: String
    let clientDisplayName: String?
    let scope: String
    let resource: String?
    let createdAt: Date
    let updatedAt: Date

    enum CodingKeys: String, CodingKey {
        case grantID = "grant_id"
        case clientID = "client_id"
        case clientDisplayName = "client_display_name"
        case scope
        case resource
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }

    var model: BearBridgeAuthGrantSummary {
        BearBridgeAuthGrantSummary(
            id: grantID,
            clientID: clientID,
            clientDisplayName: clientDisplayName,
            scope: scope,
            resource: resource,
            createdAt: createdAt,
            updatedAt: updatedAt
        )
    }
}

private struct BridgeAuthClientRecord: Codable, FetchableRecord, PersistableRecord, Hashable, Sendable {
    static let databaseTableName = "clients"

    let clientID: String
    let displayName: String?
    let redirectURIsJSON: String
    let metadataJSON: String
    let createdAt: Date
    let updatedAt: Date

    enum CodingKeys: String, CodingKey {
        case clientID = "client_id"
        case displayName = "display_name"
        case redirectURIsJSON = "redirect_uris_json"
        case metadataJSON = "metadata_json"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }

    func makeModel() throws -> BearBridgeAuthClient {
        BearBridgeAuthClient(
            id: clientID,
            displayName: displayName,
            redirectURIs: try Self.decodeStringArray(redirectURIsJSON),
            metadataJSON: metadataJSON,
            createdAt: createdAt,
            updatedAt: updatedAt
        )
    }

    static func decodeStringArray(_ json: String) throws -> [String] {
        guard let data = json.data(using: .utf8) else {
            throw BearError.configuration("Stored bridge auth redirect URIs are not valid UTF-8.")
        }
        return try JSONDecoder().decode([String].self, from: data)
    }
}

private struct BridgeAuthGrantRecord: Codable, FetchableRecord, PersistableRecord, Hashable, Sendable {
    static let databaseTableName = "grants"

    let grantID: String
    let clientID: String
    let scope: String
    let resource: String?
    let metadataJSON: String
    let createdAt: Date
    var updatedAt: Date
    var revokedAt: Date?

    enum CodingKeys: String, CodingKey {
        case grantID = "grant_id"
        case clientID = "client_id"
        case scope
        case resource
        case metadataJSON = "metadata_json"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case revokedAt = "revoked_at"
    }

    func makeModel() -> BearBridgeAuthGrant {
        BearBridgeAuthGrant(
            id: grantID,
            clientID: clientID,
            scope: scope,
            resource: resource,
            metadataJSON: metadataJSON,
            createdAt: createdAt,
            updatedAt: updatedAt,
            revokedAt: revokedAt
        )
    }
}

private struct BridgeAuthPendingRequestRecord: Codable, FetchableRecord, PersistableRecord, Hashable, Sendable {
    static let databaseTableName = "pending_authorization_requests"

    let requestID: String
    let clientID: String
    let grantID: String?
    let requestedScope: String
    let redirectURI: String
    let state: String?
    let codeChallenge: String?
    let codeChallengeMethod: String?
    var status: BearBridgeAuthRequestStatus
    let metadataJSON: String
    let createdAt: Date
    let expiresAt: Date
    var resolvedAt: Date?

    enum CodingKeys: String, CodingKey {
        case requestID = "request_id"
        case clientID = "client_id"
        case grantID = "grant_id"
        case requestedScope = "requested_scope"
        case redirectURI = "redirect_uri"
        case state
        case codeChallenge = "code_challenge"
        case codeChallengeMethod = "code_challenge_method"
        case status
        case metadataJSON = "metadata_json"
        case createdAt = "created_at"
        case expiresAt = "expires_at"
        case resolvedAt = "resolved_at"
    }

    func makeModel() -> BearBridgePendingAuthorizationRequest {
        BearBridgePendingAuthorizationRequest(
            id: requestID,
            clientID: clientID,
            grantID: grantID,
            requestedScope: requestedScope,
            redirectURI: redirectURI,
            state: state,
            codeChallenge: codeChallenge,
            codeChallengeMethod: codeChallengeMethod,
            status: status,
            metadataJSON: metadataJSON,
            createdAt: createdAt,
            expiresAt: expiresAt,
            resolvedAt: resolvedAt
        )
    }
}

private struct BridgeAuthAuthorizationCodeRecord: Codable, FetchableRecord, PersistableRecord, Hashable, Sendable {
    static let databaseTableName = "authorization_codes"

    let codeID: String
    let clientID: String
    let grantID: String?
    let pendingRequestID: String?
    let codeHash: String
    let scope: String
    let redirectURI: String
    let codeChallenge: String?
    let codeChallengeMethod: String?
    let createdAt: Date
    let expiresAt: Date
    var redeemedAt: Date?
    var revokedAt: Date?

    enum CodingKeys: String, CodingKey {
        case codeID = "code_id"
        case clientID = "client_id"
        case grantID = "grant_id"
        case pendingRequestID = "pending_request_id"
        case codeHash = "code_hash"
        case scope
        case redirectURI = "redirect_uri"
        case codeChallenge = "code_challenge"
        case codeChallengeMethod = "code_challenge_method"
        case createdAt = "created_at"
        case expiresAt = "expires_at"
        case redeemedAt = "redeemed_at"
        case revokedAt = "revoked_at"
    }

    func makeModel() -> BearBridgeAuthorizationCode {
        BearBridgeAuthorizationCode(
            id: codeID,
            clientID: clientID,
            grantID: grantID,
            pendingRequestID: pendingRequestID,
            scope: scope,
            redirectURI: redirectURI,
            codeChallenge: codeChallenge,
            codeChallengeMethod: codeChallengeMethod,
            createdAt: createdAt,
            expiresAt: expiresAt,
            redeemedAt: redeemedAt,
            revokedAt: revokedAt
        )
    }
}

private struct BridgeAuthRefreshTokenRecord: Codable, FetchableRecord, PersistableRecord, Hashable, Sendable {
    static let databaseTableName = "refresh_tokens"

    let tokenID: String
    let clientID: String
    let grantID: String?
    let tokenHash: String
    let scope: String
    let metadataJSON: String
    let createdAt: Date
    let expiresAt: Date?
    var rotatedAt: Date?
    var revokedAt: Date?
    var replacedByTokenID: String?

    enum CodingKeys: String, CodingKey {
        case tokenID = "token_id"
        case clientID = "client_id"
        case grantID = "grant_id"
        case tokenHash = "token_hash"
        case scope
        case metadataJSON = "metadata_json"
        case createdAt = "created_at"
        case expiresAt = "expires_at"
        case rotatedAt = "rotated_at"
        case revokedAt = "revoked_at"
        case replacedByTokenID = "replaced_by_token_id"
    }

    func makeModel() -> BearBridgeRefreshToken {
        BearBridgeRefreshToken(
            id: tokenID,
            clientID: clientID,
            grantID: grantID,
            scope: scope,
            metadataJSON: metadataJSON,
            createdAt: createdAt,
            expiresAt: expiresAt,
            rotatedAt: rotatedAt,
            revokedAt: revokedAt,
            replacedByTokenID: replacedByTokenID
        )
    }
}

private struct BridgeAuthAccessTokenRecord: Codable, FetchableRecord, PersistableRecord, Hashable, Sendable {
    static let databaseTableName = "access_tokens"

    let tokenID: String
    let clientID: String
    let grantID: String?
    let refreshTokenID: String?
    let tokenHash: String
    let scope: String
    let metadataJSON: String
    let createdAt: Date
    let expiresAt: Date
    var revokedAt: Date?

    enum CodingKeys: String, CodingKey {
        case tokenID = "token_id"
        case clientID = "client_id"
        case grantID = "grant_id"
        case refreshTokenID = "refresh_token_id"
        case tokenHash = "token_hash"
        case scope
        case metadataJSON = "metadata_json"
        case createdAt = "created_at"
        case expiresAt = "expires_at"
        case revokedAt = "revoked_at"
    }

    func makeModel() -> BearBridgeAccessToken {
        BearBridgeAccessToken(
            id: tokenID,
            clientID: clientID,
            grantID: grantID,
            refreshTokenID: refreshTokenID,
            scope: scope,
            metadataJSON: metadataJSON,
            createdAt: createdAt,
            expiresAt: expiresAt,
            revokedAt: revokedAt
        )
    }
}

private struct BridgeAuthRevocationRecord: Codable, FetchableRecord, PersistableRecord, Hashable, Sendable {
    static let databaseTableName = "revocations"

    let revocationID: String
    let tokenKind: BearBridgeAuthTokenKind
    let tokenHash: String
    let clientID: String?
    let reason: String?
    let metadataJSON: String
    let createdAt: Date

    enum CodingKeys: String, CodingKey {
        case revocationID = "revocation_id"
        case tokenKind = "token_kind"
        case tokenHash = "token_hash"
        case clientID = "client_id"
        case reason
        case metadataJSON = "metadata_json"
        case createdAt = "created_at"
    }

    func makeModel() -> BearBridgeAuthRevocation {
        BearBridgeAuthRevocation(
            id: revocationID,
            tokenKind: tokenKind,
            clientID: clientID,
            reason: reason,
            metadataJSON: metadataJSON,
            createdAt: createdAt
        )
    }
}
