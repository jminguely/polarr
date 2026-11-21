import Foundation
import SwiftData

@Model
public final class NewEpisodeItem {
    @Attribute(.unique) public var id: Int
    public var podcastId: Int
    public var podcastTitle: String
    public var podcastArtworkUrl: String?
    public var episodeGuid: String
    public var title: String
    public var episodeDescription: String?
    public var enclosureUrl: String?
    public var durationSecs: Int?
    public var pubDate: Date?
    public var isDismissed: Bool
    public var isQueued: Bool
    public var discoveredAt: Date

    public init(
        id: Int,
        podcastId: Int,
        podcastTitle: String,
        podcastArtworkUrl: String? = nil,
        episodeGuid: String,
        title: String,
        episodeDescription: String? = nil,
        enclosureUrl: String? = nil,
        durationSecs: Int? = nil,
        pubDate: Date? = nil,
        isDismissed: Bool = false,
        isQueued: Bool = false,
        discoveredAt: Date = Date()
    ) {
        self.id = id
        self.podcastId = podcastId
        self.podcastTitle = podcastTitle
        self.podcastArtworkUrl = podcastArtworkUrl
        self.episodeGuid = episodeGuid
        self.title = title
        self.episodeDescription = episodeDescription
        self.enclosureUrl = enclosureUrl
        self.durationSecs = durationSecs
        self.pubDate = pubDate
        self.isDismissed = isDismissed
        self.isQueued = isQueued
        self.discoveredAt = discoveredAt
    }
}
