import Foundation
import SwiftData

@Model
public final class JournalEntryItem {
    @Attribute(.unique) public var id: Int
    public var podcastId: Int
    public var podcastTitle: String
    public var podcastArtworkUrl: String?
    public var episodeGuid: String
    public var episodeTitle: String
    public var completionType: String  // "finished", "skipped", "abandoned"
    public var episodeDurationSecs: Int?
    public var timeListenedSecs: Int?
    public var rating: Int?            // 1-5
    public var personalNote: String?
    public var playedAt: Date
    public var isSkipped: Bool
    public var isSynced: Bool

    @Relationship(deleteRule: .cascade) public var bookmarks: [ChapterBookmarkItem] = []

    public init(
        id: Int,
        podcastId: Int,
        podcastTitle: String,
        podcastArtworkUrl: String? = nil,
        episodeGuid: String,
        episodeTitle: String,
        completionType: String = "finished",
        episodeDurationSecs: Int? = nil,
        timeListenedSecs: Int? = nil,
        rating: Int? = nil,
        personalNote: String? = nil,
        playedAt: Date = Date(),
        isSkipped: Bool = false,
        isSynced: Bool = true
    ) {
        self.id = id
        self.podcastId = podcastId
        self.podcastTitle = podcastTitle
        self.podcastArtworkUrl = podcastArtworkUrl
        self.episodeGuid = episodeGuid
        self.episodeTitle = episodeTitle
        self.completionType = completionType
        self.episodeDurationSecs = episodeDurationSecs
        self.timeListenedSecs = timeListenedSecs
        self.rating = rating
        self.personalNote = personalNote
        self.playedAt = playedAt
        self.isSkipped = isSkipped
        self.isSynced = isSynced
    }
}
