import BearCore
import Foundation
import Logging
import MCP
@preconcurrency import NIOCore
@preconcurrency import NIOHTTP1
@preconcurrency import NIOPosix

actor BearBridgeHTTPApplication {
    struct InitializeEnvelope: Sendable {
        let id: ID
        let protocolVersion: String
    }

    struct Configuration: Sendable {
        var host: String
        var port: Int
        var endpoint: String
        var sessionTimeout: TimeInterval

        init(
            host: String,
            port: Int,
            endpoint: String = "/mcp",
            sessionTimeout: TimeInterval = 3600
        ) {
            self.host = host
            self.port = port
            self.endpoint = endpoint
            self.sessionTimeout = sessionTimeout
        }
    }

    typealias ServerFactory = @Sendable () async throws -> Server
    typealias ReadyHandler = @Sendable () throws -> Void

    private let configuration: Configuration
    private let serverFactory: ServerFactory
    private let readyHandler: ReadyHandler?
    private let logger: Logger

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
    }

    var endpoint: String {
        configuration.endpoint
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

    func handleHTTPRequest(_ request: HTTPRequest) async -> HTTPResponse {
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
                return Self.wrapStreamingHTTPResponseIfRequested(response, for: request)
            } catch {
                logger.error(
                    "Failed to build compatibility initialize response",
                    metadata: ["error": "\(error)"]
                )
                return .error(
                    statusCode: 500,
                    .internalError("Failed to build initialize response")
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
                return .error(
                    statusCode: 503,
                    .internalError("Ursus bridge is still starting up")
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
                return Self.wrapStreamingHTTPResponseIfRequested(response, for: request)
            } catch {
                logger.error(
                    "Failed to build manual initialize response",
                    metadata: ["error": "\(error)"]
                )
                return .error(
                    statusCode: 500,
                    .internalError("Failed to build initialize response")
                )
            }
        }

        guard let transport else {
            return .error(
                statusCode: 503,
                .internalError("Ursus bridge transport is not ready yet")
            )
        }

        let response = await transport.handleRequest(request)
        return Self.wrapStreamingHTTPResponseIfRequested(response, for: request)
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
        let head = state.head
        let path = head.uri.split(separator: "?").first.map(String.init) ?? head.uri
        let endpoint = await app.endpoint

        guard path == endpoint else {
            await writeResponse(
                .error(statusCode: 404, .invalidRequest("Not Found")),
                version: head.version,
                context: context
            )
            return
        }

        let request = makeHTTPRequest(from: state)
        let response = await app.handleHTTPRequest(request)
        await writeResponse(response, version: head.version, context: context)
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

        return HTTPRequest(method: state.head.method.rawValue, headers: headers, body: body)
    }

    private func writeResponse(
        _ response: HTTPResponse,
        version: HTTPVersion,
        context: ChannelHandlerContext
    ) async {
        nonisolated(unsafe) let unsafeContext = context
        let eventLoop = unsafeContext.eventLoop

        switch response {
        case .stream(let stream, let headers):
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

        default:
            let headers = response.headers
            let bodyData = response.bodyData

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
        }
    }
}
