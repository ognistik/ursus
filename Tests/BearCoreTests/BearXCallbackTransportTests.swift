import BearCore
@testable import BearXCallback
import Foundation
import GRDB
import Network
import Testing

@Test
func createRetriesThroughTransientSQLiteLockDuringReceiptPolling() async throws {
    let transport = BearXCallbackTransport(
        readStore: LockThenCreateReadStore(),
        urlOpener: { _ in }
    )

    let receipt = try await transport.create(
        CreateNoteRequest(
            title: "Locked Create",
            content: "Body",
            tags: [],
            presentation: BearPresentationOptions(openNote: false, newWindow: false, showWindow: true, edit: false)
        )
    )

    #expect(receipt.status == "created")
    #expect(receipt.noteID == "created-note")
}

@Test
func createActivatesBearOnlyWhenTheCreatedNoteWillOpen() async throws {
    let opener = ActivationRecordingOpener()
    let transport = BearXCallbackTransport(
        readStore: StaticReadStore(note: makeNote(id: "created-note", title: "Created"), tags: []),
        urlOpenerWithActivation: opener.record
    )

    _ = try await transport.create(
        CreateNoteRequest(
            title: "Closed",
            content: "Body",
            tags: [],
            presentation: BearPresentationOptions(openNote: false, newWindow: false, showWindow: true, edit: false)
        )
    )
    _ = try await transport.create(
        CreateNoteRequest(
            title: "Opened",
            content: "Body",
            tags: [],
            presentation: BearPresentationOptions(openNote: true, newWindow: false, showWindow: true, edit: false)
        )
    )

    #expect(await opener.activations == [false, true])
}

@Test
func openNoteActivatesBear() async throws {
    let opener = ActivationRecordingOpener()
    let transport = BearXCallbackTransport(
        readStore: StaticReadStore(note: makeNote(id: "note-1", title: "Opened"), tags: []),
        urlOpenerWithActivation: opener.record
    )

    _ = try await transport.open(
        OpenNoteRequest(
            noteID: "note-1",
            presentation: BearPresentationOptions(openNote: true, newWindow: false, showWindow: true, edit: false)
        )
    )

    #expect(await opener.activations == [true])
}

@Test
func openTagActivatesBear() async throws {
    let opener = ActivationRecordingOpener()
    let transport = BearXCallbackTransport(
        readStore: StaticReadStore(note: nil, tags: []),
        urlOpenerWithActivation: opener.record
    )

    _ = try await transport.openTag(OpenTagRequest(tag: "projects"))

    #expect(await opener.activations == [true])
}

@Test
func renameTagStaysBackgroundedEvenWhenShowWindowIsTrue() async throws {
    let opener = ActivationRecordingOpener()
    let transport = BearXCallbackTransport(
        readStore: StaticReadStore(note: nil, tags: [TagSummary(name: "done", identifier: nil, noteCount: 1)]),
        urlOpenerWithActivation: opener.record
    )

    _ = try await transport.renameTag(
        RenameTagRequest(name: "todo", newName: "done", showWindow: true)
    )

    #expect(await opener.activations == [false])
}

@Test
func archiveStaysBackgroundedEvenWhenShowWindowIsTrue() async throws {
    let opener = ActivationRecordingOpener()
    let transport = BearXCallbackTransport(
        readStore: StaticReadStore(note: makeNote(id: "note-1", title: "Archived", archived: true), tags: []),
        urlOpenerWithActivation: opener.record
    )

    _ = try await transport.archive(noteID: "note-1", showWindow: true)

    #expect(await opener.activations == [false])
}

@Test
func replaceAllTreatsModifiedNoteAsUpdatedEvenWhenVersionStaysTheSame() async throws {
    let readStore = MutableTransportReadStore(
        note: makeNote(
            id: "note-1",
            title: "Example",
            version: 3,
            modifiedAt: Date(timeIntervalSince1970: 1_700_000_000),
            body: "Before"
        )
    )
    let transport = BearXCallbackTransport(
        readStore: readStore,
        urlOpener: { _ in
            readStore.replaceRawText(
                noteID: "note-1",
                rawText: BearText.composeRawText(title: "Example", body: "After"),
                preserveVersion: true
            )
        }
    )

    let receipt = try await transport.replaceAll(
        noteID: "note-1",
        fullText: BearText.composeRawText(title: "Example", body: "After"),
        presentation: BearPresentationOptions(openNote: false, newWindow: false, showWindow: true, edit: false)
    )

    #expect(receipt.status == "updated")
}

@Test
func addFileTreatsAttachmentCountChangeAsUpdatedEvenWhenNoteMetadataStaysTheSame() async throws {
    let readStore = MutableTransportReadStore(
        note: makeNote(
            id: "note-1",
            title: "Example",
            version: 3,
            modifiedAt: Date(timeIntervalSince1970: 1_700_000_000),
            body: "Before"
        )
    )
    let fileURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathExtension("txt")
    try "payload".write(to: fileURL, atomically: true, encoding: .utf8)
    defer { try? FileManager.default.removeItem(at: fileURL) }

    let transport = BearXCallbackTransport(
        readStore: readStore,
        urlOpener: { _ in
            readStore.addAttachment(noteID: "note-1", filename: fileURL.lastPathComponent)
        }
    )

    let receipt = try await transport.addFile(
        AddFileRequest(
            noteID: "note-1",
            filePath: fileURL.path,
            position: .bottom,
            presentation: BearPresentationOptions(openNote: false, newWindow: false, showWindow: true, edit: false),
            expectedVersion: nil
        )
    )

    #expect(receipt.status == "updated")
}

@Test
func resolveSelectedNoteIDUsesCallbackIdentifierAndStaysBackgrounded() async throws {
    let opener = ActivationRecordingOpener()
    let transport = BearXCallbackTransport(
        readStore: StaticReadStore(note: nil, tags: []),
        urlOpenerWithActivation: { url, activates in
            try await opener.record(url: url, activates: activates)
            try await invokeCallback(for: url, endpoint: "x-success", extraQueryItems: [
                URLQueryItem(name: "identifier", value: "selected-note"),
            ])
        },
        selectedNoteResolveTimeout: .seconds(1)
    )

    let resolved = try await transport.resolveSelectedNoteID(token: "top-secret-token")

    #expect(resolved == "selected-note")
    #expect(await opener.activations == [false])
}

@Test
func resolveSelectedNoteIDSurfacesCallbackError() async {
    let transport = BearXCallbackTransport(
        readStore: StaticReadStore(note: nil, tags: []),
        urlOpener: { url in
            try await invokeCallback(for: url, endpoint: "x-error", extraQueryItems: [
                URLQueryItem(name: "errorMessage", value: "No selected note"),
            ])
        },
        selectedNoteResolveTimeout: .seconds(1)
    )

    do {
        _ = try await transport.resolveSelectedNoteID(token: "top-secret-token")
        Issue.record("Expected selected-note callback failure.")
    } catch let error as BearError {
        guard case .xCallback(let message) = error else {
            Issue.record("Expected x-callback error, got \(error).")
            return
        }
        #expect(message.contains("No selected note"))
    } catch {
        Issue.record("Expected BearError.xCallback, got \(error).")
    }
}

@Test
func resolveSelectedNoteIDTimesOutWhenBearDoesNotCallBack() async {
    let transport = BearXCallbackTransport(
        readStore: StaticReadStore(note: nil, tags: []),
        urlOpener: { _ in },
        selectedNoteResolveTimeout: .milliseconds(50)
    )

    do {
        _ = try await transport.resolveSelectedNoteID(token: "top-secret-token")
        Issue.record("Expected selected-note timeout.")
    } catch let error as BearError {
        guard case .xCallback(let message) = error else {
            Issue.record("Expected timeout x-callback error, got \(error).")
            return
        }
        #expect(message.contains("Timed out"))
    } catch {
        Issue.record("Expected BearError.xCallback, got \(error).")
    }
}

@Test
func debugDescriptionRedactsSelectedNoteTokenAndCallbackURLs() async throws {
    let transport = BearXCallbackTransport(
        readStore: StaticReadStore(note: nil, tags: []),
        urlOpener: { _ in }
    )
    let builder = BearXCallbackURLBuilder()
    let url = try builder.resolveSelectedNoteURL(
        token: "top-secret-token",
        successURL: URL(string: "http://127.0.0.1:8080/success?state=abc")!,
        errorURL: URL(string: "http://127.0.0.1:8080/error?state=abc")!
    )

    let description = await transport.debugDescription(for: url)

    #expect(description.contains("token=<redacted>"))
    #expect(description.contains("x-success=<redacted>"))
    #expect(description.contains("x-error=<redacted>"))
    #expect(!description.contains("top-secret-token"))
    #expect(!description.contains("127.0.0.1:8080"))
}

private final class LockThenCreateReadStore: @unchecked Sendable, BearReadStore {
    private var didThrowLock = false

    func findNotes(_ query: FindNotesQuery) throws -> DiscoveryNoteBatch { DiscoveryNoteBatch(notes: [], hasMore: false) }
    func note(id: String) throws -> BearNote? { nil }
    func notes(withIDs ids: [String]) throws -> [BearNote] { [] }
    func listTags(_ query: ListTagsQuery) throws -> [TagSummary] { [] }

    func findNotes(title: String, modifiedAfter: Date?) throws -> [BearNote] {
        if !didThrowLock {
            didThrowLock = true
            throw DatabaseError(resultCode: .SQLITE_BUSY, message: "database is locked")
        }

        return [
            BearNote(
                ref: NoteRef(identifier: "created-note"),
                revision: NoteRevision(version: 1, createdAt: Date(), modifiedAt: Date()),
                title: title,
                body: "Body",
                rawText: BearText.composeRawText(title: title, body: "Body"),
                tags: [],
                archived: false,
                trashed: false,
                encrypted: false
            ),
        ]
    }
}

private struct StaticReadStore: BearReadStore {
    let note: BearNote?
    let tags: [TagSummary]

    func findNotes(_ query: FindNotesQuery) throws -> DiscoveryNoteBatch { DiscoveryNoteBatch(notes: [], hasMore: false) }

    func note(id: String) throws -> BearNote? {
        guard note?.ref.identifier == id else {
            return nil
        }
        return note
    }

    func notes(withIDs ids: [String]) throws -> [BearNote] { [] }

    func listTags(_ query: ListTagsQuery) throws -> [TagSummary] {
        tags
    }

    func findNotes(title: String, modifiedAfter: Date?) throws -> [BearNote] {
        guard let note else {
            return []
        }
        return [note]
    }
}

private final class MutableTransportReadStore: @unchecked Sendable, BearReadStore {
    private let lock = NSLock()
    private var note: BearNote
    private var storedAttachments: [NoteAttachment]

    init(note: BearNote, attachments: [NoteAttachment] = []) {
        self.note = note
        self.storedAttachments = attachments
    }

    func findNotes(_ query: FindNotesQuery) throws -> DiscoveryNoteBatch { DiscoveryNoteBatch(notes: [], hasMore: false) }
    func notes(withIDs ids: [String]) throws -> [BearNote] { [] }
    func listTags(_ query: ListTagsQuery) throws -> [TagSummary] { [] }
    func findNotes(title: String, modifiedAfter: Date?) throws -> [BearNote] { [] }

    func note(id: String) throws -> BearNote? {
        lock.lock()
        defer { lock.unlock() }
        return note.ref.identifier == id ? note : nil
    }

    func attachments(noteID: String) throws -> [NoteAttachment] {
        lock.lock()
        defer { lock.unlock() }
        guard note.ref.identifier == noteID else {
            return []
        }
        return storedAttachments
    }

    func replaceRawText(noteID: String, rawText: String, preserveVersion: Bool) {
        lock.lock()
        defer { lock.unlock() }
        guard note.ref.identifier == noteID else {
            return
        }

        note = BearNote(
            ref: note.ref,
            revision: NoteRevision(
                version: preserveVersion ? note.revision.version : note.revision.version + 1,
                createdAt: note.revision.createdAt,
                modifiedAt: note.revision.modifiedAt.addingTimeInterval(1)
            ),
            title: note.title,
            body: parseBody(rawText),
            rawText: rawText,
            tags: note.tags,
            archived: note.archived,
            trashed: note.trashed,
            encrypted: note.encrypted
        )
    }

    func addAttachment(noteID: String, filename: String) {
        lock.lock()
        defer { lock.unlock() }
        guard note.ref.identifier == noteID else {
            return
        }

        storedAttachments.append(
            NoteAttachment(
                attachmentID: UUID().uuidString,
                filename: filename,
                fileExtension: URL(fileURLWithPath: filename).pathExtension,
                searchText: nil
            )
        )
    }

    private func parseBody(_ rawText: String) -> String {
        let normalized = rawText
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")

        guard let firstNewline = normalized.firstIndex(of: "\n") else {
            return ""
        }

        return String(normalized[normalized.index(after: firstNewline)...]).trimmingCharacters(in: .newlines)
    }
}

private actor ActivationRecordingOpener {
    private(set) var activations: [Bool] = []

    func record(url _: URL, activates: Bool) async throws {
        activations.append(activates)
    }
}

private func makeNote(
    id: String,
    title: String,
    archived: Bool = false,
    version: Int = 1,
    modifiedAt: Date = Date(),
    body: String = "Body"
) -> BearNote {
    BearNote(
        ref: NoteRef(identifier: id),
        revision: NoteRevision(version: version, createdAt: Date(), modifiedAt: modifiedAt),
        title: title,
        body: body,
        rawText: BearText.composeRawText(title: title, body: body),
        tags: [],
        archived: archived,
        trashed: false,
        encrypted: false
    )
}

private func invokeCallback(for bearURL: URL, endpoint: String, extraQueryItems: [URLQueryItem]) async throws {
    let components = try #require(URLComponents(url: bearURL, resolvingAgainstBaseURL: false))
    let items = Dictionary(uniqueKeysWithValues: (components.queryItems ?? []).compactMap { item in
        item.value.map { (item.name, $0) }
    })
    let callbackTarget = try #require(items[endpoint])
    var callbackComponents = try #require(URLComponents(url: URL(string: callbackTarget)!, resolvingAgainstBaseURL: false))
    callbackComponents.queryItems = (callbackComponents.queryItems ?? []) + extraQueryItems
    let callbackURL = try #require(callbackComponents.url)
    try await sendHTTPGet(to: callbackURL)
}

private func sendHTTPGet(to url: URL) async throws {
    let host = try #require(url.host)
    let port = try #require(url.port)
    let endpointPort = try #require(NWEndpoint.Port(rawValue: UInt16(port)))
    let path = url.path + (url.query.map { "?\($0)" } ?? "")

    try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
        let connection = NWConnection(host: NWEndpoint.Host(host), port: endpointPort, using: .tcp)
        let queue = DispatchQueue(label: "bear-mcp.transport-tests.callback")
        let completion = CallbackRequestCompletion(connection: connection, continuation: continuation)

        connection.stateUpdateHandler = { state in
            switch state {
            case .ready:
                let request = "GET \(path) HTTP/1.1\r\nHost: \(host)\r\nConnection: close\r\n\r\n"
                connection.send(content: Data(request.utf8), completion: .contentProcessed { error in
                    if let error {
                        completion.finish(.failure(error))
                        return
                    }

                    connection.receive(minimumIncompleteLength: 1, maximumLength: 4_096) { _, _, _, error in
                        if let error {
                            completion.finish(.failure(error))
                        } else {
                            completion.finish(.success(()))
                        }
                    }
                })

            case .failed(let error):
                completion.finish(.failure(error))

            case .cancelled:
                completion.finish(.success(()))

            default:
                break
            }
        }

        connection.start(queue: queue)
    }
}

private final class CallbackRequestCompletion: @unchecked Sendable {
    private let connection: NWConnection
    private let continuation: CheckedContinuation<Void, Error>
    private let lock = NSLock()
    private var resumed = false

    init(connection: NWConnection, continuation: CheckedContinuation<Void, Error>) {
        self.connection = connection
        self.continuation = continuation
    }

    func finish(_ result: Result<Void, Error>) {
        lock.lock()
        guard !resumed else {
            lock.unlock()
            return
        }
        resumed = true
        lock.unlock()

        connection.cancel()
        continuation.resume(with: result)
    }
}
