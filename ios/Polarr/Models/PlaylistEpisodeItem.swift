import Foundation
import SwiftData

@Model
public final class PlaylistEpisodeItem: Identifiable {
    @Attribute(.unique) public var id: String // "\(playlistId)_\(episodeGuid)"
    public var playlistId: String
    public var episodeGuid: String
    public var episodeTitle: String
    public var podcastId: Int?
    public var podcastTitle: String
    public var podcastArtworkUrl: String?
    public var enclosureUrl: String?
    public var durationSecs: Int?
    public var position: Int
    public var isCompleted: Bool
    public var addedAt: Date

    public init(
        id: String? = nil,
        playlistId: String,
        episodeGuid: String,
        episodeTitle: String,
        podcastId: Int? = nil,
        podcastTitle: String,
        podcastArtworkUrl: String? = nil,
        enclosureUrl: String? = nil,
        durationSecs: Int? = nil,
        position: Int = 0,
        isCompleted: Bool = false,
        addedAt: Date = Date()
    ) {
        self.id = id ?? "\(playlistId)_\(episodeGuid)"
        self.playlistId = playlistId
        self.episodeGuid = episodeGuid
        self.episodeTitle = episodeTitle
        self.podcastId = podcastId
        self.podcastTitle = podcastTitle
        self.podcastArtworkUrl = podcastArtworkUrl
        self.enclosureUrl = enclosureUrl
        self.durationSecs = durationSecs
        self.position = position
        self.isCompleted = isCompleted
        self.addedAt = addedAt
    }
}
