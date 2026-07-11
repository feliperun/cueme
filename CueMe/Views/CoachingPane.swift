import SwiftUI
import AppKit

/// A dica do "amigo do lado" — herói da tela. Card mais novo grande, resto condensado.
struct CoachingPane: View {
    @Environment(AppModel.self) private var app

    private var cards: [CoachCard] {
        app.coachCards.reversed()   // mais novo primeiro
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if !app.backendAvailable {
                MissingCLIBanner()
            }

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 8) {
                    if cards.isEmpty {
                        EmptyCoachHint()
                    }
                    ForEach(Array(cards.enumerated()), id: \.element.id) { idx, card in
                        if idx == 0 {
                            HeroCard(card: card, convLang: app.brief.conversationLang, keyterms: app.brief.keyterms)
                                .transition(.opacity.combined(with: .scale(scale: 0.97)))
                        } else {
                            CondensedCard(card: card)
                        }
                    }
                }
                .padding(12)
                .animation(.spring(duration: 0.35), value: cards.first?.id)
            }
        }
    }
}

/// Card principal: **o que dizer AGORA** é o herói (maior). GUIA é contexto curto.
private struct HeroCard: View {
    let card: CoachCard
    let convLang: String
    let keyterms: [String]

    private var accent: Color {
        switch card.kind {
        case .answer: return Theme.mint
        case .correction: return Theme.amber
        case .manual: return Theme.violet
        }
    }

    private var phrase: String? {
        let p = card.sayConversation ?? (card.sayNative.isEmpty ? nil : card.sayNative)
        return (p?.isEmpty ?? true) ? nil : p
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Contexto curto (GUIA) — orienta em 1 linha.
            if !card.guidePT.isEmpty {
                HStack(alignment: .top, spacing: 6) {
                    Text("🎯").font(.system(size: 12))
                    Text(card.guidePT)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            // HERÓI: a frase pronta pra falar. Grande, com realce e copiar.
            if let say = phrase {
                VStack(alignment: .leading, spacing: 7) {
                    HStack(alignment: .top, spacing: 9) {
                        Text("🗣️").font(.system(size: 19))
                        Text(highlighted(say))
                            .lineSpacing(2)
                            .textSelection(.enabled)
                            .fixedSize(horizontal: false, vertical: true)
                        Spacer(minLength: 0)
                        CopyButton(text: say, accent: accent)
                    }
                    if card.sayConversation != nil, !card.sayNative.isEmpty {
                        Text(card.sayNative)
                            .font(.system(size: 12.5))
                            .foregroundStyle(.secondary)
                            .padding(.leading, 28)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(accent.opacity(0.1), in: RoundedRectangle(cornerRadius: 12))
                .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(accent.opacity(0.32), lineWidth: 1))
            }

            if !card.keytermsConversation.isEmpty {
                HStack(spacing: 5) {
                    ForEach(card.keytermsConversation.prefix(4), id: \.self) { term in
                        Text(term)
                            .font(.system(size: 10.5, weight: .semibold, design: .monospaced))
                            .foregroundStyle(accent)
                            .lineLimit(1)
                            .padding(.horizontal, 7).padding(.vertical, 3)
                            .background(accent.opacity(0.12), in: Capsule())
                            .overlay(Capsule().strokeBorder(accent.opacity(0.3), lineWidth: 1))
                    }
                }
            }

            // Estado inicial: frame instantâneo enquanto os tokens chegam.
            if card.isStreaming, phrase == nil, card.guidePT.isEmpty {
                HStack(spacing: 7) {
                    ProgressView().controlSize(.small)
                    Text("preparando sua deixa…")
                        .font(.system(size: 13, design: .rounded))
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 4)
            } else if card.isStreaming {
                HStack(spacing: 5) {
                    ProgressView().controlSize(.mini)
                    Text("…").font(.system(size: 11)).foregroundStyle(.secondary)
                }
            }
        }
        .padding(13)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(accent.opacity(0.45), lineWidth: 1.5))
        .shadow(color: accent.opacity(0.18), radius: 14, y: 4)
    }

    /// Realça a frase (língua da conversa) — termos-chave/nomes/números destacam.
    private func highlighted(_ say: String) -> AttributedString {
        if card.sayConversation != nil {
            return Highlighter.translation(say, native: convLang, keyterms: keyterms, base: 17)
        }
        var a = AttributedString(say)
        a.font = .system(size: 17, weight: .semibold)
        return a
    }
}

/// Botão de copiar a frase (1 clique → área de transferência).
private struct CopyButton: View {
    let text: String
    let accent: Color
    @State private var copied = false

    var body: some View {
        Button {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(text, forType: .string)
            copied = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.4) { copied = false }
        } label: {
            Image(systemName: copied ? "checkmark" : "doc.on.doc")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(copied ? Theme.mint : accent)
                .frame(width: 26, height: 26)
                .background(accent.opacity(0.12), in: RoundedRectangle(cornerRadius: 7))
        }
        .buttonStyle(.plain)
        .help("Copiar a frase")
    }
}

/// Cards antigos: uma linha só, fora do caminho.
private struct CondensedCard: View {
    let card: CoachCard

    private var line: String {
        let say = card.sayConversation ?? card.sayNative
        return say.isEmpty ? card.guidePT : say
    }

    var body: some View {
        Text(line)
            .font(.system(size: 11.5))
            .foregroundStyle(.secondary)
            .lineLimit(2)
            .padding(.horizontal, 10).padding(.vertical, 6)
            .frame(maxWidth: .infinity, alignment: .leading)
            .glassPanel(cornerRadius: 9)
            .opacity(0.75)
    }
}

private struct EmptyCoachHint: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text("👋")
                .font(.system(size: 26))
            Text("Sou teu amigo do lado.")
                .font(.system(size: 15, weight: .bold, design: .rounded))
            Text("Quando o interlocutor falar, eu cochicho aqui: o que dizer e as palavras certas.")
                .font(.system(size: 12.5))
                .foregroundStyle(.secondary)
                .lineSpacing(1.5)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassPanel()
    }
}

private struct MissingCLIBanner: View {
    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(Theme.amber)
            Text("Claude Code CLI não encontrado — só transcrição.")
                .font(.system(size: 11))
            Spacer()
        }
        .padding(.horizontal, 12).padding(.vertical, 7)
        .background(Theme.amber.opacity(0.12))
    }
}
