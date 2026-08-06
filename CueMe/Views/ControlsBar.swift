import SwiftUI

/// Só aparece quando há degradação. Poucas palavras + ação direta.
struct CaptureHealthAlert: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        if app.isRunning, let issue {
            Button(action: issue.repair) {
                HStack(spacing: 7) {
                    Image(systemName: issue.icon)
                    Text(issue.label)
                        .font(.system(size: 11.5, weight: .bold, design: .rounded))
                    Spacer()
                    Image(systemName: "arrow.clockwise")
                }
                .foregroundStyle(issue.color)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(issue.color.opacity(0.12), in: Capsule())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("capture.alert")
            .padding(.horizontal, 12)
            .padding(.bottom, 4)
        }
    }

    private var issue: (label: String, icon: String, color: Color, repair: () -> Void)? {
        if app.runtimeHealth.level == .critical,
           let reason = app.runtimeHealth.reason,
           app.micCaptureState != .silent,
           app.micCaptureState != .unavailable,
           app.systemCaptureState != .unavailable {
            return (reason.uppercased(), "exclamationmark.triangle.fill", Theme.rose, {})
        }
        switch app.micCaptureState {
        case .silent: return ("MIC SEM SINAL", "mic.slash.fill", Theme.rose, app.repairMicrophone)
        case .unavailable: return ("MIC DESCONECTADO", "mic.slash.fill", Theme.rose, app.repairMicrophone)
        case .recovering: return ("RECUPERANDO MIC", "arrow.clockwise", Theme.amber, {})
        default: break
        }
        switch app.systemCaptureState {
        case .unavailable: return ("ÁUDIO EXTERNO OFF", "headphones", Theme.amber, app.repairSystemCapture)
        case .recovering: return ("RECONECTANDO ÁUDIO", "arrow.clockwise", Theme.amber, {})
        default: return nil
        }
    }
}

/// Campo de pergunta manual, colado na base.
struct InputBar: View {
    @Environment(AppModel.self) private var app
    @FocusState private var focused: Bool
    @State private var expanded = false

    var body: some View {
        @Bindable var app = app

        Group {
            if expanded {
                HStack(spacing: 8) {
                    Image(systemName: "sparkle")
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.cyan.opacity(0.8))
                    TextField("Pergunte ao coach", text: $app.manualInput)
                        .textFieldStyle(.plain)
                        .font(.system(size: 13))
                        .focused($focused)
                        .onSubmit { app.ask(); expanded = false }
                    Button {
                        app.ask()
                        expanded = false
                    } label: {
                        Image(systemName: "arrow.up")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(Color.black.opacity(0.85))
                            .frame(width: 22, height: 22)
                            .background(Theme.brand, in: Circle())
                            .opacity(sendDisabled ? 0.3 : 1)
                    }
                    .buttonStyle(.plain)
                    .disabled(sendDisabled)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Color.white.opacity(0.05), in: Capsule())
                .overlay(
                    Capsule().strokeBorder(
                        focused ? Theme.cyan.opacity(0.5) : Theme.surfaceStroke,
                        lineWidth: 1
                    )
                )
            } else {
                Button {
                    expanded = true
                    focused = true
                } label: {
                    Label("Perguntar", systemImage: "sparkle")
                        .font(.system(size: 10.5, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(Color.white.opacity(0.04), in: Capsule())
                }
                .buttonStyle(.plain)
                .keyboardShortcut("k", modifiers: [.command])
            }
        }
        .padding(.horizontal, 12)
        .padding(.bottom, 10)
    }

    private var sendDisabled: Bool {
        app.manualInput.trimmingCharacters(in: .whitespaces).isEmpty || !app.isRunning
    }
}
