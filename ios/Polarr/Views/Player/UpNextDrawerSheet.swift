import SwiftUI
import SwiftData

public struct UpNextDrawerSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Bindable var audioManager = AudioManager.shared

    @Query(sort: \QueueEpisodeItem.position, order: .forward)
    private var queuedItems: [QueueEpisodeItem]

    public init() {}

    public var body: some View {
        NavigationStack {
            ZStack {
                BrandTheme.bgPrimary.ignoresSafeArea()

                VStack(spacing: 0) {
                    if queuedItems.isEmpty {
                        Spacer()
                        VStack(spacing: 12) {
                            Image(systemName: "tray")
                                .font(.system(size: 40))
                                .foregroundStyle(BrandTheme.textMuted)
                            Text("Up Next is empty")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundStyle(Color.white)
                            Text("Swipe right on episodes in any podcast to add them to your queue.")
                                .font(.system(size: 13))
                                .foregroundStyle(BrandTheme.textSecondary)
                                .multilineTextAlignment(.center)
                                .padding(.horizontal, 32)
                        }
                        Spacer()
                    } else {
                        List {
                            ForEach(queuedItems) { item in
                                HStack(spacing: 12) {
                                    AsyncArtworkView(urlString: item.podcastArtworkUrl, size: 44, cornerRadius: 8)

                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(item.episodeTitle)
                                            .font(.system(size: 14, weight: .semibold))
                                            .foregroundStyle(Color.white)
                                            .lineLimit(1)
                                        Text(item.podcastTitle)
                                            .font(.system(size: 12))
                                            .foregroundStyle(BrandTheme.textSecondary)
                                            .lineLimit(1)
                                    }

                                    Spacer()

                                    Button {
                                        playQueuedItem(item)
                                        dismiss()
                                    } label: {
                                        Image(systemName: "play.circle.fill")
                                            .font(.system(size: 24))
                                            .foregroundStyle(audioManager.currentPalette.accent)
                                    }
                                    .buttonStyle(.plain)
                                }
                                .padding(.vertical, 4)
                                .listRowBackground(BrandTheme.bgSecondary)
                            }
                            .onDelete(perform: deleteQueueItems)
                            .onMove(perform: moveQueueItems)
                        }
                        .listStyle(.plain)
                        .scrollContentBackground(.hidden)
                    }
                }
            }
            .navigationTitle("Up Next")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    EditButton()
                        .foregroundStyle(Color.white)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                    .foregroundStyle(Color.white)
                }
            }
        }
    }

    private func deleteQueueItems(at offsets: IndexSet) {
        for idx in offsets {
            let item = queuedItems[idx]
            modelContext.delete(item)
        }
        reindexQueue()
    }

    private func moveQueueItems(from source: IndexSet, to destination: Int) {
        var items = queuedItems
        items.move(fromOffsets: source, toOffset: destination)
        for (i, item) in items.enumerated() {
            item.position = i
        }
        try? modelContext.save()
    }

    private func reindexQueue() {
        try? modelContext.save()
        let desc = FetchDescriptor<QueueEpisodeItem>(sortBy: [SortDescriptor(\.position, order: .forward)])
        if let remaining = try? modelContext.fetch(desc) {
            for (i, item) in remaining.enumerated() {
                item.position = i
            }
            try? modelContext.save()
        }
    }

    private func playQueuedItem(_ item: QueueEpisodeItem) {
        guard let enc = item.enclosureUrl, !enc.isEmpty else { return }
        let playable = PlayableEpisode(
            podcastId: item.podcastId,
            podcastTitle: item.podcastTitle,
            podcastArtworkUrl: item.podcastArtworkUrl,
            episodeGuid: item.episodeGuid,
            episodeTitle: item.episodeTitle,
            enclosureUrl: enc,
            durationSecs: item.durationSecs
        )
        audioManager.play(episode: playable, startAt: Double(item.progressSecs))
    }
}
