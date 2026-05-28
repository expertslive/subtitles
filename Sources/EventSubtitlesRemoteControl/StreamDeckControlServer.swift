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
    private var lifecycleState: StreamDeckServerLifecycleState = .stopped

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
        while true {
            let startTask: Task<StreamDeckServerResources, Error> = lifecycleLock.withLock {
                switch lifecycleState {
                case .started:
                    return Task { throw StreamDeckControlServerError.alreadyStarted }
                case .starting(let task):
                    return task
                case .stopping(let task):
                    return Task {
                        try await task.value
                        throw StreamDeckControlServerError.retryStart
                    }
                case .stopped:
                    let task = Task { try await self.createResources() }
                    lifecycleState = .starting(task)
                    return task
                }
            }
            do {
                let resources = try await startTask.value
                lifecycleLock.withLock {
                    if case .starting = lifecycleState {
                        lifecycleState = .started(resources)
                    }
                }
                return
            } catch StreamDeckControlServerError.alreadyStarted {
                return
            } catch StreamDeckControlServerError.retryStart {
                continue
            } catch {
                lifecycleLock.withLock {
                    if case .starting = lifecycleState {
                        lifecycleState = .stopped
                    }
                }
                throw error
            }
        }
    }

    private func createResources() async throws -> StreamDeckServerResources {
        let group = MultiThreadedEventLoopGroup(numberOfThreads: 1)
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
                let processor = StreamDeckClientMessageProcessor()
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
                            processor: processor,
                            commandHandler: commandHandler,
                            statusProvider: statusProvider,
                            diagnostics: diagnostics
                        )
                    )
                }
            }
        )
        let bootstrap = ServerBootstrap(group: group)
            .serverChannelOption(ChannelOptions.socketOption(.so_reuseaddr), value: 1)
            .childChannelInitializer { channel in
                let rejectHandler = StreamDeckHTTPRejectHandler(diagnostics: self.diagnostics)
                let upgradeConfiguration: NIOHTTPServerUpgradeSendableConfiguration = (
                    upgraders: [upgrader],
                    completionHandler: { context in
                        context.pipeline.removeHandler(rejectHandler, promise: nil)
                    }
                )
                return channel.pipeline.configureHTTPServerPipeline(withServerUpgrade: upgradeConfiguration).flatMap {
                    channel.pipeline.addHandler(rejectHandler)
                }
            }
            .childChannelOption(ChannelOptions.socketOption(.so_reuseaddr), value: 1)

        var boundListener: Channel?
        do {
            let channel = try await bootstrap.bind(host: "127.0.0.1", port: 0).get()
            boundListener = channel
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
            diagnostics("streamdeck.server.started")
            return StreamDeckServerResources(group: group, listener: channel)
        } catch {
            diagnostics("streamdeck.server.start.failed")
            try? await clients.closeAll()
            try? await boundListener?.close().get()
            try? await group.shutdownGracefullyAsync()
            throw error
        }
    }

    public func stop() async throws {
        let stopTask: Task<Void, Error>? = lifecycleLock.withLock {
            switch lifecycleState {
            case .stopped:
                return nil
            case .stopping(let task):
                return task
            case .started(let resources):
                let task = Task { try await self.closeResources(resources) }
                lifecycleState = .stopping(task)
                return task
            case .starting(let startTask):
                let task = Task {
                    do {
                        let resources = try await startTask.value
                        try await self.closeResources(resources)
                    } catch {
                        try? self.discoveryStore.removeIfOwned(by: ProcessInfo.processInfo.processIdentifier)
                        throw error
                    }
                }
                lifecycleState = .stopping(task)
                return task
            }
        }

        guard let stopTask else {
            return
        }
        defer {
            lifecycleLock.withLock {
                if case .stopping = lifecycleState {
                    lifecycleState = .stopped
                }
            }
        }
        try await stopTask.value
    }

    public func publishStatus() async {
        let status = await statusProvider()
        await clients.broadcast(.status(StreamDeckStatusMessage(status: status)), diagnostics: diagnostics)
    }

    private func closeResources(_ resources: StreamDeckServerResources) async throws {
        var firstError: Error?
        do {
            try await clients.closeAll()
        } catch {
            firstError = firstError ?? error
        }
        do {
            try await resources.listener.close().get()
        } catch {
            firstError = firstError ?? error
        }
        do {
            try await resources.group.shutdownGracefullyAsync()
        } catch {
            firstError = firstError ?? error
        }
        do {
            try discoveryStore.removeIfOwned(by: ProcessInfo.processInfo.processIdentifier)
        } catch {
            firstError = firstError ?? error
        }
        diagnostics("streamdeck.server.stopped")
        if let firstError {
            throw firstError
        }
    }
}

private enum StreamDeckControlServerError: Error {
    case missingBoundPort
    case alreadyStarted
    case retryStart
}

private struct StreamDeckServerResources: @unchecked Sendable {
    let group: MultiThreadedEventLoopGroup
    let listener: Channel
}

private enum StreamDeckServerLifecycleState {
    case stopped
    case starting(Task<StreamDeckServerResources, Error>)
    case started(StreamDeckServerResources)
    case stopping(Task<Void, Error>)
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

private final class StreamDeckClientMessageProcessor: @unchecked Sendable {
    private let lock = NSLock()
    private var tail: Task<Void, Never>?
    private var active = true

    func enqueue(_ operation: @escaping @Sendable () async -> Void) {
        lock.withLock {
            guard active else {
                return
            }
            let previous = tail
            let next = Task { [weak self] in
                await previous?.value
                guard self?.isActive == true else {
                    return
                }
                await operation()
            }
            tail = next
        }
    }

    func cancel() {
        lock.withLock {
            active = false
            tail?.cancel()
        }
    }

    var isActive: Bool {
        lock.withLock { active }
    }
}

private final class StreamDeckWebSocketFrameHandler: ChannelInboundHandler, @unchecked Sendable {
    typealias InboundIn = WebSocketFrame
    typealias OutboundOut = WebSocketFrame

    private let clientID: UUID
    private let clients: StreamDeckClientRegistry
    private let processor: StreamDeckClientMessageProcessor
    private let commandHandler: StreamDeckControlServer.CommandHandler
    private let statusProvider: StreamDeckControlServer.StatusProvider
    private let diagnostics: StreamDeckControlServer.DiagnosticsHandler

    init(
        clientID: UUID,
        clients: StreamDeckClientRegistry,
        processor: StreamDeckClientMessageProcessor,
        commandHandler: @escaping StreamDeckControlServer.CommandHandler,
        statusProvider: @escaping StreamDeckControlServer.StatusProvider,
        diagnostics: @escaping StreamDeckControlServer.DiagnosticsHandler
    ) {
        self.clientID = clientID
        self.clients = clients
        self.processor = processor
        self.commandHandler = commandHandler
        self.statusProvider = statusProvider
        self.diagnostics = diagnostics
    }

    func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        let frame = unwrapInboundIn(data)
        switch frame.opcode {
        case .text:
            guard frame.fin else {
                reject("streamdeck.websocket.reject.fragmented_frame")
                return
            }
            var frameData = frame.unmaskedData
            guard let text = frameData.readString(length: frameData.readableBytes) else {
                reject("streamdeck.websocket.reject.text_decoding")
                return
            }
            handleText(text)
        case .ping:
            let pongData = frame.unmaskedData
            let pong = WebSocketFrame(fin: true, opcode: .pong, data: pongData)
            context.writeAndFlush(wrapOutboundOut(pong), promise: nil)
        case .pong:
            break
        case .connectionClose:
            processor.cancel()
            Task { await clients.close(id: clientID, diagnostics: diagnostics) }
        case .continuation:
            reject("streamdeck.websocket.reject.fragmented_frame")
        default:
            reject("streamdeck.websocket.reject.unsupported_frame")
        }
    }

    func channelInactive(context: ChannelHandlerContext) {
        processor.cancel()
        Task { await clients.remove(id: clientID) }
    }

    private func handleText(_ text: String) {
        guard let data = text.data(using: .utf8),
              let message = try? JSONDecoder().decode(StreamDeckIncomingMessage.self, from: data)
        else {
            reject("streamdeck.websocket.reject.malformed_json")
            return
        }

        processor.enqueue { [clientID, clients, processor, commandHandler, statusProvider, diagnostics] in
            switch message {
            case .hello(let hello):
                guard processor.isActive else {
                    return
                }
                guard hello.protocolVersion == streamDeckProtocolVersion else {
                    diagnostics("streamdeck.websocket.reject.protocol_version")
                    processor.cancel()
                    await clients.close(id: clientID, diagnostics: diagnostics)
                    return
                }
                await clients.markHandshaken(id: clientID)
                let status = await statusProvider()
                guard processor.isActive else {
                    return
                }
                await clients.send(.status(StreamDeckStatusMessage(status: status)), to: clientID, diagnostics: diagnostics)
            case .command(let request):
                guard processor.isActive else {
                    return
                }
                guard await clients.isHandshaken(id: clientID) else {
                    diagnostics("streamdeck.websocket.reject.command_before_hello")
                    processor.cancel()
                    await clients.close(id: clientID, diagnostics: diagnostics)
                    return
                }
                let result = await commandHandler(request)
                guard processor.isActive else {
                    return
                }
                await clients.send(.commandResult(result), to: clientID, diagnostics: diagnostics)
                let status = await statusProvider()
                guard processor.isActive else {
                    return
                }
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
        processor.cancel()
        await clients.close(id: clientID, diagnostics: diagnostics)
    }
}

private final class StreamDeckHTTPRejectHandler: ChannelInboundHandler, RemovableChannelHandler, @unchecked Sendable {
    typealias InboundIn = HTTPServerRequestPart
    typealias OutboundOut = HTTPServerResponsePart

    private let diagnostics: StreamDeckControlServer.DiagnosticsHandler

    init(diagnostics: @escaping StreamDeckControlServer.DiagnosticsHandler) {
        self.diagnostics = diagnostics
    }

    func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        switch unwrapInboundIn(data) {
        case .head:
            diagnostics("streamdeck.http.reject.request")
        case .body:
            break
        case .end:
            var headers = HTTPHeaders()
            headers.add(name: "Content-Length", value: "0")
            headers.add(name: "Connection", value: "close")
            let head = HTTPResponseHead(version: .http1_1, status: .notFound, headers: headers)
            context.write(wrapOutboundOut(.head(head)), promise: nil)
            context.write(wrapOutboundOut(.end(nil)), promise: nil)
            context.flush()
            context.close(promise: nil)
        }
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
