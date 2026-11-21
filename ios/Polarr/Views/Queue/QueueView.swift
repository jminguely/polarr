import SwiftUI
import SwiftData

public struct QueueView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \QueueEpisodeItem.position) private var queueItems: [QueueEpisodeItem]

    @Bindable var audioManager = AudioManager.shared
    @Bindable var syncManager = SyncManager.shared

    public init() {}

    public var body: some View {
        NavigationStack {
            ZStack {
                BrandTheme.bgPrimary.ignoresSafeArea()

                if queueItems.isEmpty {
                    emptyQueueView
                } else {
                    List {
                        ForEach(queueItems) { item in
                            queueRow(item)
                                .listRowBackground(Color.clear)
                                .listRowSeparator(.hidden)
                                .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
                        }
                        .onMove(perform: moveItems)
                        .onDelete(perform: deleteItems)
                    }
                    .listStyle(.plain)
                    .scrollContentBackground(.hidden)
                    .padding(.bottom, 90)
                }
            }
            .navigationTitle("Up Next")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    if !queueItems.isEmpty {
                        EditButton()
                            .foregroundStyle(BrandTheme.cyan)
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    if !queueItems.isEmpty {
                        Button("Clear") {
                            clearQueue()
                        }
                        .foregroundStyle(BrandTheme.rose)
                    }
                }
            }
        }
    }

    private func queueRow(_ item: QueueEpisodeItem) -> some View {
        let isCurrent = audioManager.currentEpisode?.episodeGuid == item.episodeGuid

        return HStack(spacing: 12) {
            AsyncArtworkView(urlString: item.podcastArtworkUrl, size: 48, cornerRadius: 10)

            VStack(alignment: .leading, spacing: 3) {
                Text(item.episodeTitle)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(isCurrent ? BrandTheme.cyan : BrandTheme.textPrimary)
                    .lineLimit(1)

                Text(item.podcastTitle)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(BrandTheme.textSecondary)
                    .lineLimit(1)

                if let dur = item.durationSecs {
                    Text(formatTime(seconds: dur))
                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                        .foregroundStyle(BrandTheme.textMuted)
                }
            }

            Spacer()

            if isCurrent {
                Image(systemName: audioManager.isPlaying ? "waveform" : "pause.circle.fill")
                    .font(.system(size: 20))
                    .foregroundStyle(BrandTheme.cyan)
                    .symbolEffect(.variableColor.iterative, isActive: audioManager.isPlaying)
            } else {
                Button {
                    playQueueItem(item)
                } label: {
                    Image(systemName: "play.circle")
                        .font(.system(size: 24))
                        .foregroundStyle(BrandTheme.textSecondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(12)
        .polarrCard(cornerRadius: 14)
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(isCurrent ? BrandTheme.cyan.opacity(0.6) : Color.clear, lineWidth: 1.5)
        )
    }

    private var emptyQueueView: some View {
        VStack(spacing: 16) {
            Image(systemName: "list.bullet.rectangle.portrait")
                .font(.system(size: 48, weight: .light))
                .foregroundStyle(BrandTheme.textMuted)

            Text("Queue is Empty")
                .font(.system(size: 18, weight: .bold))
                .foregroundStyle(BrandTheme.textPrimary)

            Text("Add episodes from your Inbox, Subscriptions, or Search to build your listening session.")
                .font(.system(size: 14))
                .foregroundStyle(BrandTheme.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
        }
    }

    private func playQueueItem(_ item: QueueEpisodeItem) {
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

    private func moveItems(from source: IndexSet, to destination: Int) {
        var items = queueItems
        items.move(fromOffsets: source, toOffset: destination)
        for (idx, it) in items.enumerated() {
            it.position = idx
        }
        try? modelContext.save()

        let ids = items.map { $0.id }
        Task {
            try? await APIClient.shared.reorderQueue(itemIds: ids)
        }
    }

    private func deleteItems(at offsets: IndexSet) {
        for idx in offsets {
            let item = queueItems[idx]
            let id = item.id
            modelContext.delete(item)
            Task {
                try? await APIClient.shared.deleteQueueItem(itemId: id)
            }
        }
        try? modelContext.save()
    }

    private func clearQueue() {
        for it in queueItems {
            modelContext.delete(it)
        }
        try? modelContext.save()
        Task {
            try? await APIClient.shared.clearQueue()
        }
    }
}
