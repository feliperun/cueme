import SwiftUI

struct SummaryPane: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            PaneHeader(title: "Resumo", systemImage: "list.bullet.rectangle")

            ScrollView {
                VStack(alignment: .leading, spacing: 6) {
                    if app.summaryBullets.isEmpty {
                        Text("O resumo aparece aqui a cada ~30s de conversa.")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(Array(app.summaryBullets.enumerated()), id: \.offset) { _, bullet in
                            HStack(alignment: .top, spacing: 6) {
                                Text("•").foregroundStyle(.secondary)
                                Text(bullet).textSelection(.enabled)
                            }
                            .font(.callout)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(12)
            }
        }
    }
}
