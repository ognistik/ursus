import Foundation

public struct TemplateContext: Hashable, Sendable {
    public let title: String
    public let content: String
    public let tags: [String]

    public init(title: String, content: String, tags: [String]) {
        self.title = title
        self.content = content
        self.tags = tags
    }
}

public enum TemplateRenderer {
    public static func renderDocument(
        context: TemplateContext,
        template: String?,
        preserveEmptyContentLine: Bool = false
    ) -> String {
        if preserveEmptyContentLine && context.content.isEmpty {
            return renderDocumentPreservingEmptyContentLine(context: context, template: template)
        }

        return render(template: template ?? "{{content}}", context: context)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    public static func render(template: String, context: TemplateContext) -> String {
        template
            .replacingOccurrences(of: "{{title}}", with: context.title)
            .replacingOccurrences(of: "{{content}}", with: context.content)
            .replacingOccurrences(of: "{{tags}}", with: renderTags(context.tags))
    }

    public static func renderTags(_ tags: [String]) -> String {
        tags
            .compactMap(BearTag.render)
            .joined(separator: " ")
    }

    private static func renderDocumentPreservingEmptyContentLine(
        context: TemplateContext,
        template: String?
    ) -> String {
        let marker = "__URSUS_EMPTY_CONTENT_\(UUID().uuidString)__"
        let markedContext = TemplateContext(title: context.title, content: marker, tags: context.tags)
        let rendered = render(template: template ?? "{{content}}", context: markedContext)
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: marker, with: "")

        return rendered.isEmpty ? "\n" : rendered
    }
}
