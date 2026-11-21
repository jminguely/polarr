import Foundation
import SwiftData

@Model
public final class PodcastItem {
    @Attribute(.unique) public var id: Int
    public var title: String
    public var feedUrl: String
    public var artworkUrl: String?
    public var isSubscribed: Bool
    public var syncOrder: String
    public var syncLimit: Int
    public var syncStartAfterGuid: String?
    public var createdAt: Date
    public var listenedCount: Int

    public init(
        id: Int,
        title: String,
        feedUrl: String,
        artworkUrl: String? = nil,
        isSubscribed: Bool = true,
        syncOrder: String = "oldest_first",
        syncLimit: Int = 5,
        syncStartAfterGuid: String? = nil,
        createdAt: Date = Date(),
        listenedCount: Int = 0
    ) {
        self.id = id
        self.title = title
        self.feedUrl = feedUrl
        self.artworkUrl = artworkUrl
        self.isSubscribed = isSubscribed
        self.syncOrder = syncOrder
        self.syncLimit = syncLimit
        self.syncStartAfterGuid = syncStartAfterGuid
        self.createdAt = createdAt
        self.listenedCount = listenedCount
    }
}
