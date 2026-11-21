import Foundation
import SwiftData
import SwiftUI

@Observable
public final class SyncManager {
    public static let shared = SyncManager()

    public var isSyncing: Bool = false
    public var lastSyncTime: Date?
    public var syncError: String?

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
    public func sync(modelContext: ModelContext) async {
        guard !isSyncing else { return }
        isSyncing = true
        syncError = nil
        defer { isSyncing = false }

        do {
            // 1. Push unsynced local journal entries
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

            // 2. Pull server changes
            let pullResult = try await APIClient.shared.syncPull()

            // 3. Upsert subscriptions
            for p in pullResult.subscriptions {
                let podId = p.id
                var podDesc = FetchDescriptor<PodcastItem>(predicate: #Predicate { $0.id == podId })
                podDesc.fetchLimit = 1
                let existing = try modelContext.fetch(podDesc).first

                if let existing = existing {
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
                }
            }

            // 4. Update Queue items from server
            let allLocalQueue = try modelContext.fetch(FetchDescriptor<QueueEpisodeItem>())
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

            // 5. Update Journal Entries from server
            for j in pullResult.journal_entries {
                let jId = j.id
                var jDesc = FetchDescriptor<JournalEntryItem>(predicate: #Predicate { $0.id == jId })
                jDesc.fetchLimit = 1
                let existing = try modelContext.fetch(jDesc).first

                let playedDate: Date
                if let pStr = j.played_at, let parsed = Self.parseServerDate(pStr) {
                    playedDate = parsed
                } else if let existing = existing {
                    playedDate = existing.playedAt
                } else {
                    playedDate = Date.distantPast
                }

                if let existing = existing {
                    existing.completionType = j.completion_type ?? "finished"
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
                        completionType: j.completion_type ?? "finished",
                        episodeDurationSecs: j.episode_duration_secs,
                        timeListenedSecs: j.time_listened_secs,
                        rating: j.rating,
                        personalNote: j.personal_note,
                        playedAt: playedDate,
                        isSkipped: j.is_skipped,
                        isSynced: true
                    )
                    modelContext.insert(newJournal)
                }
            }

            // 6. Pull fresh Inbox episodes
            let inboxData = try await APIClient.shared.fetchInbox()
            let allLocalInbox = try modelContext.fetch(FetchDescriptor<NewEpisodeItem>())
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
        } catch {
            print("Sync failed: \(error)")
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
        var qDesc = FetchDescriptor<QueueEpisodeItem>(predicate: #Predicate { $0.episodeGuid == epGuid })
        if let queued = try? modelContext.fetch(qDesc).first {
            modelContext.delete(queued)
        }

        // Remove from local Inbox
        var inbDesc = FetchDescriptor<NewEpisodeItem>(predicate: #Predicate { $0.episodeGuid == epGuid })
        if let inb = try? modelContext.fetch(inbDesc).first {
            modelContext.delete(inb)
        }

        try? modelContext.save()

        // Push immediately in background task
        Task {
            await sync(modelContext: modelContext)
        }
    }
}
