import BearCore
import Foundation
import GRDB

public enum BearDonationPromptAction: String, Codable, Hashable, Sendable {
    case notNow = "not_now"
    case dontAskAgain = "dont_ask_again"
    case donated
}

public enum BearDonationSuppressionReason: String, Codable, Hashable, Sendable {
    case dontAskAgain = "dont_ask_again"
    case donated
}

public struct BearDonationPromptSnapshot: Codable, Hashable, Sendable {
    public static let initialEligibilityThreshold = 20
    public static let repromptOperationInterval = 50

    public let totalSuccessfulOperationCount: Int
    public let nextPromptOperationCount: Int
    public let permanentSuppressionReason: BearDonationSuppressionReason?

    public init(
        totalSuccessfulOperationCount: Int,
        nextPromptOperationCount: Int,
        permanentSuppressionReason: BearDonationSuppressionReason?
    ) {
        self.totalSuccessfulOperationCount = totalSuccessfulOperationCount
        self.nextPromptOperationCount = nextPromptOperationCount
        self.permanentSuppressionReason = permanentSuppressionReason
    }

    public var hasCrossedInitialEligibilityThreshold: Bool {
        totalSuccessfulOperationCount >= Self.initialEligibilityThreshold
    }

    public var isPromptEligible: Bool {
        permanentSuppressionReason == nil && totalSuccessfulOperationCount >= nextPromptOperationCount
    }

    public var shouldShowSupportAffordance: Bool {
        permanentSuppressionReason == nil && hasCrossedInitialEligibilityThreshold
    }
}

public actor BearRuntimeStateStore {
    private let databaseURL: URL
    private let fileManager: FileManager
    private var databaseQueue: DatabaseQueue?

    public init(
        databaseURL: URL = BearPaths.runtimeStateDatabaseURL,
        fileManager: FileManager = .default
    ) {
        self.databaseURL = databaseURL
        self.fileManager = fileManager
    }

    @discardableResult
    public func loadDonationPromptSnapshot() throws -> BearDonationPromptSnapshot {
        let dbQueue = try prepareDatabaseQueue()
        return try Self.snapshot(using: dbQueue)
    }

    @discardableResult
    public func recordSuccessfulMCPToolOperations(_ count: Int) throws -> BearDonationPromptSnapshot {
        guard count > 0 else {
            return try loadDonationPromptSnapshot()
        }

        let dbQueue = try prepareDatabaseQueue()
        return try dbQueue.write { db in
            var record = try Self.fetchDonationRecord(in: db)
            record.totalSuccessfulOperationCount += count
            try record.update(db)
            return record.snapshot
        }
    }

    @discardableResult
    public func recordDonationPromptAction(_ action: BearDonationPromptAction) throws -> BearDonationPromptSnapshot {
        let dbQueue = try prepareDatabaseQueue()
        return try dbQueue.write { db in
            var record = try Self.fetchDonationRecord(in: db)

            switch action {
            case .notNow:
                record.nextPromptOperationCount = max(
                    record.nextPromptOperationCount,
                    record.totalSuccessfulOperationCount + BearDonationPromptSnapshot.repromptOperationInterval
                )
            case .dontAskAgain:
                record.permanentSuppressionReason = BearDonationSuppressionReason.dontAskAgain.rawValue
            case .donated:
                record.permanentSuppressionReason = BearDonationSuppressionReason.donated.rawValue
            }

            try record.update(db)
            return record.snapshot
        }
    }

#if DEBUG
    @discardableResult
    public func debugMarkDonationPromptEligible() throws -> BearDonationPromptSnapshot {
        let dbQueue = try prepareDatabaseQueue()
        return try dbQueue.write { db in
            var record = try Self.fetchDonationRecord(in: db)
            record.totalSuccessfulOperationCount = max(
                record.totalSuccessfulOperationCount,
                BearDonationPromptSnapshot.initialEligibilityThreshold
            )
            record.nextPromptOperationCount = BearDonationPromptSnapshot.initialEligibilityThreshold
            record.permanentSuppressionReason = nil
            try record.update(db)
            return record.snapshot
        }
    }

    @discardableResult
    public func debugResetDonationPromptState() throws -> BearDonationPromptSnapshot {
        let dbQueue = try prepareDatabaseQueue()
        return try dbQueue.write { db in
            var record = try Self.fetchDonationRecord(in: db)
            record.totalSuccessfulOperationCount = 0
            record.nextPromptOperationCount = BearDonationPromptSnapshot.initialEligibilityThreshold
            record.permanentSuppressionReason = nil
            try record.update(db)
            return record.snapshot
        }
    }
#endif
}

private extension BearRuntimeStateStore {
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

    static func fetchDonationRecord(in db: Database) throws -> DonationPromptStateRecord {
        if let existing = try DonationPromptStateRecord.fetchOne(db, key: 1) {
            return existing
        }

        var record = DonationPromptStateRecord(
            id: 1,
            totalSuccessfulOperationCount: 0,
            nextPromptOperationCount: BearDonationPromptSnapshot.initialEligibilityThreshold,
            permanentSuppressionReason: nil
        )
        try record.insert(db)
        return record
    }

    static func snapshot(using dbQueue: DatabaseQueue) throws -> BearDonationPromptSnapshot {
        try dbQueue.read { db in
            try fetchDonationRecord(in: db).snapshot
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
        configuration.label = "ursus.runtime-state"

        let dbQueue = try DatabaseQueue(path: databaseURL.path, configuration: configuration)
        var migrator = DatabaseMigrator()
        migrator.registerMigration("createDonationPromptState") { db in
            try db.create(table: "donation_prompt_state") { table in
                table.column("id", .integer).notNull().primaryKey()
                table.column("total_successful_operation_count", .integer).notNull()
                table.column("next_prompt_operation_count", .integer).notNull()
                table.column("permanent_suppression_reason", .text)
            }
        }
        try migrator.migrate(dbQueue)
        try dbQueue.write { db in
            _ = try fetchDonationRecord(in: db)
        }
        return dbQueue
    }
}

private struct DonationPromptStateRecord: Codable, FetchableRecord, MutablePersistableRecord {
    static let databaseTableName = "donation_prompt_state"

    let id: Int64
    var totalSuccessfulOperationCount: Int
    var nextPromptOperationCount: Int
    var permanentSuppressionReason: String?

    enum Columns {
        static let id = Column(CodingKeys.id)
    }

    enum CodingKeys: String, CodingKey {
        case id
        case totalSuccessfulOperationCount = "total_successful_operation_count"
        case nextPromptOperationCount = "next_prompt_operation_count"
        case permanentSuppressionReason = "permanent_suppression_reason"
    }

    var snapshot: BearDonationPromptSnapshot {
        BearDonationPromptSnapshot(
            totalSuccessfulOperationCount: totalSuccessfulOperationCount,
            nextPromptOperationCount: nextPromptOperationCount,
            permanentSuppressionReason: permanentSuppressionReason.flatMap(BearDonationSuppressionReason.init(rawValue:))
        )
    }
}
