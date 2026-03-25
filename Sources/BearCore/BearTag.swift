import Foundation

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
}
