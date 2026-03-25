import SwiftUI
import SwiftData

// MARK: - App Entry Point

@main
struct 做饭记App: App {

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .modelContainer(for: Recipe.self)
    }
}
