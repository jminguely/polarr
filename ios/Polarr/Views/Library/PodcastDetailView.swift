import SwiftUI
import SwiftData

public struct PodcastDetailView: View {
    @Environment(\.modelContext) private var modelContext
    public let podcast: PodcastItem

    @Bindable var audioManager = AudioManager.shared
    @State private var episodes: [APIEpisode] = []
    @State private var isLoading: Bool = true
    @State private var filterMode: FilterMode = .all
    @State private var errorMessage: String?

    public enum FilterMode: String, CaseIterable {
        case all = "All"
        case unplayed = "Unplayed"
        case played = "Listened"
    }

    public init(podcast: PodcastItem) {
        self.podcast = podcast
    }

    public var filteredEpisodes: [APIEpisode] {
        switch filterMode {
        case .all:
            return episodes
        case .unplayed:
            return episodes.filter { !$0.played && !$0.skipped }
        case .played:
            return episodes.filter { $0.played || $0.skipped }
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

                    // Filter Segmented Picker
                    Picker("Filter", selection: $filterMode) {
                        ForEach(FilterMode.allCases, id: \.self) { mode in
                            Text(mode.rawValue).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)
                    .padding(.horizontal, 16)

                    // Episode List
                    if isLoading {
                        ProgressView()
                            .tint(BrandTheme.cyan)
                            .padding(.top, 40)
                    } else if filteredEpisodes.isEmpty {
                        Text("No episodes in this section")
                            .font(.system(size: 14))
                            .foregroundStyle(BrandTheme.textMuted)
                            .padding(.top, 40)
                    } else {
                        LazyVStack(spacing: 10) {
                            ForEach(filteredEpisodes) { ep in
                                episodeRow(ep)
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
                        .foregroundStyle(ep.played ? BrandTheme.textMuted : BrandTheme.textPrimary)
                        .lineLimit(2)

                    HStack(spacing: 8) {
                        if let dur = ep.durationSecs {
                            Text(formatTime(seconds: dur))
                                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                                .foregroundStyle(BrandTheme.textSecondary)
                        }

                        if ep.played {
                            Label("Listened", systemImage: "checkmark.circle.fill")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(BrandTheme.emerald)
                        } else if ep.skipped {
                            Label("Skipped", systemImage: "forward.fill")
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
}
