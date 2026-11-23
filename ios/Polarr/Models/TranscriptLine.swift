import Foundation

public struct TranscriptLine: Identifiable, Equatable, Hashable, Sendable {
    public let id: String
    public let startSeconds: Double
    public let endSeconds: Double
    public let speaker: String?
    public let text: String

    public init(
        id: String = UUID().uuidString,
        startSeconds: Double,
        endSeconds: Double,
        speaker: String? = nil,
        text: String
    ) {
        self.id = id
        self.startSeconds = startSeconds
        self.endSeconds = endSeconds
        self.speaker = speaker
        self.text = text
    }
}
