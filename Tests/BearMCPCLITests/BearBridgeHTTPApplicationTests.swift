import Darwin
import Foundation
import Logging
import MCP
import Testing
@testable import BearCLIRuntime

@Test
func decodeInitializeRequestRejectsNonInitializePayloads() throws {
    let body = try JSONSerialization.data(
        withJSONObject: [
            "jsonrpc": "2.0",
            "id": "1",
            "method": "tools/list",
            "params": [:],
        ]
    )
    let request = HTTPRequest(
        method: "POST",
        headers: [
            "Content-Type": "application/json",
            "Accept": "application/json",
        ],
        body: body
    )

    #expect(BearBridgeHTTPApplication.decodeInitializeRequest(from: request) == nil)
}

@Test
func repeatedInitializeResponseReturnsFreshHandshakeForInitializedBridge() async throws {
    let server = Server(
        name: "ursus",
        version: "0.1.0",
        capabilities: .init(
            resources: .init(listChanged: false),
            tools: .init(listChanged: false)
        )
    )
    let body = try JSONSerialization.data(
        withJSONObject: [
            "jsonrpc": "2.0",
            "id": "re-init-1",
            "method": "initialize",
            "params": [
                "protocolVersion": "2025-11-25",
                "capabilities": [:],
                "clientInfo": [
                    "name": "host-app",
                    "version": "1.0",
                ],
            ],
        ]
    )
    let request = HTTPRequest(
        method: "POST",
        headers: [
            "Content-Type": "application/json",
            "Accept": "application/json",
        ],
        body: body
    )
    let initializeRequest = try #require(
        BearBridgeHTTPApplication.decodeInitializeRequest(from: request)
    )

    let response = try await BearBridgeHTTPApplication.makeInitializeResponse(
        for: initializeRequest,
        server: server
    )

    #expect(response.statusCode == 200)
    #expect(response.headers[HTTPHeaderName.contentType] == "application/json")

    let responseBody = try #require(response.bodyData)
    let initializeResponse = try JSONDecoder().decode(Response<Initialize>.self, from: responseBody)
    let result = try initializeResponse.result.get()

    #expect(initializeResponse.id == .string("re-init-1"))
    #expect(result.protocolVersion == "2025-11-25")
    #expect(result.serverInfo.name == "ursus")
    #expect(result.serverInfo.version == "0.1.0")
    #expect(result.capabilities.tools?.listChanged == false)
    #expect(result.capabilities.resources?.listChanged == false)
}

@Test
func repeatedInitializeResponseFallsBackToLatestProtocolVersion() async throws {
    let server = Server(name: "ursus", version: "0.1.0")
    let body = try JSONSerialization.data(
        withJSONObject: [
            "jsonrpc": "2.0",
            "id": "re-init-2",
            "method": "initialize",
            "params": [
                "protocolVersion": "2099-01-01",
                "capabilities": [:],
                "clientInfo": [
                    "name": "host-app",
                    "version": "1.0",
                ],
            ],
        ]
    )
    let httpRequest = HTTPRequest(
        method: "POST",
        headers: [
            "Content-Type": "application/json",
            "Accept": "application/json",
        ],
        body: body
    )
    let request = try #require(BearBridgeHTTPApplication.decodeInitializeRequest(from: httpRequest))

    let response = try await BearBridgeHTTPApplication.makeInitializeResponse(
        for: request,
        server: server
    )
    let responseBody = try #require(response.bodyData)
    let initializeResponse = try JSONDecoder().decode(Response<Initialize>.self, from: responseBody)
    let result = try initializeResponse.result.get()

    #expect(result.protocolVersion == Version.latest)
}

@Test
func bridgeInitializeSucceedsWhileRuntimeIsStillStarting() async throws {
    let port = try availableLoopbackPort()
    let application = BearBridgeHTTPApplication(
        configuration: .init(
            host: "127.0.0.1",
            port: port
        ),
        serverFactory: {
            try await Task.sleep(nanoseconds: 300_000_000)
            return Server(name: "ursus", version: "0.1.0")
        },
        logger: Logger(label: "test.ursus.bridge")
    )

    let startTask = Task {
        try await application.start()
    }
    defer {
        Task {
            await application.stop()
        }
    }

    try await waitUntilPortIsReachable(port: port)

    let responseData = try await sendInitializeRequest(port: port, requestID: "cold-start-init")
    let initializeResponse = try JSONDecoder().decode(Response<Initialize>.self, from: responseData)
    let result = try initializeResponse.result.get()

    #expect(initializeResponse.id == .string("cold-start-init"))
    #expect(result.serverInfo.name == "ursus")

    await application.stop()
    try await startTask.value
}

private func availableLoopbackPort() throws -> Int {
    let descriptor = socket(AF_INET, SOCK_STREAM, 0)
    guard descriptor >= 0 else {
        throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
    }
    defer { close(descriptor) }

    var address = sockaddr_in()
    address.sin_len = UInt8(MemoryLayout<sockaddr_in>.stride)
    address.sin_family = sa_family_t(AF_INET)
    address.sin_port = in_port_t(0).bigEndian
    address.sin_addr = in_addr(s_addr: inet_addr("127.0.0.1"))

    let bindResult = withUnsafePointer(to: &address) {
        $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
            bind(descriptor, $0, socklen_t(MemoryLayout<sockaddr_in>.stride))
        }
    }
    guard bindResult == 0 else {
        throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
    }

    var boundAddress = sockaddr_in()
    var length = socklen_t(MemoryLayout<sockaddr_in>.stride)
    let nameResult = withUnsafeMutablePointer(to: &boundAddress) {
        $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
            getsockname(descriptor, $0, &length)
        }
    }
    guard nameResult == 0 else {
        throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
    }

    return Int(UInt16(bigEndian: boundAddress.sin_port))
}

private func waitUntilPortIsReachable(
    port: Int,
    timeoutNanoseconds: UInt64 = 2_000_000_000
) async throws {
    let deadline = DispatchTime.now().uptimeNanoseconds + timeoutNanoseconds

    while true {
        if tcpConnects(port: port) {
            return
        }

        if DispatchTime.now().uptimeNanoseconds >= deadline {
            Issue.record("Timed out waiting for the bridge port to start accepting TCP connections.")
            throw CancellationError()
        }

        try await Task.sleep(nanoseconds: 20_000_000)
    }
}

private func tcpConnects(port: Int) -> Bool {
    let descriptor = socket(AF_INET, SOCK_STREAM, 0)
    guard descriptor >= 0 else {
        return false
    }
    defer { close(descriptor) }

    var address = sockaddr_in()
    address.sin_len = UInt8(MemoryLayout<sockaddr_in>.stride)
    address.sin_family = sa_family_t(AF_INET)
    address.sin_port = in_port_t(UInt16(port).bigEndian)
    address.sin_addr = in_addr(s_addr: inet_addr("127.0.0.1"))

    let connectResult = withUnsafePointer(to: &address) {
        $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
            connect(descriptor, $0, socklen_t(MemoryLayout<sockaddr_in>.stride))
        }
    }

    return connectResult == 0
}

private func sendInitializeRequest(port: Int, requestID: String) async throws -> Data {
    let url = try #require(URL(string: "http://127.0.0.1:\(port)/mcp"))
    var request = URLRequest(url: url)
    request.httpMethod = "POST"
    request.timeoutInterval = 2
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    request.setValue("application/json", forHTTPHeaderField: "Accept")
    request.httpBody = try JSONSerialization.data(
        withJSONObject: [
            "jsonrpc": "2.0",
            "id": requestID,
            "method": "initialize",
            "params": [
                "protocolVersion": Version.latest,
                "capabilities": [:],
                "clientInfo": [
                    "name": "bridge-test",
                    "version": "1.0",
                ],
            ],
        ]
    )

    let (data, response) = try await URLSession.shared.data(for: request)
    let httpResponse = try #require(response as? HTTPURLResponse)
    #expect(httpResponse.statusCode == 200)
    return data
}
