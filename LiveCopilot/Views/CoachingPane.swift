import SwiftUI

struct CoachingPane: View {
    @Environment(AppModel.self) private var app

    private var cards: [CoachCard] {
        app.coachCards.reversed()   // mais novo no topo
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            PaneHeader(title: "Coach", systemImage: "sparkles")

            if !app.backendAvailable {
                MissingCLIBanner()
            }

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 10) {
                    if cards.isEmpty {
                        Text("As sugestões do coach aparecem aqui quando o interlocutor fala.")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .padding(.top, 4)
                    }
                    ForEach(Array(cards.enumerated()), id: \.element.id) { idx, card in
                        CoachCardView(card: card, highlighted: idx == 0)
                    }
                }
                .padding(12)
            }
        }
    }
}

private struct CoachCardView: View {
    let card: CoachCard
    let highlighted: Bool

    private var accent: Color {
        switch card.kind {
        case .answer: return .green
        case .correction: return .orange
        case .manual: return .indigo
        }
    }

    private var kindLabel: String {
        switch card.kind {
        case .answer: return "Resposta"
        case .correction: return "Correção"
        case .manual: return "Manual"
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Circle().fill(accent).frame(width: 8, height: 8)
                Text(kindLabel).font(.caption.bold()).foregroundStyle(accent)
                if card.isStreaming {
                    ProgressView().controlSize(.small)
                }
                Spacer()
            }

            if !card.guidePT.isEmpty {
                Field(label: "GUIA", text: card.guidePT, mono: false)
            }
            if let conv = card.sayConversation, !conv.isEmpty {
                Field(label: "DIGA", text: conv, mono: false, emphasize: true)
            }
            if !card.sayNative.isEmpty && card.sayConversation != nil {
                Field(label: "↳", text: card.sayNative, mono: false, secondary: true)
            } else if !card.sayNative.isEmpty {
                Field(label: "DIGA", text: card.sayNative, mono: false, emphasize: true)
            }
            if !card.keytermsConversation.isEmpty {
                HStack(spacing: 6) {
                    ForEach(card.keytermsConversation, id: \.self) { term in
                        Text(term)
                            .font(.caption)
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .background(accent.opacity(0.15), in: Capsule())
                    }
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(highlighted ? accent.opacity(0.08) : Color(nsColor: .controlBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(accent.opacity(highlighted ? 0.5 : 0.2), lineWidth: 1)
        )
    }
}

private struct Field: View {
    let label: String
    let text: String
    var mono: Bool = false
    var emphasize: Bool = false
    var secondary: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).font(.caption2.bold()).foregroundStyle(.secondary)
            Text(text)
                .font(emphasize ? .body.weight(.medium) : .callout)
                .foregroundStyle(secondary ? .secondary : .primary)
                .textSelection(.enabled)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct MissingCLIBanner: View {
    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
            Text("Claude Code CLI não encontrado — só transcrição. Instale/logue com `claude`.")
                .font(.caption)
            Spacer()
        }
        .padding(.horizontal, 12).padding(.vertical, 6)
        .background(.orange.opacity(0.12))
    }
}
