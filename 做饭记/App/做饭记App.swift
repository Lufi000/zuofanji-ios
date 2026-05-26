import SwiftUI
import SwiftData

// MARK: - App Entry Point

@main
struct 做饭记App: App {

    private let modelContainer: ModelContainer
    @StateObject private var subscriptionStore = SubscriptionStore()

    init() {
        self.modelContainer = RecipeModelContainerFactory.makeContainer()
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(subscriptionStore)
        }
        .modelContainer(modelContainer)
    }
}

// MARK: - SwiftData Container

private enum RecipeModelContainerFactory {

    private static let schema = Schema([Recipe.self])
    private static let storeName = "Recipes.store"

    static func makeContainer() -> ModelContainer {
        do {
            return try ModelContainer(
                for: schema,
                configurations: [persistentConfiguration()]
            )
        } catch {
            print("[SwiftData] Failed to open persistent store: \(error)")
            resetPersistentStore()
        }

        do {
            return try ModelContainer(
                for: schema,
                configurations: [persistentConfiguration()]
            )
        } catch {
            print("[SwiftData] Failed after resetting store, using in-memory store: \(error)")
        }

        do {
            return try ModelContainer(
                for: schema,
                configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)]
            )
        } catch {
            fatalError("Unable to create SwiftData container: \(error)")
        }
    }

    private static func persistentConfiguration() throws -> ModelConfiguration {
        let directory = try applicationSupportDirectory()
        let storeURL = directory.appendingPathComponent(storeName)
        return ModelConfiguration("Recipes", schema: schema, url: storeURL, cloudKitDatabase: .none)
    }

    private static func applicationSupportDirectory() throws -> URL {
        let fileManager = FileManager.default
        let directory = try fileManager.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    private static func resetPersistentStore() {
        guard let storeURL = try? applicationSupportDirectory()
            .appendingPathComponent(storeName) else {
            return
        }

        let fileManager = FileManager.default
        let relatedStoreURLs = [
            storeURL,
            URL(fileURLWithPath: storeURL.path + "-shm"),
            URL(fileURLWithPath: storeURL.path + "-wal")
        ]

        for url in relatedStoreURLs where fileManager.fileExists(atPath: url.path) {
            do {
                try fileManager.removeItem(at: url)
            } catch {
                print("[SwiftData] Failed to remove store file \(url.lastPathComponent): \(error)")
            }
        }
    }
}
