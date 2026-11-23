import Foundation

// MARK: - API DTOs
public struct APIPodcast: Codable, Identifiable {
    public let id: Int
    public let title: String
    public let feed_url: String
    public let artwork_url: String?
    public let subscribed: Bool
    public let sync_order: String?
    public let sync_limit: Int?
    public let sync_start_after_guid: String?
    public let created_at: String?
    public let listened_count: Int
}

public struct APIEpisode: Codable, Identifiable {
    public var id: String { guid }
    public let guid: String
    public let title: String
    public let description: String?
    public let pub_date: String?
    public let link: String?
    public let enclosure_url: String?
    public let duration_secs: Int?
    public var durationSecs: Int? { duration_secs }
    public let played: Bool
    public let skipped: Bool
    public let completion_type: String?
    public let played_at: String?
    public let rating: Int?
    public let is_queued: Bool
}

public struct APINewEpisode: Codable, Identifiable {
    public let id: Int
    public let podcast_id: Int
    public let podcast_title: String?
    public let podcast_artwork_url: String?
    public let episode_guid: String
    public let title: String
    public let description: String?
    public let enclosure_url: String?
    public let duration_secs: Int?
    public let pub_date: String?
    public let is_dismissed: Bool
    public let is_queued: Bool
    public let discovered_at: String?
}

public struct APIQueueItem: Codable, Identifiable {
    public let id: Int
    public let podcast_id: Int
    public let podcast_title: String?
    public let podcast_artwork_url: String?
    public let episode_guid: String
    public let episode_title: String
    public let enclosure_url: String?
    public let duration_secs: Int?
    public let position: Int
    public let progress_secs: Int
    public let added_at: String?
}

public struct APIBookmark: Codable, Identifiable {
    public let id: Int
    public let journal_entry_id: Int
    public let timestamp_secs: Int
    public let label: String
    public let created_at: String?
}

public struct APIJournalEntry: Codable, Identifiable {
    public let id: Int
    public let podcast_id: Int
    public let podcast_title: String?
    public let podcast_artwork_url: String?
    public let episode_guid: String
    public let episode_title: String?
    public let completion_type: String?
    public let is_skipped: Bool
    public let episode_duration_secs: Int?
    public let time_listened_secs: Int?
    public let rating: Int?
    public let personal_note: String?
    public let played_at: String?
    public let bookmarks: [APIBookmark]?
}

public struct APISearchResult: Codable, Identifiable {
    public let id: Int?
    public let title: String?
    public let feed_url: String
    public let description: String?
    public let artwork_url: String?
    public let author: String?
    public let episode_count: Int?
    public let subscribed: Bool
}

public struct APISearchContainer: Codable {
    public let configured: Bool
    public let count: Int?
    public let results: [APISearchResult]
}

public struct APIStatsOverview: Codable {
    public let total_episodes_listened: Int
    public let total_episodes_skipped: Int
    public let total_episodes_abandoned: Int
    public let total_hours_listened: Double
    public let total_podcasts_tracked: Int
    public let first_listen_date: String?
}

public struct APITopPodcast: Codable, Identifiable {
    public var id: Int { podcast_id }
    public let podcast_id: Int
    public let title: String
    public let artwork_url: String?
    public let listened_count: Int
    public let hours_listened: Double
}

public struct APICompletionRate: Codable, Identifiable {
    public var id: Int { podcast_id }
    public let podcast_id: Int
    public let title: String
    public let artwork_url: String?
    public let total_feed_episodes: Int
    public let listened_episodes: Int
    public let completion_rate_pct: Double
}

// MARK: - Playlist DTOs
public struct APIPlaylist: Codable, Identifiable {
    public let id: Int
    public let uuid: String
    public let title: String
    public let description: String?
    public let is_smart: Bool
    public let smart_rules: String?
    public let auto_remove_finished: Bool
    public let last_played_episode_guid: String?
    public let last_played_position_secs: Double?
    public let episode_count: Int
    public let created_at: String?
    public let updated_at: String?
}

public struct APIPlaylistEpisode: Codable, Identifiable {
    public let id: Int
    public let playlist_id: Int
    public let episode_guid: String
    public let episode_title: String
    public let podcast_id: Int?
    public let podcast_title: String
    public let podcast_artwork_url: String?
    public let enclosure_url: String?
    public let duration_secs: Int?
    public let position: Int
    public let is_completed: Bool
    public let added_at: String?
}

public struct APIPlaylistDetail: Codable, Identifiable {
    public let id: Int
    public let uuid: String
    public let title: String
    public let description: String?
    public let is_smart: Bool
    public let smart_rules: String?
    public let auto_remove_finished: Bool
    public let last_played_episode_guid: String?
    public let last_played_position_secs: Double?
    public let episode_count: Int
    public let created_at: String?
    public let updated_at: String?
    public let episodes: [APIPlaylistEpisode]
}

public struct APISyncPullResponse: Codable {
    public let sync_token: String
    public let journal_entries: [APIJournalEntry]
    public let subscriptions: [APIPodcast]
    public let queue_items: [APIQueueItem]
}

// MARK: - API Client Implementation
public final class APIClient {
    public static let shared = APIClient()

    private let userDefaults = UserDefaults.standard
    private let serverURLKey = "polarr_server_url"
    private let apiKeyKey = "polarr_api_key"
    private let deviceIdKey = "polarr_device_id"

    public var serverURL: String {
        get { userDefaults.string(forKey: serverURLKey) ?? "http://localhost:8080" }
        set { userDefaults.set(newValue.trimmingCharacters(in: CharacterSet(charactersIn: "/ ")), forKey: serverURLKey) }
    }

    public var apiKey: String {
        get { userDefaults.string(forKey: apiKeyKey) ?? "" }
        set { userDefaults.set(newValue.trimmingCharacters(in: .whitespacesAndNewlines), forKey: apiKeyKey) }
    }

    public var deviceId: String {
        if let id = userDefaults.string(forKey: deviceIdKey) {
            return id
        }
        let newId = "ios-" + UUID().uuidString.prefix(8).lowercased()
        userDefaults.set(newId, forKey: deviceIdKey)
        return newId
    }

    private let jsonDecoder: JSONDecoder = {
        let dec = JSONDecoder()
        return dec
    }()

    private let jsonEncoder: JSONEncoder = {
        let enc = JSONEncoder()
        return enc
    }()

    private init() {}

    // MARK: - Network Request Helper
    private func makeRequest(endpoint: String, method: String = "GET", body: Data? = nil) throws -> URLRequest {
        guard let url = URL(string: "\(serverURL)/api/v1\(endpoint)") else {
            throw URLError(.badURL)
        }
        var req = URLRequest(url: url)
        req.httpMethod = method
        req.timeoutInterval = 15

        if !apiKey.isEmpty {
            req.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
            req.setValue(apiKey, forHTTPHeaderField: "X-Api-Key")
        }
        if let body = body {
            req.httpBody = body
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        return req
    }

    private func perform<T: Decodable>(endpoint: String, method: String = "GET", body: Data? = nil) async throws -> T {
        let req = try makeRequest(endpoint: endpoint, method: method, body: body)
        let (data, response) = try await URLSession.shared.data(for: req)
        guard let http = response as? HTTPURLResponse else {
            throw URLError(.badServerResponse)
        }
        guard (200...299).contains(http.statusCode) else {
            let msg = String(data: data, encoding: .utf8) ?? "HTTP \(http.statusCode)"
            throw NSError(domain: "PolarrAPI", code: http.statusCode, userInfo: [NSLocalizedDescriptionKey: msg])
        }
        return try jsonDecoder.decode(T.self, from: data)
    }

    public func performVoid(endpoint: String, method: String = "GET", body: Data? = nil) async throws {
        let req = try makeRequest(endpoint: endpoint, method: method, body: body)
        let (data, response) = try await URLSession.shared.data(for: req)
        guard let http = response as? HTTPURLResponse else {
            throw URLError(.badServerResponse)
        }
        guard (200...299).contains(http.statusCode) else {
            let msg = String(data: data, encoding: .utf8) ?? "HTTP \(http.statusCode)"
            throw NSError(domain: "PolarrAPI", code: http.statusCode, userInfo: [NSLocalizedDescriptionKey: msg])
        }
    }

    // MARK: - Podcasts API
    public func fetchPodcasts(subscribedOnly: Bool = true) async throws -> [APIPodcast] {
        return try await perform(endpoint: "/podcasts?subscribed_only=\(subscribedOnly)")
    }

    public func subscribePodcast(feedUrl: String, title: String? = nil, artworkUrl: String? = nil) async throws -> APIPodcast {
        var payload: [String: Any] = ["feed_url": feedUrl]
        if let t = title { payload["title"] = t }
        if let a = artworkUrl { payload["artwork_url"] = a }
        let body = try JSONSerialization.data(withJSONObject: payload)
        return try await perform(endpoint: "/podcasts", method: "POST", body: body)
    }

    public func unsubscribePodcast(podcastId: Int) async throws {
        try await performVoid(endpoint: "/podcasts/\(podcastId)", method: "DELETE")
    }

    public func fetchPodcastEpisodes(podcastId: Int) async throws -> [APIEpisode] {
        return try await perform(endpoint: "/podcasts/\(podcastId)/episodes")
    }

    public func toggleEpisodeSkipped(podcastId: Int, episodeGuid: String) async throws -> Bool {
        guard let encoded = episodeGuid.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) else {
            return false
        }
        struct ToggleSkipResponse: Codable {
            let status: String
            let skipped: Bool
        }
        let res: ToggleSkipResponse = try await perform(endpoint: "/podcasts/\(podcastId)/episodes/\(encoded)/toggle-skip", method: "POST")
        return res.skipped
    }

    // MARK: - Inbox API
    public func fetchInbox(limit: Int = 50) async throws -> [APINewEpisode] {
        return try await perform(endpoint: "/inbox?limit=\(limit)")
    }

    public func dismissInboxEpisode(id: Int) async throws {
        try await performVoid(endpoint: "/inbox/\(id)/dismiss", method: "POST")
    }

    public func queueInboxEpisode(id: Int) async throws -> APIQueueItem {
        return try await perform(endpoint: "/inbox/\(id)/queue", method: "POST")
    }

    public func refreshInbox() async throws {
        try await performVoid(endpoint: "/inbox/refresh", method: "POST")
    }

    // MARK: - Journal API
    public func fetchJournal(page: Int = 1, pageSize: Int = 50, completionType: String? = nil) async throws -> [APIJournalEntry] {
        var ep = "/journal?page=\(page)&page_size=\(pageSize)"
        if let ct = completionType { ep += "&completion_type=\(ct)" }
        return try await perform(endpoint: ep)
    }

    public func createJournalEntry(
        podcastId: Int,
        episodeGuid: String,
        episodeTitle: String,
        completionType: String = "finished",
        episodeDurationSecs: Int? = nil,
        timeListenedSecs: Int? = nil,
        rating: Int? = nil,
        personalNote: String? = nil
    ) async throws -> APIJournalEntry {
        var payload: [String: Any] = [
            "podcast_id": podcastId,
            "episode_guid": episodeGuid,
            "episode_title": episodeTitle,
            "completion_type": completionType
        ]
        if let d = episodeDurationSecs { payload["episode_duration_secs"] = d }
        if let tl = timeListenedSecs { payload["time_listened_secs"] = tl }
        if let r = rating { payload["rating"] = r }
        if let pn = personalNote { payload["personal_note"] = pn }
        let body = try JSONSerialization.data(withJSONObject: payload)
        return try await perform(endpoint: "/journal", method: "POST", body: body)
    }

    public func updateJournalEntry(
        entryId: Int,
        rating: Int? = nil,
        personalNote: String? = nil,
        completionType: String? = nil
    ) async throws -> APIJournalEntry {
        var payload: [String: Any] = [:]
        if let r = rating { payload["rating"] = r }
        if let pn = personalNote { payload["personal_note"] = pn }
        if let ct = completionType { payload["completion_type"] = ct }
        let body = try JSONSerialization.data(withJSONObject: payload)
        return try await perform(endpoint: "/journal/\(entryId)", method: "PATCH", body: body)
    }

    public func addBookmark(journalId: Int, timestampSecs: Int, label: String) async throws -> APIBookmark {
        let payload: [String: Any] = [
            "timestamp_secs": timestampSecs,
            "label": label
        ]
        let body = try JSONSerialization.data(withJSONObject: payload)
        return try await perform(endpoint: "/journal/\(journalId)/bookmarks", method: "POST", body: body)
    }

    public func deleteBookmark(bookmarkId: Int) async throws {
        try await performVoid(endpoint: "/journal/bookmarks/\(bookmarkId)", method: "DELETE")
    }

    // MARK: - Queue API
    public func fetchQueue() async throws -> [APIQueueItem] {
        return try await perform(endpoint: "/queue")
    }

    public func addToQueue(
        podcastId: Int,
        episodeGuid: String,
        episodeTitle: String,
        enclosureUrl: String?,
        durationSecs: Int?
    ) async throws -> APIQueueItem {
        var payload: [String: Any] = [
            "podcast_id": podcastId,
            "episode_guid": episodeGuid,
            "episode_title": episodeTitle
        ]
        if let enc = enclosureUrl { payload["enclosure_url"] = enc }
        if let dur = durationSecs { payload["duration_secs"] = dur }
        let body = try JSONSerialization.data(withJSONObject: payload)
        return try await perform(endpoint: "/queue", method: "POST", body: body)
    }

    public func reorderQueue(itemIds: [Int]) async throws {
        let payload = ["item_ids": itemIds]
        let body = try JSONSerialization.data(withJSONObject: payload)
        try await performVoid(endpoint: "/queue/reorder", method: "PATCH", body: body)
    }

    public func updateQueueProgress(itemId: Int, progressSecs: Int) async throws {
        let payload = ["progress_secs": progressSecs]
        let body = try JSONSerialization.data(withJSONObject: payload)
        try await performVoid(endpoint: "/queue/\(itemId)/progress", method: "PATCH", body: body)
    }

    public func deleteQueueItem(itemId: Int) async throws {
        try await performVoid(endpoint: "/queue/\(itemId)", method: "DELETE")
    }

    public func clearQueue() async throws {
        try await performVoid(endpoint: "/queue/clear", method: "POST")
    }

    // MARK: - Search API
    public func searchDirectory(query: String) async throws -> [APISearchResult] {
        guard let encoded = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) else {
            return []
        }
        let container: APISearchContainer = try await perform(endpoint: "/search?q=\(encoded)")
        return container.results
    }

    // MARK: - Sync API
    public func syncPull(since: String? = nil) async throws -> APISyncPullResponse {
        var ep = "/sync/pull"
        if let s = since, let enc = s.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) {
            ep += "?since=\(enc)"
        }
        return try await perform(endpoint: ep)
    }

    public func syncPush(journalPayloads: [[String: Any]], queuePayloads: [[String: Any]]? = nil) async throws {
        var payload: [String: Any] = [
            "device_id": deviceId,
            "journal_entries": journalPayloads
        ]
        if let qp = queuePayloads {
            payload["queue_items"] = qp
        }
        let body = try JSONSerialization.data(withJSONObject: payload)
        try await performVoid(endpoint: "/sync/push", method: "POST", body: body)
    }

    // MARK: - Stats API
    public func fetchStatsOverview() async throws -> APIStatsOverview {
        return try await perform(endpoint: "/stats/overview")
    }

    public func fetchTopPodcasts(period: String = "all", limit: Int = 10) async throws -> [APITopPodcast] {
        return try await perform(endpoint: "/stats/top?period=\(period)&limit=\(limit)")
    }

    public func fetchCompletionRates() async throws -> [APICompletionRate] {
        return try await perform(endpoint: "/stats/completion-rates")
    }

    // MARK: - Playlist API
    public func fetchPlaylists() async throws -> [APIPlaylist] {
        return try await perform(endpoint: "/playlists")
    }

    public func fetchPlaylistDetail(uuid: String) async throws -> APIPlaylistDetail {
        return try await perform(endpoint: "/playlists/\(uuid)")
    }

    public func createPlaylist(
        title: String,
        description: String? = nil,
        isSmart: Bool = false,
        smartRules: String? = nil,
        autoRemoveFinished: Bool = false,
        uuid: String? = nil
    ) async throws -> APIPlaylistDetail {
        var payload: [String: Any] = [
            "title": title,
            "is_smart": isSmart,
            "auto_remove_finished": autoRemoveFinished
        ]
        if let d = description { payload["description"] = d }
        if let sr = smartRules { payload["smart_rules"] = sr }
        if let u = uuid { payload["uuid"] = u }
        let body = try JSONSerialization.data(withJSONObject: payload)
        return try await perform(endpoint: "/playlists", method: "POST", body: body)
    }

    public func deletePlaylist(uuid: String) async throws {
        try await performVoid(endpoint: "/playlists/\(uuid)", method: "DELETE")
    }

    public func addEpisodeToPlaylist(
        playlistUuid: String,
        episodeGuid: String,
        episodeTitle: String,
        podcastId: Int?,
        podcastTitle: String,
        podcastArtworkUrl: String?,
        enclosureUrl: String?,
        durationSecs: Int?
    ) async throws -> APIPlaylistEpisode {
        var payload: [String: Any] = [
            "episode_guid": episodeGuid,
            "episode_title": episodeTitle,
            "podcast_title": podcastTitle
        ]
        if let pid = podcastId { payload["podcast_id"] = pid }
        if let art = podcastArtworkUrl { payload["podcast_artwork_url"] = art }
        if let enc = enclosureUrl { payload["enclosure_url"] = enc }
        if let dur = durationSecs { payload["duration_secs"] = dur }
        let body = try JSONSerialization.data(withJSONObject: payload)
        return try await perform(endpoint: "/playlists/\(playlistUuid)/episodes", method: "POST", body: body)
    }

    public func removeEpisodeFromPlaylist(playlistUuid: String, episodeGuid: String) async throws {
        guard let enc = episodeGuid.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) else { return }
        try await performVoid(endpoint: "/playlists/\(playlistUuid)/episodes/\(enc)", method: "DELETE")
    }

    public func reorderPlaylistEpisodes(playlistUuid: String, episodeGuids: [String]) async throws -> APIPlaylistDetail {
        let payload: [String: Any] = ["episode_guids": episodeGuids]
        let body = try JSONSerialization.data(withJSONObject: payload)
        return try await perform(endpoint: "/playlists/\(playlistUuid)/episodes/reorder", method: "PUT", body: body)
    }

    public func updatePlaylistProgress(playlistUuid: String, lastPlayedEpisodeGuid: String, lastPlayedPositionSecs: Double) async throws {
        let payload: [String: Any] = [
            "last_played_episode_guid": lastPlayedEpisodeGuid,
            "last_played_position_secs": lastPlayedPositionSecs
        ]
        let body = try JSONSerialization.data(withJSONObject: payload)
        try await performVoid(endpoint: "/playlists/\(playlistUuid)/progress", method: "POST", body: body)
    }

    public func completePlaylistEpisode(playlistUuid: String, episodeGuid: String) async throws -> APIPlaylistDetail {
        guard let enc = episodeGuid.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) else {
            throw URLError(.badURL)
        }
        return try await perform(endpoint: "/playlists/\(playlistUuid)/episodes/\(enc)/complete", method: "POST")
    }
}
