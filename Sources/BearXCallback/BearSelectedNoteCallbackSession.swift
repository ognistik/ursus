import BearCore
import Foundation
import Network

struct BearSelectedNoteCallbackTarget: Sendable {
    let successURL: URL
    let errorURL: URL
}

actor BearSelectedNoteCallbackSession {
    private let listener: NWListener
    private let stateToken = UUID().uuidString.replacingOccurrences(of: "-", with: "")
    private let requestID = UUID().uuidString.replacingOccurrences(of: "-", with: "")
    private let host = "127.0.0.1"
    private var readyContinuation: CheckedContinuation<BearSelectedNoteCallbackTarget, Error>?
    private var resultContinuation: CheckedContinuation<String, Error>?
    private var completed = false
    private var listenerStarted = false
    private var pendingResult: Result<String, Error>?

    init() throws {
        do {
            listener = try NWListener(using: .tcp, on: .any)
        } catch {
            throw BearError.xCallback("Failed to start selected-note callback listener. \(error.localizedDescription)")
        }
    }

    deinit {
        listener.stateUpdateHandler = nil
        listener.newConnectionHandler = nil
        listener.cancel()
    }

    func start() async throws -> BearSelectedNoteCallbackTarget {
        guard !listenerStarted else {
            throw BearError.xCallback("Selected-note callback listener was started more than once.")
        }

        listenerStarted = true
        listener.stateUpdateHandler = { state in
            Task {
                await self.handleStateUpdate(state)
            }
        }
        listener.newConnectionHandler = { connection in
            Task {
                await self.handleConnection(connection)
            }
        }
        listener.start(queue: DispatchQueue(label: "bear-mcp.selected-note-callback"))

        return try await withCheckedThrowingContinuation { continuation in
            readyContinuation = continuation
        }
    }

    func waitForResult(timeout: Duration) async throws -> String {
        defer {
            finish()
        }

        return try await withThrowingTaskGroup(of: String.self) { group in
            group.addTask {
                try await self.awaitCallback()
            }

            group.addTask {
                try await Task.sleep(for: timeout)
                throw BearError.xCallback("Timed out while waiting for Bear to resolve the selected note.")
            }

            let result = try await group.next() ?? ""
            group.cancelAll()
            return result
        }
    }

    private func awaitCallback() async throws -> String {
        if let pendingResult {
            self.pendingResult = nil
            return try pendingResult.get()
        }

        return try await withCheckedThrowingContinuation { continuation in
            resultContinuation = continuation
        }
    }

    private func handleStateUpdate(_ state: NWListener.State) {
        switch state {
        case .ready:
            guard let port = listener.port?.rawValue else {
                failReady(BearError.xCallback("Selected-note callback listener did not expose a local port."))
                return
            }

            let basePath = "/bear-mcp/\(requestID)"
            guard
                let successURL = URL(string: "http://\(host):\(port)\(basePath)/success?state=\(stateToken)"),
                let errorURL = URL(string: "http://\(host):\(port)\(basePath)/error?state=\(stateToken)")
            else {
                failReady(BearError.xCallback("Failed to build selected-note callback URLs."))
                return
            }

            readyContinuation?.resume(returning: BearSelectedNoteCallbackTarget(successURL: successURL, errorURL: errorURL))
            readyContinuation = nil

        case .failed(let error):
            let wrapped = BearError.xCallback("Selected-note callback listener failed. \(error.localizedDescription)")
            failReady(wrapped)
            failResult(wrapped)

        case .cancelled:
            let wrapped = BearError.xCallback("Selected-note callback listener was cancelled before Bear responded.")
            failReady(wrapped)
            failResult(wrapped)

        default:
            break
        }
    }

    private func handleConnection(_ connection: NWConnection) {
        connection.start(queue: DispatchQueue(label: "bear-mcp.selected-note-connection"))
        connection.receive(minimumIncompleteLength: 1, maximumLength: 64 * 1024) { data, _, _, error in
            Task {
                var responseStatus: String
                var responseBody: String

                defer {
                    let payload = Self.httpResponse(status: responseStatus, body: responseBody)
                    connection.send(content: payload, completion: .contentProcessed { _ in
                        connection.cancel()
                    })
                }

                if let error {
                    await self.failResult(BearError.xCallback("Selected-note callback connection failed. \(error.localizedDescription)"))
                    responseStatus = "500 Internal Server Error"
                    responseBody = "error"
                    return
                }

                guard let data, let request = String(data: data, encoding: .utf8) else {
                    responseStatus = "400 Bad Request"
                    responseBody = "invalid"
                    return
                }

                do {
                    let callback = try await self.parseRequest(request)
                    try await self.consumeCallback(callback)
                    responseStatus = "200 OK"
                    responseBody = "ok"
                } catch {
                    responseStatus = "400 Bad Request"
                    responseBody = "invalid"
                    await self.failResult(error)
                }
            }
        }
    }

    private func parseRequest(_ request: String) throws -> CallbackRequest {
        guard let firstLine = request.components(separatedBy: "\r\n").first else {
            throw BearError.xCallback("Selected-note callback request was malformed.")
        }

        let parts = firstLine.split(separator: " ")
        guard parts.count >= 2 else {
            throw BearError.xCallback("Selected-note callback request line was malformed.")
        }

        guard let url = URL(string: "http://\(host)\(parts[1])"),
              let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        else {
            throw BearError.xCallback("Selected-note callback URL was malformed.")
        }

        let queryItems = Dictionary(uniqueKeysWithValues: (components.queryItems ?? []).map { ($0.name, $0.value ?? "") })
        guard queryItems["state"] == stateToken else {
            throw BearError.xCallback("Selected-note callback state did not match the current request.")
        }

        return CallbackRequest(path: components.path, queryItems: queryItems)
    }

    private func consumeCallback(_ callback: CallbackRequest) async throws {
        guard callback.path.hasPrefix("/bear-mcp/\(requestID)/") else {
            throw BearError.xCallback("Selected-note callback path did not match the current request.")
        }

        if callback.path.hasSuffix("/error") {
            let message = callback.queryItems["errorMessage"] ?? callback.queryItems["error"] ?? "Bear did not return the selected note."
            throw BearError.xCallback(message)
        }

        guard callback.path.hasSuffix("/success") else {
            throw BearError.xCallback("Selected-note callback path was not recognized.")
        }

        let identifier = callback.queryItems["identifier"] ?? callback.queryItems["id"]
        guard let identifier, !identifier.isEmpty else {
            throw BearError.xCallback("Bear did not return an identifier for the selected note.")
        }

        succeed(identifier)
    }

    private func succeed(_ identifier: String) {
        guard !completed else {
            return
        }

        completed = true
        if let resultContinuation {
            self.resultContinuation = nil
            resultContinuation.resume(returning: identifier)
        } else {
            pendingResult = .success(identifier)
        }
    }

    private func failReady(_ error: Error) {
        guard let readyContinuation else {
            return
        }

        self.readyContinuation = nil
        readyContinuation.resume(throwing: error)
    }

    private func failResult(_ error: Error) {
        guard !completed else {
            return
        }

        completed = true
        if let resultContinuation {
            self.resultContinuation = nil
            resultContinuation.resume(throwing: error)
        } else {
            pendingResult = .failure(error)
        }
    }

    private func finish() {
        listener.stateUpdateHandler = nil
        listener.newConnectionHandler = nil
        listener.cancel()
    }

    private static func httpResponse(status: String, body: String) -> Data {
        let payload = "HTTP/1.1 \(status)\r\nContent-Type: text/plain; charset=utf-8\r\nContent-Length: \(body.utf8.count)\r\nConnection: close\r\n\r\n\(body)"
        return Data(payload.utf8)
    }
}

private struct CallbackRequest {
    let path: String
    let queryItems: [String: String]
}
