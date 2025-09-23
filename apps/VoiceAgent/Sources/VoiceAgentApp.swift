import SwiftUI

@main
struct VoiceAgentApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
                .preferredColorScheme(.light)
                .statusBar(hidden: true)
        }
    }
}