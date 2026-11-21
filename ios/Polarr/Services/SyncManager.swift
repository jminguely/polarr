import Foundation
import SwiftData
import SwiftUI

@Observable
public final class SyncManager {
    public static let shared = SyncManager()

    public var isSyncing: Bool = false
    public var lastSyncTime: Date?
    public var syncError: String?

    private let kLastSyncTokenKey = "polarr_last_sync_token"

    private init() {}

    public static func parseServerDate(_ str: String?) -> Date? {
        guard let str = str?.trimmingCharacters(in: .whitespacesAndNewlines), !str.isEmpty else { return nil }

        // 1. Try ISO8601 with fractional seconds (e.g. 2025-03-15T13:16:20.126000Z or +00:00)
        let f1 = ISO8601DateFormatter()
        f1.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = f1.date(from: str) { return d }

        // 2. Try standard ISO8601 without fractional seconds
        let f2 = ISO8601DateFormatter()
        f2.formatOptions = [.withInternetDateTime]
        if let d = f2.date(from: str) { return d }

        // 3. Fallback date formatter for space-separated or non-standard date strings
        let df = DateFormatter()
        df.locale = Locale(identifier: "en_US_POSIX")
        df.timeZone = TimeZone(secondsFromGMT: 0)
        for format in [
            "yyyy-MM-dd'T'HH:mm:ss.SSSSSSZ",
            "yyyy-MM-dd'T'HH:mm:ss.SSSSSS",
            "yyyy-MM-dd'T'HH:mm:ss.SSSZ",
            "yyyy-MM-dd'T'HH:mm:ss.SSS",
            "yyyy-MM-dd HH:mm:ss.SSSSSS",
            "yyyy-MM-dd HH:mm:ss",
            "yyyy-MM-dd'T'HH:mm:ss",
            "yyyy-MM-dd"
        ] {
            df.dateFormat = format
            if let d = df.date(from: str) { return d }
        }
        return nil
    }

    @MainActor
    public func sync(modelContext: ModelContext, force: Bool = false) async {
        guard !isSyncing else { return }

        // Debounce: Avoid re-syncing if a successful sync ran within the last 20 seconds, unless forced
        if !force, let last = lastSyncTime, Date().timeIntervalSince(last) < 20 {
            return
        }

        isSyncing = true
        syncError = nil
        defer { isSyncing = false }

        do {
            // 1. Push unsynced local journal entries first
            let descriptor = FetchDescriptor<JournalEntryItem>(predicate: #Predicate { !$0.isSynced })
            let unsyncedEntries = try modelContext.fetch(descriptor)

            if !unsyncedEntries.isEmpty {
                let payloads = unsyncedEntries.map { entry -> [String: Any] in
                    var dict: [String: Any] = [
                        "podcast_id": entry.podcastId,
                        "episode_guid": entry.episodeGuid,
                        "episode_title": entry.episodeTitle,
                        "completion_type": entry.completionType,
                        "played_at": ISO8601DateFormatter().string(from: entry.playedAt)
                    ]
                    if let dur = entry.episodeDurationSecs { dict["episode_duration_secs"] = dur }
                    if let tl = entry.timeListenedSecs { dict["time_listened_secs"] = tl }
                    if let r = entry.rating { dict["rating"] = r }
                    if let n = entry.personalNote { dict["personal_note"] = n }
                    return dict
                }
                try await APIClient.shared.syncPush(journalPayloads: payloads)
                for entry in unsyncedEntries {
                    entry.isSynced = true
                }
                try modelContext.save()
            }

            // Yield to main run loop so UI remains completely responsive
            await Task.yield()

            // 2. Incremental Pull: Pass last_sync_token to fetch only changes
            let lastToken = force ? nil : UserDefaults.standard.string(forKey: kLastSyncTokenKey)
            let pullResult = try await APIClient.shared.syncPull(since: lastToken)

            await Task.yield()

            // 3. Batch upsert subscriptions using in-memory dictionary lookup (O(1) instead of N queries)
            let allLocalPods = (try? modelContext.fetch(FetchDescriptor<PodcastItem>())) ?? []
            var podDict: [Int: PodcastItem] = [:]
            for pod in allLocalPods {
                podDict[pod.id] = pod
            }

            for p in pullResult.subscriptions {
                if let existing = podDict[p.id] {
                    existing.title = p.title
                    existing.feedUrl = p.feed_url
                    existing.artworkUrl = p.artwork_url
                    existing.isSubscribed = p.subscribed
                    existing.syncOrder = p.sync_order ?? "oldest_first"
                    existing.syncLimit = p.sync_limit ?? 5
                    existing.listenedCount = p.listened_count
                } else {
                    let newPod = PodcastItem(
                        id: p.id,
                        title: p.title,
                        feedUrl: p.feed_url,
                        artworkUrl: p.artwork_url,
                        isSubscribed: p.subscribed,
                        syncOrder: p.sync_order ?? "oldest_first",
                        syncLimit: p.sync_limit ?? 5,
                        syncStartAfterGuid: p.sync_start_after_guid,
                        listenedCount: p.listened_count
                    )
                    modelContext.insert(newPod)
                    podDict[p.id] = newPod
                }
            }

            await Task.yield()

            // 4. Update Queue items from server
            let allLocalQueue = (try? modelContext.fetch(FetchDescriptor<QueueEpisodeItem>())) ?? []
            for item in allLocalQueue {
                modelContext.delete(item)
            }
            for q in pullResult.queue_items {
                let queueItem = QueueEpisodeItem(
                    id: q.id,
                    podcastId: q.podcast_id,
                    podcastTitle: q.podcast_title ?? "Podcast",
                    podcastArtworkUrl: q.podcast_artwork_url,
                    episodeGuid: q.episode_guid,
                    episodeTitle: q.episode_title,
                    enclosureUrl: q.enclosure_url,
                    durationSecs: q.duration_secs,
                    position: q.position,
                    progressSecs: q.progress_secs
                )
                modelContext.insert(queueItem)
            }

            await Task.yield()

            // 5. Batch upsert Journal Entries using in-memory dictionary lookup
            // Pre-fetches all local IDs in 1 query instead of thousands of individual queries
            let allLocalJournal = (try? modelContext.fetch(FetchDescriptor<JournalEntryItem>())) ?? []
            var journalDict: [Int: JournalEntryItem] = [:]
            for entry in allLocalJournal {
                journalDict[entry.id] = entry
            }

            for j in pullResult.journal_entries {
                let isSkip = j.is_skipped || j.completion_type == "skipped"
                let playedDate: Date
                if let pStr = j.played_at, let parsed = Self.parseServerDate(pStr) {
                    playedDate = parsed
                } else if let existing = journalDict[j.id] {
                    playedDate = existing.playedAt
                } else {
                    playedDate = Date.distantPast
                }

                if let existing = journalDict[j.id] {
                    existing.completionType = isSkip ? "skipped" : (j.completion_type ?? "finished")
                    existing.isSkipped = isSkip
                    existing.rating = j.rating
                    existing.personalNote = j.personal_note
                    existing.episodeDurationSecs = j.episode_duration_secs
                    existing.timeListenedSecs = j.time_listened_secs
                    existing.playedAt = playedDate
                    existing.isSynced = true
                } else {
                    let newJournal = JournalEntryItem(
                        id: j.id,
                        podcastId: j.podcast_id,
                        podcastTitle: j.podcast_title ?? "Podcast",
                        podcastArtworkUrl: j.podcast_artwork_url,
                        episodeGuid: j.episode_guid,
                        episodeTitle: j.episode_title ?? "Episode",
                        completionType: isSkip ? "skipped" : (j.completion_type ?? "finished"),
                        episodeDurationSecs: j.episode_duration_secs,
                        timeListenedSecs: j.time_listened_secs,
                        rating: j.rating,
                        personalNote: j.personal_note,
                        playedAt: playedDate,
                        isSkipped: isSkip,
                        isSynced: true
                    )
                    modelContext.insert(newJournal)
                    journalDict[j.id] = newJournal
                }
            }

            await Task.yield()

            // 6. Pull fresh Inbox episodes
            let inboxData = try await APIClient.shared.fetchInbox()
            let allLocalInbox = (try? modelContext.fetch(FetchDescriptor<NewEpisodeItem>())) ?? []
            for item in allLocalInbox {
                modelContext.delete(item)
            }
            for inb in inboxData {
                let pubDate: Date? = Self.parseServerDate(inb.pub_date)
                let newInb = NewEpisodeItem(
                    id: inb.id,
                    podcastId: inb.podcast_id,
                    podcastTitle: inb.podcast_title ?? "Podcast",
                    podcastArtworkUrl: inb.podcast_artwork_url,
                    episodeGuid: inb.episode_guid,
                    title: inb.title,
                    episodeDescription: inb.description,
                    enclosureUrl: inb.enclosure_url,
                    durationSecs: inb.duration_secs,
                    pubDate: pubDate,
                    isDismissed: inb.is_dismissed,
                    isQueued: inb.is_queued
                )
                modelContext.insert(newInb)
            }

            try modelContext.save()
            lastSyncTime = Date()
            UserDefaults.standard.set(pullResult.sync_token, forKey: kLastSyncTokenKey)
        } catch {
            print("Background sync finished with notice: \(error.localizedDescription)")
            syncError = error.localizedDescription
        }
    }

    @MainActor
    public func recordPlaybackFinished(
        episode: PlayableEpisode,
        timeListened: Double,
        completionType: String = "finished",
        modelContext: ModelContext
    ) {
        // Create local journal entry
        let entry = JournalEntryItem(
            id: Int.random(in: 100_000...999_999),
            podcastId: episode.podcastId,
            podcastTitle: episode.podcastTitle,
            podcastArtworkUrl: episode.podcastArtworkUrl,
            episodeGuid: episode.episodeGuid,
            episodeTitle: episode.episodeTitle,
            completionType: completionType,
            episodeDurationSecs: episode.durationSecs,
            timeListenedSecs: Int(timeListened),
            playedAt: Date(),
            isSkipped: completionType == "skipped",
            isSynced: false
        )
        modelContext.insert(entry)

        // Remove from local Queue
        let epGuid = episode.episodeGuid
        let qDesc = FetchDescriptor<QueueEpisodeItem>(predicate: #Predicate { $0.episodeGuid == epGuid })
        if let queued = try? modelContext.fetch(qDesc).first {
            modelContext.delete(queued)
        }

        // Remove from local Inbox
        let inbDesc = FetchDescriptor<NewEpisodeItem>(predicate: #Predicate { $0.episodeGuid == epGuid })
        if let inb = try? modelContext.fetch(inbDesc).first {
            modelContext.delete(inb)
        }

        try? modelContext.save()

        // Push immediately in background task
        Task(priority: .utility) {
            await sync(modelContext: modelContext, force: true)
        }
    }
}
