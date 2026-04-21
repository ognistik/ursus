import Foundation

public struct ParsedBearText: Hashable, Sendable {
    public let frontmatter: BearFrontmatter?
    public let titleLine: String?
    public let hasExplicitTitle: Bool
    public let body: String
    public let titleBodySeparator: String
}

public enum BearText {
    public static func parse(rawText: String, fallbackTitle: String) -> ParsedBearText {
        let normalized = rawText
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
        let extractedFrontmatter = extractFrontmatter(from: normalized)
        let afterFrontmatter = extractedFrontmatter.map { text(after: $0.range, in: normalized) } ?? normalized
        let postFrontmatter = trimmingLeadingNewlines(afterFrontmatter)
        let lines = postFrontmatter.components(separatedBy: "\n")

        guard let first = lines.first, first.hasPrefix("# ") else {
            return ParsedBearText(
                frontmatter: extractedFrontmatter?.value,
                titleLine: nil,
                hasExplicitTitle: false,
                body: postFrontmatter.trimmingCharacters(in: .whitespacesAndNewlines),
                titleBodySeparator: "\n\n"
            )
        }

        let parsedTitle = String(first.dropFirst(2))
        let remaining = Array(lines.dropFirst())
        let body = remaining
            .drop { $0.isEmpty }
            .joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        return ParsedBearText(
            frontmatter: extractedFrontmatter?.value,
            titleLine: parsedTitle.isEmpty ? fallbackTitle : parsedTitle,
            hasExplicitTitle: true,
            body: body,
            titleBodySeparator: titleBodySeparator(from: postFrontmatter, titleLine: first)
        )
    }

    public static func composeRawText(title: String, body: String) -> String {
        composeRawText(title: title, body: body, separator: "\n\n")
    }

    public static func composeRawText(title: String, body: String, separator: String) -> String {
        composeRawText(
            title: title,
            hasExplicitTitle: true,
            body: body,
            frontmatter: nil,
            separator: separator
        )
    }

    public static func composeRawText(
        title: String,
        hasExplicitTitle: Bool,
        body: String,
        frontmatter: BearFrontmatter?,
        separator: String
    ) -> String {
        let trimmedBody = body.trimmingCharacters(in: .whitespacesAndNewlines)
        let effectiveSeparator = separator.isEmpty ? "\n\n" : separator
        var parts: [String] = []

        if let frontmatter, frontmatter.content.trimmingCharacters(in: .newlines).isEmpty == false {
            parts.append(renderFrontmatterBlock(content: frontmatter.content))
        }

        if hasExplicitTitle {
            let titleLine = "# \(title)"
            if trimmedBody.isEmpty {
                parts.append(titleLine)
            } else {
                parts.append(titleLine + effectiveSeparator + trimmedBody)
            }
        } else if trimmedBody.isEmpty == false {
            parts.append(trimmedBody)
        }

        return parts.joined(separator: "\n")
    }

    public static func normalizeFrontmatterReplacement(_ content: String) -> String {
        let normalized = content
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
        let trimmed = normalized.trimmingCharacters(in: .whitespacesAndNewlines)
        let lines = trimmed.components(separatedBy: "\n")
        guard lines.count >= 2, lines.first == "---", lines.last == "---" else {
            return trimmed
        }

        return lines.dropFirst().dropLast().joined(separator: "\n").trimmingCharacters(in: .newlines)
    }

    public static func renderFrontmatterBlock(content: String) -> String {
        let normalizedContent = content
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .trimmingCharacters(in: .newlines)
        return "---\n\(normalizedContent)\n---"
    }

    private static func trimmingLeadingNewlines(_ text: String) -> String {
        var remainder = text
        while remainder.first == "\n" {
            remainder.removeFirst()
        }
        return remainder
    }

    private static func titleBodySeparator(from text: String, titleLine: String) -> String {
        guard text.hasPrefix(titleLine) else {
            return "\n\n"
        }

        let separatorStart = text.index(text.startIndex, offsetBy: titleLine.count)
        var cursor = separatorStart
        while cursor < text.endIndex, text[cursor] == "\n" {
            cursor = text.index(after: cursor)
        }

        let separator = String(text[separatorStart..<cursor])
        return separator.isEmpty ? "\n\n" : separator
    }

    private static func text(after range: Range<String.Index>, in text: String) -> String {
        guard range.upperBound < text.endIndex else {
            return ""
        }
        return String(text[range.upperBound...])
    }

    private static func extractFrontmatter(from rawText: String) -> (value: BearFrontmatter, range: Range<String.Index>)? {
        guard rawText.components(separatedBy: "\n").first == "---" else {
            return nil
        }

        let lines = rawText.components(separatedBy: "\n")
        guard lines.count >= 2 else {
            return nil
        }

        for index in 1 ..< lines.count {
            guard lines[index] == "---" else {
                continue
            }

            let rawBlock = lines[0...index].joined(separator: "\n")
            guard let range = rawText.range(of: rawBlock), range.lowerBound == rawText.startIndex else {
                continue
            }

            let content = lines.dropFirst().prefix(index - 1).joined(separator: "\n")
            return (
                BearFrontmatter(content: content),
                range
            )
        }

        return nil
    }
}
