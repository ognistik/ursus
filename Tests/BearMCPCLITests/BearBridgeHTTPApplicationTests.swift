import Foundation
import MCP
import Testing
@testable import BearMCPCLI

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
