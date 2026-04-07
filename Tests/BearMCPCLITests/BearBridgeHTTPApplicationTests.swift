import BearApplication
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
func bridgeRouterClassifiesMCPAndOAuthPaths() {
    #expect(BearBridgeHTTPApplication.route(for: "/mcp", mcpEndpoint: "/mcp") == .mcp)
    #expect(BearBridgeHTTPApplication.route(for: "/.well-known/oauth-protected-resource", mcpEndpoint: "/mcp") == .oauthProtectedResourceMetadata)
    #expect(BearBridgeHTTPApplication.route(for: "/.well-known/oauth-authorization-server?resource=http://127.0.0.1:6190/mcp", mcpEndpoint: "/mcp") == .oauthAuthorizationServerMetadata)
    #expect(BearBridgeHTTPApplication.route(for: "/oauth/authorize", mcpEndpoint: "/mcp") == .oauthAuthorize)
    #expect(BearBridgeHTTPApplication.route(for: "/oauth/decision", mcpEndpoint: "/mcp") == .oauthDecision)
    #expect(BearBridgeHTTPApplication.route(for: "/oauth/request-status?request_id=abc", mcpEndpoint: "/mcp") == .notFound)
    #expect(BearBridgeHTTPApplication.route(for: "/oauth/token", mcpEndpoint: "/mcp") == .oauthToken)
    #expect(BearBridgeHTTPApplication.route(for: "/oauth/register", mcpEndpoint: "/mcp") == .oauthRegister)
    #expect(BearBridgeHTTPApplication.route(for: "/unknown", mcpEndpoint: "/mcp") == .notFound)
}

@Test
func oauthOriginUsesCanonicalPublicHTTPSPortForTunnelHostHeaders() {
    let publicOrigin = BearBridgeOAuthServer.originURL(
        hostHeader: "mcp.afadingthought.com",
        fallbackHost: "127.0.0.1",
        fallbackPort: 6190
    )
    #expect(publicOrigin.absoluteString == "https://mcp.afadingthought.com")

    let leakedPortOrigin = BearBridgeOAuthServer.originURL(
        hostHeader: "mcp.afadingthought.com:6190",
        fallbackHost: "127.0.0.1",
        fallbackPort: 6190
    )
    #expect(leakedPortOrigin.absoluteString == "https://mcp.afadingthought.com")

    let explicitPublicPortOrigin = BearBridgeOAuthServer.originURL(
        hostHeader: "mcp.afadingthought.com:8443",
        fallbackHost: "127.0.0.1",
        fallbackPort: 6190
    )
    #expect(explicitPublicPortOrigin.absoluteString == "https://mcp.afadingthought.com:8443")
}

@Test
func oauthMetadataUsesCanonicalPublicOriginForTunnelHostHeaders() async throws {
    let fileManager = FileManager.default
    let temporaryRoot = fileManager.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    let authDatabaseURL = temporaryRoot
        .appendingPathComponent("Auth", isDirectory: true)
        .appendingPathComponent("bridge-auth.sqlite", isDirectory: false)
    defer {
        try? fileManager.removeItem(at: temporaryRoot)
    }

    let oauthServer = BearBridgeOAuthServer(
        configuration: .init(
            host: "127.0.0.1",
            port: 6190,
            mcpEndpoint: "/mcp",
            authDatabaseURL: authDatabaseURL
        )
    )

    let protectedResourceResponse = await oauthServer.handle(
        request: HTTPRequest(
            method: "GET",
            headers: ["Host": "mcp.afadingthought.com"],
            path: "/.well-known/oauth-protected-resource/mcp"
        )
    )
    let protectedResourceBody: Data
    switch protectedResourceResponse {
    case .plain(_, _, let body):
        protectedResourceBody = try #require(body)
    case .mcp:
        Issue.record("Expected a plain protected-resource metadata response.")
        throw CancellationError()
    }

    let protectedResourceObject = try #require(
        try JSONSerialization.jsonObject(with: protectedResourceBody) as? [String: Any]
    )
    #expect(protectedResourceObject["resource"] as? String == "https://mcp.afadingthought.com/mcp")
    #expect(
        protectedResourceObject["authorization_servers"] as? [String]
            == ["https://mcp.afadingthought.com"]
    )

    let authorizationServerResponse = await oauthServer.handle(
        request: HTTPRequest(
            method: "GET",
            headers: ["Host": "mcp.afadingthought.com"],
            path: "/.well-known/oauth-authorization-server?resource=https://mcp.afadingthought.com/mcp"
        )
    )
    let authorizationServerBody: Data
    switch authorizationServerResponse {
    case .plain(let statusCode, _, let body):
        #expect(statusCode == 200)
        authorizationServerBody = try #require(body)
    case .mcp:
        Issue.record("Expected a plain authorization-server metadata response.")
        throw CancellationError()
    }

    let authorizationServerObject = try #require(
        try JSONSerialization.jsonObject(with: authorizationServerBody) as? [String: Any]
    )
    #expect(authorizationServerObject["issuer"] as? String == "https://mcp.afadingthought.com")
    #expect(
        authorizationServerObject["registration_endpoint"] as? String
            == "https://mcp.afadingthought.com/oauth/register"
    )

    let challengeResponse = BearBridgeHTTPApplication.oauthRequiredResponse(
        for: HTTPRequest(
            method: "POST",
            headers: ["Host": "mcp.afadingthought.com"],
            path: "/mcp"
        ),
        host: "127.0.0.1",
        port: 6190,
        mcpEndpoint: "/mcp"
    )
    let challenge = challengeResponse.headers[HTTPHeaderName.wwwAuthenticate]
    #expect(
        challenge?.contains(
            #"resource_metadata="https://mcp.afadingthought.com/.well-known/oauth-protected-resource/mcp""#
        ) == true
    )
}

@Test
func bridgeSupportsBrowserCORSPreflightForOAuthRegistration() async throws {
    let fileManager = FileManager.default
    let temporaryRoot = fileManager.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    let authDatabaseURL = temporaryRoot
        .appendingPathComponent("Auth", isDirectory: true)
        .appendingPathComponent("bridge-auth.sqlite", isDirectory: false)
    defer {
        try? fileManager.removeItem(at: temporaryRoot)
    }

    let port = try availableLoopbackPort()
    let application = BearBridgeHTTPApplication(
        configuration: .init(
            host: "127.0.0.1",
            port: port,
            authMode: .oauth,
            authDatabaseURL: authDatabaseURL
        ),
        serverFactory: {
            await makeToolsListTestingServer()
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

    let response = try await sendHTTPRequest(
        port: port,
        path: "/oauth/register",
        method: "OPTIONS",
        headers: [
            "Origin": "https://chatgpt.com",
            "Access-Control-Request-Method": "POST",
            "Access-Control-Request-Headers": "content-type",
        ]
    )

    #expect(response.statusCode == 204)
    #expect(response.httpResponse.value(forHTTPHeaderField: "Access-Control-Allow-Origin") == "https://chatgpt.com")
    #expect(response.httpResponse.value(forHTTPHeaderField: "Access-Control-Allow-Headers") == "content-type")
    #expect(response.httpResponse.value(forHTTPHeaderField: "Access-Control-Allow-Methods")?.contains("POST") == true)

    await application.stop()
    try await startTask.value
}

@Test
func bridgeExposesOAuthChallengeHeadersToBrowserClients() async throws {
    let fileManager = FileManager.default
    let temporaryRoot = fileManager.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    let authDatabaseURL = temporaryRoot
        .appendingPathComponent("Auth", isDirectory: true)
        .appendingPathComponent("bridge-auth.sqlite", isDirectory: false)
    defer {
        try? fileManager.removeItem(at: temporaryRoot)
    }

    let port = try availableLoopbackPort()
    let application = BearBridgeHTTPApplication(
        configuration: .init(
            host: "127.0.0.1",
            port: port,
            authMode: .oauth,
            authDatabaseURL: authDatabaseURL
        ),
        serverFactory: {
            await makeToolsListTestingServer()
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

    let response = try await sendHTTPRequest(
        port: port,
        path: "/mcp",
        method: "POST",
        headers: [
            "Origin": "https://chatgpt.com",
            "Content-Type": "application/json",
            "Accept": "application/json",
        ],
        body: try makeInitializeRequestBody(requestID: "oauth-browser-required")
    )

    #expect(response.statusCode == 401)
    #expect(response.httpResponse.value(forHTTPHeaderField: "Access-Control-Allow-Origin") == "https://chatgpt.com")
    #expect(response.httpResponse.value(forHTTPHeaderField: "Access-Control-Expose-Headers")?.contains("WWW-Authenticate") == true)
    #expect(response.httpResponse.value(forHTTPHeaderField: HTTPHeaderName.wwwAuthenticate)?.contains("resource_metadata=") == true)

    await application.stop()
    try await startTask.value
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
    let initializeEnvelope = try #require(
        BearBridgeHTTPApplication.decodeInitializeEnvelope(from: request)
    )

    let response = try await BearBridgeHTTPApplication.makeInitializeResponse(
        id: initializeEnvelope.id,
        clientRequestedVersion: initializeEnvelope.protocolVersion,
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
    let initializeEnvelope = try #require(BearBridgeHTTPApplication.decodeInitializeEnvelope(from: httpRequest))

    let response = try await BearBridgeHTTPApplication.makeInitializeResponse(
        id: initializeEnvelope.id,
        clientRequestedVersion: initializeEnvelope.protocolVersion,
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

@Test
func bridgeToolsListSucceedsAfterInitializeOverLocalHTTP() async throws {
    let port = try availableLoopbackPort()
    let application = BearBridgeHTTPApplication(
        configuration: .init(
            host: "127.0.0.1",
            port: port
        ),
        serverFactory: {
            await makeToolsListTestingServer()
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

    let initializeData = try await sendInitializeRequest(port: port, requestID: "tools-list-init")
    let initializeResponse = try JSONDecoder().decode(Response<Initialize>.self, from: initializeData)
    let initializeResult = try initializeResponse.result.get()
    let toolsListData = try await sendToolsListRequest(
        port: port,
        requestID: "tools-list-request",
        protocolVersion: initializeResult.protocolVersion
    )

    guard let object = try JSONSerialization.jsonObject(with: toolsListData) as? [String: Any],
          object["jsonrpc"] as? String == "2.0",
          let result = object["result"] as? [String: Any],
          result["tools"] as? [Any] != nil
    else {
        Issue.record("Expected a valid JSON-RPC tools/list response.")
        throw CancellationError()
    }

    await application.stop()
    try await startTask.value
}

@Test
func bridgeReturnsNotFoundForOAuthRoutesWhenBridgeIsOpen() async throws {
    let port = try availableLoopbackPort()
    let application = BearBridgeHTTPApplication(
        configuration: .init(
            host: "127.0.0.1",
            port: port
        ),
        serverFactory: {
            await makeToolsListTestingServer()
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

    let response = try await sendHTTPRequest(
        port: port,
        path: "/.well-known/oauth-authorization-server"
    )

    #expect(response.statusCode == 404)

    await application.stop()
    try await startTask.value
}

@Test
func bridgeReturnsNotFoundForUnknownRoutes() async throws {
    let port = try availableLoopbackPort()
    let application = BearBridgeHTTPApplication(
        configuration: .init(
            host: "127.0.0.1",
            port: port
        ),
        serverFactory: {
            await makeToolsListTestingServer()
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

    let response = try await sendHTTPRequest(
        port: port,
        path: "/not-found"
    )

    #expect(response.statusCode == 404)

    await application.stop()
    try await startTask.value
}

@Test
func bridgeRequiresOAuthAcrossEntireMCPSurfaceWhenEnabled() async throws {
    let fileManager = FileManager.default
    let temporaryRoot = fileManager.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    let authDatabaseURL = temporaryRoot
        .appendingPathComponent("Auth", isDirectory: true)
        .appendingPathComponent("bridge-auth.sqlite", isDirectory: false)
    defer {
        try? fileManager.removeItem(at: temporaryRoot)
    }

    let port = try availableLoopbackPort()
    let application = BearBridgeHTTPApplication(
        configuration: .init(
            host: "127.0.0.1",
            port: port,
            authMode: .oauth,
            authDatabaseURL: authDatabaseURL
        ),
        serverFactory: {
            await makeToolsListTestingServer()
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

    let response = try await sendHTTPRequest(
        port: port,
        path: "/mcp",
        method: "POST",
        headers: [
            "Content-Type": "application/json",
            "Accept": "application/json",
        ],
        body: try makeInitializeRequestBody(requestID: "oauth-required")
    )

    #expect(response.statusCode == 401)
    let challenge = response.httpResponse.value(forHTTPHeaderField: HTTPHeaderName.wwwAuthenticate)
    #expect(challenge?.contains("Bearer") == true)
    #expect(challenge?.contains("resource_metadata=") == true)

    await application.stop()
    try await startTask.value
}

@Test
func bridgeRejectsInvalidBearerTokenOnProtectedMCPSurface() async throws {
    let fileManager = FileManager.default
    let temporaryRoot = fileManager.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    let authDatabaseURL = temporaryRoot
        .appendingPathComponent("Auth", isDirectory: true)
        .appendingPathComponent("bridge-auth.sqlite", isDirectory: false)
    defer {
        try? fileManager.removeItem(at: temporaryRoot)
    }

    let port = try availableLoopbackPort()
    let application = BearBridgeHTTPApplication(
        configuration: .init(
            host: "127.0.0.1",
            port: port,
            authMode: .oauth,
            authDatabaseURL: authDatabaseURL
        ),
        serverFactory: {
            await makeToolsListTestingServer()
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

    let response = try await sendHTTPRequest(
        port: port,
        path: "/mcp",
        method: "POST",
        headers: [
            "Authorization": "Bearer invalid-token",
            "Content-Type": "application/json",
            "Accept": "application/json",
        ],
        body: try makeInitializeRequestBody(requestID: "oauth-invalid-token")
    )

    #expect(response.statusCode == 401)
    let challenge = response.httpResponse.value(forHTTPHeaderField: HTTPHeaderName.wwwAuthenticate)
    #expect(challenge?.contains(#"error="invalid_token""#) == true)
    #expect(challenge?.contains("resource_metadata=") == true)

    await application.stop()
    try await startTask.value
}

@Test
func bridgeServesOAuthMetadataWhenEnabled() async throws {
    let fileManager = FileManager.default
    let temporaryRoot = fileManager.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    let authDatabaseURL = temporaryRoot
        .appendingPathComponent("Auth", isDirectory: true)
        .appendingPathComponent("bridge-auth.sqlite", isDirectory: false)
    defer {
        try? fileManager.removeItem(at: temporaryRoot)
    }

    let port = try availableLoopbackPort()
    let application = BearBridgeHTTPApplication(
        configuration: .init(
            host: "127.0.0.1",
            port: port,
            authMode: .oauth,
            authDatabaseURL: authDatabaseURL
        ),
        serverFactory: {
            await makeToolsListTestingServer()
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

    let protectedResourceResponse = try await sendHTTPRequest(
        port: port,
        path: "/.well-known/oauth-protected-resource/mcp"
    )
    #expect(protectedResourceResponse.statusCode == 200)
    let protectedResourceObject = try #require(
        try JSONSerialization.jsonObject(with: protectedResourceResponse.data) as? [String: Any]
    )
    #expect(protectedResourceObject["resource"] as? String == "http://127.0.0.1:\(port)/mcp")
    let authorizationServers = try #require(protectedResourceObject["authorization_servers"] as? [String])
    #expect(authorizationServers == ["http://127.0.0.1:\(port)"])

    let authorizationServerResponse = try await sendHTTPRequest(
        port: port,
        path: "/.well-known/oauth-authorization-server?resource=http://127.0.0.1:\(port)/mcp"
    )
    #expect(authorizationServerResponse.statusCode == 200)
    let authorizationServerObject = try #require(
        try JSONSerialization.jsonObject(with: authorizationServerResponse.data) as? [String: Any]
    )
    #expect(authorizationServerObject["issuer"] as? String == "http://127.0.0.1:\(port)")
    #expect(authorizationServerObject["authorization_endpoint"] as? String == "http://127.0.0.1:\(port)/oauth/authorize")
    #expect(authorizationServerObject["token_endpoint"] as? String == "http://127.0.0.1:\(port)/oauth/token")
    #expect(authorizationServerObject["registration_endpoint"] as? String == "http://127.0.0.1:\(port)/oauth/register")

    await application.stop()
    try await startTask.value
}

@Test
func bridgeDynamicClientRegistrationWorksForPublicClient() async throws {
    let fileManager = FileManager.default
    let temporaryRoot = fileManager.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    let authDatabaseURL = temporaryRoot
        .appendingPathComponent("Auth", isDirectory: true)
        .appendingPathComponent("bridge-auth.sqlite", isDirectory: false)
    defer {
        try? fileManager.removeItem(at: temporaryRoot)
    }

    let port = try availableLoopbackPort()
    let application = BearBridgeHTTPApplication(
        configuration: .init(
            host: "127.0.0.1",
            port: port,
            authMode: .oauth,
            authDatabaseURL: authDatabaseURL
        ),
        serverFactory: {
            await makeToolsListTestingServer()
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

    let requestBody = try JSONSerialization.data(
        withJSONObject: [
            "redirect_uris": ["https://example.com/callback"],
            "client_name": "Bridge HTTP Test Client",
            "grant_types": ["authorization_code", "refresh_token"],
            "response_types": ["code"],
            "token_endpoint_auth_method": "none",
        ]
    )
    let response = try await sendHTTPRequest(
        port: port,
        path: "/oauth/register",
        method: "POST",
        headers: [
            "Content-Type": "application/json",
            "Accept": "application/json",
        ],
        body: requestBody
    )

    #expect(response.statusCode == 201)
    let object = try #require(try JSONSerialization.jsonObject(with: response.data) as? [String: Any])
    #expect((object["client_id"] as? String)?.isEmpty == false)
    #expect(object["client_name"] as? String == "Bridge HTTP Test Client")
    #expect(object["token_endpoint_auth_method"] as? String == "none")
    let redirectURIs = try #require(object["redirect_uris"] as? [String])
    #expect(redirectURIs == ["https://example.com/callback"])

    await application.stop()
    try await startTask.value
}

@Test
func bridgeAuthorizationCodeAndRefreshFlowWorksEndToEnd() async throws {
    let fileManager = FileManager.default
    let temporaryRoot = fileManager.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    let authDatabaseURL = temporaryRoot
        .appendingPathComponent("Auth", isDirectory: true)
        .appendingPathComponent("bridge-auth.sqlite", isDirectory: false)
    defer {
        try? fileManager.removeItem(at: temporaryRoot)
    }

    let port = try availableLoopbackPort()
    let application = BearBridgeHTTPApplication(
        configuration: .init(
            host: "127.0.0.1",
            port: port,
            authMode: .oauth,
            authDatabaseURL: authDatabaseURL
        ),
        serverFactory: {
            await makeToolsListTestingServer()
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

    let registrationBody = try JSONSerialization.data(
        withJSONObject: [
            "redirect_uris": ["https://example.com/callback"],
            "client_name": "OAuth Flow Test Client",
            "token_endpoint_auth_method": "none",
        ]
    )
    let registrationResponse = try await sendHTTPRequest(
        port: port,
        path: "/oauth/register",
        method: "POST",
        headers: [
            "Content-Type": "application/json",
            "Accept": "application/json",
        ],
        body: registrationBody
    )
    let registrationObject = try #require(
        try JSONSerialization.jsonObject(with: registrationResponse.data) as? [String: Any]
    )
    let clientID = try #require(registrationObject["client_id"] as? String)
    let verifier = "test-verifier-abcdefghijklmnopqrstuvwxyz-0123456789"
    let challenge = try PKCE.makeChallenge(from: verifier)
    let authorizationResponse = try await sendHTTPRequest(
        port: port,
        path: "/oauth/authorize?response_type=code&client_id=\(clientID)&redirect_uri=https://example.com/callback&state=state-123&resource=http://127.0.0.1:\(port)/mcp&scope=mcp&code_challenge=\(challenge)&code_challenge_method=S256",
        followRedirects: false
    )

    #expect(authorizationResponse.statusCode == 200)
    let authorizationHTML = String(decoding: authorizationResponse.data, as: UTF8.self)
    #expect(authorizationHTML.contains("Approve access to your local Ursus bridge"))
    let pendingRequestID = try #require(hiddenInputValue(named: "request_id", in: authorizationHTML))
    let decisionToken = try #require(hiddenInputValue(named: "decision_token", in: authorizationHTML))

    let store = BearBridgeAuthStore(databaseURL: authDatabaseURL)
    let pendingRequest = try await store.pendingAuthorizationRequest(id: pendingRequestID)
    #expect(pendingRequest?.clientID == clientID)
    #expect(pendingRequest?.requestedScope == "mcp")
    #expect(pendingRequest?.status == .pending)

    let decisionResponse = try await sendHTTPRequest(
        port: port,
        path: "/oauth/decision",
        method: "POST",
        headers: [
            "Content-Type": "application/x-www-form-urlencoded",
        ],
        body: Data(
            "request_id=\(urlEncodeFormValue(pendingRequestID))&decision=approve&decision_token=\(urlEncodeFormValue(decisionToken))".utf8
        ),
        followRedirects: false
    )

    #expect(decisionResponse.statusCode == 200)
    let decisionHTML = String(decoding: decisionResponse.data, as: UTF8.self)
    #expect(decisionHTML.contains("Authorization Approved"))
    #expect(!decisionHTML.contains("Open Client Again"))
    #expect(!decisionHTML.contains("Close This Window"))
    let location = try #require(hiddenInputValue(named: "callback_url", in: decisionHTML))
    let redirectURL = try #require(URL(string: location))
    let redirectComponents = try #require(URLComponents(url: redirectURL, resolvingAgainstBaseURL: false))
    let code = try #require(redirectComponents.queryItems?.first(where: { $0.name == "code" })?.value)
    #expect(redirectComponents.queryItems?.first(where: { $0.name == "state" })?.value == "state-123")

    let tokenExchangeResponse = try await sendHTTPRequest(
        port: port,
        path: "/oauth/token",
        method: "POST",
        headers: [
            "Content-Type": "application/x-www-form-urlencoded",
            "Accept": "application/json",
        ],
        body: Data(
            "grant_type=authorization_code&client_id=\(clientID)&code=\(code)&redirect_uri=https%3A%2F%2Fexample.com%2Fcallback&code_verifier=\(verifier)&resource=http%3A%2F%2F127.0.0.1%3A\(port)%2Fmcp".utf8
        )
    )

    #expect(tokenExchangeResponse.statusCode == 200)
    let tokenJSONObject = try JSONSerialization.jsonObject(with: tokenExchangeResponse.data)
    let tokenObject = try #require(tokenJSONObject as? [String: Any])
    let accessToken = try #require(tokenObject["access_token"] as? String)
    let refreshToken = try #require(tokenObject["refresh_token"] as? String)
    #expect(!accessToken.isEmpty)
    #expect(!refreshToken.isEmpty)
    #expect(tokenObject["token_type"] as? String == "Bearer")
    #expect(tokenObject["scope"] as? String == "mcp")

    let refreshResponse = try await sendHTTPRequest(
        port: port,
        path: "/oauth/token",
        method: "POST",
        headers: [
            "Content-Type": "application/x-www-form-urlencoded",
            "Accept": "application/json",
        ],
        body: Data(
            "grant_type=refresh_token&client_id=\(clientID)&refresh_token=\(refreshToken)&resource=http%3A%2F%2F127.0.0.1%3A\(port)%2Fmcp".utf8
        )
    )

    #expect(refreshResponse.statusCode == 200)
    let refreshJSONObject = try JSONSerialization.jsonObject(with: refreshResponse.data)
    let refreshObject = try #require(refreshJSONObject as? [String: Any])
    let rotatedRefreshToken = try #require(refreshObject["refresh_token"] as? String)
    #expect(rotatedRefreshToken != refreshToken)
    #expect((refreshObject["access_token"] as? String)?.isEmpty == false)
    #expect(refreshObject["scope"] as? String == "mcp")

    let completedRequest = try await store.pendingAuthorizationRequest(id: pendingRequestID)
    #expect(completedRequest?.status == .completed)

    await application.stop()
    try await startTask.value
}

@Test
func bridgeAllowsAuthenticatedMCPRequestsAndRepeatedInitializeWhenOAuthEnabled() async throws {
    let fileManager = FileManager.default
    let temporaryRoot = fileManager.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    let authDatabaseURL = temporaryRoot
        .appendingPathComponent("Auth", isDirectory: true)
        .appendingPathComponent("bridge-auth.sqlite", isDirectory: false)
    defer {
        try? fileManager.removeItem(at: temporaryRoot)
    }

    let port = try availableLoopbackPort()
    let application = BearBridgeHTTPApplication(
        configuration: .init(
            host: "127.0.0.1",
            port: port,
            authMode: .oauth,
            authDatabaseURL: authDatabaseURL
        ),
        serverFactory: {
            await makeToolsListTestingServer()
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

    let oauthFlow = try await performBridgeOAuthAuthorizationCodeFlow(
        port: port,
        clientName: "Authenticated MCP Test Client"
    )

    let initializeData = try await sendInitializeRequest(
        port: port,
        requestID: "oauth-tools-list-init",
        bearerToken: oauthFlow.accessToken
    )
    let initializeResponse = try JSONDecoder().decode(Response<Initialize>.self, from: initializeData)
    let initializeResult = try initializeResponse.result.get()

    let toolsListData = try await sendToolsListRequest(
        port: port,
        requestID: "oauth-tools-list-request",
        protocolVersion: initializeResult.protocolVersion,
        bearerToken: oauthFlow.accessToken
    )

    guard let object = try JSONSerialization.jsonObject(with: toolsListData) as? [String: Any],
          object["jsonrpc"] as? String == "2.0",
          let result = object["result"] as? [String: Any],
          result["tools"] as? [Any] != nil
    else {
        Issue.record("Expected a valid authenticated JSON-RPC tools/list response.")
        throw CancellationError()
    }

    let repeatedInitializeData = try await sendInitializeRequest(
        port: port,
        requestID: "oauth-repeat-init",
        bearerToken: oauthFlow.accessToken
    )
    let repeatedInitializeResponse = try JSONDecoder().decode(
        Response<Initialize>.self,
        from: repeatedInitializeData
    )
    let repeatedInitializeResult = try repeatedInitializeResponse.result.get()
    #expect(repeatedInitializeResponse.id == .string("oauth-repeat-init"))
    #expect(repeatedInitializeResult.protocolVersion == initializeResult.protocolVersion)

    await application.stop()
    try await startTask.value
}

@Test
func bridgeAuthorizationStatusReturnsDeniedRedirectAfterLocalDenial() async throws {
    let fileManager = FileManager.default
    let temporaryRoot = fileManager.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    let authDatabaseURL = temporaryRoot
        .appendingPathComponent("Auth", isDirectory: true)
        .appendingPathComponent("bridge-auth.sqlite", isDirectory: false)
    defer {
        try? fileManager.removeItem(at: temporaryRoot)
    }

    let port = try availableLoopbackPort()
    let application = BearBridgeHTTPApplication(
        configuration: .init(
            host: "127.0.0.1",
            port: port,
            authMode: .oauth,
            authDatabaseURL: authDatabaseURL
        ),
        serverFactory: {
            await makeToolsListTestingServer()
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

    let registrationBody = try JSONSerialization.data(
        withJSONObject: [
            "redirect_uris": ["https://example.com/callback"],
            "client_name": "Denied OAuth Flow Test Client",
            "token_endpoint_auth_method": "none",
        ]
    )
    let registrationResponse = try await sendHTTPRequest(
        port: port,
        path: "/oauth/register",
        method: "POST",
        headers: [
            "Content-Type": "application/json",
            "Accept": "application/json",
        ],
        body: registrationBody
    )
    let registrationObject = try #require(
        try JSONSerialization.jsonObject(with: registrationResponse.data) as? [String: Any]
    )
    let clientID = try #require(registrationObject["client_id"] as? String)
    let challenge = try PKCE.makeChallenge(from: "denied-verifier-abcdefghijklmnopqrstuvwxyz")

    let authorizationResponse = try await sendHTTPRequest(
        port: port,
        path: "/oauth/authorize?response_type=code&client_id=\(clientID)&redirect_uri=https://example.com/callback&state=denied-state&resource=http://127.0.0.1:\(port)/mcp&scope=mcp&code_challenge=\(challenge)&code_challenge_method=S256",
        followRedirects: false
    )

    #expect(authorizationResponse.statusCode == 200)
    let authorizationHTML = String(decoding: authorizationResponse.data, as: UTF8.self)
    let pendingRequestID = try #require(hiddenInputValue(named: "request_id", in: authorizationHTML))
    let decisionToken = try #require(hiddenInputValue(named: "decision_token", in: authorizationHTML))

    let store = BearBridgeAuthStore(databaseURL: authDatabaseURL)
    let pendingRequest = try await store.pendingAuthorizationRequest(id: pendingRequestID)
    #expect(pendingRequest?.status == .pending)

    let decisionResponse = try await sendHTTPRequest(
        port: port,
        path: "/oauth/decision",
        method: "POST",
        headers: [
            "Content-Type": "application/x-www-form-urlencoded",
        ],
        body: Data(
            "request_id=\(urlEncodeFormValue(pendingRequestID))&decision=deny&decision_token=\(urlEncodeFormValue(decisionToken))".utf8
        ),
        followRedirects: false
    )

    #expect(decisionResponse.statusCode == 200)
    let decisionHTML = String(decoding: decisionResponse.data, as: UTF8.self)
    #expect(decisionHTML.contains("Authorization Denied"))
    #expect(!decisionHTML.contains("Open Client Again"))
    #expect(!decisionHTML.contains("Close This Window"))
    let location = try #require(hiddenInputValue(named: "callback_url", in: decisionHTML))
    #expect(location.contains("error=access_denied"))
    #expect(location.contains("state=denied-state"))

    let deniedRequest = try await store.pendingAuthorizationRequest(id: pendingRequestID)
    #expect(deniedRequest?.status == .denied)

    await application.stop()
    try await startTask.value
}

@Test
func bridgeRememberedGrantSkipsLocalPromptOnRepeatAuthorization() async throws {
    let fileManager = FileManager.default
    let temporaryRoot = fileManager.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    let authDatabaseURL = temporaryRoot
        .appendingPathComponent("Auth", isDirectory: true)
        .appendingPathComponent("bridge-auth.sqlite", isDirectory: false)
    defer {
        try? fileManager.removeItem(at: temporaryRoot)
    }

    let port = try availableLoopbackPort()
    let application = BearBridgeHTTPApplication(
        configuration: .init(
            host: "127.0.0.1",
            port: port,
            authMode: .oauth,
            authDatabaseURL: authDatabaseURL
        ),
        serverFactory: {
            await makeToolsListTestingServer()
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

    let store = BearBridgeAuthStore(databaseURL: authDatabaseURL)
    let client = try await store.registerClient(
        BearBridgeAuthClientDraft(
            displayName: "Remembered Client",
            redirectURIs: ["https://example.com/callback"],
            metadataJSON: #"{"client_name":"Remembered Client"}"#
        )
    )
    _ = try await store.createGrant(
        BearBridgeAuthGrantDraft(
            clientID: client.id,
            scope: "mcp",
            resource: "http://127.0.0.1:\(port)/mcp",
            metadataJSON: "{\"resource\":\"http://127.0.0.1:\(port)/mcp\"}"
        )
    )

    let verifier = "remembered-verifier-abcdefghijklmnopqrstuvwxyz"
    let challenge = try PKCE.makeChallenge(from: verifier)
    let authorizationResponse = try await sendHTTPRequest(
        port: port,
        path: "/oauth/authorize?response_type=code&client_id=\(client.id)&redirect_uri=https://example.com/callback&state=repeat-state&resource=http://127.0.0.1:\(port)/mcp&scope=mcp&code_challenge=\(challenge)&code_challenge_method=S256",
        followRedirects: false
    )

    #expect(authorizationResponse.statusCode == 302)
    let location = try #require(authorizationResponse.httpResponse.value(forHTTPHeaderField: "Location"))
    #expect(location.contains("code="))
    #expect(location.contains("state=repeat-state"))

    let reviewSnapshot = try await store.reviewSnapshot(prepareIfMissing: false)
    #expect(reviewSnapshot.pendingRequests.isEmpty)
    #expect(reviewSnapshot.activeGrants.count == 1)

    await application.stop()
    try await startTask.value
}

@Test
func bridgeValidationPipelineAllowsForwardedHostHeader() async throws {
    let (server, transport) = try await BearBridgeHTTPApplication.makeStartedRuntime(
        serverFactory: {
            await makeToolsListTestingServer()
        },
        logger: Logger(label: "test.ursus.bridge")
    )
    defer {
        Task {
            await transport.disconnect()
            await server.stop()
        }
    }

    let initializeRequest = HTTPRequest(
        method: "POST",
        headers: [
            "Host": "mcp.afadingthought.com",
            "Content-Type": "application/json",
            "Accept": "application/json",
        ],
        body: try makeInitializeRequestBody(requestID: "forwarded-host-init")
    )
    let initializeResponse = await transport.handleRequest(initializeRequest)
    #expect(initializeResponse.statusCode == 200)

    let toolsListRequest = HTTPRequest(
        method: "POST",
        headers: [
            "Host": "mcp.afadingthought.com",
            "Content-Type": "application/json",
            "Accept": "application/json",
            HTTPHeaderName.protocolVersion: Version.latest,
        ],
        body: try makeToolsListRequestBody(requestID: "forwarded-host-tools")
    )
    let toolsListResponse = await transport.handleRequest(toolsListRequest)

    #expect(toolsListResponse.statusCode == 200)
    let responseBody = try #require(toolsListResponse.bodyData)
    guard let object = try JSONSerialization.jsonObject(with: responseBody) as? [String: Any],
          object["jsonrpc"] as? String == "2.0",
          let result = object["result"] as? [String: Any],
          result["tools"] as? [Any] != nil
    else {
        Issue.record("Expected a valid JSON-RPC tools/list response for a forwarded Host header.")
        throw CancellationError()
    }
}

@Test
func bridgeWrapsInitializeResponseAsEventStreamWhenRequested() async throws {
    let port = try availableLoopbackPort()
    let application = BearBridgeHTTPApplication(
        configuration: .init(
            host: "127.0.0.1",
            port: port
        ),
        serverFactory: {
            await makeToolsListTestingServer()
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

    let responseText = try await sendStreamingInitializeRequest(port: port, requestID: "streaming-init")
    #expect(responseText.contains("event: message"))
    #expect(responseText.contains("\"jsonrpc\":\"2.0\""))
    #expect(responseText.contains("\"id\":\"streaming-init\""))

    await application.stop()
    try await startTask.value
}

@Test
func bridgeAcceptsInitializeWithExperimentalCapabilityObjects() async throws {
    let port = try availableLoopbackPort()
    let application = BearBridgeHTTPApplication(
        configuration: .init(
            host: "127.0.0.1",
            port: port
        ),
        serverFactory: {
            await makeToolsListTestingServer()
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

    let responseText = try await sendStreamingInitializeRequest(
        port: port,
        requestID: 1,
        body: makeInitializeRequestBodyWithExperimentalCapabilities(requestID: 1)
    )
    #expect(responseText.contains("event: message"))
    #expect(responseText.contains("\"jsonrpc\":\"2.0\""))
    #expect(responseText.contains("\"id\":1"))
    #expect(responseText.contains("\"result\""))

    let toolsListData = try await sendToolsListRequest(
        port: port,
        requestID: "post-experimental-init-tools-list",
        protocolVersion: Version.latest
    )
    guard let object = try JSONSerialization.jsonObject(with: toolsListData) as? [String: Any],
          object["jsonrpc"] as? String == "2.0",
          let result = object["result"] as? [String: Any],
          result["tools"] as? [Any] != nil
    else {
        Issue.record("Expected tools/list to remain available after tolerant initialize handling.")
        throw CancellationError()
    }

    await application.stop()
    try await startTask.value
}

@Test
func bridgeWrapsRepeatedInitializeCompatibilityResponseAsEventStreamWhenRequested() async throws {
    let port = try availableLoopbackPort()
    let application = BearBridgeHTTPApplication(
        configuration: .init(
            host: "127.0.0.1",
            port: port
        ),
        serverFactory: {
            await makeToolsListTestingServer()
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

    _ = try await sendInitializeRequest(port: port, requestID: "priming-init")
    let responseText = try await sendStreamingInitializeRequest(
        port: port,
        requestID: "streaming-repeat-init"
    )

    #expect(responseText.contains("event: message"))
    #expect(responseText.contains("\"jsonrpc\":\"2.0\""))
    #expect(responseText.contains("\"id\":\"streaming-repeat-init\""))

    await application.stop()
    try await startTask.value
}

@Test
func bridgeWrapsToolsListResponseAsEventStreamWhenRequested() async throws {
    let port = try availableLoopbackPort()
    let application = BearBridgeHTTPApplication(
        configuration: .init(
            host: "127.0.0.1",
            port: port
        ),
        serverFactory: {
            await makeToolsListTestingServer()
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

    let initializeData = try await sendInitializeRequest(port: port, requestID: "streaming-tools-list-init")
    let initializeResponse = try JSONDecoder().decode(Response<Initialize>.self, from: initializeData)
    let initializeResult = try initializeResponse.result.get()
    let responseText = try await sendStreamingToolsListRequest(
        port: port,
        requestID: "streaming-tools-list",
        protocolVersion: initializeResult.protocolVersion
    )

    #expect(responseText.contains("event: message"))
    #expect(responseText.contains("\"jsonrpc\":\"2.0\""))
    #expect(responseText.contains("\"id\":\"streaming-tools-list\""))
    #expect(responseText.contains("\"tools\""))

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

private func sendInitializeRequest(
    port: Int,
    requestID: String,
    bearerToken: String? = nil
) async throws -> Data {
    var headers = [
        "Content-Type": "application/json",
        "Accept": "application/json",
    ]
    if let bearerToken {
        headers["Authorization"] = "Bearer \(bearerToken)"
    }

    let response = try await sendHTTPRequest(
        port: port,
        path: "/mcp",
        method: "POST",
        headers: headers,
        body: try makeInitializeRequestBody(requestID: requestID)
    )
    #expect(response.statusCode == 200)
    return response.data
}

private func sendToolsListRequest(
    port: Int,
    requestID: String,
    protocolVersion: String,
    bearerToken: String? = nil
) async throws -> Data {
    var headers = [
        "Content-Type": "application/json",
        "Accept": "application/json",
        HTTPHeaderName.protocolVersion: protocolVersion,
    ]
    if let bearerToken {
        headers["Authorization"] = "Bearer \(bearerToken)"
    }

    let response = try await sendHTTPRequest(
        port: port,
        path: "/mcp",
        method: "POST",
        headers: headers,
        body: try makeToolsListRequestBody(requestID: requestID)
    )
    #expect(response.statusCode == 200)
    return response.data
}

private func sendStreamingInitializeRequest(port: Int, requestID: String) async throws -> String {
    try await sendStreamingInitializeRequest(
        port: port,
        requestID: requestID,
        body: makeInitializeRequestBody(requestID: requestID)
    )
}

private func sendStreamingInitializeRequest<T: LosslessStringConvertible>(
    port: Int,
    requestID: T,
    body: Data
) async throws -> String {
    let response = try await sendHTTPRequest(
        port: port,
        path: "/mcp",
        method: "POST",
        headers: [
            "Content-Type": "application/json",
            "Accept": "application/json, text/event-stream",
        ],
        body: body
    )
    #expect(response.statusCode == 200)
    #expect(response.httpResponse.value(forHTTPHeaderField: "Content-Type") == "text/event-stream")
    return String(decoding: response.data, as: UTF8.self)
}

private func sendStreamingToolsListRequest(
    port: Int,
    requestID: String,
    protocolVersion: String
) async throws -> String {
    let response = try await sendHTTPRequest(
        port: port,
        path: "/mcp",
        method: "POST",
        headers: [
            "Content-Type": "application/json",
            "Accept": "application/json, text/event-stream",
            HTTPHeaderName.protocolVersion: protocolVersion,
        ],
        body: try makeToolsListRequestBody(requestID: requestID)
    )
    #expect(response.statusCode == 200)
    #expect(response.httpResponse.value(forHTTPHeaderField: "Content-Type") == "text/event-stream")
    return String(decoding: response.data, as: UTF8.self)
}

private struct HTTPTestResponse {
    let data: Data
    let httpResponse: HTTPURLResponse

    var statusCode: Int {
        httpResponse.statusCode
    }
}

private struct OAuthFlowResult {
    let clientID: String
    let accessToken: String
    let refreshToken: String
}

private func sendHTTPRequest(
    port: Int,
    path: String,
    method: String = "GET",
    headers: [String: String] = [:],
    body: Data? = nil,
    followRedirects: Bool = true
) async throws -> HTTPTestResponse {
    let url = try #require(URL(string: "http://127.0.0.1:\(port)\(path)"))
    var request = URLRequest(url: url)
    request.httpMethod = method
    request.timeoutInterval = 2
    for (name, value) in headers {
        request.setValue(value, forHTTPHeaderField: name)
    }
    request.httpBody = body

    let session: URLSession
    if followRedirects {
        session = .shared
    } else {
        session = URLSession(
            configuration: .ephemeral,
            delegate: NoRedirectURLSessionDelegate(),
            delegateQueue: nil
        )
    }
    defer {
        if !followRedirects {
            session.invalidateAndCancel()
        }
    }

    let (data, response) = try await session.data(for: request)
    let httpResponse = try #require(response as? HTTPURLResponse)
    return HTTPTestResponse(data: data, httpResponse: httpResponse)
}

private final class NoRedirectURLSessionDelegate: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    func urlSession(
        _: URLSession,
        task _: URLSessionTask,
        willPerformHTTPRedirection _: HTTPURLResponse,
        newRequest _: URLRequest
    ) async -> URLRequest? {
        nil
    }
}

private func makeInitializeRequestBody(requestID: String) throws -> Data {
    try JSONSerialization.data(
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
}

private func makeInitializeRequestBodyWithExperimentalCapabilities(requestID: Int) throws -> Data {
    try JSONSerialization.data(
        withJSONObject: [
            "jsonrpc": "2.0",
            "id": requestID,
            "method": "initialize",
            "params": [
                "protocolVersion": Version.latest,
                "capabilities": [
                    "experimental": [
                        "openai": [
                            "connectorImport": true,
                            "variant": "chatgpt",
                        ],
                    ],
                ],
                "clientInfo": [
                    "name": "openai-mcp",
                    "version": "1.0.0",
                ],
            ],
        ]
    )
}

private func makeToolsListRequestBody(requestID: String) throws -> Data {
    try JSONSerialization.data(
        withJSONObject: [
            "jsonrpc": "2.0",
            "id": requestID,
            "method": "tools/list",
            "params": [:],
        ]
    )
}

private func hiddenInputValue(named name: String, in html: String) -> String? {
    let pattern = #"name="\#(NSRegularExpression.escapedPattern(for: name))"\s+value="([^"]+)""#
    guard let expression = try? NSRegularExpression(pattern: pattern) else {
        return nil
    }
    let range = NSRange(html.startIndex..<html.endIndex, in: html)
    guard let match = expression.firstMatch(in: html, range: range),
          let valueRange = Range(match.range(at: 1), in: html)
    else {
        return nil
    }
    return String(html[valueRange])
        .replacingOccurrences(of: "&amp;", with: "&")
        .replacingOccurrences(of: "&quot;", with: "\"")
        .replacingOccurrences(of: "&#39;", with: "'")
}

private func urlEncodeFormValue(_ value: String) -> String {
    var allowed = CharacterSet.urlQueryAllowed
    allowed.remove(charactersIn: "&+=?")
    return value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value
}

private func performBridgeOAuthAuthorizationCodeFlow(
    port: Int,
    clientName: String
) async throws -> OAuthFlowResult {
    let registrationBody = try JSONSerialization.data(
        withJSONObject: [
            "redirect_uris": ["https://example.com/callback"],
            "client_name": clientName,
            "token_endpoint_auth_method": "none",
        ]
    )
    let registrationResponse = try await sendHTTPRequest(
        port: port,
        path: "/oauth/register",
        method: "POST",
        headers: [
            "Content-Type": "application/json",
            "Accept": "application/json",
        ],
        body: registrationBody
    )
    let registrationObject = try #require(
        try JSONSerialization.jsonObject(with: registrationResponse.data) as? [String: Any]
    )
    let clientID = try #require(registrationObject["client_id"] as? String)

    let verifier = "phase5-verifier-abcdefghijklmnopqrstuvwxyz-0123456789"
    let challenge = try PKCE.makeChallenge(from: verifier)
    let authorizationResponse = try await sendHTTPRequest(
        port: port,
        path: "/oauth/authorize?response_type=code&client_id=\(clientID)&redirect_uri=https://example.com/callback&state=phase5-state&resource=http://127.0.0.1:\(port)/mcp&scope=mcp&code_challenge=\(challenge)&code_challenge_method=S256",
        followRedirects: false
    )

    #expect(authorizationResponse.statusCode == 200)
    let authorizationHTML = String(decoding: authorizationResponse.data, as: UTF8.self)
    let pendingRequestID = try #require(hiddenInputValue(named: "request_id", in: authorizationHTML))
    let decisionToken = try #require(hiddenInputValue(named: "decision_token", in: authorizationHTML))

    let decisionResponse = try await sendHTTPRequest(
        port: port,
        path: "/oauth/decision",
        method: "POST",
        headers: [
            "Content-Type": "application/x-www-form-urlencoded",
        ],
        body: Data(
            "request_id=\(urlEncodeFormValue(pendingRequestID))&decision=approve&decision_token=\(urlEncodeFormValue(decisionToken))".utf8
        ),
        followRedirects: false
    )
    #expect(decisionResponse.statusCode == 200)
    let decisionHTML = String(decoding: decisionResponse.data, as: UTF8.self)
    #expect(decisionHTML.contains("Authorization Approved"))
    #expect(!decisionHTML.contains("Open Client Again"))
    #expect(!decisionHTML.contains("Close This Window"))
    let location = try #require(hiddenInputValue(named: "callback_url", in: decisionHTML))
    let redirectURL = try #require(URL(string: location))
    let redirectComponents = try #require(
        URLComponents(url: redirectURL, resolvingAgainstBaseURL: false)
    )
    let code = try #require(
        redirectComponents.queryItems?.first(where: { $0.name == "code" })?.value
    )

    let tokenExchangeResponse = try await sendHTTPRequest(
        port: port,
        path: "/oauth/token",
        method: "POST",
        headers: [
            "Content-Type": "application/x-www-form-urlencoded",
            "Accept": "application/json",
        ],
        body: Data(
            "grant_type=authorization_code&client_id=\(clientID)&code=\(code)&redirect_uri=https%3A%2F%2Fexample.com%2Fcallback&code_verifier=\(verifier)&resource=http%3A%2F%2F127.0.0.1%3A\(port)%2Fmcp".utf8
        )
    )
    let tokenObject = try #require(
        try JSONSerialization.jsonObject(with: tokenExchangeResponse.data) as? [String: Any]
    )
    let accessToken = try #require(tokenObject["access_token"] as? String)
    let refreshToken = try #require(tokenObject["refresh_token"] as? String)
    return OAuthFlowResult(
        clientID: clientID,
        accessToken: accessToken,
        refreshToken: refreshToken
    )
}

private func makeToolsListTestingServer() async -> Server {
    let server = Server(
        name: "ursus",
        version: "0.1.0",
        capabilities: .init(
            resources: .init(listChanged: false),
            tools: .init(listChanged: false)
        )
    )
    await server.withMethodHandler(ListTools.self) { _ in
        .init(tools: [])
    }
    return server
}
