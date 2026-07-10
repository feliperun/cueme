import Foundation

/// Raia de tradução: usa uma sessão persistente (Haiku) — warm após o 1º uso.
/// System prompt do tradutor fica fixo na sessão; aqui só mandamos a fala.
final class TranslationLane: Sendable {
    private let session: ClaudeSession?

    init(session: ClaudeSession?) {
        self.session = session
    }

    /// Traduz uma fala. Retorna nil se não há sessão ou em falha (degrada silencioso).
    func translate(_ text: String) async -> String? {
        guard let session else { return nil }
        let result = try? await session.complete(text)
        guard let result, !result.isEmpty else { return nil }
        return result
    }
}
