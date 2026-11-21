import Foundation
import SwiftData

@Model
public final class ChapterBookmarkItem {
    @Attribute(.unique) public var id: Int
    public var journalEntryId: Int
    public var timestampSecs: Int
    public var label: String
    public var createdAt: Date

    public init(
        id: Int,
        journalEntryId: Int,
        timestampSecs: Int,
        label: String,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.journalEntryId = journalEntryId
        self.timestampSecs = timestampSecs
        self.label = label
        self.createdAt = createdAt
    }
}
