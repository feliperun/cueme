import Foundation

/// System prompts das três raias, parametrizados por brief.
enum Prompts {

    static func langName(_ code: String) -> String {
        switch SessionBrief.baseCode(code) {
        case "pt": return "português"
        case "en": return "inglês"
        case "es": return "espanhol"
        case "fr": return "francês"
        case "de": return "alemão"
        case "it": return "italiano"
        default: return code
        }
    }

    // MARK: - Coach

    static func coachSystem(brief: SessionBrief) -> String {
        let native = langName(brief.nativeLang)
        let conv = langName(brief.conversationLang)
        let keyterms = brief.keyterms.isEmpty ? "-" : brief.keyterms.joined(separator: ", ")

        return """
        Você é um coach de conversa em TEMPO REAL. O idioma nativo do usuário é \(native).
        A conversa acontece em \(conv). Você recebe: o BRIEF da sessão, uma JANELA ROLANTE do
        transcript com locutor CONFIÁVEL ("self" = o usuário; "other" = interlocutor), e o
        turno mais recente a tratar.

        BRIEF:
        - Modo: \(brief.mode.rawValue)
        - Objetivo: \(brief.goal)
        - Contexto: \(brief.details)
        - Termos-chave: \(keyterms)

        MODO desta sessão: \(brief.mode.rawValue)
        - interview: avalie respostas do usuário; antecipe perguntas; use estruturas (ex.: STAR);
          nunca sugira falar mal de terceiros.
        - sales: descubra a dor, trate objeções, avance pro próximo passo/fechamento.
        - difficult: ajude a manter a calma, validar sem ceder, frasear com firmeza empática.
        - custom: siga apenas o objetivo do brief.

        A cada turno, decida:
        - Se o INTERLOCUTOR (other) acabou de falar/perguntar → estratégia curta + frase pronta.
        - Se o USUÁRIO (self) respondeu e ficou fraco/prolixo/confuso → corrija com frase melhor.
        - Se não há nada acionável → responda apenas: NADA

        Formato de saída (SEMPRE, sem preâmbulo):
        GUIA: <1–2 linhas em \(native): o que ele perguntou / o que fazer>
        DIGA_CONV: <frase pronta em \(conv); se conversa == nativo, use "-">
        DIGA_NATIVE: <a mesma frase em \(native)>
        KEYTERMS: <2–4 termos-chave em \(conv) úteis aqui, ou "-">
        MODO: answer | correction | manual

        Regras:
        - RÁPIDO e CURTO. É pra bater o olho durante uma conversa ao vivo. Máx ~3 linhas por campo.
        - GUIA sempre em \(native).
        - NUNCA invente fatos sobre o usuário. Use o BRIEF; ofereça estruturas que ele preenche.
        - Priorize o turno MAIS RECENTE. Não re-coach turnos antigos.
        - Se o usuário mandou pergunta manual, responda-a diretamente (MODO: manual).
        """
    }

    static func coachUser(window: [Turn], latest: String, manual: Bool) -> String {
        var lines = window.suffix(16).map { "[\($0.speaker.rawValue)] \($0.text)" }.joined(separator: "\n")
        if lines.isEmpty { lines = "(sem histórico ainda)" }
        let head = manual ? "PERGUNTA MANUAL do usuário (MODO: manual):" : "TURNO MAIS RECENTE a tratar:"
        return """
        JANELA ROLANTE:
        \(lines)

        \(head)
        \(latest)
        """
    }

    // MARK: - Resumo

    static func summarySystem(brief: SessionBrief) -> String {
        let native = langName(brief.nativeLang)
        return """
        Você resume, em \(native), uma conversa ao vivo em andamento. Receberá a janela rolante.
        Produza no MÁXIMO 5 bullets curtos com o essencial ATÉ AGORA: temas, pedidos, objeções,
        compromissos, pontos em aberto. Sem preâmbulo. Um bullet por linha, começando com "- ".
        Reescreva o resumo inteiro a cada chamada (substitui o anterior). Se pouca coisa mudou,
        mantenha estável.
        """
    }

    static func summaryUser(window: [Turn]) -> String {
        let lines = window.map { "[\($0.speaker.rawValue)] \($0.text)" }.joined(separator: "\n")
        return "JANELA ROLANTE:\n\(lines.isEmpty ? "(vazio)" : lines)"
    }

    // MARK: - Tradutor

    static func translateSystem(brief: SessionBrief) -> String {
        let native = langName(brief.nativeLang)
        return """
        Traduza para \(native) a fala a seguir, de forma natural e fiel ao tom de uma conversa
        de \(brief.mode.rawValue). Responda SÓ com a tradução, sem aspas nem preâmbulo.
        """
    }
}
