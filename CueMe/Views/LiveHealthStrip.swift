import SwiftUI

struct LiveHealthStrip: View {
    @Environment(AppModel.self) private var app
    @State private var showingDetails = false

    var body: some View {
        Button { showingDetails.toggle() } label: {
            HStack(spacing: 7) {
                ForEach(app.liveHealthItems) { item in
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

