import SwiftUI
import SwiftData

@main
public struct PolarrApp: App {
    public let sharedModelContainer: ModelContainer

    public init() {
        let schema = Schema([
            PodcastItem.self,
            NewEpisodeItem.self,
            QueueEpisodeItem.self,
            JournalEntryItem.self,
            ChapterBookmarkItem.self,
        ])
        let modelConfiguration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)

        do {
            sharedModelContainer = try ModelContainer(for: schema, configurations: [modelConfiguration])
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }
    }

    public var body: some Scene {
        WindowGroup {
            ContentView()
                .preferredColorScheme(.dark)
        }
        .modelContainer(sharedModelContainer)
    }
}
