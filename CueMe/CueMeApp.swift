import SwiftUI
import AppKit

@main
struct CueMeApp: App {
    @State private var app = AppModel()
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(app)
                .frame(minWidth: 380, minHeight: 520)
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 460, height: 720)
        .commands {
            CommandGroup(after: .windowArrangement) {
                Button("Mostrar/Ocultar CueMe") { HotkeyManager.toggleMainWindow() }
                    .keyboardShortcut(.space, modifiers: [.option])
            }
        }

        MenuBarExtra("CueMe", systemImage: app.isRunning ? "waveform.badge.mic" : "waveform") {
            MenuBarContent().environment(app)
        }
    }
}

/// Instala o atalho global ⌥Space no launch.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let hotkeys = HotkeyManager()

    func applicationDidFinishLaunching(_ notification: Notification) {
        hotkeys.onToggle = { HotkeyManager.toggleMainWindow() }
        hotkeys.start()
    }
}

/// Conteúdo do menu na barra: status + controles rápidos.
private struct MenuBarContent: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        Text(app.isRunning ? "● Ao vivo" : "○ Pronto")

        Button(app.isRunning ? "Parar" : "Iniciar") {
            app.isRunning ? app.stop() : app.start()
        }
        Button("Mostrar / Ocultar") { HotkeyManager.toggleMainWindow() }
            .keyboardShortcut(.space, modifiers: [.option])

        if app.isRunning {
            Toggle("Modo silêncio", isOn: Binding(get: { app.silenceMode }, set: { _ in app.toggleSilence() }))
            if !app.systemCaptureActive {
                Button("Corrigir captura do interlocutor…") { app.openScreenRecordingSettings() }
            }
        }

        Divider()
        Button("Sair") { NSApp.terminate(nil) }
            .keyboardShortcut("q")
    }
}
