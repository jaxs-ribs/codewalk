import SwiftUI

@main
struct WalkingComputerApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
                .preferredColorScheme(.light)
                .statusBar(hidden: true)
        }
    }
}