import SwiftUI

struct ControlsBar: View {
    @Environment(AppModel.self) private var app

    private let langs = ["pt-BR", "en-US", "es-ES", "fr-FR", "de-DE", "it-IT"]

    var body: some View {
        @Bindable var app = app

        VStack(spacing: 8) {
            HStack(spacing: 12) {
                Picker("Modo", selection: $app.brief.mode) {
                    ForEach(Mode.allCases) { Text($0.label).tag($0) }
                }
                .frame(width: 180)

                Picker("Conversa", selection: $app.brief.conversationLang) {
                    ForEach(langs, id: \.self) { Text($0).tag($0) }
                }
                .frame(width: 140)

                Picker("Nativo", selection: $app.brief.nativeLang) {
                    ForEach(langs, id: \.self) { Text($0).tag($0) }
                }
                .frame(width: 140)

                Picker("STT", selection: $app.sttSource) {
                    ForEach(SttSource.allCases) { Text($0.label).tag($0) }
                }
                .frame(width: 190)
                .disabled(app.isRunning)

                Spacer()

                Text(app.statusText)
                    .font(.caption)
                    .foregroundStyle(app.isRunning ? .green : .secondary)

                Button(app.isRunning ? "Parar" : "Iniciar") {
                    app.isRunning ? app.stop() : app.start()
                }
                .keyboardShortcut(.return, modifiers: [.command])
                .buttonStyle(.borderedProminent)
                .tint(app.isRunning ? .red : .accentColor)

                Toggle(isOn: Binding(get: { app.silenceMode }, set: { _ in app.toggleSilence() })) {
                    Label("Silêncio", systemImage: app.silenceMode ? "speaker.slash" : "speaker.wave.2")
                }
                .toggleStyle(.button)
                .help("Pausa o coach, mantém a transcrição")
            }

            HStack(spacing: 8) {
                Image(systemName: "text.bubble")
                    .foregroundStyle(.secondary)
                TextField("Dúvida no meio da conversa → coach (Sonnet)…", text: $app.manualInput)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit { app.ask() }
                Button("Perguntar") { app.ask() }
                    .disabled(app.manualInput.trimmingCharacters(in: .whitespaces).isEmpty || !app.isRunning)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.bar)
    }
}
