import SwiftUI

struct RootView: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        VStack(spacing: 0) {
            HSplitView {
                TranscriptPane()
                    .frame(minWidth: 360)

                VStack(spacing: 0) {
                    SummaryPane()
                        .frame(minHeight: 120, maxHeight: 220)
                    Divider()
                    CoachingPane()
                        .frame(maxHeight: .infinity)
                }
                .frame(minWidth: 360)
            }
            .frame(maxHeight: .infinity)

            Divider()
            ControlsBar()
        }
        .background(.background)
    }
}

#Preview {
    RootView().environment(AppModel())
}
