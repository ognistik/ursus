import BearCore
import Foundation

public struct BearXCallbackURLBuilder: Sendable {
    public init() {}

    public func createURL(request: CreateNoteRequest) throws -> URL {
        try makeURL(
            action: "create",
            queryItems: [
                URLQueryItem(name: "title", value: request.title),
                URLQueryItem(name: "text", value: request.content),
            ] + presentationItems(request.presentation)
        )
    }

    public func insertTextURL(request: InsertTextRequest) throws -> URL {
        guard let position = request.position else {
            throw BearError.invalidInput("Direct Bear insert-text transport requires a concrete top/bottom position.")
        }

        return try makeURL(
            action: "add-text",
            queryItems: [
                URLQueryItem(name: "id", value: request.noteID),
                URLQueryItem(name: "text", value: request.text),
                URLQueryItem(name: "mode", value: position == .top ? "prepend" : "append"),
                URLQueryItem(name: "new_line", value: position == .bottom ? "yes" : nil),
            ] + presentationItems(request.presentation)
        )
    }

    public func replaceAllURL(noteID: String, fullText: String, presentation: BearPresentationOptions) throws -> URL {
        try makeURL(
            action: "add-text",
            queryItems: [
                URLQueryItem(name: "id", value: noteID),
                URLQueryItem(name: "text", value: fullText),
                URLQueryItem(name: "mode", value: "replace_all"),
            ] + presentationItems(presentation)
        )
    }

    public func addFileURL(request: AddFileRequest) throws -> URL {
        guard let position = request.position else {
            throw BearError.invalidInput("Direct Bear add-file transport requires a concrete top/bottom position.")
        }

        let fileURL = URL(fileURLWithPath: request.filePath)
        let fileData: Data

        do {
            fileData = try Data(contentsOf: fileURL)
        } catch {
            throw BearError.invalidInput(
                "Failed to read local file for Bear add-file: \(request.filePath). \(error.localizedDescription)"
            )
        }

        return try makeURL(
            action: "add-file",
            queryItems: [
                URLQueryItem(name: "id", value: request.noteID),
                URLQueryItem(name: "file", value: fileData.base64EncodedString()),
                URLQueryItem(name: "filename", value: fileURL.lastPathComponent),
                URLQueryItem(name: "header", value: request.header),
                URLQueryItem(name: "mode", value: position == .top ? "prepend" : "append"),
            ] + presentationItems(request.presentation)
        )
    }

    public func openURL(request: OpenNoteRequest) throws -> URL {
        try makeURL(
            action: "open-note",
            queryItems: [
                URLQueryItem(name: "id", value: request.noteID),
            ] + presentationItems(request.presentation)
        )
    }

    public func resolveSelectedNoteURL(token: String) throws -> URL {
        try makeURL(
            action: "open-note",
            queryItems: [
                URLQueryItem(name: "selected", value: yesNo(true)),
                URLQueryItem(name: "token", value: token),
            ] + presentationItems(
                BearPresentationOptions(
                    openNote: false,
                    newWindow: false,
                    showWindow: false,
                    edit: false
                )
            )
        )
    }

    public func resolveSelectedNoteURL() throws -> URL {
        try makeURL(
            action: "open-note",
            queryItems: [
                URLQueryItem(name: "selected", value: yesNo(true)),
            ] + presentationItems(
                BearPresentationOptions(
                    openNote: false,
                    newWindow: false,
                    showWindow: false,
                    edit: false
                )
            )
        )
    }

    public func resolveSelectedNoteURL(
        token: String,
        successURL: URL,
        errorURL: URL
    ) throws -> URL {
        try makeURL(
            action: "open-note",
            queryItems: [
                URLQueryItem(name: "selected", value: yesNo(true)),
                URLQueryItem(name: "token", value: token),
                URLQueryItem(name: "x-success", value: successURL.absoluteString),
                URLQueryItem(name: "x-error", value: errorURL.absoluteString),
            ] + presentationItems(
                BearPresentationOptions(
                    openNote: false,
                    newWindow: false,
                    showWindow: false,
                    edit: false
                )
            )
        )
    }

    public func openTagURL(request: OpenTagRequest) throws -> URL {
        try makeURL(
            action: "open-tag",
            queryItems: [
                URLQueryItem(name: "name", value: request.tag),
            ]
        )
    }

    public func renameTagURL(request: RenameTagRequest) throws -> URL {
        var queryItems: [URLQueryItem] = [
            URLQueryItem(name: "name", value: request.name),
            URLQueryItem(name: "new_name", value: request.newName),
        ]

        if let showWindow = request.showWindow {
            queryItems.append(URLQueryItem(name: "show_window", value: yesNo(showWindow)))
        }

        return try makeURL(
            action: "rename-tag",
            queryItems: queryItems
        )
    }

    public func deleteTagURL(request: DeleteTagRequest) throws -> URL {
        var queryItems: [URLQueryItem] = [
            URLQueryItem(name: "name", value: request.name),
        ]

        if let showWindow = request.showWindow {
            queryItems.append(URLQueryItem(name: "show_window", value: yesNo(showWindow)))
        }

        return try makeURL(
            action: "delete-tag",
            queryItems: queryItems
        )
    }

    public func archiveURL(noteID: String, showWindow: Bool) throws -> URL {
        try makeURL(
            action: "archive",
            queryItems: [
                URLQueryItem(name: "id", value: noteID),
                URLQueryItem(name: "show_window", value: yesNo(showWindow)),
            ]
        )
    }

    public func trashURL(noteID: String) throws -> URL {
        try makeURL(
            action: "trash",
            queryItems: [
                URLQueryItem(name: "id", value: noteID),
                URLQueryItem(name: "show_window", value: yesNo(false)),
            ]
        )
    }

    private func makeURL(action: String, queryItems: [URLQueryItem]) throws -> URL {
        var components = URLComponents()
        components.scheme = "bear"
        components.host = "x-callback-url"
        components.path = "/\(action)"
        components.queryItems = queryItems.filter { item in
            !(item.value?.isEmpty ?? true)
        }

        guard let url = components.url else {
            throw BearError.xCallback("Failed to build Bear x-callback URL for action '\(action)'.")
        }

        return url
    }

    private func presentationItems(_ presentation: BearPresentationOptions) -> [URLQueryItem] {
        let opensNote = presentation.openNoteOverride ?? presentation.openNote
        var items: [URLQueryItem] = []

        if opensNote {
            items.append(URLQueryItem(name: "show_window", value: yesNo(presentation.showWindow)))
            if let openNoteOverride = presentation.openNoteOverride {
                items.append(URLQueryItem(name: "open_note", value: yesNo(openNoteOverride)))
            } else {
                items.append(URLQueryItem(name: "open_note", value: yesNo(true)))
            }
        } else {
            items.append(URLQueryItem(name: "show_window", value: yesNo(false)))
            items.append(URLQueryItem(name: "open_note", value: yesNo(false)))
            return items
        }

        if let newWindowOverride = presentation.newWindowOverride {
            items.append(URLQueryItem(name: "new_window", value: yesNo(newWindowOverride)))
        } else if presentation.newWindow {
            items.append(URLQueryItem(name: "new_window", value: yesNo(true)))
        }
        if presentation.edit {
            items.append(URLQueryItem(name: "edit", value: yesNo(true)))
        }

        return items
    }

    private func yesNo(_ flag: Bool) -> String {
        flag ? "yes" : "no"
    }
}
