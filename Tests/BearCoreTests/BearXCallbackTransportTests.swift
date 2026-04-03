import BearCore
@testable import BearXCallback
import Foundation
import GRDB
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
func backgroundOpenArgumentsUseLaunchServicesBackgroundMode() {
    let arguments = BearXCallbackTransport.backgroundOpenArguments(
        for: URL(string: "bear://x-callback-url/trash?id=note-1&show_window=no")!
    )

    #expect(arguments == [
        "-g",
        "-u",
        "bear://x-callback-url/trash?id=note-1&show_window=no",
    ])
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
func trashUsesTrashActionAndStaysBackgrounded() async throws {
    let opener = ActivationRecordingOpener()
    let readStore = MutableTransportReadStore(
        note: makeNote(
            id: "note-1",
            title: "Disposable",
            modifiedAt: Date(timeIntervalSince1970: 1_700_000_000)
        )
    )
    let transport = BearXCallbackTransport(
        readStore: readStore,
        urlOpenerWithActivation: { url, activates in
            try await opener.record(url: url, activates: activates)
            readStore.setTrashed(noteID: "note-1")
        }
    )

    let receipt = try await transport.trash(noteID: "note-1")

    let openedURL = try #require(await opener.urls.first)
    #expect(openedURL.path == "/trash")
    #expect(await opener.activations == [false])
    #expect(receipt.status == "trashed")
}

@Test
func trashSkipsOpeningWhenNoteIsAlreadyTrashed() async throws {
    let opener = ActivationRecordingOpener()
    let readStore = MutableTransportReadStore(
        note: makeNote(
            id: "note-1",
            title: "Disposable",
            trashed: true,
            modifiedAt: Date(timeIntervalSince1970: 1_700_000_000)
        )
    )
    let transport = BearXCallbackTransport(
        readStore: readStore,
        urlOpenerWithActivation: opener.record
    )

    let receipt = try await transport.trash(noteID: "note-1")

    #expect(await opener.urls.isEmpty)
    #expect(receipt.status == "already_trashed")
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
            presentation: BearPresentationOptions(openNote: false, newWindow: false, showWindow: true, edit: false)
        )
    )

    #expect(receipt.status == "updated")
}

@Test
func resolveSelectedNoteIDInvokesConfiguredHelperAndParsesIdentifier() async throws {
    let helperURL = try makeSelectedNoteHelperScript(
        body: """
        if [ "$ACTIVATE_APP" != "NO" ]; then
          printf '{"errorMessage":"activateApp mismatch"}\n' >&2
          exit 1
        fi
        case "$BEAR_URL" in
          *"selected=yes"* ) ;;
          * )
            printf '{"errorMessage":"missing selected=yes"}\n' >&2
            exit 1
            ;;
        esac
        case "$BEAR_URL" in
          *"token=top-secret-token"* ) ;;
          * )
            printf '{"errorMessage":"missing token"}\n' >&2
            exit 1
            ;;
        esac
        printf '{"identifier":"selected-note"}\n'
        """
    )
    defer { try? FileManager.default.removeItem(at: helperURL) }

    let transport = BearXCallbackTransport(
        readStore: StaticReadStore(note: nil, tags: []),
        selectedNoteResolveTimeout: .seconds(1),
        selectedNoteResolver: { url, timeout in
            try await BearSelectedNoteHelperRunner.resolveSelectedNoteID(
                executableURL: helperURL,
                bearURL: url,
                timeout: timeout
            )
        }
    )

    let resolved = try await transport.resolveSelectedNoteID(token: "top-secret-token")

    #expect(resolved == "selected-note")
}

@Test
func resolveSelectedNoteIDSurfacesSelectedNoteHelperJSONError() async {
    let helperURL: URL
    do {
        helperURL = try makeSelectedNoteHelperScript(
            body: """
            printf '{"errorMessage":"No selected note"}\n' >&2
            exit 1
            """
        )
    } catch {
        Issue.record("Failed to create helper script: \(error)")
        return
    }
    defer { try? FileManager.default.removeItem(at: helperURL) }

    let transport = BearXCallbackTransport(
        readStore: StaticReadStore(note: nil, tags: []),
        selectedNoteResolveTimeout: .seconds(1),
        selectedNoteResolver: { url, timeout in
            try await BearSelectedNoteHelperRunner.resolveSelectedNoteID(
                executableURL: helperURL,
                bearURL: url,
                timeout: timeout
            )
        }
    )

    do {
        _ = try await transport.resolveSelectedNoteID(token: "top-secret-token")
        Issue.record("Expected selected-note helper failure.")
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
func resolveSelectedNoteIDTimesOutWhenSelectedNoteHelperStalls() async {
    let helperURL: URL
    do {
        helperURL = try makeSelectedNoteHelperScript(
            body: """
            sleep 1
            printf '{"identifier":"selected-note"}\n'
            """
        )
    } catch {
        Issue.record("Failed to create helper script: \(error)")
        return
    }
    defer { try? FileManager.default.removeItem(at: helperURL) }

    let transport = BearXCallbackTransport(
        readStore: StaticReadStore(note: nil, tags: []),
        selectedNoteResolveTimeout: .milliseconds(50),
        selectedNoteResolver: { url, timeout in
            try await BearSelectedNoteHelperRunner.resolveSelectedNoteID(
                executableURL: helperURL,
                bearURL: url,
                timeout: timeout
            )
        }
    )

    do {
        _ = try await transport.resolveSelectedNoteID(token: "top-secret-token")
        Issue.record("Expected selected-note helper timeout.")
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

@Test
func selectedNoteHelperLaunchArgumentsKeepHostHidden() {
    let arguments = BearSelectedNoteHelperRunner.launchArguments(
        appBundleURL: URL(fileURLWithPath: "/Applications/Ursus.app", isDirectory: true),
        bearURL: URL(string: "bear://x-callback-url/open-note?selected=yes&show_window=no&open_note=no")!,
        responseFileURL: URL(fileURLWithPath: "/tmp/selected-note.json", isDirectory: false),
        timeout: .seconds(4)
    )

    #expect(arguments == [
        "-g",
        "-j",
        "-a", "/Applications/Ursus.app",
        "--args",
        "-url", "bear://x-callback-url/open-note?selected=yes&show_window=no&open_note=no",
        "-activateApp", "NO",
        "-responseFile", "/tmp/selected-note.json",
        "-timeoutSeconds", "4.0",
    ])
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

    func setTrashed(noteID: String) {
        lock.lock()
        defer { lock.unlock() }
        guard note.ref.identifier == noteID else {
            return
        }

        note = BearNote(
            ref: note.ref,
            revision: NoteRevision(
                version: note.revision.version + 1,
                createdAt: note.revision.createdAt,
                modifiedAt: note.revision.modifiedAt.addingTimeInterval(1)
            ),
            title: note.title,
            body: note.body,
            rawText: note.rawText,
            tags: note.tags,
            archived: note.archived,
            trashed: true,
            encrypted: note.encrypted
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
    private(set) var urls: [URL] = []

    func record(url: URL, activates: Bool) async throws {
        urls.append(url)
        activations.append(activates)
    }
}

private func makeNote(
    id: String,
    title: String,
    archived: Bool = false,
    trashed: Bool = false,
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
        trashed: trashed,
        encrypted: false
    )
}

private func makeSelectedNoteHelperScript(body: String) throws -> URL {
    let scriptURL = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString, isDirectory: false)
        .appendingPathExtension("sh")

    let script = """
    #!/bin/sh
    BEAR_URL=""
    ACTIVATE_APP=""
    while [ "$#" -gt 0 ]; do
      case "$1" in
        -url)
          BEAR_URL="$2"
          shift 2
          ;;
        -activateApp)
          ACTIVATE_APP="$2"
          shift 2
          ;;
        *)
          shift
          ;;
      esac
    done
    \(body)
    """

    try script.write(to: scriptURL, atomically: true, encoding: .utf8)
    try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: scriptURL.path)
    return scriptURL
}
