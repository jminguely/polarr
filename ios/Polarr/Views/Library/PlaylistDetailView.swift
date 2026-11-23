import SwiftUI
import SwiftData

public struct PlaylistDetailView: View {
    @Environment(\.modelContext) private var modelContext
    @Bindable var playlist: PlaylistItem
    @Bindable var audioManager = AudioManager.shared
    @Bindable var playlistManager = PlaylistManager.shared

    @Query(sort: \PlaylistEpisodeItem.position, order: .forward)
    private var allPlaylistEpisodes: [PlaylistEpisodeItem]

    @State private var isEditingOrder: Bool = false

    public init(playlist: PlaylistItem) {
        self.playlist = playlist
    }

    private var episodesInPlaylist: [PlaylistEpisodeItem] {
        allPlaylistEpisodes.filter { $0.playlistId == playlist.id }
    }

    public var body: some View {
        ZStack {
            BrandTheme.bgPrimary.ignoresSafeArea()

            VStack(spacing: 0) {
                // Header with Playlist Play/Resume Action
                VStack(spacing: 14) {
                    HStack(alignment: .top) {
                        VStack(alignment: .leading, spacing: 4) {
                            HStack(spacing: 6) {
                                Text(playlist.title)
                                    .font(.system(size: 22, weight: .bold))
                                    .foregroundStyle(Color.white)

                                if playlist.isSmart {
                                    Text("SMART")
                                        .font(.system(size: 9, weight: .bold))
                                        .foregroundStyle(Color.black)
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 2)
                                        .background(Color.white)
                                        .clipShape(Capsule())
                                }

                                if playlistManager.activePlaylistId == playlist.id {
                                    Text("ACTIVE")
                                        .font(.system(size: 9, weight: .bold))
                                        .foregroundStyle(Color.black)
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 2)
                                        .background(Color.white)
                                        .clipShape(Capsule())
                                }
                            }

                            if let desc = playlist.playlistDescription, !desc.isEmpty {
                                Text(desc)
                                    .font(.system(size: 13))
                                    .foregroundStyle(BrandTheme.textSecondary)
                                    .lineLimit(2)
                            }

                            Text("\(episodesInPlaylist.count) episodes in playlist")
                                .font(.system(size: 12))
                                .foregroundStyle(BrandTheme.textMuted)

                            if let lastGuid = playlist.lastPlayedEpisodeGuid,
                               let lastEp = episodesInPlaylist.first(where: { $0.episodeGuid == lastGuid }) {
                                let pos = Int(playlist.lastPlayedPositionSecs ?? 0)
                                Text("Resume: \(lastEp.episodeTitle) (\(formatSeconds(pos)))")
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundStyle(audioManager.currentPalette.accent)
                                    .lineLimit(1)
                                    .padding(.top, 2)
                            }
                        }

                        Spacer()

                        Button {
                            playPlaylist()
                        } label: {
                            ZStack {
                                Circle()
                                    .fill(audioManager.currentPalette.accent)
                                    .frame(width: 56, height: 56)
                                    .shadow(color: audioManager.currentPalette.accent.opacity(0.3), radius: 10, x: 0, y: 4)
                                Image(systemName: isPlaylistPlaying ? "pause.fill" : "play.fill")
                                    .font(.system(size: 24, weight: .bold))
                                    .foregroundStyle(audioManager.currentPalette.controlOnAccent)
                            }
                        }
                    }

                    // Playlist Settings Toggle
                    HStack {
                        Toggle(isOn: $playlist.autoRemoveFinished) {
                            Text("Auto-remove completed episodes")
                                .font(.system(size: 13, weight: .medium))
                                .foregroundStyle(BrandTheme.textSecondary)
                        }
                        .tint(audioManager.currentPalette.accent)
                        .onChange(of: playlist.autoRemoveFinished) { _, newValue in
                            Task {
                                _ = try? await APIClient.shared.createPlaylist(
                                    title: playlist.title,
                                    autoRemoveFinished: newValue,
                                    uuid: playlist.id
                                )
                            }
                        }
                    }
                    .padding(.top, 4)
                }
                .padding(20)
                .background(BrandTheme.bgSecondary)
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .stroke(BrandTheme.border, lineWidth: 1)
                )
                .padding(.horizontal, 16)
                .padding(.vertical, 12)

                // Episode List
                if episodesInPlaylist.isEmpty {
                    Spacer()
                    VStack(spacing: 10) {
                        Image(systemName: "plus.rectangle.on.folder")
                            .font(.system(size: 40))
                            .foregroundStyle(BrandTheme.textMuted)
                        Text("Playlist is empty")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(Color.white)
                        Text("Add episodes using the 'Add to Playlist' action across Polarr.")
                            .font(.system(size: 13))
                            .foregroundStyle(BrandTheme.textSecondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 32)
                    }
                    Spacer()
                } else {
                    List {
                        ForEach(episodesInPlaylist) { ep in
                            HStack(spacing: 12) {
                                AsyncArtworkView(urlString: ep.podcastArtworkUrl, size: 48, cornerRadius: 10)

                                VStack(alignment: .leading, spacing: 3) {
                                    HStack(spacing: 6) {
                                        Text(ep.episodeTitle)
                                            .font(.system(size: 14, weight: .semibold))
                                            .foregroundStyle(Color.white)
                                            .lineLimit(1)

                                        if ep.isCompleted {
                                            Image(systemName: "checkmark.circle.fill")
                                                .font(.system(size: 12))
                                                .foregroundStyle(BrandTheme.emerald)
                                        }
                                    }

                                    HStack(spacing: 6) {
                                        Text(ep.podcastTitle)
                                            .font(.system(size: 12))
                                            .foregroundStyle(BrandTheme.textSecondary)
                                            .lineLimit(1)

                                        if let dur = ep.durationSecs, dur > 0 {
                                            Text("•")
                                                .foregroundStyle(BrandTheme.textMuted)
                                            Text(formatSeconds(dur))
                                                .font(.system(size: 11, design: .monospaced))
                                                .foregroundStyle(BrandTheme.textMuted)
                                        }
                                    }
                                }

                                Spacer()

                                Button {
                                    playSingleEpisode(ep)
                                } label: {
                                    Image(systemName: isCurrentEpisode(ep) ? "waveform" : "play.circle.fill")
                                        .font(.system(size: 24))
                                        .foregroundStyle(isCurrentEpisode(ep) ? audioManager.currentPalette.accent : BrandTheme.textMuted)
                                }
                                .buttonStyle(.plain)
                            }
                            .padding(.vertical, 4)
                            .listRowBackground(BrandTheme.bgSecondary)
                        }
                        .onDelete(perform: removeEpisodes)
                        .onMove(perform: moveEpisodes)
                    }
                    .listStyle(.plain)
                    .scrollContentBackground(.hidden)
                }
            }
        }
        .navigationTitle(playlist.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if !episodesInPlaylist.isEmpty {
                ToolbarItem(placement: .topBarTrailing) {
                    EditButton()
                }
            }
        }
    }

    private var isPlaylistPlaying: Bool {
        playlistManager.activePlaylistId == playlist.id && audioManager.isPlaying
    }

    private func isCurrentEpisode(_ ep: PlaylistEpisodeItem) -> Bool {
        audioManager.currentEpisode?.episodeGuid == ep.episodeGuid
    }

    private func playPlaylist() {
        playlistManager.setActivePlaylist(playlist)
        if let lastGuid = playlist.lastPlayedEpisodeGuid,
           let lastEp = episodesInPlaylist.first(where: { $0.episodeGuid == lastGuid }) {
            playSingleEpisode(lastEp, startAt: playlist.lastPlayedPositionSecs ?? 0)
        } else if let first = episodesInPlaylist.first {
            playSingleEpisode(first, startAt: 0)
        }
    }

    private func playSingleEpisode(_ ep: PlaylistEpisodeItem, startAt: Double = -1) {
        playlistManager.setActivePlaylist(playlist)
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

    private func removeEpisodes(at offsets: IndexSet) {
        for idx in offsets {
            let ep = episodesInPlaylist[idx]
            playlistManager.removeEpisode(guid: ep.episodeGuid, from: playlist, modelContext: modelContext)
        }
    }

    private func moveEpisodes(from source: IndexSet, to destination: Int) {
        var updatedGuids = playlist.episodeGuids
        updatedGuids.move(fromOffsets: source, toOffset: destination)
        playlistManager.reorderEpisodes(playlist: playlist, newGuids: updatedGuids, modelContext: modelContext)
    }

    private func formatSeconds(_ s: Int) -> String {
        let m = s / 60
        return String(format: "%d:%02d", m, s % 60)
    }
}
