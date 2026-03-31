import Foundation
import Testing

@Test
func repoIdentityGateAllowsOnlyIntentionalLegacyMentions() throws {
    let repoRootURL = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()

    let files = try repositoryTextFiles(rootURL: repoRootURL)
    let gates = try legacyIdentityGates()
    var failures: [String] = []

    for fileURL in files {
        let relativePath = fileURL.path.replacingOccurrences(of: repoRootURL.path + "/", with: "")
        let contents = try String(contentsOf: fileURL, encoding: .utf8)

        for gate in gates where gate.allowedRelativePaths.contains(relativePath) == false {
            let matchingLines = gate.matchingLineNumbers(in: contents)
            guard matchingLines.isEmpty == false else {
                continue
            }

            failures.append(
                "\(gate.label): \(relativePath):\(matchingLines.map(String.init).joined(separator: ","))"
            )
        }
    }

    if failures.isEmpty == false {
        Issue.record(
            """
            Unexpected legacy identity matches:
            \(failures.joined(separator: "\n"))
            """
        )
    }

    #expect(failures.isEmpty)
}

private struct LegacyIdentityGate {
    let label: String
    let expression: NSRegularExpression
    let allowedRelativePaths: Set<String>

    init(label: String, pattern: String, allowedRelativePaths: Set<String>) throws {
        self.label = label
        expression = try NSRegularExpression(pattern: pattern)
        self.allowedRelativePaths = allowedRelativePaths
    }

    func matchingLineNumbers(in contents: String) -> [Int] {
        return contents
            .components(separatedBy: .newlines)
            .enumerated()
            .compactMap { index, line in
                let range = NSRange(line.startIndex..<line.endIndex, in: line)
                return expression.firstMatch(in: line, range: range) == nil ? nil : index + 1
            }
    }
}

private func legacyIdentityGates() throws -> [LegacyIdentityGate] {
    let currentTestFile = "Tests/BearCoreTests/UrsusIdentityGateTests.swift"

    return try [
        LegacyIdentityGate(
            label: "legacy product phrase",
            pattern: #"Bear MCP"#,
            allowedRelativePaths: [
                "docs/LOCAL_BUILD_AND_CLEAN_INSTALL.md",
                currentTestFile,
            ]
        ),
        LegacyIdentityGate(
            label: "legacy product slug",
            pattern: #"\bbear-mcp\b"#,
            allowedRelativePaths: [
                "AGENTS.md",
                "Package.swift",
                "Tests/BearApplicationTests/BearRuntimeBootstrapTests.swift",
                "Tests/BearCoreTests/BearRuntimePathsTests.swift",
                "docs/LOCAL_BUILD_AND_CLEAN_INSTALL.md",
                currentTestFile,
            ]
        ),
        LegacyIdentityGate(
            label: "legacy helper callback scheme",
            pattern: #"\bbearmcphelper\b"#,
            allowedRelativePaths: [
                currentTestFile,
            ]
        ),
        LegacyIdentityGate(
            label: "legacy config/runtime path",
            pattern: #"""
            (?x)
            \.config/bear-mcp
            |Application\ Support/Bear\ MCP
            |Library/Logs/bear-mcp
            |com\.aft\.bear-mcp
            """#,
            allowedRelativePaths: [
                "Tests/BearApplicationTests/BearRuntimeBootstrapTests.swift",
                "Tests/BearCoreTests/BearRuntimePathsTests.swift",
                "docs/LOCAL_BUILD_AND_CLEAN_INSTALL.md",
                currentTestFile,
            ]
        ),
        LegacyIdentityGate(
            label: "legacy host server key",
            pattern: #"\[mcp_servers\.bear\]|"bear"\s*:"#,
            allowedRelativePaths: [
                "Sources/BearApplication/BearHostAppSupport.swift",
                "Tests/BearApplicationTests/BearAppSupportTests.swift",
                currentTestFile,
            ]
        ),
    ]
}

private func repositoryTextFiles(rootURL: URL) throws -> [URL] {
    let fileManager = FileManager.default
    let excludedDirectories = Set([".build", ".git", ".swiftpm"])
    var files: [URL] = []

    let enumerator = fileManager.enumerator(
        at: rootURL,
        includingPropertiesForKeys: [.isDirectoryKey],
        options: [.skipsPackageDescendants, .skipsHiddenFiles]
    )

    while let fileURL = enumerator?.nextObject() as? URL {
        let resourceValues = try fileURL.resourceValues(forKeys: [.isDirectoryKey])
        if resourceValues.isDirectory == true {
            if excludedDirectories.contains(fileURL.lastPathComponent) {
                enumerator?.skipDescendants()
            }
            continue
        }

        let data = try Data(contentsOf: fileURL)
        if data.contains(0) {
            continue
        }

        if String(data: data, encoding: .utf8) != nil {
            files.append(fileURL)
        }
    }

    return files
}
