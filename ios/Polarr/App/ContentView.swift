import SwiftUI
import SwiftData

public struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \QueueEpisodeItem.position) private var queueItems: [QueueEpisodeItem]

    @State private var selectedTab: TabItem = .inbox
    @State private var showFullPlayer: Bool = false
    @State private var showSettingsSheet: Bool = false

    @Bindable var audioManager = AudioManager.shared
    @Bindable var syncManager = SyncManager.shared

    public enum TabItem: Int {
        case inbox = 0
        case library = 1
        case queue = 2
        case journal = 3
        case search = 4
    }

    public init() {}

    public var body: some View {
        ZStack(alignment: .bottom) {
            TabView(selection: $selectedTab) {
                InboxView()
                    .tabItem {
                        Label("Inbox", systemImage: "tray.fill")
                    }
                    .tag(TabItem.inbox)

                LibraryView()
                    .tabItem {
                        Label("Library", systemImage: "square.grid.2x2.fill")
                    }
                    .tag(TabItem.library)

                QueueView()
                    .tabItem {
                        Label("Queue", systemImage: "list.bullet.rectangle.portrait.fill")
                    }
                    .tag(TabItem.queue)

                JournalView()
                    .tabItem {
                        Label("Journal", systemImage: "book.pages.fill")
                    }
                    .tag(TabItem.journal)

                SearchView()
                    .tabItem {
                        Label("Discover", systemImage: "magnifyingglass")
                    }
                    .tag(TabItem.search)
            }
            .tint(BrandTheme.cyan)

            // Floating Mini Player above TabBar
            VStack {
                Spacer()
                MiniPlayerBar(showFullPlayer: $showFullPlayer)
                    .padding(.bottom, 50) // float above native tab bar
            }
            .ignoresSafeArea(.keyboard)
        }
        .fullScreenCover(isPresented: $showFullPlayer) {
            NowPlayingView()
        }
        .sheet(isPresented: $showSettingsSheet) {
            SettingsView()
        }
        .onAppear {
            setupAudioFinishedHook()
            if APIClient.shared.apiKey.isEmpty {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    showSettingsSheet = true
                }
            }
            Task(priority: .utility) {
                await syncManager.sync(modelContext: modelContext)
            }
        }
    }

    private func setupAudioFinishedHook() {
        audioManager.onEpisodeFinished = { [self] finishedEpisode, timeListened in
            SyncManager.shared.recordPlaybackFinished(
                episode: finishedEpisode,
                timeListened: timeListened,
                completionType: "finished",
                modelContext: modelContext
            )

            // Auto-advance to next episode in Queue if available
            advanceToNextInQueue(after: finishedEpisode.episodeGuid)
        }
    }

    private func advanceToNextInQueue(after currentGuid: String) {
        let remaining = queueItems.filter { $0.episodeGuid != currentGuid }
        if let nextItem = remaining.first, let enc = nextItem.enclosureUrl, !enc.isEmpty {
            let nextEp = PlayableEpisode(
                podcastId: nextItem.podcastId,
                podcastTitle: nextItem.podcastTitle,
                podcastArtworkUrl: nextItem.podcastArtworkUrl,
                episodeGuid: nextItem.episodeGuid,
                episodeTitle: nextItem.episodeTitle,
                enclosureUrl: enc,
                durationSecs: nextItem.durationSecs
            )
            audioManager.play(episode: nextEp, startAt: Double(nextItem.progressSecs))
        }
    }
}
