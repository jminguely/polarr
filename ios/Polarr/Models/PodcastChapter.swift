import Foundation

public struct PodcastChapter: Identifiable, Equatable, Hashable, Sendable {
    public let id: String
    public let title: String
    public let startTime: Double
    public let duration: Double?
    public let imageUrl: String?
    public let url: String?

    public init(
        id: String = UUID().uuidString,
        title: String,
        startTime: Double,
        duration: Double? = nil,
        imageUrl: String? = nil,
        url: String? = nil
    ) {
        self.id = id
        self.title = title
        self.startTime = startTime
        self.duration = duration
        self.imageUrl = imageUrl
        self.url = url
    }
}
