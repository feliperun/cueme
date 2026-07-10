import SwiftUI

struct TranscriptPane: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            PaneHeader(title: "Transcrição ao vivo", systemImage: "waveform")

            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 10) {
                        ForEach(app.transcript) { line in
                            TranscriptRow(line: line)
                                .id(line.id)
                        }
                    }
                    .padding(12)
                }
                .onChange(of: app.transcript.count) { _, _ in
                    if let last = app.transcript.last {
                        withAnimation(.easeOut(duration: 0.15)) {
                            proxy.scrollTo(last.id, anchor: .bottom)
                        }
                    }
                }
            }
        }
    }
}

private struct TranscriptRow: View {
    let line: TranscriptLine

    private var color: Color {
        line.speaker == .self ? .blue : .purple
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 6) {
                Text(line.speaker.label)
                    .font(.caption.bold())
                    .foregroundStyle(color)
                if !line.isFinal {
                    Text("…")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Text(line.text)
                .foregroundStyle(line.isFinal ? .primary : .secondary)
                .italic(!line.isFinal)
                .textSelection(.enabled)

            if let translation = line.translation, !translation.isEmpty {
                HStack(alignment: .top, spacing: 4) {
                    Text("↳")
                        .foregroundStyle(.secondary)
                    Text(translation)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
                .font(.callout)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct PaneHeader: View {
    let title: String
    let systemImage: String

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: systemImage)
            Text(title).font(.headline)
            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.quaternary.opacity(0.5))
    }
}
