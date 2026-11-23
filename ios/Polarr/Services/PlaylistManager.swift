import Foundation
import SwiftData
import SwiftUI

@Observable
public final class PlaylistManager {
    public static let shared = PlaylistManager()

    public private(set) var activePlaylistId: String?
    public private(set) var activePlaylistTitle: String?

    private init() {
        activePlaylistId = UserDefaults.standard.string(forKey: "polarr_active_playlist_id")
        activePlaylistTitle = UserDefaults.standard.string(forKey: "polarr_active_playlist_title")
    }

    public func setActivePlaylist(_ playlist: PlaylistItem?) {
        activePlaylistId = playlist?.id
        activePlaylistTitle = playlist?.title
        if let pl = playlist {
            UserDefaults.standard.set(pl.id, forKey: "polarr_active_playlist_id")
            UserDefaults.standard.set(pl.title, forKey: "polarr_active_playlist_title")
        } else {
            UserDefaults.standard.removeObject(forKey: "polarr_active_playlist_id")
            UserDefaults.standard.removeObject(forKey: "polarr_active_playlist_title")
        }
    }

    public func recordPlaybackProgress(
        episodeGuid: String,
        positionSecs: Double,
        modelContext: ModelContext
    ) {
        guard let pId = activePlaylistId else { return }
        var desc = FetchDescriptor<PlaylistItem>(predicate: #Predicate { $0.id == pId })
        desc.fetchLimit = 1
        if let playlist = try? modelContext.fetch(desc).first {
            playlist.lastPlayedEpisodeGuid = episodeGuid
            playlist.lastPlayedPositionSecs = positionSecs
            playlist.updatedAt = Date()
            try? modelContext.save()

            Task {
                try? await APIClient.shared.updatePlaylistProgress(
                    playlistUuid: pId,
                    lastPlayedEpisodeGuid: episodeGuid,
                    lastPlayedPositionSecs: positionSecs
                )
            }
        }
    }

    public func addEpisode(
        guid: String,
        title: String,
        podcastId: Int?,
        podcastTitle: String,
        podcastArtworkUrl: String?,
        enclosureUrl: String?,
        durationSecs: Int?,
        to playlist: PlaylistItem,
        modelContext: ModelContext
    ) {
        let epId = "\(playlist.id)_\(guid)"
        var desc = FetchDescriptor<PlaylistEpisodeItem>(predicate: #Predicate { $0.id == epId })
        desc.fetchLimit = 1

        if (try? modelContext.fetch(desc).first) == nil {
            let pos = playlist.episodeGuids.count
            let newEpisode = PlaylistEpisodeItem(
                id: epId,
                playlistId: playlist.id,
                episodeGuid: guid,
                episodeTitle: title,
                podcastId: podcastId,
                podcastTitle: podcastTitle,
                podcastArtworkUrl: podcastArtworkUrl,
                enclosureUrl: enclosureUrl,
                durationSecs: durationSecs,
                position: pos,
                isCompleted: false,
                addedAt: Date()
            )
            modelContext.insert(newEpisode)
            playlist.episodeGuids.append(guid)
            playlist.updatedAt = Date()
            try? modelContext.save()

            let generator = UINotificationFeedbackGenerator()
            generator.notificationOccurred(.success)

            Task {
                _ = try? await APIClient.shared.addEpisodeToPlaylist(
                    playlistUuid: playlist.id,
                    episodeGuid: guid,
                    episodeTitle: title,
                    podcastId: podcastId,
                    podcastTitle: podcastTitle,
                    podcastArtworkUrl: podcastArtworkUrl,
                    enclosureUrl: enclosureUrl,
                    durationSecs: durationSecs
                )
            }
        }
    }

    public func removeEpisode(guid: String, from playlist: PlaylistItem, modelContext: ModelContext) {
        playlist.episodeGuids.removeAll(where: { $0 == guid })
        if playlist.lastPlayedEpisodeGuid == guid {
            playlist.lastPlayedEpisodeGuid = playlist.episodeGuids.first
            playlist.lastPlayedPositionSecs = 0
        }
        playlist.updatedAt = Date()

        let epId = "\(playlist.id)_\(guid)"
        var desc = FetchDescriptor<PlaylistEpisodeItem>(predicate: #Predicate { $0.id == epId })
        desc.fetchLimit = 1
        if let existing = try? modelContext.fetch(desc).first {
            modelContext.delete(existing)
        }
        try? modelContext.save()

        Task {
            try? await APIClient.shared.removeEpisodeFromPlaylist(playlistUuid: playlist.id, episodeGuid: guid)
        }
    }

    public func reorderEpisodes(playlist: PlaylistItem, newGuids: [String], modelContext: ModelContext) {
        playlist.episodeGuids = newGuids
        playlist.updatedAt = Date()

        let pId = playlist.id
        var desc = FetchDescriptor<PlaylistEpisodeItem>(predicate: #Predicate { $0.playlistId == pId })
        if let episodes = try? modelContext.fetch(desc) {
            for ep in episodes {
                if let newPos = newGuids.firstIndex(of: ep.episodeGuid) {
                    ep.position = newPos
                }
            }
        }
        try? modelContext.save()

        Task {
            _ = try? await APIClient.shared.reorderPlaylistEpisodes(playlistUuid: playlist.id, episodeGuids: newGuids)
        }
    }

    /// Called by AudioManager when an episode finishes playback.
    /// Handles continuous auto-advancing to the next episode in the active playlist.
    public func handleEpisodeFinished(episodeGuid: String, modelContext: ModelContext) {
        guard let pId = activePlaylistId else { return }

        var plDesc = FetchDescriptor<PlaylistItem>(predicate: #Predicate { $0.id == pId })
        plDesc.fetchLimit = 1
        guard let playlist = try? modelContext.fetch(plDesc).first else { return }

        let epId = "\(pId)_\(episodeGuid)"
        var epDesc = FetchDescriptor<PlaylistEpisodeItem>(predicate: #Predicate { $0.id == epId })
        epDesc.fetchLimit = 1
        let currentEpItem = try? modelContext.fetch(epDesc).first

        if playlist.autoRemoveFinished {
            playlist.episodeGuids.removeAll(where: { $0 == episodeGuid })
            if let item = currentEpItem {
                modelContext.delete(item)
            }
        } else {
            currentEpItem?.isCompleted = true
        }

        // Fetch remaining ordered episodes
        var allDesc = FetchDescriptor<PlaylistEpisodeItem>(
            predicate: #Predicate { $0.playlistId == pId },
            sortBy: [SortDescriptor(\.position, order: .forward)]
        )
        let allEpisodes = (try? modelContext.fetch(allDesc)) ?? []
        let remaining = allEpisodes.filter { $0.episodeGuid != episodeGuid && !$0.isCompleted }

        if let nextEp = remaining.first, let enclosure = nextEp.enclosureUrl, !enclosure.isEmpty {
            // Auto-advance to the next episode!
            playlist.lastPlayedEpisodeGuid = nextEp.episodeGuid
            playlist.lastPlayedPositionSecs = 0.0
            playlist.updatedAt = Date()
            try? modelContext.save()

            let playable = PlayableEpisode(
                podcastId: nextEp.podcastId ?? 0,
                podcastTitle: nextEp.podcastTitle,
                podcastArtworkUrl: nextEp.podcastArtworkUrl,
                episodeGuid: nextEp.episodeGuid,
                episodeTitle: nextEp.episodeTitle,
                enclosureUrl: enclosure,
                durationSecs: nextEp.durationSecs
            )

            Task { @MainActor in
                AudioManager.shared.play(episode: playable, startAt: 0)
            }
        } else {
            // Playlist finished
            playlist.lastPlayedEpisodeGuid = nil
            playlist.lastPlayedPositionSecs = 0.0
            playlist.updatedAt = Date()
            try? modelContext.save()
        }

        Task {
            _ = try? await APIClient.shared.completePlaylistEpisode(playlistUuid: pId, episodeGuid: episodeGuid)
        }
    }

    /// Sync local playlists with the Polarr server
    public func syncPlaylists(modelContext: ModelContext) async {
        do {
            let remotePlaylists = try await APIClient.shared.fetchPlaylists()
            for rpl in remotePlaylists {
                let pId = rpl.uuid
                var desc = FetchDescriptor<PlaylistItem>(predicate: #Predicate { $0.id == pId })
                desc.fetchLimit = 1
                let local = try? modelContext.fetch(desc).first

                if let loc = local {
                    loc.title = rpl.title
                    loc.playlistDescription = rpl.description
                    loc.isSmart = rpl.is_smart
                    loc.smartRules = rpl.smart_rules
                    loc.autoRemoveFinished = rpl.auto_remove_finished
                    if loc.lastPlayedEpisodeGuid == nil {
                        loc.lastPlayedEpisodeGuid = rpl.last_played_episode_guid
                        loc.lastPlayedPositionSecs = rpl.last_played_position_secs
                    }
                } else {
                    let newLoc = PlaylistItem(
                        id: rpl.uuid,
                        title: rpl.title,
                        playlistDescription: rpl.description,
                        isSmart: rpl.is_smart,
                        smartRules: rpl.smart_rules,
                        autoRemoveFinished: rpl.auto_remove_finished,
                        lastPlayedEpisodeGuid: rpl.last_played_episode_guid,
                        lastPlayedPositionSecs: rpl.last_played_position_secs
                    )
                    modelContext.insert(newLoc)
                }

                // Sync episodes for this playlist
                if let detail = try? await APIClient.shared.fetchPlaylistDetail(uuid: rpl.uuid) {
                    var epGuids: [String] = []
                    for ep in detail.episodes {
                        epGuids.append(ep.episode_guid)
                        let epId = "\(rpl.uuid)_\(ep.episode_guid)"
                        var epDesc = FetchDescriptor<PlaylistEpisodeItem>(predicate: #Predicate { $0.id == epId })
                        epDesc.fetchLimit = 1
                        if let locEp = try? modelContext.fetch(epDesc).first {
                            locEp.position = ep.position
                            locEp.isCompleted = ep.is_completed
                        } else {
                            let newEp = PlaylistEpisodeItem(
                                id: epId,
                                playlistId: rpl.uuid,
                                episodeGuid: ep.episode_guid,
                                episodeTitle: ep.episode_title,
                                podcastId: ep.podcast_id,
                                podcastTitle: ep.podcast_title,
                                podcastArtworkUrl: ep.podcast_artwork_url,
                                enclosureUrl: ep.enclosure_url,
                                durationSecs: ep.duration_secs,
                                position: ep.position,
                                isCompleted: ep.is_completed
                            )
                            modelContext.insert(newEp)
                        }
                    }
                    if let loc = local ?? (try? modelContext.fetch(desc).first) {
                        loc.episodeGuids = epGuids
                    }
                }
            }
            try? modelContext.save()
        } catch {
            print("Failed to sync playlists: \(error)")
        }
    }
}
