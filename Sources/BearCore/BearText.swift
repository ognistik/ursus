import Foundation

public struct ParsedBearText: Hashable, Sendable {
    public let titleLine: String?
    public let body: String
}

public enum BearText {
    public static func parse(rawText: String, fallbackTitle: String) -> ParsedBearText {
        let normalized = rawText.replacingOccurrences(of: "\r\n", with: "\n")
        let lines = normalized.components(separatedBy: "\n")

        guard let first = lines.first, first.hasPrefix("# ") else {
            return ParsedBearText(titleLine: nil, body: normalized.trimmingCharacters(in: .whitespacesAndNewlines))
        }

        let titleLine = String(first.dropFirst(2))
        let remaining = Array(lines.dropFirst())
        let body = remaining
            .drop { $0.isEmpty }
            .joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        if titleLine.isEmpty {
            return ParsedBearText(titleLine: fallbackTitle, body: body)
        }

        return ParsedBearText(titleLine: titleLine, body: body)
    }

    public static func composeRawText(title: String, body: String) -> String {
        let trimmedBody = body.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedBody.isEmpty {
            return "# \(title)"
        }

        return "# \(title)\n\n\(trimmedBody)"
    }
}
