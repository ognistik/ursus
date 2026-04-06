import BearCore
import Foundation
import Logging
import MCP
@preconcurrency import NIOCore
@preconcurrency import NIOHTTP1
@preconcurrency import NIOPosix

actor BearBridgeHTTPApplication {
    enum BridgeHTTPResponse: Sendable {
        case mcp(HTTPResponse)
        case plain(statusCode: Int, headers: [String: String] = [:], body: Data? = nil)

        var statusCode: Int {
            switch self {
            case .mcp(let response):
                response.statusCode
            case .plain(let statusCode, _, _):
                statusCode
            }
        }
    }

    struct InitializeEnvelope: Sendable {
        let id: ID
        let protocolVersion: String
    }

    struct Configuration: Sendable {
        var host: String
        var port: Int
        var endpoint: String
        var authMode: BearBridgeAuthMode
        var sessionTimeout: TimeInterval
        var authDatabaseURL: URL

        init(
            host: String,
            port: Int,
            endpoint: String = "/mcp",
            authMode: BearBridgeAuthMode = .open,
            sessionTimeout: TimeInterval = 3600,
            authDatabaseURL: URL = BearPaths.bridgeAuthDatabaseURL
        ) {
            self.host = host
            self.port = port
            self.endpoint = endpoint
            self.authMode = authMode
            self.sessionTimeout = sessionTimeout
            self.authDatabaseURL = authDatabaseURL
        }
    }

    enum Route: Equatable {
        case mcp
        case oauthProtectedResourceMetadata
        case oauthAuthorizationServerMetadata
        case oauthAuthorize
        case oauthToken
        case oauthRegister
        case notFound
    }

    typealias ServerFactory = @Sendable () async throws -> Server
    typealias ReadyHandler = @Sendable () throws -> Void

    private let configuration: Configuration
    private let serverFactory: ServerFactory
    private let readyHandler: ReadyHandler?
    private let logger: Logger
    private let oauthServer: BearBridgeOAuthServer

    private var channel: Channel?
    private var eventLoopGroup: MultiThreadedEventLoopGroup?
    private var server: Server?
    private var transport: StatelessHTTPServerTransport?
    private var startupTask: Task<(Server, StatelessHTTPServerTransport), Error>?
    private var hasCompletedInitializationHandshake = false

    init(
        configuration: Configuration,
        serverFactory: @escaping ServerFactory,
        readyHandler: ReadyHandler? = nil,
        logger: Logger
    ) {
        self.configuration = configuration
        self.serverFactory = serverFactory
        self.readyHandler = readyHandler
        self.logger = logger
        self.oauthServer = BearBridgeOAuthServer(
            configuration: .init(
                host: configuration.host,
                port: configuration.port,
                mcpEndpoint: configuration.endpoint,
                authDatabaseURL: configuration.authDatabaseURL
            )
        )
    }

    var endpoint: String {
        configuration.endpoint
    }

    var authMode: BearBridgeAuthMode {
        configuration.authMode
    }

    func start() async throws {
        guard channel == nil, eventLoopGroup == nil else {
            throw BearError.configuration("The bridge HTTP application is already running.")
        }

        let group = MultiThreadedEventLoopGroup(numberOfThreads: 1)
        eventLoopGroup = group

        do {
            let bootstrap = ServerBootstrap(group: group)
                .serverChannelOption(ChannelOptions.backlog, value: 256)
                .serverChannelOption(ChannelOptions.socketOption(.so_reuseaddr), value: 1)
                .childChannelInitializer { channel in
                    channel.pipeline.configureHTTPServerPipeline().flatMap {
                        channel.pipeline.addHandler(BearBridgeHTTPHandler(app: self))
                    }
                }
                .childChannelOption(ChannelOptions.socketOption(.so_reuseaddr), value: 1)
                .childChannelOption(ChannelOptions.maxMessagesPerRead, value: 1)

            logger.info("Starting Ursus bridge at http://\(configuration.host):\(configuration.port)\(configuration.endpoint)")

            let channel = try await bootstrap.bind(host: configuration.host, port: configuration.port).get()
            self.channel = channel
            let startupTask = Task { [serverFactory, logger] in
                try await Self.makeStartedRuntime(serverFactory: serverFactory, logger: logger)
            }
            self.startupTask = startupTask

            do {
                let (server, transport) = try await startupTask.value
                if self.channel == nil {
                    await transport.disconnect()
                    await server.stop()
                } else {
                    self.server = server
                    self.transport = transport
                    try readyHandler?()
                }
                self.startupTask = nil
            } catch {
                self.startupTask = nil
                throw error
            }

            try await channel.closeFuture.get()
        } catch {
            await teardown()
            throw error
        }

        await teardown()
    }

    func stop() async {
        if let channel {
            _ = try? await channel.close().get()
            self.channel = nil
        }
        await teardown()
        logger.info("Ursus bridge stopped")
    }

    func handleHTTPRequest(_ request: HTTPRequest) async -> BridgeHTTPResponse {
        switch Self.route(for: request.path, mcpEndpoint: configuration.endpoint) {
        case .mcp:
            break
        case .oauthProtectedResourceMetadata,
             .oauthAuthorizationServerMetadata,
             .oauthAuthorize,
             .oauthToken,
             .oauthRegister:
            guard configuration.authMode.requiresOAuth else {
                return Self.notFoundResponse()
            }
            return await oauthServer.handle(request: request)
        case .notFound:
            return Self.notFoundResponse()
        }

        if configuration.authMode.requiresOAuth {
            return .mcp(
                Self.oauthRequiredResponse(
                    for: request,
                    host: configuration.host,
                    port: configuration.port,
                    mcpEndpoint: configuration.endpoint
                )
            )
        }

        if hasCompletedInitializationHandshake,
           let server,
           let initializeEnvelope = Self.decodeInitializeEnvelope(from: request)
        {
            logger.info("Returning compatibility initialize response for already-initialized bridge")

            do {
                let response = try await Self.makeInitializeResponse(
                    id: initializeEnvelope.id,
                    clientRequestedVersion: initializeEnvelope.protocolVersion,
                    server: server
                )
                return .mcp(Self.wrapStreamingHTTPResponseIfRequested(response, for: request))
            } catch {
                logger.error(
                    "Failed to build compatibility initialize response",
                    metadata: ["error": "\(error)"]
                )
                return .mcp(
                    .error(
                        statusCode: 500,
                        .internalError("Failed to build initialize response")
                    )
                )
            }
        }

        if transport == nil,
           let startupTask
        {
            do {
                let (server, transport) = try await startupTask.value
                if self.server == nil, self.channel != nil {
                    self.server = server
                    self.transport = transport
                } else if self.channel == nil {
                    await transport.disconnect()
                    await server.stop()
                }
                self.startupTask = nil
            } catch {
                self.startupTask = nil
                logger.error(
                    "Ursus bridge runtime failed during startup",
                    metadata: ["error": "\(error)"]
                )
                return .mcp(
                    .error(
                        statusCode: 503,
                        .internalError("Ursus bridge is still starting up")
                    )
                )
            }
        }

        if let server,
           let initializeEnvelope = Self.decodeInitializeEnvelope(from: request)
        {
            do {
                let response = try await Self.makeInitializeResponse(
                    id: initializeEnvelope.id,
                    clientRequestedVersion: initializeEnvelope.protocolVersion,
                    server: server
                )
                hasCompletedInitializationHandshake = true
                return .mcp(Self.wrapStreamingHTTPResponseIfRequested(response, for: request))
            } catch {
                logger.error(
                    "Failed to build manual initialize response",
                    metadata: ["error": "\(error)"]
                )
                return .mcp(
                    .error(
                        statusCode: 500,
                        .internalError("Failed to build initialize response")
                    )
                )
            }
        }

        guard let transport else {
            return .mcp(
                .error(
                    statusCode: 503,
                    .internalError("Ursus bridge transport is not ready yet")
                )
            )
        }

        let response = await transport.handleRequest(request)
        return .mcp(Self.wrapStreamingHTTPResponseIfRequested(response, for: request))
    }

    private func teardown() async {
        startupTask?.cancel()
        startupTask = nil
        if let transport {
            await transport.disconnect()
            self.transport = nil
        }
        if let server {
            await server.stop()
            self.server = nil
        }
        if let group = eventLoopGroup {
            try? await group.shutdownGracefully()
            eventLoopGroup = nil
        }
        channel = nil
        hasCompletedInitializationHandshake = false
    }
}

extension BearBridgeHTTPApplication {
    static func bridgeValidationPipeline() -> StandardValidationPipeline {
        // Keep the bridge's stateless JSON request/response behavior, but avoid
        // localhost-only host/origin validation so forwarded tunnel requests can
        // reach the loopback-bound bridge without extra user-facing modes.
        StandardValidationPipeline(validators: [
            AcceptHeaderValidator(mode: .jsonOnly),
            ContentTypeValidator(),
            ProtocolVersionValidator(),
        ])
    }

    static func wrapStreamingHTTPResponseIfRequested(
        _ response: HTTPResponse,
        for request: HTTPRequest
    ) -> HTTPResponse {
        guard request.method.caseInsensitiveCompare("POST") == .orderedSame,
              requestAcceptsEventStream(request)
        else {
            return response
        }

        switch response {
        case .data(let body, let headers):
            var streamingHeaders = headers
            streamingHeaders[HTTPHeaderName.contentType] = "text/event-stream"
            streamingHeaders[HTTPHeaderName.cacheControl] = "no-cache"
            streamingHeaders[HTTPHeaderName.connection] = "keep-alive"

            let stream = AsyncThrowingStream<Data, Swift.Error> { continuation in
                continuation.yield(formatSSEMessageEvent(body))
                continuation.finish()
            }

            return .stream(stream, headers: streamingHeaders)

        default:
            return response
        }
    }

    static func requestAcceptsEventStream(_ request: HTTPRequest) -> Bool {
        let acceptHeader = request.header(HTTPHeaderName.accept) ?? ""
        return acceptHeader
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .contains { $0.hasPrefix("text/event-stream") }
    }

    static func formatSSEMessageEvent(_ body: Data) -> Data {
        let payload = String(decoding: body, as: UTF8.self)
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map { "data: \($0)" }
            .joined(separator: "\n")

        return Data("event: message\n\(payload)\n\n".utf8)
    }

    static func decodeJSONRPCID(_ id: Any?) -> ID? {
        switch id {
        case let value as String:
            return .string(value)
        case let value as NSNumber:
            return .number(value.intValue)
        default:
            return nil
        }
    }

    static func makeStartedRuntime(
        serverFactory: ServerFactory,
        logger: Logger
    ) async throws -> (Server, StatelessHTTPServerTransport) {
        let transport = StatelessHTTPServerTransport(
            validationPipeline: bridgeValidationPipeline(),
            logger: logger
        )
        let server = try await serverFactory()

        do {
            try Task.checkCancellation()
            try await server.start(transport: transport)
            try Task.checkCancellation()
            return (server, transport)
        } catch {
            await transport.disconnect()
            await server.stop()
            throw error
        }
    }

    static func decodeInitializeRequest(from request: HTTPRequest) -> Request<Initialize>? {
        guard request.method.caseInsensitiveCompare("POST") == .orderedSame,
              let body = request.body,
              !body.isEmpty,
              let initializeRequest = try? JSONDecoder().decode(Request<Initialize>.self, from: body),
              initializeRequest.method == Initialize.name
        else {
            return nil
        }

        return initializeRequest
    }

    static func decodeInitializeEnvelope(from request: HTTPRequest) -> InitializeEnvelope? {
        guard request.method.caseInsensitiveCompare("POST") == .orderedSame,
              let body = request.body,
              !body.isEmpty,
              let jsonObject = try? JSONSerialization.jsonObject(with: body),
              let dictionary = jsonObject as? [String: Any],
              let method = dictionary["method"] as? String,
              method == Initialize.name
        else {
            return nil
        }

        let id = decodeJSONRPCID(dictionary["id"]) ?? .string("")
        let params = dictionary["params"] as? [String: Any]
        let protocolVersion = params?["protocolVersion"] as? String ?? Version.latest
        return InitializeEnvelope(id: id, protocolVersion: protocolVersion)
    }

    static func makeInitializeResponse(
        id: ID,
        clientRequestedVersion: String,
        server: Server
    ) async throws -> HTTPResponse {
        let negotiatedProtocolVersion = negotiatedProtocolVersion(
            for: clientRequestedVersion
        )
        let result = Initialize.Result(
            protocolVersion: negotiatedProtocolVersion,
            capabilities: await server.capabilities,
            serverInfo: .init(
                name: server.name,
                version: server.version,
                title: server.title
            ),
            instructions: server.instructions
        )

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]

        return .data(
            try encoder.encode(Initialize.response(id: id, result: result)),
            headers: [HTTPHeaderName.contentType: "application/json"]
        )
    }

    static func negotiatedProtocolVersion(for clientRequestedVersion: String) -> String {
        if Version.supported.contains(clientRequestedVersion) {
            return clientRequestedVersion
        }

        return Version.latest
    }

    static func route(for requestPath: String?, mcpEndpoint: String) -> Route {
        let normalizedPath = normalizedPath(from: requestPath) ?? mcpEndpoint

        if normalizedPath == mcpEndpoint {
            return .mcp
        }

        if normalizedPath.hasPrefix("/.well-known/oauth-protected-resource") {
            return .oauthProtectedResourceMetadata
        }

        if normalizedPath.hasPrefix("/.well-known/oauth-authorization-server") {
            return .oauthAuthorizationServerMetadata
        }

        if normalizedPath.hasPrefix("/oauth/authorize") {
            return .oauthAuthorize
        }

        if normalizedPath.hasPrefix("/oauth/token") {
            return .oauthToken
        }

        if normalizedPath.hasPrefix("/oauth/register") {
            return .oauthRegister
        }

        return .notFound
    }

    static func normalizedPath(from requestPath: String?) -> String? {
        guard let requestPath else {
            return nil
        }

        let trimmedPath = requestPath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedPath.isEmpty else {
            return nil
        }

        return trimmedPath.split(separator: "?").first.map(String.init) ?? trimmedPath
    }

    static func oauthRequiredResponse(
        for request: HTTPRequest,
        host: String,
        port: Int,
        mcpEndpoint: String
    ) -> HTTPResponse {
        let hasAuthorizationHeader = request.header(HTTPHeaderName.authorization)?.isEmpty == false
        let resourceMetadata = oauthProtectedResourceMetadataURL(
            for: request,
            host: host,
            port: port,
            mcpEndpoint: mcpEndpoint
        )
        let challenge = hasAuthorizationHeader
            ? #"Bearer realm="ursus-bridge", error="invalid_token", resource_metadata="\#(resourceMetadata)""#
            : #"Bearer realm="ursus-bridge", resource_metadata="\#(resourceMetadata)""#

        return .error(
            statusCode: 401,
            .invalidRequest("OAuth is required for the Ursus HTTP bridge."),
            extraHeaders: [HTTPHeaderName.wwwAuthenticate: challenge]
        )
    }

    static func oauthProtectedResourceMetadataURL(
        for request: HTTPRequest,
        host: String,
        port: Int,
        mcpEndpoint: String
    ) -> String {
        let origin = BearBridgeOAuthServer.originURL(
            hostHeader: request.header(HTTPHeaderName.host),
            fallbackHost: host,
            fallbackPort: port
        )
        var metadataURL = origin
            .appendingPathComponent(".well-known", isDirectory: true)
            .appendingPathComponent("oauth-protected-resource", isDirectory: true)
        for component in mcpEndpoint.split(separator: "/", omittingEmptySubsequences: true) {
            metadataURL.appendPathComponent(String(component), isDirectory: false)
        }
        return metadataURL.absoluteString
    }

    static func notFoundResponse() -> BridgeHTTPResponse {
        .plain(
            statusCode: 404,
            headers: [HTTPHeaderName.contentType: "text/plain; charset=utf-8"],
            body: Data("Not Found".utf8)
        )
    }
}

private final class BearBridgeHTTPHandler: ChannelInboundHandler, @unchecked Sendable {
    typealias InboundIn = HTTPServerRequestPart
    typealias OutboundOut = HTTPServerResponsePart

    private let app: BearBridgeHTTPApplication

    private struct RequestState {
        var head: HTTPRequestHead
        var bodyBuffer: ByteBuffer
    }

    private var requestState: RequestState?

    init(app: BearBridgeHTTPApplication) {
        self.app = app
    }

    func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        let part = unwrapInboundIn(data)

        switch part {
        case .head(let head):
            requestState = RequestState(
                head: head,
                bodyBuffer: context.channel.allocator.buffer(capacity: 0)
            )
        case .body(var buffer):
            requestState?.bodyBuffer.writeBuffer(&buffer)
        case .end:
            guard let state = requestState else {
                return
            }
            requestState = nil

            nonisolated(unsafe) let unsafeContext = context
            Task { [app] in
                await self.handleRequest(state: state, context: unsafeContext, app: app)
            }
        }
    }

    private func handleRequest(
        state: RequestState,
        context: ChannelHandlerContext,
        app: BearBridgeHTTPApplication
    ) async {
        let request = makeHTTPRequest(from: state)
        let response = await app.handleHTTPRequest(request)
        await writeResponse(response, version: state.head.version, context: context)
    }

    private func makeHTTPRequest(from state: RequestState) -> HTTPRequest {
        var headers: [String: String] = [:]
        for (name, value) in state.head.headers {
            if let existing = headers[name] {
                headers[name] = existing + ", " + value
            } else {
                headers[name] = value
            }
        }

        let body: Data?
        if state.bodyBuffer.readableBytes > 0,
           let bytes = state.bodyBuffer.getBytes(at: 0, length: state.bodyBuffer.readableBytes)
        {
            body = Data(bytes)
        } else {
            body = nil
        }

        return HTTPRequest(
            method: state.head.method.rawValue,
            headers: headers,
            body: body,
            path: state.head.uri
        )
    }

    private func writeResponse(
        _ response: BearBridgeHTTPApplication.BridgeHTTPResponse,
        version: HTTPVersion,
        context: ChannelHandlerContext
    ) async {
        nonisolated(unsafe) let unsafeContext = context
        let eventLoop = unsafeContext.eventLoop

        switch response {
        case .mcp(.stream(let stream, let headers)):
            eventLoop.execute {
                var responseHead = HTTPResponseHead(
                    version: version,
                    status: HTTPResponseStatus(statusCode: response.statusCode)
                )
                for (name, value) in headers {
                    responseHead.headers.add(name: name, value: value)
                }
                unsafeContext.write(self.wrapOutboundOut(.head(responseHead)), promise: nil)
                unsafeContext.flush()
            }

            do {
                for try await chunk in stream {
                    eventLoop.execute {
                        var buffer = unsafeContext.channel.allocator.buffer(capacity: chunk.count)
                        buffer.writeBytes(chunk)
                        unsafeContext.writeAndFlush(
                            self.wrapOutboundOut(.body(.byteBuffer(buffer))),
                            promise: nil
                        )
                    }
                }
            } catch {
                eventLoop.execute {
                    unsafeContext.close(promise: nil)
                }
                return
            }

            eventLoop.execute {
                unsafeContext.writeAndFlush(self.wrapOutboundOut(.end(nil)), promise: nil)
            }

        case .mcp(let mcpResponse):
            let headers = mcpResponse.headers
            let bodyData = mcpResponse.bodyData

            eventLoop.execute {
                var responseHead = HTTPResponseHead(
                    version: version,
                    status: HTTPResponseStatus(statusCode: response.statusCode)
                )
                for (name, value) in headers {
                    responseHead.headers.add(name: name, value: value)
                }

                unsafeContext.write(self.wrapOutboundOut(.head(responseHead)), promise: nil)

                if let bodyData {
                    var buffer = unsafeContext.channel.allocator.buffer(capacity: bodyData.count)
                    buffer.writeBytes(bodyData)
                    unsafeContext.write(self.wrapOutboundOut(.body(.byteBuffer(buffer))), promise: nil)
                }

                unsafeContext.writeAndFlush(self.wrapOutboundOut(.end(nil)), promise: nil)
            }

        case .plain(let statusCode, let headers, let bodyData):
            eventLoop.execute {
                var responseHead = HTTPResponseHead(
                    version: version,
                    status: HTTPResponseStatus(statusCode: statusCode)
                )
                for (name, value) in headers {
                    responseHead.headers.add(name: name, value: value)
                }

                unsafeContext.write(self.wrapOutboundOut(.head(responseHead)), promise: nil)

                if let bodyData {
                    var buffer = unsafeContext.channel.allocator.buffer(capacity: bodyData.count)
                    buffer.writeBytes(bodyData)
                    unsafeContext.write(self.wrapOutboundOut(.body(.byteBuffer(buffer))), promise: nil)
                }

                unsafeContext.writeAndFlush(self.wrapOutboundOut(.end(nil)), promise: nil)
            }
        }
    }
}
