import BearCore
import BearXCallback
import Foundation
import Testing

@Test
func addFileURLReadsLocalFileAsBase64AndIncludesHeaderTarget() throws {
    let builder = BearXCallbackURLBuilder()
    let fileURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathExtension("txt")
    try "payload".write(to: fileURL, atomically: true, encoding: .utf8)
    defer { try? FileManager.default.removeItem(at: fileURL) }

    let url = try builder.addFileURL(
        request: AddFileRequest(
            noteID: "abc123",
            filePath: fileURL.path,
            header: "Attachments",
            position: .bottom,
            presentation: BearPresentationOptions(openNote: false, newWindow: false, showWindow: true, edit: false),
            expectedVersion: nil
        )
    )

    let components = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false))
    let items = Dictionary(uniqueKeysWithValues: (components.queryItems ?? []).compactMap { item in
        item.value.map { (item.name, $0) }
    })

    #expect(components.path == "/add-file")
    #expect(items["id"] == "abc123")
    #expect(items["filename"] == fileURL.lastPathComponent)
    #expect(items["header"] == "Attachments")
    #expect(items["mode"] == "append")
    #expect(items["file"] == Data("payload".utf8).base64EncodedString())
}

@Test
func replaceAllURLUsesAddTextAndReplaceAllMode() throws {
    let builder = BearXCallbackURLBuilder()
    let url = try builder.replaceAllURL(
        noteID: "abc123",
        fullText: "# Updated",
        presentation: BearPresentationOptions(openNote: false, newWindow: false, showWindow: true, edit: false)
    )

    let absolute = url.absoluteString
    #expect(absolute.contains("bear://x-callback-url/add-text"))
    #expect(absolute.contains("mode=replace_all"))
    #expect(absolute.contains("id=abc123"))
}

@Test
func createURLSendsTitleAndTextButNotTagsParameter() throws {
    let builder = BearXCallbackURLBuilder()
    let url = try builder.createURL(
        request: CreateNoteRequest(
            title: "Example",
            content: "Body\n\n#inbox",
            tags: ["inbox"],
            presentation: BearPresentationOptions(openNote: true, newWindow: false, showWindow: true, edit: false)
        )
    )

    let absolute = url.absoluteString
    #expect(absolute.contains("bear://x-callback-url/create"))
    #expect(absolute.contains("title=Example"))
    #expect(absolute.contains("text=Body"))
    #expect(absolute.contains("open_note=yes"))
    #expect(!absolute.contains("tags="))
}

@Test
func createURLSendsExplicitClosedOverrideAndSuppressesOpenOnlyFlags() throws {
    let builder = BearXCallbackURLBuilder()
    let url = try builder.createURL(
        request: CreateNoteRequest(
            title: "Closed Example",
            content: "Body",
            tags: [],
            presentation: BearPresentationOptions(
                openNote: false,
                openNoteOverride: false,
                newWindow: true,
                newWindowOverride: true,
                showWindow: true,
                edit: true
            )
        )
    )

    let absolute = url.absoluteString
    #expect(absolute.contains("open_note=no"))
    #expect(!absolute.contains("new_window="))
    #expect(!absolute.contains("edit="))
    #expect(!absolute.contains("float="))
}

@Test
func createURLSendsExplicitNewWindowOverrideWhenOpened() throws {
    let builder = BearXCallbackURLBuilder()
    let url = try builder.createURL(
        request: CreateNoteRequest(
            title: "Window Override",
            content: "Body",
            tags: [],
            presentation: BearPresentationOptions(
                openNote: true,
                openNoteOverride: true,
                newWindow: false,
                newWindowOverride: false,
                showWindow: true,
                edit: false
            )
        )
    )

    let absolute = url.absoluteString
    #expect(absolute.contains("open_note=yes"))
    #expect(absolute.contains("new_window=no"))
    #expect(!absolute.contains("float="))
}

@Test
func openTagURLUsesSingleTagNameOnly() throws {
    let builder = BearXCallbackURLBuilder()
    let url = try builder.openTagURL(
        request: OpenTagRequest(tag: "projects/workflows")
    )

    let absolute = url.absoluteString
    #expect(absolute.contains("bear://x-callback-url/open-tag"))
    #expect(absolute.contains("name=projects/workflows"))
    #expect(!absolute.contains("show_window="))
}

@Test
func renameTagURLOmitsShowWindowWhenNotRequested() throws {
    let builder = BearXCallbackURLBuilder()
    let url = try builder.renameTagURL(
        request: RenameTagRequest(name: "todo", newName: "done", showWindow: nil)
    )

    let absolute = url.absoluteString
    #expect(absolute.contains("bear://x-callback-url/rename-tag"))
    #expect(absolute.contains("name=todo"))
    #expect(absolute.contains("new_name=done"))
    #expect(!absolute.contains("show_window="))
}

@Test
func renameTagURLIncludesExplicitShowWindowOverride() throws {
    let builder = BearXCallbackURLBuilder()
    let url = try builder.renameTagURL(
        request: RenameTagRequest(name: "todo", newName: "done", showWindow: false)
    )

    let absolute = url.absoluteString
    #expect(absolute.contains("show_window=no"))
}
