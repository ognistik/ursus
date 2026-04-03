import AppKit
import BearCore
@testable import BearXCallback
import Foundation
import Testing

@Test
@MainActor
func callbackHostRewritesCallbackURLsAndPersistsSuccessPayload() throws {
    let recorder = CallbackHostRecorder()
    let responseFileURL = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString, isDirectory: false)
        .appendingPathExtension("json")
    defer { try? FileManager.default.removeItem(at: responseFileURL) }

    let host = BearSelectedNoteCallbackHost(
        outputWriter: { data, channel in
            recorder.recordOutput(data, channel: channel)
        },
        urlOpener: { url, activateApp, completion in
            recorder.recordOpen(url: url, activateApp: activateApp)
            completion(nil)
        },
        terminator: {
            recorder.recordTermination()
        }
    )

    host.start(
        arguments: [
            "ursus-helper",
            "-url", "bear://x-callback-url/open-note?selected=yes&token=top-secret-token",
            "-activateApp", "NO",
            "-responseFile", responseFileURL.path,
        ]
    )

    let started = recorder.snapshot()
    guard let openedURL = started.openedURL else {
        Issue.record("Expected Bear callback host to open a Bear x-callback URL.")
        return
    }

    #expect(started.activateApp == false)

    guard let openedComponents = URLComponents(url: openedURL, resolvingAgainstBaseURL: false) else {
        Issue.record("Expected opened Bear URL to parse cleanly.")
        return
    }
    let queryItems = openedComponents.queryItems ?? []
    guard let successValue = queryItems.first(where: { $0.name == "x-success" })?.value,
          let errorValue = queryItems.first(where: { $0.name == "x-error" })?.value
    else {
        Issue.record("Expected rewritten callback URLs to be attached to the Bear request.")
        return
    }

    #expect(successValue.hasPrefix("ursushelper://x-callback-url/handle-success?state="))
    #expect(errorValue.hasPrefix("ursushelper://x-callback-url/handle-error?state="))

    guard var callbackComponents = URLComponents(string: successValue) else {
        Issue.record("Expected success callback URL to parse cleanly.")
        return
    }
    callbackComponents.queryItems = (callbackComponents.queryItems ?? []) + [
        URLQueryItem(name: "identifier", value: "selected-note"),
    ]
    guard let callbackURL = callbackComponents.url else {
        Issue.record("Expected success callback URL to remain valid after adding an identifier.")
        return
    }

    host.handleAppleEvent(makeURLAppleEvent(callbackURL))

    let finished = recorder.snapshot()
    #expect(host.exitCode == 0)
    #expect(finished.terminatedCount == 1)
    #expect(finished.stdout.contains("\"identifier\""))
    #expect(finished.stdout.contains("selected-note"))
    #expect(finished.stderr.isEmpty)

    let responseData = try Data(contentsOf: responseFileURL)
    let payload = try parsePayload(responseData)
    #expect(payload["identifier"] == "selected-note")
}

@Test
@MainActor
func callbackHostCanAuthorizeTokenlessSelectedNoteRequestsBeforeOpeningBear() throws {
    let recorder = CallbackHostRecorder()
    let responseFileURL = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString, isDirectory: false)
        .appendingPathExtension("json")
    defer { try? FileManager.default.removeItem(at: responseFileURL) }

    let host = BearSelectedNoteCallbackHost(
        outputWriter: { data, channel in
            recorder.recordOutput(data, channel: channel)
        },
        requestURLAuthorizer: { requestURL in
            guard var components = URLComponents(url: requestURL, resolvingAgainstBaseURL: false) else {
                return requestURL
            }
            var items = components.queryItems ?? []
            items.append(URLQueryItem(name: "token", value: "managed-token"))
            components.queryItems = items
            return components.url ?? requestURL
        },
        urlOpener: { url, activateApp, completion in
            recorder.recordOpen(url: url, activateApp: activateApp)
            completion(nil)
        },
        terminator: {
            recorder.recordTermination()
        }
    )

    host.start(
        arguments: [
            "Ursus",
            "-url", "bear://x-callback-url/open-note?selected=yes&open_note=no&show_window=no",
            "-activateApp", "NO",
            "-responseFile", responseFileURL.path,
        ]
    )

    let started = recorder.snapshot()
    let openedURL = try #require(started.openedURL)
    let items = Dictionary(uniqueKeysWithValues: (URLComponents(url: openedURL, resolvingAgainstBaseURL: false)?.queryItems ?? []).compactMap { item in
        item.value.map { (item.name, $0) }
    })
    #expect(items["token"] == "managed-token")
    #expect(items["selected"] == "yes")
}

@Test
@MainActor
func callbackHostReportsInvalidInvocationWithoutLaunchingBear() {
    let recorder = CallbackHostRecorder()
    let host = BearSelectedNoteCallbackHost(
        outputWriter: { data, channel in
            recorder.recordOutput(data, channel: channel)
        },
        urlOpener: { url, activateApp, completion in
            recorder.recordOpen(url: url, activateApp: activateApp)
            completion(nil)
        },
        terminator: {
            recorder.recordTermination()
        }
    )

    host.start(arguments: ["ursus-helper"])

    let snapshot = recorder.snapshot()
    #expect(host.exitCode == 1)
    #expect(snapshot.terminatedCount == 1)
    #expect(snapshot.openedURL == nil)
    #expect(snapshot.stderr.contains("Missing required `-url` argument."))
}

@Test
@MainActor
func callbackHostPersistsInvocationErrorsToResponseFile() throws {
    let recorder = CallbackHostRecorder()
    let responseFileURL = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString, isDirectory: false)
        .appendingPathExtension("json")
    defer { try? FileManager.default.removeItem(at: responseFileURL) }

    let host = BearSelectedNoteCallbackHost(
        outputWriter: { data, channel in
            recorder.recordOutput(data, channel: channel)
        },
        requestURLAuthorizer: { _ in
            throw BearError.configuration("Missing shared keychain access.")
        },
        urlOpener: { url, activateApp, completion in
            recorder.recordOpen(url: url, activateApp: activateApp)
            completion(nil)
        },
        terminator: {
            recorder.recordTermination()
        }
    )

    host.start(
        arguments: [
            "ursus-helper",
            "-url", "bear://x-callback-url/open-note?selected=yes&open_note=no&show_window=no",
            "-responseFile", responseFileURL.path,
        ]
    )

    let snapshot = recorder.snapshot()
    #expect(host.exitCode == 1)
    #expect(snapshot.openedURL == nil)
    #expect(snapshot.stderr.contains("Missing shared keychain access."))

    let responseData = try Data(contentsOf: responseFileURL)
    let payload = try parsePayload(responseData)
    #expect(payload["errorMessage"] == "Missing shared keychain access.")
}

@Test
@MainActor
func callbackHostTimesOutIfBearNeverCallsBack() async throws {
    let recorder = CallbackHostRecorder()
    let host = BearSelectedNoteCallbackHost(
        outputWriter: { data, channel in
            recorder.recordOutput(data, channel: channel)
        },
        urlOpener: { url, activateApp, completion in
            recorder.recordOpen(url: url, activateApp: activateApp)
            completion(nil)
        },
        terminator: {
            recorder.recordTermination()
        }
    )

    host.start(
        arguments: [
            "ursus-helper",
            "-url", "bear://x-callback-url/open-note?selected=yes&token=top-secret-token",
            "-timeoutSeconds", "0.01",
        ]
    )

    try await Task.sleep(for: .milliseconds(100))

    let snapshot = recorder.snapshot()
    #expect(host.exitCode == 1)
    #expect(snapshot.terminatedCount == 1)
    #expect(snapshot.stderr.contains("timed out"))
}

private func makeURLAppleEvent(_ url: URL) -> NSAppleEventDescriptor {
    let event = NSAppleEventDescriptor.appleEvent(
        withEventClass: AEEventClass(kInternetEventClass),
        eventID: AEEventID(kAEGetURL),
        targetDescriptor: nil,
        returnID: AEReturnID(kAutoGenerateReturnID),
        transactionID: AETransactionID(kAnyTransactionID)
    )
    event.setParam(
        NSAppleEventDescriptor(string: url.absoluteString),
        forKeyword: AEKeyword(keyDirectObject)
    )
    return event
}

private func parsePayload(_ data: Data) throws -> [String: String] {
    guard let object = try JSONSerialization.jsonObject(with: data) as? [String: String] else {
        Issue.record("Expected callback host payload to be a JSON object of strings.")
        return [:]
    }
    return object
}

private struct CallbackHostSnapshot {
    let openedURL: URL?
    let activateApp: Bool?
    let stdout: String
    let stderr: String
    let terminatedCount: Int
}

private final class CallbackHostRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var openedURL: URL?
    private var activateApp: Bool?
    private var stdout = ""
    private var stderr = ""
    private var terminatedCount = 0

    func recordOpen(url: URL, activateApp: Bool) {
        lock.lock()
        self.openedURL = url
        self.activateApp = activateApp
        lock.unlock()
    }

    func recordOutput(_ data: Data, channel: BearSelectedNoteCallbackOutputChannel) {
        let text = String(decoding: data, as: UTF8.self)
        lock.lock()
        switch channel {
        case .stdout:
            stdout.append(text)
        case .stderr:
            stderr.append(text)
        }
        lock.unlock()
    }

    func recordTermination() {
        lock.lock()
        terminatedCount += 1
        lock.unlock()
    }

    func snapshot() -> CallbackHostSnapshot {
        lock.lock()
        defer { lock.unlock() }

        return CallbackHostSnapshot(
            openedURL: openedURL,
            activateApp: activateApp,
            stdout: stdout,
            stderr: stderr,
            terminatedCount: terminatedCount
        )
    }
}
