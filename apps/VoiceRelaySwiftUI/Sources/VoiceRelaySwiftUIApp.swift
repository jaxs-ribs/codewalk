import SwiftUI

/// Entry point. Sets up dark theme and navigation bar appearance.
@main
struct VoiceRelaySwiftUIApp: App {
  init() {
    // Set up appearance for the entire app
    UINavigationBar.appearance().largeTitleTextAttributes = [.foregroundColor: UIColor.white]
    UINavigationBar.appearance().titleTextAttributes = [.foregroundColor: UIColor.white]
    UINavigationBar.appearance().backgroundColor = .clear
    UINavigationBar.appearance().barTintColor = .clear
    UINavigationBar.appearance().setBackgroundImage(UIImage(), for: .default)
    UINavigationBar.appearance().shadowImage = UIImage()
  }
  
  var body: some Scene {
    WindowGroup {
      ContentView()
        .preferredColorScheme(.dark)
        .statusBar(hidden: false)
    }
  }
}

