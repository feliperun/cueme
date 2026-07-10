import SwiftUI

@main
struct LiveCopilotApp: App {
    @State private var app = AppModel()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(app)
                .frame(minWidth: 900, minHeight: 560)
        }
        .windowStyle(.titleBar)
        .defaultSize(width: 1120, height: 720)
    }
}
