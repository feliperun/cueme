import AVFoundation
import Foundation

/// Deterministic, in-memory archive used only when the UI-test runner explicitly
/// launches CueMe with CUEME_UI_TESTING=1. It never writes into the user's archive.
enum UITestFixtures {
    static let profileID = UUID(uuidString: "70000000-0000-0000-0000-000000000001")!

    static let brief = SessionBrief(
        mode: .meeting,
        conversationLang: "en-US",
        nativeLang: "pt-BR",
        goal: "Synthetic meeting baseline",
        details: "Deterministic UI-test configuration.",
        keyterms: ["synthetic"],
        cv: nil
    )

    static let profile = BriefProfile(
        id: profileID,
        name: "UI Test Focus",
        brief: .init(
            mode: .sales,
            conversationLang: "en-US",
            nativeLang: "pt-BR",
            goal: "Synthetic profile applied",
            details: "Profile changes stay inside the UI-test process.",
            keyterms: ["profile", "synthetic"],
            cv: nil
        ),
        coachModel: .opus,
        summaryModel: .sonnet,
        echoCancellation: false,
        recordAudio: false,
        contextIDs: [],
        glossaryModel: .sonnet
    )

    /// Unique per process. XCTest runs test classes in parallel runner
    /// processes, and `configureIsolatedStorage` starts by deleting the root —
    /// with a fixed name, one process wipes another's semantic index mid-test.
    static var uiTestRoot: URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent(
                "CueMeUITests-archive-\(ProcessInfo.processInfo.processIdentifier)",
                isDirectory: true
            )
    }

    static func configureIsolatedStorage(at root: URL) {
        try? FileManager.default.removeItem(at: root)
        CorpusStore.rootOverride = root
        ExternalAudioInbox.rootOverride = root.appendingPathComponent("IncomingAudio", isDirectory: true)
        DiagnosticsLog.rootOverride = root.appendingPathComponent("Logs", isDirectory: true)
    }

    /// A sibling of the corpus root, not a descendant — the semantic index is
    /// a derived cache, not part of the user's Markdown corpus, and living
    /// inside `root` would make `CorpusStore.loadNotes()` walk right over it.
    static func semanticIndexURL(at root: URL) -> URL {
        root.deletingLastPathComponent()
            .appendingPathComponent("\(root.lastPathComponent)-Derived", isDirectory: true)
            .appendingPathComponent("Memory/memory.sqlite3")
    }

    static func audioImportStatus(named name: String) -> AudioImportStatus? {
        let fixtureSessionID = UUID(uuidString: "20000000-0000-0000-0000-000000000001")!
        switch name {
        case "completed":
            return .init(
                phase: .completed,
                title: "Synthetic import",
                detail: "Synthetic import completed.",
                sessionID: nil
            )
        case "failed":
            return .init(
                phase: .failed,
                title: "Synthetic import",
                detail: "Synthetic processing failed.",
                sessionID: fixtureSessionID
            )
        default:
            return nil
        }
    }

    static func enqueueVoiceMemoImport() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("CueMeUITests-voice-memo-source", isDirectory: true)
        try? FileManager.default.removeItem(at: root)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let source = root.appendingPathComponent("Voice Memo.m4a")
        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVSampleRateKey: 48_000,
            AVNumberOfChannelsKey: 1,
            AVEncoderBitRateKey: 128_000
        ]
        var file: AVAudioFile? = try AVAudioFile(forWriting: source, settings: settings)
        guard let format = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: 48_000,
            channels: 1,
            interleaved: false
        ) else { throw CocoaError(.fileWriteUnknown) }
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 4_800) else {
            throw CocoaError(.fileWriteUnknown)
        }
        buffer.frameLength = 4_800
        try file?.write(from: buffer)
        file = nil

        try ExternalAudioInbox.enqueueCopy(
            from: source,
            filename: "Planejamento semanal do Voice Memos"
        )
    }

    struct Embedding: EmbeddingProvider {
        let modelID = "ui-test-semantic-v1"
        let dimensions = 512
        func embedding(for text: String) -> [Float] {
            var vector = [Float](repeating: 0, count: dimensions)
            let value = text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            if value.contains("zzzz") {
                vector[47] = 1
            } else if value.contains("veiculo") || value.contains("carro") || value.contains("sustentavel") {
                vector[17] = 1
            } else {
                vector[31] = 1
            }
            return vector
        }
    }

    /// There is no project or person entity: the fixture is a note tree.
    /// "Projeto Mobilidade" and "Marina" are ordinary notes, the sessions are
    /// children of the project note, and the session points at the person with
    /// a link.
    struct Memory {
        let records: [MemoryNote]
    }

    static var memory: Memory {
        let mobilityNoteID = UUID(uuidString: "10000000-0000-0000-0000-000000000001")!
        let sessionID = UUID(uuidString: "20000000-0000-0000-0000-000000000001")!
        let earlierID = UUID(uuidString: "20000000-0000-0000-0000-000000000002")!
        let evidenceID = UUID(uuidString: "30000000-0000-0000-0000-000000000001")!
        let decisionID = UUID(uuidString: "30000000-0000-0000-0000-000000000002")!
        let turnID = UUID(uuidString: "40000000-0000-0000-0000-000000000001")!
        let personID = UUID(uuidString: "50000000-0000-0000-0000-000000000001")!
        let now = Date(timeIntervalSince1970: 1_780_000_000)
        let evidence = MemoryEvidence(
            id: evidenceID, turnID: turnID, timestamp: 42,
            quote: "O veículo elétrico será adotado no próximo trimestre."
        )
        let current = MemoryNote(
            id: sessionID, startedAt: now, endedAt: now.addingTimeInterval(1_800),
            mode: .meeting, training: false, conversationLang: "pt-BR", nativeLang: "pt-BR",
            goal: "Definir a estratégia de mobilidade", transcript: [
                TranscriptLine(
                    id: turnID, speaker: .other,
                    text: "O veículo elétrico será adotado no próximo trimestre.",
                    isFinal: true, ts: now.addingTimeInterval(42)
                )
            ], coachCards: [],
            minutes: MeetingMinutes(
                overview: "A equipe aprovou a migração da frota.",
                topics: [.init(title: "Mobilidade", summary: "Troca gradual da frota por veículos elétricos.")]
            ), notes: [.init(timeOffset: 50, text: "Orçamento reservado para carregadores")],
            takeaways: [.init(
                text: "Solicitar propostas aos fornecedores", evidence: [evidence],
                confidence: 0.94, assignee: "Marina"
            )], displayTitle: "Estratégia de frota elétrica",
            review: MeetingReview(
                decisions: [.init(
                    id: decisionID, text: "Adotar veículos elétricos no próximo trimestre", evidence: [evidence],
                    confidence: 0.97
                )],
                openQuestions: [.init(text: "Qual fornecedor terá melhor cobertura?", evidence: [evidence])]
            ), links: ["/projeto-mobilidade/pessoas/marina.md"]
        )
        let earlier = MemoryNote(
            id: earlierID, startedAt: now.addingTimeInterval(-86_400),
            endedAt: now.addingTimeInterval(-84_600), mode: .meeting, training: false,
            conversationLang: "pt-BR", nativeLang: "pt-BR", goal: "Mapear custos",
            transcript: [], coachCards: [],
            minutes: MeetingMinutes(overview: "Custos iniciais da frota foram levantados."),
            displayTitle: "Levantamento de custos"
        )
        var project = MemoryNote(
            id: mobilityNoteID, startedAt: now.addingTimeInterval(-172_800),
            endedAt: now.addingTimeInterval(-172_800), mode: .recording, training: false,
            conversationLang: "pt-BR", nativeLang: "pt-BR", goal: "Eletrificação da frota",
            transcript: [], coachCards: [], origin: .written,
            displayTitle: "Projeto Mobilidade", noteKind: .note, titleSource: .user
        )
        project.relativeFolderPath = ""
        project.archiveFolderName = "projeto-mobilidade"

        var person = MemoryNote(
            id: personID, startedAt: now.addingTimeInterval(-172_800),
            endedAt: now.addingTimeInterval(-172_800), mode: .recording, training: false,
            conversationLang: "pt-BR", nativeLang: "pt-BR", goal: "Compras",
            transcript: [], coachCards: [], origin: .written,
            displayTitle: "Marina", noteKind: .note, titleSource: .user
        )
        person.relativeFolderPath = "projeto-mobilidade/pessoas"
        person.archiveFolderName = "marina"

        var placedCurrent = current
        placedCurrent.relativeFolderPath = "projeto-mobilidade"
        placedCurrent.archiveFolderName = "estrategia-de-frota-eletrica"
        var placedEarlier = earlier
        placedEarlier.relativeFolderPath = "projeto-mobilidade"
        placedEarlier.archiveFolderName = "levantamento-de-custos"

        return Memory(records: [project, person, placedCurrent, placedEarlier])
    }

    static func answer(for records: [MemoryNote]) -> String {
        guard let record = records.first else { return "Nenhuma memória relevante encontrada." }
        return "A frota elétrica foi aprovada para o próximo trimestre [S1].\n\nFontes\n[S1] \(record.title)"
    }
}
