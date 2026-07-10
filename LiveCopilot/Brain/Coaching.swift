import Foundation

/// Raia de coaching: Sonnet (ou Opus para input manual "deep"), streaming e cancelável.
/// Emite `CoachCard` progressivamente conforme o modelo gera.
final class CoachingLane: Sendable {
    private let session: ClaudeSession?   // Sonnet (turno ao vivo e input manual)

    init(session: ClaudeSession?) {
        self.session = session
    }

    /// Stream de cards parciais (deltas do CLI). O card final tem `isStreaming = false`.
    /// Stream vazio se não há sessão — o coordinator trata.
    func coach(
        window: [Turn],
        latest: String,
        manual: Bool
    ) -> AsyncThrowingStream<CoachCard, Error> {
        AsyncThrowingStream { continuation in
            guard let session else {
                continuation.finish()
                return
            }
            let user = Prompts.coachUser(window: window, latest: latest, manual: manual)
            let cardID = UUID()

            let task = Task {
                var accumulated = ""
                do {
                    let deltas = await session.send(user)
                    for try await delta in deltas {
                        if Task.isCancelled { break }
                        accumulated += delta
                        if let card = CoachCardParser.parse(accumulated, id: cardID, manual: manual, streaming: true) {
                            continuation.yield(card)
                        }
                    }
                    if let final = CoachCardParser.parse(accumulated, id: cardID, manual: manual, streaming: false) {
                        continuation.yield(final)
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}

/// Parser do formato de saída do coach (GUIA/DIGA_CONV/DIGA_NATIVE/KEYTERMS/MODO).
enum CoachCardParser {
    static func parse(_ text: String, id: UUID, manual: Bool, streaming: Bool) -> CoachCard? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return nil }
        if trimmed.uppercased().hasPrefix("NADA") { return nil }

        var guide = ""
        var sayConv: String?
        var sayNative = ""
        var keyterms: [String] = []
        var kind: CoachKind = manual ? .manual : .answer

        // Acumula por rótulo até o próximo rótulo (campos podem ter múltiplas linhas).
        let labels = ["GUIA:", "DIGA_CONV:", "DIGA_NATIVE:", "KEYTERMS:", "MODO:"]
        var current: String?
        var buffers: [String: String] = [:]

        for rawLine in trimmed.split(separator: "\n", omittingEmptySubsequences: false) {
            let line = String(rawLine)
            if let label = labels.first(where: { line.uppercased().hasPrefix($0) }) {
                current = label
                let value = String(line.dropFirst(label.count)).trimmingCharacters(in: .whitespaces)
                buffers[label, default: ""] = value
            } else if let current {
                buffers[current, default: ""] += "\n" + line
            }
        }

        func value(_ label: String) -> String {
            buffers[label]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        }

        guide = value("GUIA:")
        let conv = value("DIGA_CONV:")
        sayConv = (conv == "-" || conv.isEmpty) ? nil : conv
        sayNative = value("DIGA_NATIVE:")

        let ktRaw = value("KEYTERMS:")
        if ktRaw != "-" && !ktRaw.isEmpty {
            keyterms = ktRaw
                .split(whereSeparator: { $0 == "·" || $0 == "," || $0 == "\n" })
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }
        }

        let modo = value("MODO:").lowercased()
        if modo.contains("correction") { kind = .correction }
        else if modo.contains("manual") { kind = .manual }
        else if modo.contains("answer") { kind = .answer }

        // Durante streaming, GUIA pode ainda estar vazio — só emite quando há algo útil.
        if streaming && guide.isEmpty && sayNative.isEmpty { return nil }

        return CoachCard(
            id: id,
            guidePT: guide,
            sayConversation: sayConv,
            sayNative: sayNative,
            keytermsConversation: keyterms,
            kind: kind,
            severity: kind == .correction ? .warn : .info,
            isStreaming: streaming
        )
    }
}
