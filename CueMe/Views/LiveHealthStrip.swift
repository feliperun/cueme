import SwiftUI

struct LiveHealthStrip: View {
    @Environment(AppModel.self) private var app
    @State private var showingDetails = false

    var body: some View {
        HStack(spacing: 7) {
            captureButton(
                icon: "mic.fill",
                identifier: "capture.microphone",
                state: app.micCaptureState,
                repair: app.repairMicrophone
            )
            captureButton(
                icon: "headphones",
                identifier: "capture.system",
                state: app.systemCaptureState,
                repair: app.repairSystemCapture
            )
            Button { showingDetails.toggle() } label: {
                HStack(spacing: 7) {
                    ForEach(app.liveHealthItems.filter {
                        $0.subsystem != .microphone && $0.subsystem != .callAudio
                    }) { item in
                        ZStack(alignment: .bottomTrailing) {
                            Image(systemName: item.subsystem.icon)
                                .font(.system(size: 9, weight: .semibold))
                                .foregroundStyle(color(for: item.state).opacity(item.state == .disabled ? 0.35 : 1))
                            Circle().fill(color(for: item.state)).frame(width: 4, height: 4)
                        }
                        .frame(width: 14, height: 16)
                        .help("\(item.subsystem.label): \(item.detail)")
                    }
                }
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("capture.health")
            .popover(isPresented: $showingDetails) {
                VStack(alignment: .leading, spacing: 9) {
                    Text("SAÚDE DA SESSÃO")
                        .font(.system(size: 9, weight: .heavy, design: .rounded)).foregroundStyle(.secondary)
                    ForEach(app.liveHealthItems) { item in
                        HStack(spacing: 8) {
                            Image(systemName: item.subsystem.icon)
                                .frame(width: 15).foregroundStyle(color(for: item.state))
                            VStack(alignment: .leading, spacing: 1) {
                                Text(item.subsystem.label).font(.system(size: 11, weight: .semibold))
                                Text(item.detail).font(.system(size: 9.5)).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Circle().fill(color(for: item.state)).frame(width: 7, height: 7)
                            repairButton(for: item)
                        }
                    }
                }
                .padding(12).frame(width: 310)
            }
        }
    }

    private func captureButton(
        icon: String,
        identifier: String,
        state: CaptureChannelState,
        repair: @escaping () -> Void
    ) -> some View {
        Button {
            if state == .silent || state == .unavailable {
                repair()
            }
        } label: {
            ZStack(alignment: .bottomTrailing) {
                Image(systemName: icon)
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(captureColor(for: state))
                Circle()
                    .fill(captureColor(for: state))
                    .frame(width: 4, height: 4)
            }
            .frame(width: 14, height: 16)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(identifier)
        .accessibilityValue(accessibilityValue(for: state))
        .help(captureHelp(for: state))
    }

    private func accessibilityValue(for state: CaptureChannelState) -> String {
        switch state {
        case .waiting: return "waiting"
        case .active: return "active"
        case .silent: return "silent"
        case .recovering: return "recovering"
        case .unavailable: return "unavailable"
        }
    }

    private func captureColor(for state: CaptureChannelState) -> Color {
        switch state {
        case .active: return Theme.mint
        case .waiting, .recovering: return Theme.amber
        case .silent, .unavailable: return Theme.rose
        }
    }

    private func captureHelp(for state: CaptureChannelState) -> String {
        switch state {
        case .active: return "Canal ativo"
        case .waiting: return "Aguardando sinal"
        case .recovering: return "Reconectando"
        case .silent: return "Sem sinal — clique para reparar"
        case .unavailable: return "Indisponível — clique para reparar"
        }
    }

    @ViewBuilder
    private func repairButton(for item: LiveHealthItem) -> some View {
        if item.state == .failed, item.subsystem == .microphone {
            Button("Reparar", action: app.repairMicrophone).controlSize(.mini)
        } else if item.state == .failed, item.subsystem == .callAudio {
            Button("Reparar", action: app.repairSystemCapture).controlSize(.mini)
        }
    }

    private func color(for state: LiveHealthState) -> Color {
        switch state {
        case .healthy: return Theme.mint
        case .waiting, .recovering: return Theme.amber
        case .failed: return Theme.rose
        case .disabled: return .secondary
        }
    }
}
