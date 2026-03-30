import BearCore
import Foundation
import Logging
import MCP
@preconcurrency import NIOCore
@preconcurrency import NIOHTTP1
@preconcurrency import NIOPosix

actor BearBridgeHTTPApplication {
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

    typealias ServerFactory = @Sendable (String) async throws -> Server

    private let configuration: Configuration
    private let serverFactory: ServerFactory
    private let logger: Logger

    private var channel: Channel?
    private var eventLoopGroup: MultiThreadedEventLoopGroup?
    private var sessions: [String: SessionContext] = [:]

    private struct SessionContext {
        let server: Server
        let transport: StatefulHTTPServerTransport
        let createdAt: Date
        var lastAccessedAt: Date
    }

    init(
        configuration: Configuration,
        serverFactory: @escaping ServerFactory,
        logger: Logger
    ) {
        self.configuration = configuration
        self.serverFactory = serverFactory
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

            logger.info("Starting Bear MCP bridge at http://\(configuration.host):\(configuration.port)\(configuration.endpoint)")

            let channel = try await bootstrap.bind(host: configuration.host, port: configuration.port).get()
            self.channel = channel

            Task { [weak self] in
                await self?.sessionCleanupLoop()
            }

            try await channel.closeFuture.get()
        } catch {
            await teardown()
            throw error
        }

        await teardown()
    }

    func stop() async {
        await closeAllSessions()
        if let channel {
            _ = try? await channel.close().get()
            self.channel = nil
        }
        await teardown()
        logger.info("Bear MCP bridge stopped")
    }

    func handleHTTPRequest(_ request: HTTPRequest) async -> HTTPResponse {
        let sessionID = request.header(HTTPHeaderName.sessionID)

        if let sessionID, var session = sessions[sessionID] {
            session.lastAccessedAt = Date()
            sessions[sessionID] = session

            let response = await session.transport.handleRequest(request)
            if request.method.uppercased() == "DELETE", response.statusCode == 200 {
                sessions.removeValue(forKey: sessionID)
            }
            return response
        }

        if request.method.uppercased() == "POST",
           let body = request.body,
           isInitializeRequest(body)
        {
            return await createSessionAndHandle(request)
        }

        if sessionID != nil {
            return .error(statusCode: 404, .invalidRequest("Not Found: Session not found or expired"))
        }

        return .error(
            statusCode: 400,
            .invalidRequest("Bad Request: Missing \(HTTPHeaderName.sessionID) header")
        )
    }

    private struct FixedSessionIDGenerator: SessionIDGenerator {
        let sessionID: String

        func generateSessionID() -> String {
            sessionID
        }
    }

    private func createSessionAndHandle(_ request: HTTPRequest) async -> HTTPResponse {
        let sessionID = UUID().uuidString
        let transport = StatefulHTTPServerTransport(
            sessionIDGenerator: FixedSessionIDGenerator(sessionID: sessionID),
            logger: logger
        )

        do {
            let server = try await serverFactory(sessionID)
            try await server.start(transport: transport)

            sessions[sessionID] = SessionContext(
                server: server,
                transport: transport,
                createdAt: Date(),
                lastAccessedAt: Date()
            )

            let response = await transport.handleRequest(request)
            if case .error = response {
                sessions.removeValue(forKey: sessionID)
                await transport.disconnect()
            }

            return response
        } catch {
            await transport.disconnect()
            return .error(
                statusCode: 500,
                .internalError("Failed to create bridge session: \(error.localizedDescription)")
            )
        }
    }

    private func closeSession(_ sessionID: String) async {
        guard let session = sessions.removeValue(forKey: sessionID) else {
            return
        }

        await session.transport.disconnect()
        await session.server.stop()
        logger.info("Closed Bear MCP bridge session \(sessionID)")
    }

    private func closeAllSessions() async {
        for sessionID in sessions.keys {
            await closeSession(sessionID)
        }
    }

    private func isInitializeRequest(_ body: Data) -> Bool {
        guard
            let object = try? JSONSerialization.jsonObject(with: body) as? [String: Any],
            let method = object["method"] as? String
        else {
            return false
        }

        return method == "initialize"
    }

    private func sessionCleanupLoop() async {
        while !Task.isCancelled {
            try? await Task.sleep(for: .seconds(60))

            let now = Date()
            let expiredSessions = sessions.filter { _, context in
                now.timeIntervalSince(context.lastAccessedAt) > configuration.sessionTimeout
            }

            for (sessionID, _) in expiredSessions {
                logger.info("Expiring idle Bear MCP bridge session \(sessionID)")
                await closeSession(sessionID)
            }
        }
    }

    private func teardown() async {
        if let group = eventLoopGroup {
            try? await group.shutdownGracefully()
            eventLoopGroup = nil
        }
        channel = nil
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
