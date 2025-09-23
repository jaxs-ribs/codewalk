import SwiftUI

@main
struct WalkCoachApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
                .preferredColorScheme(.light)
                .statusBar(hidden: true)
        }
    }
}