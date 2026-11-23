import SwiftUI
import SwiftData

public struct PodcastDetailView: View {
    @Environment(\.modelContext) private var modelContext
    public let podcast: PodcastItem

    @Bindable var audioManager = AudioManager.shared
    @Bindable var downloadManager = DownloadManager.shared

    @State private var episodes: [APIEpisode] = []
    @State private var isLoading: Bool = true
    @State private var isOffline: Bool = false
    @State private var filterMode: FilterMode = .all
    @State private var isAscendingOrder: Bool = false
    @State private var selectedEpisode: APIEpisode?
    @State private var selectedEpisodeForPlaylist: APIEpisode? = nil
    @State private var errorMessage: String?

    public enum FilterMode: String, CaseIterable {
        case all = "All"
        case unplayed = "Unplayed"
        case played = "Listened"
        case skipped = "Skipped"
        case downloaded = "Downloaded"
    }

    public init(podcast: PodcastItem) {
        self.podcast = podcast
    }

    public var sortedAndFilteredEpisodes: [APIEpisode] {
        var list: [APIEpisode]
        switch filterMode {
        case .all:
            list = episodes
        case .unplayed:
            list = episodes.filter { !$0.played && !$0.skipped }
        case .played:
            list = episodes.filter { $0.played && !$0.skipped }
        case .skipped:
            list = episodes.filter { $0.skipped }
        case .downloaded:
            list = episodes.filter { downloadManager.isDownloaded(guid: $0.guid) }
        }

        if isAscendingOrder {
            // Oldest to newest
            return list.reversed()
        } else {
            // Newest to oldest (default)
            return list
        }
    }

    public var body: some View {
        ZStack {
            BrandTheme.bgPrimary.ignoresSafeArea()

            ScrollView {
                VStack(spacing: 18) {
                    // Header Card
                    VStack(spacing: 14) {
                        AsyncArtworkView(urlString: podcast.artworkUrl, size: 140, cornerRadius: 20)
                            .shadow(color: BrandTheme.cyan.opacity(0.3), radius: 20, x: 0, y: 6)

                        VStack(spacing: 6) {
                            Text(podcast.title)
                                .font(.system(size: 20, weight: .bold))
                                .foregroundStyle(BrandTheme.textPrimary)
                                .multilineTextAlignment(.center)

                            HStack(spacing: 12) {
                                Label("\(episodes.count) episodes", systemImage: "music.note.list")
                                Label("\(podcast.listenedCount) listened", systemImage: "checkmark.circle")
                            }
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(BrandTheme.textSecondary)

                            if isOffline {
                                HStack(spacing: 4) {
                                    Image(systemName: "wifi.slash")
                                    Text("Offline Mode (Cached Data)")
                                }
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(BrandTheme.amber)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 4)
                                .background(BrandTheme.amber.opacity(0.12))
                                .clipShape(Capsule())
                                .padding(.top, 2)
                            }
                        }
                    }
                    .padding(.top, 12)

                    // Horizontal Filter Capsules & Sort Order Toggle
                    HStack(spacing: 10) {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                ForEach(FilterMode.allCases, id: \.self) { mode in
                                    Button {
                                        filterMode = mode
                                    } label: {
                                        HStack(spacing: 4) {
                                            Text(mode.rawValue)
                                            if mode == .downloaded {
                                                let count = episodes.filter { downloadManager.isDownloaded(guid: $0.guid) }.count
                                                if count > 0 {
                                                    Text("(\(count))")
                                                        .font(.system(size: 10, weight: .bold))
                                                }
                                            }
                                        }
                                        .font(.system(size: 13, weight: .semibold))
                                        .foregroundStyle(filterMode == mode ? Color.black : BrandTheme.textSecondary)
                                        .padding(.horizontal, 14)
                                        .padding(.vertical, 7)
                                        .background(filterMode == mode ? BrandTheme.cyan : BrandTheme.bgSecondary)
                                        .clipShape(Capsule())
                                    }
                                }
                            }
                        }

                        Spacer()

                        // 1-Tap Sort Order Toggle (Newest ⇄ Oldest)
                        Button {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                isAscendingOrder.toggle()
                            }
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: isAscendingOrder ? "arrow.up" : "arrow.down")
                                    .font(.system(size: 11, weight: .bold))
                                Text(isAscendingOrder ? "Oldest" : "Newest")
                                    .font(.system(size: 12, weight: .semibold))
                            }
                            .foregroundStyle(BrandTheme.cyan)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(BrandTheme.bgSecondary)
                            .clipShape(Capsule())
                        }
                    }
                    .padding(.horizontal, 16)

                    // Episode List
                    if isLoading && episodes.isEmpty {
                        ProgressView()
                            .tint(BrandTheme.cyan)
                            .padding(.top, 40)
                    } else if sortedAndFilteredEpisodes.isEmpty {
                        Text("No episodes in this section")
                            .font(.system(size: 14))
                            .foregroundStyle(BrandTheme.textMuted)
                            .padding(.top, 40)
                    } else {
                        LazyVStack(spacing: 10) {
                            ForEach(sortedAndFilteredEpisodes) { ep in
                                Button {
                                    selectedEpisode = ep
                                } label: {
                                    episodeRow(ep)
                                }
                                .buttonStyle(.plain)
                                .swipeActions(edge: .leading, allowsFullSwipe: true) {
                                    Button {
                                        addToQueue(ep)
                                    } label: {
                                        Label("Queue", systemImage: "text.badge.plus")
                                    }
                                    .tint(BrandTheme.emerald)

                                    Button {
                                        selectedEpisodeForPlaylist = ep
                                    } label: {
                                        Label("Playlist", systemImage: "music.note.list")
                                    }
                                    .tint(Color.white)
                                }
                                .contextMenu {
                                    Button {
                                        selectedEpisodeForPlaylist = ep
                                    } label: {
                                        Label("Add to Playlist", systemImage: "music.note.list")
                                    }

                                    Button {
                                        addToQueue(ep)
                                    } label: {
                                        Label("Add to Queue", systemImage: "text.badge.plus")
                                    }

                                    Button {
                                        togglePlayed(ep)
                                    } label: {
                                        Label(ep.played ? "Mark Unplayed" : "Mark Listened", systemImage: ep.played ? "arrow.uturn.backward" : "checkmark.circle")
                                    }

                                    Button {
                                        toggleSkip(ep)
                                    } label: {
                                        Label(ep.skipped ? "Unskip" : "Skip", systemImage: ep.skipped ? "arrow.uturn.backward" : "slash.circle")
                                    }
                                }
                                .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                    Button {
                                        toggleSkip(ep)
                                    } label: {
                                        Label(ep.skipped ? "Unskip" : "Skip", systemImage: ep.skipped ? "arrow.uturn.backward" : "slash.circle")
                                    }
                                    .tint(BrandTheme.amber)

                                    Button {
                                        togglePlayed(ep)
                                    } label: {
                                        Label(ep.played ? "Unplay" : "Listened", systemImage: ep.played ? "arrow.uturn.backward" : "checkmark.circle.fill")
                                    }
                                    .tint(Color.white.opacity(0.3))
                                }
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.bottom, 90)
                    }
                }
            }
        }
        .navigationTitle(podcast.title)
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $selectedEpisode) { ep in
            EpisodeDetailSheet(podcast: podcast, episode: ep)
        }
        .sheet(item: $selectedEpisodeForPlaylist) { ep in
            AddToPlaylistSheet(
                episodeGuid: ep.guid,
                episodeTitle: ep.title,
                podcastId: podcast.id,
                podcastTitle: podcast.title,
                podcastArtworkUrl: podcast.artworkUrl,
                enclosureUrl: ep.enclosure_url,
                durationSecs: ep.duration_secs
            )
        }
        .task {
            // Instant offline load from cache
            if let cached = EpisodeCacheManager.shared.getCachedEpisodes(for: podcast.id), !cached.isEmpty {
                episodes = cached
                isLoading = false
            }
            await loadEpisodes()
        }
    }

    private func episodeRow(_ ep: APIEpisode) -> some View {
        let isCurrent = audioManager.currentEpisode?.episodeGuid == ep.guid
        let isDownloaded = downloadManager.isDownloaded(guid: ep.guid)
        let downloadState = downloadManager.downloadStates[ep.guid]
        let savedProgress = isCurrent ? audioManager.currentTime : (audioManager.getSavedProgress(for: ep.guid) ?? 0)
        let hasResumeProgress = savedProgress > 10 && !(ep.played || ep.skipped)

        return VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 10) {
                VStack(alignment: .leading, spacing: 5) {
                    Text(ep.title)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle((ep.played || ep.skipped) ? BrandTheme.textMuted : BrandTheme.textPrimary)
                        .lineLimit(2)

                    HStack(spacing: 8) {
                        if let dur = ep.durationSecs {
                            Text(formatTime(seconds: dur))
                                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                                .foregroundStyle(BrandTheme.textSecondary)
                        }

                        if let pub = ep.pub_date, let date = SyncManager.parseServerDate(pub) {
                            Text(date.formatted(date: .abbreviated, time: .omitted))
                                .font(.system(size: 11))
                                .foregroundStyle(BrandTheme.textMuted)
                        }

                        if ep.played && !ep.skipped {
                            Label("Listened", systemImage: "checkmark.circle.fill")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(BrandTheme.emerald)
                        } else if ep.skipped {
                            Label("Skipped", systemImage: "slash.circle.fill")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(BrandTheme.amber)
                        }

                        if isDownloaded {
                            Label("Offline", systemImage: "arrow.down.circle.fill")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(BrandTheme.cyan)
                        }
                    }

                    // In-progress Resume Capsule & Bar
                    if hasResumeProgress {
                        VStack(alignment: .leading, spacing: 4) {
                            HStack(spacing: 6) {
                                Image(systemName: isCurrent && audioManager.isPlaying ? "waveform" : "clock.arrow.circlepath")
                                    .font(.system(size: 10, weight: .bold))
                                Text("Resume at \(formatTime(seconds: Int(savedProgress)))")
                                    .font(.system(size: 11, weight: .semibold))
                            }
                            .foregroundStyle(BrandTheme.cyan)

                            if let totalDur = ep.durationSecs, totalDur > 0 {
                                let pct = min(1.0, max(0.0, savedProgress / Double(totalDur)))
                                GeometryReader { geo in
                                    ZStack(alignment: .leading) {
                                        Capsule().fill(Color.white.opacity(0.12))
                                        Capsule().fill(BrandTheme.cyan).frame(width: geo.size.width * CGFloat(pct))
                                    }
                                }
                                .frame(height: 3)
                            }
                        }
                        .padding(.top, 2)
                    }
                }

                Spacer()

                // Actions: Download Button & Play/Pause Button
                HStack(spacing: 8) {
                    // Download toggle button
                    Button {
                        handleDownloadToggle(for: ep)
                    } label: {
                        if let state = downloadState, case .downloading(let pct) = state {
                            ZStack {
                                ProgressView()
                                    .tint(BrandTheme.cyan)
                                    .scaleEffect(0.6)
                                Text("\(Int(pct * 100))%")
                                    .font(.system(size: 8, weight: .bold))
                                    .foregroundStyle(BrandTheme.cyan)
                                    .offset(y: 14)
                            }
                            .frame(width: 32, height: 32)
                        } else if isDownloaded {
                            Image(systemName: "arrow.down.circle.fill")
                                .font(.system(size: 20))
                                .foregroundStyle(BrandTheme.emerald)
                                .frame(width: 32, height: 32)
                        } else {
                            Image(systemName: "arrow.down.circle")
                                .font(.system(size: 20))
                                .foregroundStyle(BrandTheme.textMuted)
                                .frame(width: 32, height: 32)
                        }
                    }
                    .buttonStyle(.plain)

                    // Play / Resume Button
                    Button {
                        if isCurrent && audioManager.isPlaying {
                            audioManager.pause()
                        } else {
                            playEpisode(ep, startAt: hasResumeProgress ? savedProgress : 0)
                        }
                    } label: {
                        Image(systemName: isCurrent && audioManager.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                            .font(.system(size: 32))
                            .foregroundStyle(BrandTheme.cyan)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(14)
        .polarrCard(cornerRadius: 14)
    }

    private func handleDownloadToggle(for ep: APIEpisode) {
        if downloadManager.isDownloaded(guid: ep.guid) {
            downloadManager.deleteDownload(guid: ep.guid)
        } else if let enc = ep.enclosure_url, !enc.isEmpty {
            downloadManager.startDownload(guid: ep.guid, urlString: enc)
        }
    }

    private func playEpisode(_ ep: APIEpisode, startAt: Double = -1) {
        guard let enc = ep.enclosure_url, !enc.isEmpty else { return }
        let playable = PlayableEpisode(
            podcastId: podcast.id,
            podcastTitle: podcast.title,
            podcastArtworkUrl: podcast.artworkUrl,
            episodeGuid: ep.guid,
            episodeTitle: ep.title,
            enclosureUrl: enc,
            durationSecs: ep.durationSecs
        )
        audioManager.play(episode: playable, startAt: startAt)
    }

    private func loadEpisodes() async {
        if episodes.isEmpty { isLoading = true }
        defer { isLoading = false }
        do {
            let freshEpisodes = try await APIClient.shared.fetchPodcastEpisodes(podcastId: podcast.id)
            episodes = freshEpisodes
            isOffline = false
            EpisodeCacheManager.shared.saveEpisodes(freshEpisodes, for: podcast.id)
        } catch {
            print("Failed to fetch fresh episodes: \(error)")
            if !episodes.isEmpty {
                isOffline = true
            } else {
                errorMessage = error.localizedDescription
            }
        }
    }

    private func togglePlayed(_ ep: APIEpisode) {
        let newPlayed = !ep.played
        if let idx = episodes.firstIndex(where: { $0.guid == ep.guid }) {
            let old = episodes[idx]
            episodes[idx] = APIEpisode(
                guid: old.guid,
                title: old.title,
                description: old.description,
                pub_date: old.pub_date,
                link: old.link,
                enclosure_url: old.enclosure_url,
                duration_secs: old.duration_secs,
                played: newPlayed,
                skipped: false,
                completion_type: newPlayed ? "finished" : nil,
                played_at: newPlayed ? ISO8601DateFormatter().string(from: Date()) : nil,
                rating: old.rating,
                is_queued: old.is_queued
            )
            EpisodeCacheManager.shared.saveEpisodes(episodes, for: podcast.id)
        }

        let playable = PlayableEpisode(
            podcastId: podcast.id,
            podcastTitle: podcast.title,
            podcastArtworkUrl: podcast.artworkUrl,
            episodeGuid: ep.guid,
            episodeTitle: ep.title,
            enclosureUrl: ep.enclosure_url ?? "",
            durationSecs: ep.durationSecs
        )

        if newPlayed {
            audioManager.clearSavedProgress(for: ep.guid)
            SyncManager.shared.recordPlaybackFinished(
                episode: playable,
                timeListened: Double(ep.durationSecs ?? 0),
                completionType: "finished",
                modelContext: modelContext
            )
        } else {
            let epGuid = ep.guid
            let jDesc = FetchDescriptor<JournalEntryItem>(predicate: #Predicate { $0.episodeGuid == epGuid })
            if let entries = try? modelContext.fetch(jDesc) {
                for item in entries { modelContext.delete(item) }
                try? modelContext.save()
            }
        }
    }

    private func toggleSkip(_ ep: APIEpisode) {
        let newSkipped = !ep.skipped
        // Optimistically update local list
        if let idx = episodes.firstIndex(where: { $0.guid == ep.guid }) {
            let old = episodes[idx]
            episodes[idx] = APIEpisode(
                guid: old.guid,
                title: old.title,
                description: old.description,
                pub_date: old.pub_date,
                link: old.link,
                enclosure_url: old.enclosure_url,
                duration_secs: old.duration_secs,
                played: old.played && !newSkipped,
                skipped: newSkipped,
                completion_type: newSkipped ? "skipped" : (old.completion_type == "skipped" ? nil : old.completion_type),
                played_at: old.played_at,
                rating: old.rating,
                is_queued: old.is_queued
            )
            // Update cache
            EpisodeCacheManager.shared.saveEpisodes(episodes, for: podcast.id)
        }

        Task {
            _ = try? await APIClient.shared.toggleEpisodeSkipped(podcastId: podcast.id, episodeGuid: ep.guid)
            await SyncManager.shared.sync(modelContext: modelContext)
        }
    }

    private func addToQueue(_ ep: APIEpisode) {
        let queueDesc = FetchDescriptor<QueueEpisodeItem>(sortBy: [SortDescriptor(\.position, order: .forward)])
        let existing = try? modelContext.fetch(queueDesc)
        if existing?.contains(where: { $0.episodeGuid == ep.guid }) == true {
            return
        }
        let pos = (existing?.map(\.position).max() ?? -1) + 1
        let newItem = QueueEpisodeItem(
            id: Int.random(in: 100_000...999_999),
            podcastId: podcast.id,
            podcastTitle: podcast.title,
            podcastArtworkUrl: podcast.artworkUrl,
            episodeGuid: ep.guid,
            episodeTitle: ep.title,
            enclosureUrl: ep.enclosure_url,
            durationSecs: ep.duration_secs,
            position: pos,
            progressSecs: 0
        )
        modelContext.insert(newItem)
        try? modelContext.save()
        let generator = UINotificationFeedbackGenerator()
        generator.notificationOccurred(.success)
    }
}
