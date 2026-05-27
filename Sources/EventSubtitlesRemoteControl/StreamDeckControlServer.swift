import Foundation
import NIOCore
import NIOHTTP1
import NIOPosix
import NIOWebSocket

public final class StreamDeckControlServer: @unchecked Sendable {
    public typealias CommandHandler = @Sendable (StreamDeckCommandRequest) async -> StreamDeckCommandResult
    public typealias StatusProvider = @Sendable () async -> StreamDeckStatusSnapshot
    public typealias DiagnosticsHandler = @Sendable (String) -> Void

    private let discoveryStore: StreamDeckDiscoveryStore
    private let commandHandler: CommandHandler
    private let statusProvider: StatusProvider
    private let diagnostics: DiagnosticsHandler
    private let clients = StreamDeckClientRegistry()
    private let lifecycleLock = NSLock()
    private var group: MultiThreadedEventLoopGroup?
    private var listener: Channel?

    public init(
        discoveryStore: StreamDeckDiscoveryStore = .init(),
        commandHandler: @escaping CommandHandler,
        statusProvider: @escaping StatusProvider,
        diagnostics: @escaping DiagnosticsHandler = { _ in }
    ) {
        self.discoveryStore = discoveryStore
        self.commandHandler = commandHandler
        self.statusProvider = statusProvider
        self.diagnostics = diagnostics
    }

    public func start() async throws {
        let group = MultiThreadedEventLoopGroup(numberOfThreads: 1)
        let shouldStart = lifecycleLock.withLock {
            if listener != nil {
                return false
            }
            self.group = group
            return true
        }
        if !shouldStart {
            try await group.shutdownGracefullyAsync()
            return
        }

        let upgrader = NIOWebSocketServerUpgrader(
            maxFrameSize: 1 << 20,
            automaticErrorHandling: true,
            shouldUpgrade: { [diagnostics] channel, request in
                guard request.uri == "/streamdeck/v1" else {
                    diagnostics("streamdeck.websocket.reject.path")
                    return channel.eventLoop.makeSucceededFuture(nil)
                }
                return channel.eventLoop.makeSucceededFuture(HTTPHeaders())
            },
            upgradePipelineHandler: { [clients, commandHandler, statusProvider, diagnostics] channel, _ in
                let clientID = UUID()
                let registration = channel.eventLoop.makePromise(of: Void.self)
                Task {
                    await clients.register(id: clientID, channel: channel)
                    registration.succeed(())
                }
                return registration.futureResult.flatMap {
                    channel.pipeline.addHandler(
                        StreamDeckWebSocketFrameHandler(
                            clientID: clientID,
                            clients: clients,
                            commandHandler: commandHandler,
                            statusProvider: statusProvider,
                            diagnostics: diagnostics
                        )
                    )
                }
            }
        )
        let upgradeConfiguration: NIOHTTPServerUpgradeSendableConfiguration = (
            upgraders: [upgrader],
            completionHandler: { _ in }
        )
        let bootstrap = ServerBootstrap(group: group)
            .serverChannelOption(ChannelOptions.socketOption(.so_reuseaddr), value: 1)
            .childChannelInitializer { channel in
                channel.pipeline.configureHTTPServerPipeline(withServerUpgrade: upgradeConfiguration)
            }
            .childChannelOption(ChannelOptions.socketOption(.so_reuseaddr), value: 1)

        do {
            let channel = try await bootstrap.bind(host: "127.0.0.1", port: 0).get()
            guard let port = channel.localAddress?.port else {
                throw StreamDeckControlServerError.missingBoundPort
            }
            try discoveryStore.write(
                StreamDeckDiscoveryRecord(
                    host: "127.0.0.1",
                    port: port,
                    protocolVersion: streamDeckProtocolVersion,
                    processID: ProcessInfo.processInfo.processIdentifier,
                    generatedAt: Date()
                )
            )
            lifecycleLock.withLock {
                listener = channel
            }
            diagnostics("streamdeck.server.started")
        } catch {
            diagnostics("streamdeck.server.start.failed")
            try? await clients.closeAll()
            try? await group.shutdownGracefullyAsync()
            lifecycleLock.withLock {
                if self.group === group {
                    self.group = nil
                    self.listener = nil
                }
            }
            throw error
        }
    }

    public func stop() async throws {
        let state = lifecycleLock.withLock {
            let state = (listener: self.listener, group: self.group)
            self.listener = nil
            self.group = nil
            return state
        }

        try await clients.closeAll()
        if let listener = state.listener {
            try await listener.close().get()
        }
        if let group = state.group {
            try await group.shutdownGracefullyAsync()
        }
        try discoveryStore.removeIfOwned(by: ProcessInfo.processInfo.processIdentifier)
        diagnostics("streamdeck.server.stopped")
    }

    public func publishStatus() async {
        let status = await statusProvider()
        await clients.broadcast(.status(StreamDeckStatusMessage(status: status)), diagnostics: diagnostics)
    }
}

private enum StreamDeckControlServerError: Error {
    case missingBoundPort
}

private actor StreamDeckClientRegistry {
    private struct Client {
        let channel: Channel
        var didHandshake: Bool
    }

    private var clients: [UUID: Client] = [:]

    func register(id: UUID, channel: Channel) {
        clients[id] = Client(channel: channel, didHandshake: false)
    }

    func markHandshaken(id: UUID) {
        guard var client = clients[id] else {
            return
        }
        client.didHandshake = true
        clients[id] = client
    }

    func isHandshaken(id: UUID) -> Bool {
        clients[id]?.didHandshake == true
    }

    func remove(id: UUID) {
        clients.removeValue(forKey: id)
    }

    func send(_ message: StreamDeckOutgoingMessage, to id: UUID, diagnostics: StreamDeckControlServer.DiagnosticsHandler) async {
        guard let client = clients[id] else {
            return
        }
        await Self.write(message, to: client.channel, diagnostics: diagnostics)
    }

    func broadcast(_ message: StreamDeckOutgoingMessage, diagnostics: StreamDeckControlServer.DiagnosticsHandler) async {
        let handshakenChannels = clients.values
            .filter(\.didHandshake)
            .map(\.channel)
        for channel in handshakenChannels {
            await Self.write(message, to: channel, diagnostics: diagnostics)
        }
    }

    func close(id: UUID, diagnostics: StreamDeckControlServer.DiagnosticsHandler) async {
        guard let client = clients.removeValue(forKey: id) else {
            return
        }
        await Self.close(client.channel, diagnostics: diagnostics)
    }

    func closeAll() async throws {
        let channels = clients.values.map(\.channel)
        clients.removeAll()
        for channel in channels {
            try await channel.close().get()
        }
    }

    private static func write(
        _ message: StreamDeckOutgoingMessage,
        to channel: Channel,
        diagnostics: StreamDeckControlServer.DiagnosticsHandler
    ) async {
        do {
            let data = try JSONEncoder().encode(message)
            guard let text = String(data: data, encoding: .utf8) else {
                diagnostics("streamdeck.websocket.write.encoding_failed")
                return
            }
            let promise = channel.eventLoop.makePromise(of: Void.self)
            channel.eventLoop.execute {
                let frame = WebSocketFrame(fin: true, opcode: .text, data: channel.allocator.buffer(string: text))
                channel.writeAndFlush(frame, promise: promise)
            }
            try await promise.futureResult.get()
        } catch {
            diagnostics("streamdeck.websocket.write.failed")
        }
    }

    private static func close(
        _ channel: Channel,
        diagnostics: StreamDeckControlServer.DiagnosticsHandler
    ) async {
        let promise = channel.eventLoop.makePromise(of: Void.self)
        channel.eventLoop.execute {
            var buffer = channel.allocator.buffer(capacity: 2)
            buffer.write(webSocketErrorCode: .normalClosure)
            let frame = WebSocketFrame(fin: true, opcode: .connectionClose, data: buffer)
            channel.writeAndFlush(frame).whenComplete { _ in
                channel.close(promise: promise)
            }
        }
        do {
            try await promise.futureResult.get()
        } catch {
            diagnostics("streamdeck.websocket.close.failed")
        }
    }
}

private final class StreamDeckWebSocketFrameHandler: ChannelInboundHandler, @unchecked Sendable {
    typealias InboundIn = WebSocketFrame
    typealias OutboundOut = WebSocketFrame

    private let clientID: UUID
    private let clients: StreamDeckClientRegistry
    private let commandHandler: StreamDeckControlServer.CommandHandler
    private let statusProvider: StreamDeckControlServer.StatusProvider
    private let diagnostics: StreamDeckControlServer.DiagnosticsHandler

    init(
        clientID: UUID,
        clients: StreamDeckClientRegistry,
        commandHandler: @escaping StreamDeckControlServer.CommandHandler,
        statusProvider: @escaping StreamDeckControlServer.StatusProvider,
        diagnostics: @escaping StreamDeckControlServer.DiagnosticsHandler
    ) {
        self.clientID = clientID
        self.clients = clients
        self.commandHandler = commandHandler
        self.statusProvider = statusProvider
        self.diagnostics = diagnostics
    }

    func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        let frame = unwrapInboundIn(data)
        switch frame.opcode {
        case .text:
            var frameData = frame.unmaskedData
            guard let text = frameData.readString(length: frameData.readableBytes) else {
                reject("streamdeck.websocket.reject.text_decoding")
                return
            }
            handleText(text)
        case .ping:
            let pong = WebSocketFrame(fin: true, opcode: .pong, data: frame.data)
            context.writeAndFlush(wrapOutboundOut(pong), promise: nil)
        case .pong:
            break
        case .connectionClose:
            Task { await clients.close(id: clientID, diagnostics: diagnostics) }
        default:
            reject("streamdeck.websocket.reject.unsupported_frame")
        }
    }

    func channelInactive(context: ChannelHandlerContext) {
        Task { await clients.remove(id: clientID) }
    }

    private func handleText(_ text: String) {
        guard let data = text.data(using: .utf8),
              let message = try? JSONDecoder().decode(StreamDeckIncomingMessage.self, from: data)
        else {
            reject("streamdeck.websocket.reject.malformed_json")
            return
        }

        Task {
            switch message {
            case .hello(let hello):
                guard hello.protocolVersion == streamDeckProtocolVersion else {
                    await rejectAsync("streamdeck.websocket.reject.protocol_version")
                    return
                }
                await clients.markHandshaken(id: clientID)
                let status = await statusProvider()
                await clients.send(.status(StreamDeckStatusMessage(status: status)), to: clientID, diagnostics: diagnostics)
            case .command(let request):
                guard await clients.isHandshaken(id: clientID) else {
                    await rejectAsync("streamdeck.websocket.reject.command_before_hello")
                    return
                }
                let result = await commandHandler(request)
                await clients.send(.commandResult(result), to: clientID, diagnostics: diagnostics)
                let status = await statusProvider()
                await clients.send(.status(StreamDeckStatusMessage(status: status)), to: clientID, diagnostics: diagnostics)
            }
        }
    }

    private func reject(_ diagnostic: String) {
        Task {
            await rejectAsync(diagnostic)
        }
    }

    private func rejectAsync(_ diagnostic: String) async {
        diagnostics(diagnostic)
        await clients.close(id: clientID, diagnostics: diagnostics)
    }
}

private extension MultiThreadedEventLoopGroup {
    func shutdownGracefullyAsync() async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            shutdownGracefully { error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume()
                }
            }
        }
    }
}
