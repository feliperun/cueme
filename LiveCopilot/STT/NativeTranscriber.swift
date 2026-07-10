import Foundation
import AVFoundation
import Speech
import OSLog

/// STT nativo on-device via `SpeechAnalyzer` + `SpeechTranscriber` (macOS 26).
/// Uma instância por fluxo → locutor conhecido pela origem, sem diarização.
actor NativeTranscriber: SttSession {
    private let log = Logger(subsystem: "LiveCopilot", category: "NativeTranscriber")

    private let config: SttConfig

    nonisolated let events: AsyncStream<TranscriptEvent>
    private let eventsCont: AsyncStream<TranscriptEvent>.Continuation

    private var analyzer: SpeechAnalyzer?
    private var transcriber: SpeechTranscriber?
    private var inputCont: AsyncStream<AnalyzerInput>.Continuation?
    private var converter: AudioConverter?
    private var resultsTask: Task<Void, Never>?

    init(config: SttConfig) {
        self.config = config
        var cont: AsyncStream<TranscriptEvent>.Continuation!
        self.events = AsyncStream(bufferingPolicy: .bufferingNewest(256)) { cont = $0 }
        self.eventsCont = cont
    }

    func start() async throws {
        let locale = Locale(identifier: config.localeIdentifier)

        let transcriber = SpeechTranscriber(
            locale: locale,
            transcriptionOptions: [],
            reportingOptions: [.volatileResults],
            attributeOptions: []
        )
        self.transcriber = transcriber

        try await Self.ensureModel(for: transcriber, locale: locale)

        guard let format = await SpeechAnalyzer.bestAvailableAudioFormat(compatibleWith: [transcriber]) else {
            throw SttError.noAudioFormat
        }
        self.converter = AudioConverter(outputFormat: format)

        let (inputSeq, inputCont) = AsyncStream<AnalyzerInput>.makeStream(bufferingPolicy: .bufferingNewest(64))
        self.inputCont = inputCont

        let analyzer = SpeechAnalyzer(modules: [transcriber])
        self.analyzer = analyzer
        try await analyzer.start(inputSequence: inputSeq)

        let speaker = config.speaker
        resultsTask = Task { [weak self, eventsCont] in
            do {
                for try await result in transcriber.results {
                    let text = String(result.text.characters).trimmingCharacters(in: .whitespaces)
                    guard !text.isEmpty else { continue }
                    eventsCont.yield(
                        TranscriptEvent(
                            speaker: speaker,
                            text: text,
                            isFinal: result.isFinal,
                            isEndOfTurn: result.isFinal
                        )
                    )
                }
            } catch {
                await self?.logResultsError(error)
            }
        }

        let spk = config.speaker.rawValue
        let loc = config.localeIdentifier
        log.info("NativeTranscriber iniciado (\(spk, privacy: .public), \(loc, privacy: .public))")
    }

    func feed(_ buffer: AVAudioPCMBuffer) {
        guard let inputCont, let converter else { return }
        guard let converted = converter.convert(buffer) else { return }
        inputCont.yield(AnalyzerInput(buffer: converted))
    }

    func finish() async {
        inputCont?.finish()
        inputCont = nil
        if let analyzer {
            try? await analyzer.finalizeAndFinishThroughEndOfInput()
        }
        resultsTask?.cancel()
        resultsTask = nil
        analyzer = nil
        transcriber = nil
        eventsCont.finish()
    }

    private func logResultsError(_ error: Error) {
        log.error("Erro no stream de resultados: \(error.localizedDescription, privacy: .public)")
    }

    // MARK: - Assets de idioma

    /// Garante que o modelo do idioma esteja instalado on-device; baixa se preciso.
    static func ensureModel(for transcriber: SpeechTranscriber, locale: Locale) async throws {
        let supported = await SpeechTranscriber.supportedLocales
        let target = locale.identifier(.bcp47)
        guard supported.contains(where: { $0.identifier(.bcp47) == target }) else {
            throw SttError.localeUnsupported(locale.identifier)
        }

        let installed = await SpeechTranscriber.installedLocales
        if installed.contains(where: { $0.identifier(.bcp47) == target }) {
            return
        }

        do {
            if let request = try await AssetInventory.assetInstallationRequest(supporting: [transcriber]) {
                try await request.downloadAndInstall()
            }
        } catch {
            throw SttError.assetInstallFailed(error.localizedDescription)
        }
    }
}
