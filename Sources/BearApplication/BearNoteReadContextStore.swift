import CryptoKit
import Foundation

public final class BearNoteReadContextStore: @unchecked Sendable {
    private struct CachedNoteContext {
        let noteID: String
        let version: Int
        let content: String
        let capturedAt: Date
    }

    private struct EligibleVersionEntry {
        let version: Int
        let observedAt: Date
    }

    private struct ConflictTokenEntry {
        let token: String
        let noteID: String
        let currentVersion: Int
        let requestedContentHash: String
        let expiresAt: Date
        var consumed: Bool
    }

    private let lock = NSLock()
    private let contextTTL: TimeInterval
    private let tokenTTL: TimeInterval
    private let maxContextsPerNote: Int
    private let maxEligibleVersionsPerNote: Int
    private var contextsByNoteID: [String: [CachedNoteContext]] = [:]
    private var eligibleVersionsByNoteID: [String: [EligibleVersionEntry]] = [:]
    private var tokensByValue: [String: ConflictTokenEntry] = [:]

    public init(
        contextTTL: TimeInterval = 15 * 60,
        tokenTTL: TimeInterval = 5 * 60,
        maxContextsPerNote: Int = 6,
        maxEligibleVersionsPerNote: Int = 24
    ) {
        self.contextTTL = contextTTL
        self.tokenTTL = tokenTTL
        self.maxContextsPerNote = maxContextsPerNote
        self.maxEligibleVersionsPerNote = maxEligibleVersionsPerNote
    }

    public func remember(
        noteID: String,
        version: Int,
        content: String,
        replaceEligible: Bool = false,
        now: Date = Date()
    ) {
        guard !noteID.isEmpty else {
            return
        }

        lock.lock()
        defer { lock.unlock() }
        purgeExpired(now: now)

        var contexts = contextsByNoteID[noteID, default: []]
        contexts.removeAll { $0.version == version }
        contexts.append(
            CachedNoteContext(
                noteID: noteID,
                version: version,
                content: content,
                capturedAt: now
            )
        )
        contexts.sort { $0.capturedAt > $1.capturedAt }
        if contexts.count > maxContextsPerNote {
            contexts = Array(contexts.prefix(maxContextsPerNote))
        }
        contextsByNoteID[noteID] = contexts

        if replaceEligible {
            markReplaceEligibleLocked(noteID: noteID, version: version, now: now)
        }
    }

    public func context(noteID: String, version: Int, now: Date = Date()) -> (content: String, capturedAt: Date)? {
        lock.lock()
        defer { lock.unlock() }
        purgeExpired(now: now)

        guard
            let context = contextsByNoteID[noteID]?.first(where: { $0.version == version })
        else {
            return nil
        }

        return (context.content, context.capturedAt)
    }

    public func markReplaceEligible(noteID: String, version: Int, now: Date = Date()) {
        guard !noteID.isEmpty else {
            return
        }

        lock.lock()
        defer { lock.unlock() }
        purgeExpired(now: now)
        markReplaceEligibleLocked(noteID: noteID, version: version, now: now)
    }

    public func isReplaceEligible(noteID: String, version: Int, now: Date = Date()) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        purgeExpired(now: now)

        return eligibleVersionsByNoteID[noteID]?.contains(where: { $0.version == version }) == true
    }

    public func matchingReplaceEligibleVersion(noteID: String, content: String, now: Date = Date()) -> Int? {
        lock.lock()
        defer { lock.unlock() }
        purgeExpired(now: now)

        guard let contexts = contextsByNoteID[noteID], let eligibleEntries = eligibleVersionsByNoteID[noteID] else {
            return nil
        }

        let eligibleVersions = Set(eligibleEntries.map(\.version))
        return contexts.first(where: { context in
            eligibleVersions.contains(context.version) && context.content == content
        })?.version
    }

    public func issueConflictToken(
        noteID: String,
        currentVersion: Int,
        requestedContent: String,
        now: Date = Date()
    ) -> String {
        let token = UUID().uuidString
        let entry = ConflictTokenEntry(
            token: token,
            noteID: noteID,
            currentVersion: currentVersion,
            requestedContentHash: Self.sha256(requestedContent),
            expiresAt: now.addingTimeInterval(tokenTTL),
            consumed: false
        )

        lock.lock()
        defer { lock.unlock() }
        purgeExpired(now: now)
        tokensByValue[token] = entry
        return token
    }

    public func consumeConflictToken(
        _ token: String,
        noteID: String,
        currentVersion: Int,
        requestedContent: String,
        now: Date = Date()
    ) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        purgeExpired(now: now)

        guard var entry = tokensByValue[token] else {
            return false
        }

        guard
            entry.consumed == false,
            entry.noteID == noteID,
            entry.currentVersion == currentVersion,
            entry.requestedContentHash == Self.sha256(requestedContent)
        else {
            return false
        }

        entry.consumed = true
        tokensByValue[token] = entry
        return true
    }

    private func purgeExpired(now: Date) {
        contextsByNoteID = contextsByNoteID.reduce(into: [:]) { partialResult, entry in
            let filtered = entry.value.filter { now.timeIntervalSince($0.capturedAt) <= contextTTL }
            if !filtered.isEmpty {
                partialResult[entry.key] = filtered
            }
        }

        tokensByValue = tokensByValue.filter { _, entry in
            entry.expiresAt > now && entry.consumed == false
        }
    }

    private func markReplaceEligibleLocked(noteID: String, version: Int, now: Date) {
        var versions = eligibleVersionsByNoteID[noteID, default: []]
        versions.removeAll { $0.version == version }
        versions.append(EligibleVersionEntry(version: version, observedAt: now))
        versions.sort { $0.observedAt > $1.observedAt }
        if versions.count > maxEligibleVersionsPerNote {
            versions = Array(versions.prefix(maxEligibleVersionsPerNote))
        }
        eligibleVersionsByNoteID[noteID] = versions
    }

    private static func sha256(_ value: String) -> String {
        let digest = SHA256.hash(data: Data(value.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }
}
