import Foundation

/// Local disk cache for podcast episode lists, allowing full offline browsing and resilience against server crashes.
public final class EpisodeCacheManager {
    public static let shared = EpisodeCacheManager()

    private let fileManager = FileManager.default

    private var cacheFolder: URL {
        let dir = fileManager.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("PolarrEpisodeCache", isDirectory: true)
        if !fileManager.fileExists(atPath: dir.path) {
            try? fileManager.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        return dir
    }

    private func fileURL(for podcastId: Int) -> URL {
        cacheFolder.appendingPathComponent("podcast_\(podcastId)_episodes.json")
    }

    public func getCachedEpisodes(for podcastId: Int) -> [APIEpisode]? {
        let url = fileURL(for: podcastId)
        guard let data = try? Data(contentsOf: url),
              let list = try? JSONDecoder().decode([APIEpisode].self, from: data) else {
            return nil
        }
        return list
    }

    public func saveEpisodes(_ episodes: [APIEpisode], for podcastId: Int) {
        let url = fileURL(for: podcastId)
        if let data = try? JSONEncoder().encode(episodes) {
            try? data.write(to: url, options: .atomic)
        }
    }
}
