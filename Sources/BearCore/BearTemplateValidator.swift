import Foundation

public enum BearTemplateValidationIssueSeverity: String, Codable, Hashable, Sendable {
    case error
    case warning
}

public struct BearTemplateValidationIssue: Codable, Hashable, Sendable, Identifiable {
    public let severity: BearTemplateValidationIssueSeverity
    public let message: String

    public var id: String {
        "\(severity.rawValue):\(message)"
    }

    public init(
        severity: BearTemplateValidationIssueSeverity,
        message: String
    ) {
        self.severity = severity
        self.message = message
    }
}

public struct BearTemplateValidationReport: Codable, Hashable, Sendable {
    public let issues: [BearTemplateValidationIssue]

    public init(issues: [BearTemplateValidationIssue] = []) {
        self.issues = issues
    }

    public var errors: [BearTemplateValidationIssue] {
        issues.filter { $0.severity == .error }
    }

    public var warnings: [BearTemplateValidationIssue] {
        issues.filter { $0.severity == .warning }
    }

    public var hasErrors: Bool {
        !errors.isEmpty
    }
}

public enum BearTemplateValidator {
    public static func validate(_ template: String) -> BearTemplateValidationReport {
        let normalizedTemplate = normalizedLineEndings(template)
        let contentMatches = normalizedTemplate.components(separatedBy: "{{content}}").count - 1
        let tagsMatches = normalizedTemplate.components(separatedBy: "{{tags}}").count - 1

        var issues: [BearTemplateValidationIssue] = []

        switch contentMatches {
        case 1:
            break
        case 0:
            issues.append(
                BearTemplateValidationIssue(
                    severity: .error,
                    message: "Template must include one `{{content}}` slot."
                )
            )
        default:
            issues.append(
                BearTemplateValidationIssue(
                    severity: .error,
                    message: "Template can include `{{content}}` only once."
                )
            )
        }

        switch tagsMatches {
        case 1:
            break
        case 0:
            issues.append(
                BearTemplateValidationIssue(
                    severity: .error,
                    message: "Template must include one `{{tags}}` slot."
                )
            )
        default:
            issues.append(
                BearTemplateValidationIssue(
                    severity: .error,
                    message: "Template can include `{{tags}}` only once."
                )
            )
        }

        if normalizedTemplate.contains("{{title}}") {
            issues.append(
                BearTemplateValidationIssue(
                    severity: .warning,
                    message: "Ursus applies the template below Bear's note title. Avoid `{{title}}` unless you intentionally want title text inside the body."
                )
            )
        }

        issues.append(contentsOf: unknownPlaceholderWarnings(in: normalizedTemplate))
        return BearTemplateValidationReport(issues: issues)
    }

    private static func unknownPlaceholderWarnings(in template: String) -> [BearTemplateValidationIssue] {
        guard let placeholderRegex = try? NSRegularExpression(pattern: #"\{\{[^{}\n]+\}\}"#) else {
            return []
        }

        let nsTemplate = template as NSString
        let matches = placeholderRegex.matches(
            in: template,
            options: [],
            range: NSRange(location: 0, length: nsTemplate.length)
        )

        let knownPlaceholders: Set<String> = ["{{title}}", "{{content}}", "{{tags}}"]
        var seen: Set<String> = []
        var warnings: [BearTemplateValidationIssue] = []

        for match in matches {
            let placeholder = nsTemplate.substring(with: match.range)
            guard !knownPlaceholders.contains(placeholder), !seen.contains(placeholder) else {
                continue
            }

            seen.insert(placeholder)
            warnings.append(
                BearTemplateValidationIssue(
                    severity: .warning,
                    message: "Unknown placeholder `\(placeholder)` will be saved literally."
                )
            )
        }

        return warnings
    }

    private static func normalizedLineEndings(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
    }
}
