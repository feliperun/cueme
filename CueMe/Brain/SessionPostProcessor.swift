import Foundation

enum SessionPostProcessorError: LocalizedError {
    case backendUnavailable
    case emptyResponse

    var errorDescription: String? {
        switch self {
        case .backendUnavailable: return "O assistente não está disponível."
        case .emptyResponse: return "O assistente não retornou conteúdo."
        }
    }
}

enum SessionPostProcessor {
    static func generate(
        record: MemoryNote,
        request: String,
        kind: SessionArtifactKind,
        model: CoachModel
    ) async throws -> String {
        let client = ClaudeClient()
        let prompt = """
            PEDIDO:
            \(request)

            MEMÓRIA DA SESSÃO:
            \(SessionMemoryDigest.text(for: record))
            """
        let models: [CoachModel] = model.isDeepSeek ? [model, .sonnet] : [model, .deepseekPro]
        var lastError: Error = SessionPostProcessorError.backendUnavailable
        for candidate in models {
            guard let session = client.makeCoachSession(
                model: candidate,
                system: systemPrompt(language: record.nativeLang, kind: kind)
            ) else { continue }
            do {
                let result = try await session.complete(prompt)
                await session.shutdown()
                guard !result.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                    throw SessionPostProcessorError.emptyResponse
                }
                return result
            } catch {
                lastError = error
                await session.shutdown()
            }
        }
        throw lastError
    }

    private static func systemPrompt(language: String, kind: SessionArtifactKind) -> String {
        let native = Prompts.langName(language)
        let format: String
        switch kind {
        case .review:
            format = """
            Responda SOMENTE JSON válido no formato:
            {"title":"título específico de 3 a 9 palavras","overview":"um parágrafo","topics":[{"title":"Assunto","summary":"mini resumo"}],"decisions":["decisão confirmada"],"actions":["ação pendente com responsável/prazo somente quando explícitos"],"openQuestions":["questão não resolvida"],"followUp":"próximo contato recomendado"}.
            Use no máximo 12 assuntos e separe rigorosamente decisão, ação e dúvida.
            """
        case .summary:
            format = """
            Responda SOMENTE JSON válido: {"overview":"um parágrafo","topics":[{"title":"Assunto","summary":"mini resumo"}]}. Use no máximo 12 assuntos.
            """
        case .takeaways:
            format = "Liste apenas ações ainda pendentes como '- [ ] ação'. Se não houver, responda NENHUMA."
        case .answer, .custom:
            format = "Responda de forma objetiva e organizada; use Markdown simples quando ajudar."
        }
        return """
        Você é um assistente de memória pós-reunião. Responda em \(native) e use SOMENTE
        a memória fornecida. Diferencie fatos, decisões e inferências; nunca invente nomes,
        prazos ou compromissos. \(format)
        """
    }
}
