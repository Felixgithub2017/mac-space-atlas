import SwiftUI

@main
struct SpaceAtlasApp: App {
    @StateObject private var model = DiskModel()

    var body: some Scene {
        WindowGroup {
            ContentView(model: model)
                .frame(minWidth: 1020, minHeight: 700)
                .onAppear {
                    if model.phase == .idle { model.startScan(model.home) }
                }
        }
        .windowStyle(.titleBar)
        .defaultSize(width: 1240, height: 820)
    }
}
