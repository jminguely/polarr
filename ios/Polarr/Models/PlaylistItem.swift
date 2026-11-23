import Foundation
import SwiftData

@Model
public final class PlaylistItem: Identifiable {
    @Attribute(.unique) public var id: String
    public var title: String
    public var playlistDescription: String?
    public var isSmart: Bool
    public var smartRules: String?
    public var autoRemoveFinished: Bool
    public var createdAt: Date
    public var updatedAt: Date

    // Independent persistent playback state per playlist
    public var lastPlayedEpisodeGuid: String?
    public var lastPlayedPositionSecs: Double?

    // Array of episode GUIDs in position order
    public var episodeGuids: [String] = []

    public init(
        id: String = UUID().uuidString,
        title: String,
        playlistDescription: String? = nil,
        isSmart: Bool = false,
        smartRules: String? = nil,
        autoRemoveFinished: Bool = false,
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        episodeGuids: [String] = [],
        lastPlayedEpisodeGuid: String? = nil,
        lastPlayedPositionSecs: Double? = nil
    ) {
        self.id = id
        self.title = title
        self.playlistDescription = playlistDescription
        self.isSmart = isSmart
        self.smartRules = smartRules
        self.autoRemoveFinished = autoRemoveFinished
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.episodeGuids = episodeGuids
        self.lastPlayedEpisodeGuid = lastPlayedEpisodeGuid
        self.lastPlayedPositionSecs = lastPlayedPositionSecs
    }
}
