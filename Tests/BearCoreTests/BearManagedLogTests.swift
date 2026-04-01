import BearCore
import Foundation
import Testing

@Test
func managedAppendRotationKeepsOnlyCurrentAndOneArchive() throws {
    let fileManager = FileManager.default
    let temporaryDirectory = fileManager.temporaryDirectory
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    let logsDirectoryURL = temporaryDirectory.appendingPathComponent("Logs", isDirectory: true)
    let logURL = logsDirectoryURL.appendingPathComponent("debug.log", isDirectory: false)

    try fileManager.createDirectory(at: logsDirectoryURL, withIntermediateDirectories: true)
    try Data(repeating: 0x61, count: BearManagedLog.maxFileSizeBytes).write(to: logURL, options: .atomic)
    try "oldest".write(
        to: logsDirectoryURL.appendingPathComponent("debug.log.3", isDirectory: false),
        atomically: true,
        encoding: .utf8
    )
    try "older".write(
        to: logsDirectoryURL.appendingPathComponent("debug.log.2", isDirectory: false),
        atomically: true,
        encoding: .utf8
    )
    try "old".write(
        to: logsDirectoryURL.appendingPathComponent("debug.log.1", isDirectory: false),
        atomically: true,
        encoding: .utf8
    )
    defer {
        try? fileManager.removeItem(at: temporaryDirectory)
    }

    BearDebugLog.append(
        "rotation-check",
        fileManager: fileManager,
        logURL: logURL,
        logsDirectoryURL: logsDirectoryURL
    )

    let firstArchiveURL = logsDirectoryURL.appendingPathComponent("debug.log.1", isDirectory: false)
    let secondArchiveURL = logsDirectoryURL.appendingPathComponent("debug.log.2", isDirectory: false)
    let thirdArchiveURL = logsDirectoryURL.appendingPathComponent("debug.log.3", isDirectory: false)

    #expect(fileManager.fileExists(atPath: logURL.path))
    #expect(fileManager.fileExists(atPath: firstArchiveURL.path))
    #expect(fileManager.fileExists(atPath: secondArchiveURL.path) == false)
    #expect(fileManager.fileExists(atPath: thirdArchiveURL.path) == false)

    let activeContents = try String(contentsOf: logURL, encoding: .utf8)
    #expect(activeContents.contains("rotation-check"))
}

@Test
func externalProcessLogMaintenanceSnapshotsAndTruncatesInPlace() throws {
    let fileManager = FileManager.default
    let temporaryDirectory = fileManager.temporaryDirectory
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    let logsDirectoryURL = temporaryDirectory.appendingPathComponent("Logs", isDirectory: true)
    let logURL = logsDirectoryURL.appendingPathComponent("bridge.stderr.log", isDirectory: false)

    try fileManager.createDirectory(at: logsDirectoryURL, withIntermediateDirectories: true)
    try Data(repeating: 0x62, count: BearManagedLog.maxFileSizeBytes + 128).write(to: logURL, options: .atomic)
    try "older".write(
        to: logsDirectoryURL.appendingPathComponent("bridge.stderr.log.2", isDirectory: false),
        atomically: true,
        encoding: .utf8
    )
    defer {
        try? fileManager.removeItem(at: temporaryDirectory)
    }

    try BearManagedLog.prepareLogFile(
        fileManager: fileManager,
        logURL: logURL,
        logsDirectoryURL: logsDirectoryURL,
        writer: .externalProcess
    )

    let firstArchiveURL = logsDirectoryURL.appendingPathComponent("bridge.stderr.log.1", isDirectory: false)
    let secondArchiveURL = logsDirectoryURL.appendingPathComponent("bridge.stderr.log.2", isDirectory: false)
    let activeSize = (try fileManager.attributesOfItem(atPath: logURL.path)[.size] as? NSNumber)?.intValue
    let archivedSize = (try fileManager.attributesOfItem(atPath: firstArchiveURL.path)[.size] as? NSNumber)?.intValue

    #expect(fileManager.fileExists(atPath: logURL.path))
    #expect(fileManager.fileExists(atPath: firstArchiveURL.path))
    #expect(fileManager.fileExists(atPath: secondArchiveURL.path) == false)
    #expect(activeSize == 0)
    #expect(archivedSize == BearManagedLog.maxFileSizeBytes + 128)
}
