import AVFoundation
import Foundation
import OSLog

/// Low-latency Deepgram Nova-3 streaming session for one capture origin.
actor DeepgramTranscriber: SttSession, SttHealthReporting {
    private let log = Logger(subsystem: "CueMe", category: "DeepgramTranscriber")
    private let config: SttConfig
    private let apiKey: String
    private let encoder = DeepgramAudioEncoder()
    private var assembler: DeepgramTranscriptAssembler

    nonisolated let events: AsyncStream<TranscriptEvent>
    private let eventsContinuation: AsyncStream<TranscriptEvent>.Continuation
    private let audioStream: AsyncStream<Data>
    private let audioContinuation: AsyncStream<Data>.Continuation

    private var socket: URLSessionWebSocketTask?
    private var networkSession: URLSession?
    private var senderTask: Task<Void, Never>?
    private var receiverTask: Task<Void, Never>?
    private var keepAliveTask: Task<Void, Never>?
    private var reconnectTask: Task<Bool, Never>?
    private var reconnectBlockedUntil: Date?
    private var isActive = false
    private var inputFailures = 0
    private var sendFailures = 0
    private var reconnects = 0

    private static let reconnectAttempts = 4
    private static let reconnectCooldownSeconds: TimeInterval = 5
    private static let reconnectCooldown = Duration.seconds(5)

    init(config: SttConfig, apiKey: String) {
        self.config = config
        self.apiKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        self.assembler = DeepgramTranscriptAssembler(speaker: config.speaker)

        let (events, eventsContinuation) = AsyncStream<TranscriptEvent>.makeStream(
            bufferingPolicy: .unbounded
        )
        self.events = events
        self.eventsContinuation = eventsContinuation
        let (audioStream, audioContinuation) = AsyncStream<Data>.makeStream(
            bufferingPolicy: .unbounded
        )
        self.audioStream = audioStream
        self.audioContinuation = audioContinuation
    }

    func start() async throws {
        guard !apiKey.isEmpty else { throw DeepgramError.missingAPIKey }
        let connection = try await DeepgramSocketConnector.connect(config: config, apiKey: apiKey)
        self.networkSession = connection.session
        self.socket = connection.socket
        isActive = true

        senderTask = Task { [weak self, audioStream] in
            for await data in audioStream {
                guard let self, !Task.isCancelled else { return }
                await self.sendAudio(data)
            }
        }
        receiverTask = Task { [weak self] in await self?.receiveLoop() }
        keepAliveTask = Task { [weak self] in await self?.keepAliveLoop() }

        log.info("Deepgram Nova-3 iniciado (\(self.config.speaker.rawValue, privacy: .public), \(self.config.localeIdentifier, privacy: .public))")
    }

    func feed(_ buffer: AVAudioPCMBuffer) {
        guard isActive else { return }
        guard let data = encoder.encode(buffer), !data.isEmpty else {
            inputFailures += 1
            return
        }
        audioContinuation.yield(data)
    }

    func healthSnapshot() -> SttHealthSnapshot {
        .init(inputFailures: inputFailures, sendFailures: sendFailures, reconnects: reconnects)
    }

    func finish() async {
        guard isActive else {
            eventsContinuation.finish()
            return
        }
        isActive = false
        audioContinuation.finish()
        await senderTask?.value
        if let socket {
            try? await socket.send(.string(#"{"type":"CloseStream"}"#))
            try? await Task.sleep(for: .milliseconds(180))
            socket.cancel(with: .normalClosure, reason: nil)
        }
        senderTask?.cancel()
        receiverTask?.cancel()
        keepAliveTask?.cancel()
        reconnectTask?.cancel()
        senderTask = nil
        receiverTask = nil
        keepAliveTask = nil
        reconnectTask = nil
        socket = nil
        networkSession?.invalidateAndCancel()
        networkSession = nil
        eventsContinuation.finish()
    }

    /// A failed send never retries the chunk and never blocks the sender: the
    /// audio queue has to keep draining while the socket is down, otherwise a
    /// network outage turns into unbounded memory growth plus a reconnect storm
    /// of one full backoff cycle per buffered chunk.
    private func sendAudio(_ data: Data) async {
        guard isActive, let socket, reconnectTask == nil else { return }
        do {
            try await socket.send(.data(data))
        } catch {
            sendFailures += 1
            guard self.socket === socket else { return }
            log.error("Falha ao enviar áudio para a Deepgram; agendando reconexão")
            startReconnectIfIdle()
        }
    }

    private func receiveLoop() async {
        while isActive, !Task.isCancelled {
            guard let socket else {
                if !(await reconnect()) {
                    try? await Task.sleep(for: Self.reconnectCooldown)
                }
                continue
            }
            do {
                while isActive, !Task.isCancelled {
                    let message = try await socket.receive()
                    let data: Data
                    switch message {
                    case .data(let value): data = value
                    case .string(let value): data = Data(value.utf8)
                    @unknown default: continue
                    }
                    if let event = assembler.consume(data) {
                        eventsContinuation.yield(event)
                    }
                }
            } catch {
                guard isActive, !Task.isCancelled else { return }
                guard self.socket === socket else { continue }
                log.error("Stream da Deepgram foi interrompido; reconectando")
                if !(await reconnect()) {
                    try? await Task.sleep(for: Self.reconnectCooldown)
                }
            }
        }
    }

    /// Circuit breaker: after a failed backoff cycle no new attempt starts until
    /// the cooldown expires, so callers stay cheap while the network is down.
    private var isReconnectBlocked: Bool {
        guard let reconnectBlockedUntil else { return false }
        return Date() < reconnectBlockedUntil
    }

    private func startReconnectIfIdle() {
        guard isActive, reconnectTask == nil, !isReconnectBlocked else { return }
        reconnectTask = Task { [weak self] in
            guard let self else { return false }
            return await self.performReconnect()
        }
    }

    private func reconnect() async -> Bool {
        startReconnectIfIdle()
        guard let task = reconnectTask else { return false }
        return await task.value
    }

    private func performReconnect() async -> Bool {
        defer { reconnectTask = nil }
        var lastError: Error?
        for attempt in 0..<Self.reconnectAttempts {
            guard isActive, !Task.isCancelled else { return false }
            if attempt > 0 {
                do { try await Task.sleep(for: .milliseconds(250 * (1 << (attempt - 1)))) }
                catch { return false }
            }
            do {
                let connection = try await DeepgramSocketConnector.connect(config: config, apiKey: apiKey)
                guard isActive else {
                    connection.socket.cancel(with: .goingAway, reason: nil)
                    connection.session.invalidateAndCancel()
                    return false
                }
                socket?.cancel(with: .goingAway, reason: nil)
                networkSession?.invalidateAndCancel()
                socket = connection.socket
                networkSession = connection.session
                reconnectBlockedUntil = nil
                reconnects += 1
                log.info("Deepgram reconectada (reconexão \(self.reconnects, privacy: .public))")
                return true
            } catch {
                lastError = error
            }
        }
        reconnectBlockedUntil = Date().addingTimeInterval(Self.reconnectCooldownSeconds)
        log.error("Deepgram não reconectou após backoff: \(lastError?.localizedDescription ?? "-", privacy: .public)")
        return false
    }

    private func keepAliveLoop() async {
        while isActive, !Task.isCancelled {
            do { try await Task.sleep(for: .seconds(4)) } catch { return }
            guard isActive, let socket else { return }
            try? await socket.send(.string(#"{"type":"KeepAlive"}"#))
        }
    }

}
