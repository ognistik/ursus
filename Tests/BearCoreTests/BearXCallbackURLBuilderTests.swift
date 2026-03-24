import BearCore
import BearXCallback
import Foundation
import Testing

@Test
func replaceAllURLUsesAddTextAndReplaceAllMode() throws {
    let builder = BearXCallbackURLBuilder()
    let url = try builder.replaceAllURL(
        noteID: "abc123",
        fullText: "# Updated",
        presentation: BearPresentationOptions(openNote: false, newWindow: false, floatingWindow: false, showWindow: true, edit: false)
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
            presentation: BearPresentationOptions(openNote: true, newWindow: false, floatingWindow: false, showWindow: true, edit: false)
        )
    )

    let absolute = url.absoluteString
    #expect(absolute.contains("bear://x-callback-url/create"))
    #expect(absolute.contains("title=Example"))
    #expect(absolute.contains("text=Body"))
    #expect(absolute.contains("open_note=yes"))
    #expect(!absolute.contains("float="))
    #expect(!absolute.contains("tags="))
}
