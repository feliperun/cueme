import SwiftUI

/// Persistent post-meeting Q&A composer at the foot of a note. Answers are
/// grounded in this note's session.json (transcript, minutes, cards) and persist
/// as `.answer` artifacts. Violet = agent (mint stays exclusive to live coach).
struct AskCueMeBar: View {
    @Environment(AppModel.self) private var app
    let record: SessionRecord
    @Binding var tab: SessionWorkspaceTab

    private var answers: [SessionArtifact] {
        record.artifacts.filter { $0.kind == .answer }
    }
    private var isAnswering: Bool { app.postProcessingSessionID == record.id }

    var body: some View {
        VStack(spacing: 0) {
            Rectangle().fill(Theme.line2).frame(height: 1)
            VStack(spacing: 10) {
                if let latest = answers.last {
                    answerCard(latest)
                }
                composer
            }
            .frame(maxWidth: 700)
            .padding(.horizontal, 26).padding(.vertical, 12)
            .frame(maxWidth: .infinity)
        }
        .background(Theme.paper)
    }

    private var composer: some View {
        @Bindable var app = app
        return HStack(spacing: 9) {
            Image(systemName: "sparkles").font(.system(size: 12)).foregroundStyle(Theme.violet)
            TextField(
                "Pergunte ao CueMe sobre esta nota — esclareça, melhore, resuma…",
                text: $app.postSessionPrompt
            )
            .textFieldStyle(.plain).font(.ui(13))
            .accessibilityIdentifier("ask.input")
            .onSubmit { app.askAboutSession(record.id) }
            if isAnswering { ProgressView().controlSize(.small) }
            Button { app.askAboutSession(record.id) } label: {
                Text("Ask").font(.ui(11, .semibold)).foregroundStyle(.white)
                    .padding(.horizontal, 12).padding(.vertical, 4)
                    .background(Theme.violet, in: RoundedRectangle(cornerRadius: 6))
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("ask.submit")
            .disabled(isAnswering || app.postSessionPrompt.trimmingCharacters(in: .whitespaces).isEmpty)
        }
        .padding(.horizontal, 12).frame(height: 40)
        .background(Theme.canvas, in: RoundedRectangle(cornerRadius: 9))
        .overlay(RoundedRectangle(cornerRadius: 9).strokeBorder(Theme.line))
    }

    private func answerCard(_ artifact: SessionArtifact) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 10) {
                Text("You").font(.ui(11, .semibold)).foregroundStyle(Theme.violet).frame(width: 46, alignment: .leading)
                Text(artifact.title).font(.ui(14)).foregroundStyle(Theme.ink)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Rectangle().fill(Theme.line2).frame(height: 1)
            HStack(alignment: .top, spacing: 10) {
                Text("CueMe").font(.ui(11, .semibold)).foregroundStyle(Theme.violetDeep).frame(width: 46, alignment: .leading)
                VStack(alignment: .leading, spacing: 9) {
                    Text(.init(artifact.body)).font(.read(15)).foregroundStyle(Theme.ink)
                        .textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("ask.answer")
                    HStack(spacing: 6) {
                        if record.containsRecording {
                            chip("▶ Transcrição", filled: false) { tab = .transcript }
                            chip("Minutes", filled: false) { tab = .summary }
                        }
                        Spacer(minLength: 8)
                        chip("Inserir como bloco", filled: true) { insertAsBlock(artifact.body) }
                        chip("Rascunhar e-mail", filled: false) {
                            Task { await app.generateFollowUp(for: record.id, format: .email) }
                        }
                    }
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.canvas, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Theme.line))
    }

    private func chip(_ title: String, filled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title).font(.ui(10.5, filled ? .semibold : .regular))
                .foregroundStyle(filled ? .white : Theme.ink2)
                .padding(.horizontal, 9).padding(.vertical, 3)
                .background {
                    if filled {
                        RoundedRectangle(cornerRadius: 6).fill(Theme.violet)
                    } else {
                        RoundedRectangle(cornerRadius: 6).strokeBorder(Theme.line)
                    }
                }
        }
        .buttonStyle(.plain)
    }

    private func insertAsBlock(_ answer: String) {
        let base = record.markdownBody.trimmingCharacters(in: .whitespacesAndNewlines)
        let joined = base.isEmpty ? answer : base + "\n\n" + answer
        app.updateMarkdownBody(record.id, body: joined)
    }
}
