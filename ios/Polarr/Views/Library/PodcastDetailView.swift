import SwiftUI
import SwiftData

public struct PodcastDetailView: View {
    @Environment(\.modelContext) private var modelContext
    public let podcast: PodcastItem

    @Bindable var audioManager = AudioManager.shared
    @State private var episodes: [APIEpisode] = []
    @State private var isLoading: Bool = true
    @State private var filterMode: FilterMode = .all
    @State private var isAscendingOrder: Bool = false
    @State private var selectedEpisode: APIEpisode?
    @State private var errorMessage: String?

    public enum FilterMode: String, CaseIterable {
        case all = "All"
        case unplayed = "Unplayed"
        case played = "Listened"
        case skipped = "Skipped"
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

                        VStack(spacing: 4) {
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
                        }
                    }
                    .padding(.top, 12)

                    // Horizontal Filter Capsules & Sort Order Toggle
                    HStack(spacing: 10) {
                        // Horizontal filter capsules
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                ForEach(FilterMode.allCases, id: \.self) { mode in
                                    Button {
                                        filterMode = mode
                                    } label: {
                                        Text(mode.rawValue)
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
                    if isLoading {
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
                                        toggleSkip(ep)
                                    } label: {
                                        Label(ep.skipped ? "Unskip" : "Skip", systemImage: ep.skipped ? "arrow.uturn.backward" : "slash.circle")
                                    }
                                    .tint(ep.skipped ? BrandTheme.cyan : BrandTheme.amber)
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
        .task {
            await loadEpisodes()
        }
    }

    private func episodeRow(_ ep: APIEpisode) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 10) {
                VStack(alignment: .leading, spacing: 4) {
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

                        if let rating = ep.rating {
                            HStack(spacing: 2) {
                                Image(systemName: "star.fill").font(.system(size: 10))
                                Text("\(rating)")
                            }
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(BrandTheme.amber)
                        }
                    }
                }

                Spacer()

                // Play Button
                Button {
                    playEpisode(ep)
                } label: {
                    Image(systemName: "play.circle.fill")
                        .font(.system(size: 32))
                        .foregroundStyle(BrandTheme.cyan)
                }
            }
        }
        .padding(14)
        .polarrCard(cornerRadius: 14)
    }

    private func playEpisode(_ ep: APIEpisode) {
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
        audioManager.play(episode: playable)
    }

    private func loadEpisodes() async {
        isLoading = true
        defer { isLoading = false }
        do {
            episodes = try await APIClient.shared.fetchPodcastEpisodes(podcastId: podcast.id)
        } catch {
            errorMessage = error.localizedDescription
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
        }

        Task {
            _ = try? await APIClient.shared.toggleEpisodeSkipped(podcastId: podcast.id, episodeGuid: ep.guid)
            await SyncManager.shared.sync(modelContext: modelContext)
        }
    }
}
