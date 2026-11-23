import SwiftUI
import SwiftData

public struct PlaylistsView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \PlaylistItem.updatedAt, order: .reverse) private var playlists: [PlaylistItem]
    @Query(sort: \PlaylistEpisodeItem.position, order: .forward) private var allEpisodes: [PlaylistEpisodeItem]

    @Bindable var playlistManager = PlaylistManager.shared
    @Bindable var audioManager = AudioManager.shared

    @State private var showNewPlaylistAlert: Bool = false
    @State private var newPlaylistTitle: String = ""

    public init() {}

    public var body: some View {
        ZStack {
            BrandTheme.bgPrimary.ignoresSafeArea()

            PlaylistsContentView(
                playlists: playlists,
                allEpisodes: allEpisodes,
                showNewPlaylistAlert: $showNewPlaylistAlert,
                newPlaylistTitle: $newPlaylistTitle
            )
        }
        .refreshable {
            await playlistManager.syncPlaylists(modelContext: modelContext)
        }
        .navigationTitle("Playlists")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    newPlaylistTitle = ""
                    showNewPlaylistAlert = true
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(Color.white)
                }
            }
        }
        .alert("New Playlist", isPresented: $showNewPlaylistAlert) {
            TextField("Playlist title", text: $newPlaylistTitle)
            Button("Create") {
                createPlaylist()
            }
            Button("Cancel", role: .cancel) {}
        }
    }

    private func createPlaylist() {
        let title = newPlaylistTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { return }
        let playlist = PlaylistItem(title: title)
        modelContext.insert(playlist)
        try? modelContext.save()

        Task {
            _ = try? await APIClient.shared.createPlaylist(
                title: title,
                uuid: playlist.id
            )
        }
    }
}

public struct PlaylistsContentView: View {
    @Environment(\.modelContext) private var modelContext
    public let playlists: [PlaylistItem]
    public let allEpisodes: [PlaylistEpisodeItem]

    @Binding public var showNewPlaylistAlert: Bool
    @Binding public var newPlaylistTitle: String

    @Bindable var playlistManager = PlaylistManager.shared
    @Bindable var audioManager = AudioManager.shared

    public init(
        playlists: [PlaylistItem],
        allEpisodes: [PlaylistEpisodeItem],
        showNewPlaylistAlert: Binding<Bool>,
        newPlaylistTitle: Binding<String>
    ) {
        self.playlists = playlists
        self.allEpisodes = allEpisodes
        self._showNewPlaylistAlert = showNewPlaylistAlert
        self._newPlaylistTitle = newPlaylistTitle
    }

    public var body: some View {
        VStack(spacing: 0) {
            if playlists.isEmpty {
                Spacer()
                VStack(spacing: 14) {
                    Image(systemName: "music.note.list")
                        .font(.system(size: 44))
                        .foregroundStyle(BrandTheme.textMuted)

                    Text("No Custom Playlists Yet")
                        .font(.system(size: 17, weight: .bold))
                        .foregroundStyle(Color.white)

                    Text("Create playlists to organize episodes across any of your podcasts.")
                        .font(.system(size: 13))
                        .foregroundStyle(BrandTheme.textSecondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 32)

                    Button {
                        newPlaylistTitle = ""
                        showNewPlaylistAlert = true
                    } label: {
                        Label("Create Playlist", systemImage: "plus.circle.fill")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(Color.black)
                            .padding(.horizontal, 18)
                            .padding(.vertical, 10)
                            .background(Color.white)
                            .clipShape(Capsule())
                    }
                    .padding(.top, 8)
                }
                Spacer()
            } else {
                List {
                    ForEach(playlists) { playlist in
                        let playlistEps = allEpisodes.filter { $0.playlistId == playlist.id }
                        let isPlayingThis = playlistManager.activePlaylistId == playlist.id && audioManager.isPlaying

                        HStack(spacing: 14) {
                            NavigationLink(destination: PlaylistDetailView(playlist: playlist)) {
                                HStack(spacing: 14) {
                                    ZStack {
                                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                                            .fill(BrandTheme.bgCard)
                                            .frame(width: 50, height: 50)

                                        if let firstArt = playlistEps.first?.podcastArtworkUrl {
                                            AsyncArtworkView(urlString: firstArt, size: 50, cornerRadius: 12)
                                        } else {
                                            Image(systemName: "music.note.list")
                                                .font(.system(size: 20, weight: .bold))
                                                .foregroundStyle(Color.white)
                                        }
                                    }

                                    VStack(alignment: .leading, spacing: 3) {
                                        HStack(spacing: 6) {
                                            Text(playlist.title)
                                                .font(.system(size: 15, weight: .semibold))
                                                .foregroundStyle(Color.white)

                                            if playlist.isSmart {
                                                Text("SMART")
                                                    .font(.system(size: 8, weight: .bold))
                                                    .foregroundStyle(Color.black)
                                                    .padding(.horizontal, 5)
                                                    .padding(.vertical, 1.5)
                                                    .background(Color.white)
                                                    .clipShape(Capsule())
                                            }

                                            if playlistManager.activePlaylistId == playlist.id {
                                                Text("ACTIVE")
                                                    .font(.system(size: 8, weight: .bold))
                                                    .foregroundStyle(Color.black)
                                                    .padding(.horizontal, 5)
                                                    .padding(.vertical, 1.5)
                                                    .background(Color.white)
                                                    .clipShape(Capsule())
                                            }
                                        }

                                        Text("\(playlistEps.count) episodes")
                                            .font(.system(size: 12))
                                            .foregroundStyle(BrandTheme.textSecondary)

                                        if let lastGuid = playlist.lastPlayedEpisodeGuid,
                                           let lastEp = playlistEps.first(where: { $0.episodeGuid == lastGuid }) {
                                            let pos = Int(playlist.lastPlayedPositionSecs ?? 0)
                                            Text("Resume: \(lastEp.episodeTitle) (\(pos / 60):\(String(format: "%02d", pos % 60)))")
                                                .font(.system(size: 11, weight: .semibold))
                                                .foregroundStyle(audioManager.currentPalette.accent)
                                                .lineLimit(1)
                                        }
                                    }
                                }
                            }

                            Spacer()

                            // Direct 1-Tap Play/Pause Button
                            Button {
                                togglePlayPlaylist(playlist, episodes: playlistEps)
                            } label: {
                                ZStack {
                                    Circle()
                                        .fill(isPlayingThis ? audioManager.currentPalette.accent : Color.white)
                                        .frame(width: 38, height: 38)
                                    Image(systemName: isPlayingThis ? "pause.fill" : "play.fill")
                                        .font(.system(size: 15, weight: .bold))
                                        .foregroundStyle(Color.black)
                                        .offset(x: isPlayingThis ? 0 : 1)
                                }
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(.vertical, 6)
                        .listRowBackground(BrandTheme.bgSecondary)
                    }
                    .onDelete(perform: deletePlaylists)
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
                .padding(.bottom, 90)
            }
        }
    }

    private func togglePlayPlaylist(_ playlist: PlaylistItem, episodes: [PlaylistEpisodeItem]) {
        if playlistManager.activePlaylistId == playlist.id && audioManager.isPlaying {
            audioManager.pause()
            return
        }

        playlistManager.setActivePlaylist(playlist)
        if let lastGuid = playlist.lastPlayedEpisodeGuid,
           let lastEp = episodes.first(where: { $0.episodeGuid == lastGuid }) {
            playSingle(lastEp, startAt: playlist.lastPlayedPositionSecs ?? 0)
        } else if let first = episodes.first {
            playSingle(first, startAt: 0)
        }
    }

    private func playSingle(_ ep: PlaylistEpisodeItem, startAt: Double) {
        guard let enc = ep.enclosureUrl, !enc.isEmpty else { return }
        let playable = PlayableEpisode(
            podcastId: ep.podcastId ?? 0,
            podcastTitle: ep.podcastTitle,
            podcastArtworkUrl: ep.podcastArtworkUrl,
            episodeGuid: ep.episodeGuid,
            episodeTitle: ep.episodeTitle,
            enclosureUrl: enc,
            durationSecs: ep.durationSecs
        )
        audioManager.play(episode: playable, startAt: startAt)
    }

    private func deletePlaylists(at offsets: IndexSet) {
        for idx in offsets {
            let item = playlists[idx]
            if playlistManager.activePlaylistId == item.id {
                playlistManager.setActivePlaylist(nil)
            }
            let uId = item.id
            modelContext.delete(item)
            Task {
                try? await APIClient.shared.deletePlaylist(uuid: uId)
            }
        }
        try? modelContext.save()
    }
}
