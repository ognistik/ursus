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
        template: String?
    ) -> String {
        render(template: template ?? "{{content}}", context: context)
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
            .map { tag in
                let trimmed = tag.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty else {
                    return nil
                }
                return trimmed.hasPrefix("#") ? trimmed : "#\(trimmed)"
            }
            .compactMap { $0 }
            .joined(separator: " ")
    }
}
