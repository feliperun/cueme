import CryptoKit
import Foundation

/// Building and parsing the preflight glossary for a meeting context:
/// which terms are worth keeping, how a model response is parsed, and how
/// the request is shaped. Split out of `MeetingContext`, which is the
/// context value and its store.
enum GlossaryTermPolicy {
    static let maximumTerms = 100
    static let maximumTokens = 500
    static let maximumCharactersPerTerm = 120

    static func sanitized(_ rawTerms: [String]) -> [String] {
        var result: [String] = []
        var seen: Set<String> = []
        var tokenCount = 0

        for raw in rawTerms {
            let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            let bounded = String(trimmed.prefix(maximumCharactersPerTerm))
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let identity = bounded.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            guard !bounded.isEmpty, seen.insert(identity).inserted else { continue }

            let termTokens = estimatedTokenCount(bounded)
            guard tokenCount + termTokens <= maximumTokens else { continue }
            result.append(bounded)
            tokenCount += termTokens
            if result.count == maximumTerms { break }
        }
        return result
    }

    /// Conservative local estimate. The provider tokenizer is not public, so
    /// short word pieces are counted at roughly one token per four UTF-8 bytes.
    static func estimatedTokenCount(_ terms: [String]) -> Int {
        terms.reduce(0) { $0 + estimatedTokenCount($1) }
    }

    static func estimatedTokenCount(_ text: String) -> Int {
        text.split(whereSeparator: { $0.isWhitespace }).reduce(0) { count, piece in
            count + max(1, (piece.utf8.count + 3) / 4)
        }
    }
}

enum ContextGlossaryParser {
    static func parse(_ response: String) -> [String] {
        let trimmed = response
            .replacingOccurrences(of: "```json", with: "")
            .replacingOccurrences(of: "```", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        if let terms = decodeTerms(trimmed) {
            return GlossaryTermPolicy.sanitized(terms)
        }
        if let start = trimmed.firstIndex(of: "["), let end = trimmed.lastIndex(of: "]"), start < end,
           let terms = decodeTerms(String(trimmed[start...end])) {
            return GlossaryTermPolicy.sanitized(terms)
        }

        let fallback = trimmed
            .components(separatedBy: .newlines)
            .flatMap { $0.components(separatedBy: ";") }
            .map {
                $0.replacingOccurrences(
                    of: #"^\s*(?:[-*•]|\d+[.)])\s*"#,
                    with: "",
                    options: .regularExpression
                )
                .trimmingCharacters(in: CharacterSet.whitespacesAndNewlines.union(CharacterSet(charactersIn: "\"'")))
            }
        return GlossaryTermPolicy.sanitized(fallback)
    }

    private static func decodeTerms(_ value: String) -> [String]? {
        guard let data = value.data(using: .utf8) else { return nil }
        if let terms = try? JSONDecoder().decode([String].self, from: data) { return terms }
        if let object = try? JSONDecoder().decode([String: [String]].self, from: data) {
            return object["terms"] ?? object["keyterms"]
        }
        return nil
    }
}

enum ContextGlossaryRequest {
    static func signature(contexts: [MeetingContext], brief: SessionBrief, model: CoachModel) -> String {
        let contextBlock = contexts
            .sorted { $0.id.uuidString < $1.id.uuidString }
            .map { "\($0.id.uuidString)\n\($0.name)\n\($0.content)" }
            .joined(separator: "\n---\n")
        let payload = [
            model.rawValue,
            brief.mode.rawValue,
            brief.conversationLang,
            brief.goal,
            brief.details,
            brief.keyterms.joined(separator: "\n"),
            brief.cv ?? "",
            contextBlock,
        ].joined(separator: "\n===\n")
        return SHA256.hash(data: Data(payload.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    static func prompt(contexts: [MeetingContext], brief: SessionBrief) -> String {
        let sources = contexts.map { context in
            "## \(context.name)\n\(String(context.content.prefix(16_000)))"
        }.joined(separator: "\n\n")
        let cv = brief.cv.map { String($0.prefix(8_000)) } ?? "(não informado)"
        let existing = brief.keyterms.isEmpty ? "(nenhum)" : brief.keyterms.joined(separator: ", ")
        return """
        Prepare o glossário para uma transcrição de reunião em \(brief.conversationLang).

        OBJETIVO: \(brief.goal)
        DETALHES: \(brief.details)
        TERMOS JÁ INFORMADOS: \(existing)

        CONTEXTOS SELECIONADOS:
        \(String(sources.prefix(40_000)))

        CV OPCIONAL:
        \(cv)

        Retorne SOMENTE um array JSON de strings, sem markdown. Busque 100 termos
        relevantes entre nomes próprios, pessoas, empresas, produtos, siglas, tecnologias e frases
        técnicas que provavelmente serão faladas e que um STT poderia errar.
        Preserve a grafia/capitalização canônica. Não inclua palavras comuns,
        explicações ou variantes duplicadas. Use menos de 100 somente quando as
        fontes não sustentarem mais termos úteis. O total deve ficar abaixo de 500 tokens.
        """
    }
}
