import SwiftUI

@main
struct vita3kiosApp: App {
    @State private var core = CoreStatusModel()

    var body: some Scene {
        WindowGroup {
            RootView(core: core)
                .tint(PlayStationAccent.blue)
        }
    }
}
