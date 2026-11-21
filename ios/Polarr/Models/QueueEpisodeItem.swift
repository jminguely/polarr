import Foundation
import SwiftData

@Model
public final class QueueEpisodeItem {
    @Attribute(.unique) public var id: Int
    public var podcastId: Int
    public var podcastTitle: String
    public var podcastArtworkUrl: String?
    public var episodeGuid: String
    public var episodeTitle: String
    public var enclosureUrl: String?
    public var durationSecs: Int?
    public var position: Int
    public var progressSecs: Int
    public var addedAt: Date

    public init(
        id: Int,
        podcastId: Int,
        podcastTitle: String,
        podcastArtworkUrl: String? = nil,
        episodeGuid: String,
        episodeTitle: String,
        enclosureUrl: String? = nil,
        durationSecs: Int? = nil,
        position: Int = 0,
        progressSecs: Int = 0,
        addedAt: Date = Date()
    ) {
        self.id = id
        self.podcastId = podcastId
        self.podcastTitle = podcastTitle
        self.podcastArtworkUrl = podcastArtworkUrl
        self.episodeGuid = episodeGuid
        self.episodeTitle = episodeTitle
        self.enclosureUrl = enclosureUrl
        self.durationSecs = durationSecs
        self.position = position
        self.progressSecs = progressSecs
        self.addedAt = addedAt
    }
}
