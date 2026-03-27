import Foundation

public struct BearTagToken: Hashable, Sendable {
    public let rawValue: String
    public let normalizedName: String
    public let utf16Range: Range<Int>

    public init(rawValue: String, normalizedName: String, utf16Range: Range<Int>) {
        self.rawValue = rawValue
        self.normalizedName = normalizedName
        self.utf16Range = utf16Range
    }

    public func range(in text: String) -> Range<String.Index>? {
        let lowerBound = String.Index(utf16Offset: utf16Range.lowerBound, in: text)
        let upperBound = String.Index(utf16Offset: utf16Range.upperBound, in: text)
        return lowerBound..<upperBound
    }
}

public enum BearTag {
    public static func normalizedName(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return ""
        }

        let withoutLeadingHash = trimmed.hasPrefix("#") ? String(trimmed.dropFirst()) : trimmed
        let withoutWrappingHashes = withoutLeadingHash.hasSuffix("#") ? String(withoutLeadingHash.dropLast()) : withoutLeadingHash
        return withoutWrappingHashes.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    public static func render(_ raw: String) -> String? {
        let normalized = normalizedName(raw)
        guard !normalized.isEmpty else {
            return nil
        }

        return normalized.contains(where: \.isWhitespace) ? "#\(normalized)#" : "#\(normalized)"
    }

    public static func deduplicationKey(_ raw: String) -> String {
        normalizedName(raw).lowercased()
    }

    public static func normalizedParentPath(_ raw: String) -> String {
        let normalized = normalizedName(raw)
        guard !normalized.isEmpty else {
            return ""
        }

        let withoutTrailingSlash = normalized.hasSuffix("/") ? String(normalized.dropLast()) : normalized
        return withoutTrailingSlash.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    public static func extractTokens(from text: String) -> [BearTagToken] {
        var tokens: [BearTagToken] = []
        var index = text.startIndex

        while index < text.endIndex {
            guard text[index] == "#" else {
                index = text.index(after: index)
                continue
            }

            let start = index
            let afterHash = text.index(after: index)
            guard afterHash < text.endIndex else {
                break
            }

            if let wrappedEnd = wrappedTagEnd(in: text, startingAt: afterHash) {
                let rawValue = String(text[start...wrappedEnd])
                let normalized = normalizedName(rawValue)
                if !normalized.isEmpty {
                    tokens.append(
                        BearTagToken(
                            rawValue: rawValue,
                            normalizedName: normalized,
                            utf16Range: start.utf16Offset(in: text)..<text.index(after: wrappedEnd).utf16Offset(in: text)
                        )
                    )
                    index = text.index(after: wrappedEnd)
                    continue
                }
            }

            let bareEnd = bareTagEnd(in: text, startingAt: afterHash)
            guard bareEnd > afterHash else {
                index = afterHash
                continue
            }

            let rawValue = String(text[start..<bareEnd])
            let normalized = normalizedName(rawValue)
            if !normalized.isEmpty {
                tokens.append(
                    BearTagToken(
                        rawValue: rawValue,
                        normalizedName: normalized,
                        utf16Range: start.utf16Offset(in: text)..<bareEnd.utf16Offset(in: text)
                    )
                )
            }
            index = bareEnd
        }

        return tokens
    }

    public static func extractNormalizedNames(from text: String) -> [String] {
        var seen: Set<String> = []
        var names: [String] = []

        for token in extractTokens(from: text) {
            let key = deduplicationKey(token.normalizedName)
            guard seen.insert(key).inserted else {
                continue
            }
            names.append(token.normalizedName)
        }

        return names
    }

    private static func wrappedTagEnd(in text: String, startingAt start: String.Index) -> String.Index? {
        var cursor = start

        while cursor < text.endIndex {
            let character = text[cursor]
            if character == "\n" || character == "\r" {
                return nil
            }

            if character == "#" {
                let candidate = String(text[start..<cursor])
                let trimmed = candidate.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty && trimmed == candidate && candidate.contains("#") == false {
                    return cursor
                }
            }

            cursor = text.index(after: cursor)
        }

        return nil
    }

    private static func bareTagEnd(in text: String, startingAt start: String.Index) -> String.Index {
        var cursor = start

        while cursor < text.endIndex, isBareTagCharacter(text[cursor]) {
            cursor = text.index(after: cursor)
        }

        return cursor
    }

    private static func isBareTagCharacter(_ character: Character) -> Bool {
        guard !character.isWhitespace, character != "#" else {
            return false
        }

        let disallowed: Set<Character> = [",", ".", ";", ":", "!", "?", ")", "]", "}", ">", "\"", "'"]
        return disallowed.contains(character) == false
    }
}
