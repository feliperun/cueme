import Foundation

/// Raia de resumo: sessão persistente (Haiku), fora do caminho crítico.
final class SummaryLane: Sendable {
    private let session: ClaudeSession?

    init(session: ClaudeSession?) {
        self.session = session
    }

    /// Resume a janela. Retorna nil se não há sessão/janela vazia/erro.
    func summarize(window: [Turn]) async -> [String]? {
        guard let session, !window.isEmpty else { return nil }
        guard let text = try? await session.complete(Prompts.summaryUser(window: window)) else {
            return nil
        }
        let bullets = text
            .split(separator: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .map { line -> String in
                var l = line
                while l.hasPrefix("-") || l.hasPrefix("•") || l.hasPrefix("*") {
                    l = String(l.dropFirst()).trimmingCharacters(in: .whitespaces)
                }
                // Remove markdown bold/itálico residual (**texto**, *texto*).
                l = l.replacingOccurrences(of: "**", with: "")
                return l.trimmingCharacters(in: .whitespaces)
            }
            .filter { !$0.isEmpty }
        return Array(bullets.prefix(5))
    }
}
