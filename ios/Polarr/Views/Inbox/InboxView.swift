import SwiftUI
import SwiftData

struct InboxDetailTarget: Identifiable {
    var id: String { episode.guid }
    let podcast: PodcastItem
    let episode: APIEpisode
}

public struct InboxView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(filter: #Predicate<NewEpisodeItem> { !$0.isDismissed }, sort: \.pubDate, order: .reverse)
    private var episodes: [NewEpisodeItem]
    @Query private var allPodcasts: [PodcastItem]

    @Bindable var audioManager = AudioManager.shared
    @Bindable var syncManager = SyncManager.shared
    @State private var isRefreshing: Bool = false
    @State private var showSettings: Bool = false
    @State private var detailTarget: InboxDetailTarget?

    public init() {}

    public var body: some View {
        NavigationStack {
            ZStack {
                BrandTheme.bgPrimary.ignoresSafeArea()

                if episodes.isEmpty {
                    emptyInboxView
                } else {
                    ScrollView {
                        LazyVStack(spacing: 12) {
                            ForEach(episodes) { ep in
                                inboxCard(for: ep)
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.top, 12)
                        .padding(.bottom, 90) // clearance for mini player
                    }
                    .refreshable {
                        await refreshInbox()
                    }
                }
            }
            .navigationTitle("What's New")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        showSettings = true
                    } label: {
                        Image(systemName: "gearshape")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(BrandTheme.textSecondary)
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        Task { await refreshInbox() }
                    } label: {
                        if syncManager.isSyncing || isRefreshing {
                            ProgressView()
                                .tint(BrandTheme.cyan)
                                .scaleEffect(0.8)
                        } else {
                            Image(systemName: "arrow.clockwise")
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundStyle(BrandTheme.cyan)
                        }
                    }
                }
            }
            .sheet(isPresented: $showSettings) {
                SettingsView()
            }
            .sheet(item: $detailTarget) { target in
                EpisodeDetailSheet(podcast: target.podcast, episode: target.episode)
            }
        }
    }

    private func inboxCard(for ep: NewEpisodeItem) -> some View {
        let matchingPod = allPodcasts.first(where: { $0.id == ep.podcastId })

        return VStack(alignment: .leading, spacing: 10) {
            // Tappable Header: Artwork + Podcast Title + Navigation to Podcast View
            if let pod = matchingPod {
                NavigationLink(destination: PodcastDetailView(podcast: pod)) {
                    inboxHeaderRow(for: ep, showChevron: true)
                }
                .buttonStyle(.plain)
            } else {
                inboxHeaderRow(for: ep, showChevron: false)
            }

            // Episode Title & Description (Tappable to open Episode Details)
            Button {
                if let pod = matchingPod {
                    let apiEp = APIEpisode(
                        guid: ep.episodeGuid,
                        title: ep.title,
                        description: ep.episodeDescription,
                        pub_date: ep.pubDate != nil ? ISO8601DateFormatter().string(from: ep.pubDate!) : nil,
                        link: nil,
                        enclosure_url: ep.enclosureUrl,
                        duration_secs: ep.durationSecs,
                        played: false,
                        skipped: false,
                        completion_type: nil,
                        played_at: nil,
                        rating: nil,
                        is_queued: ep.isQueued
                    )
                    detailTarget = InboxDetailTarget(podcast: pod, episode: apiEp)
                }
            } label: {
                VStack(alignment: .leading, spacing: 6) {
                    Text(ep.title)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(BrandTheme.textPrimary)
                        .multilineTextAlignment(.leading)
                        .lineLimit(2)

                    if let desc = ep.episodeDescription, !desc.isEmpty {
                        Text(cleanHTML(desc))
                            .font(.system(size: 13))
                            .foregroundStyle(BrandTheme.textSecondary)
                            .multilineTextAlignment(.leading)
                            .lineLimit(2)
                    }
                }
            }
            .buttonStyle(.plain)

            Divider().background(BrandTheme.border)

            // Action Buttons
            HStack(spacing: 12) {
                // Play Now
                Button {
                    playEpisode(ep)
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "play.fill")
                            .font(.system(size: 12, weight: .bold))
                        Text("Play")
                            .font(.system(size: 13, weight: .bold))
                    }
                    .foregroundStyle(Color.black)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(BrandTheme.brandGradient)
                    .clipShape(Capsule())
                }

                // Add to Queue
                Button {
                    queueEpisode(ep)
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: ep.isQueued ? "checkmark" : "plus")
                            .font(.system(size: 12, weight: .bold))
                        Text(ep.isQueued ? "Queued" : "Queue")
                            .font(.system(size: 13, weight: .semibold))
                    }
                    .foregroundStyle(ep.isQueued ? BrandTheme.emerald : BrandTheme.textPrimary)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(BrandTheme.bgSecondary)
                    .clipShape(Capsule())
                }

                Spacer()

                // Dismiss Button
                Button {
                    dismissEpisode(ep)
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(BrandTheme.textMuted)
                        .padding(8)
                }
            }
        }
        .padding(14)
        .polarrCard(cornerRadius: 16)
    }

    private var emptyInboxView: some View {
        VStack(spacing: 16) {
            Image(systemName: "tray")
                .font(.system(size: 48, weight: .light))
                .foregroundStyle(BrandTheme.textMuted)

            Text("All Caught Up!")
                .font(.system(size: 18, weight: .bold))
                .foregroundStyle(BrandTheme.textPrimary)

            Text("New episodes from your subscribed podcasts will automatically appear here as they are released.")
                .font(.system(size: 14))
                .foregroundStyle(BrandTheme.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)

            HStack(spacing: 12) {
                Button {
                    Task { await refreshInbox() }
                } label: {
                    Text("Check for New Episodes")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(BrandTheme.cyan)
                        .padding(.horizontal, 18)
                        .padding(.vertical, 10)
                        .background(BrandTheme.bgSecondary)
                        .clipShape(Capsule())
                }

                Button {
                    showSettings = true
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "gearshape.fill")
                        Text("Settings")
                    }
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(BrandTheme.textPrimary)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(BrandTheme.bgCard)
                    .clipShape(Capsule())
                }
            }
            .padding(.top, 8)
        }
    }

    private func playEpisode(_ ep: NewEpisodeItem) {
        guard let enc = ep.enclosureUrl, !enc.isEmpty else { return }
        let playable = PlayableEpisode(
            podcastId: ep.podcastId,
            podcastTitle: ep.podcastTitle,
            podcastArtworkUrl: ep.podcastArtworkUrl,
            episodeGuid: ep.episodeGuid,
            episodeTitle: ep.title,
            enclosureUrl: enc,
            durationSecs: ep.durationSecs
        )
        audioManager.play(episode: playable)
    }

    private func queueEpisode(_ ep: NewEpisodeItem) {
        ep.isQueued = true
        let qItem = QueueEpisodeItem(
            id: Int.random(in: 100_000...999_999),
            podcastId: ep.podcastId,
            podcastTitle: ep.podcastTitle,
            podcastArtworkUrl: ep.podcastArtworkUrl,
            episodeGuid: ep.episodeGuid,
            episodeTitle: ep.title,
            enclosureUrl: ep.enclosureUrl,
            durationSecs: ep.durationSecs
        )
        modelContext.insert(qItem)
        try? modelContext.save()

        Task {
            _ = try? await APIClient.shared.queueInboxEpisode(id: ep.id)
        }
    }

    private func dismissEpisode(_ ep: NewEpisodeItem) {
        ep.isDismissed = true
        try? modelContext.save()

        Task {
            try? await APIClient.shared.dismissInboxEpisode(id: ep.id)
        }
    }

    private func refreshInbox() async {
        isRefreshing = true
        defer { isRefreshing = false }
        try? await APIClient.shared.refreshInbox()
        await syncManager.sync(modelContext: modelContext, force: true)
    }

    private func inboxHeaderRow(for ep: NewEpisodeItem, showChevron: Bool) -> some View {
        HStack(spacing: 10) {
            AsyncArtworkView(urlString: ep.podcastArtworkUrl, size: 40, cornerRadius: 8)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Text(ep.podcastTitle)
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(BrandTheme.cyan)
                        .lineLimit(1)

                    if showChevron {
                        Image(systemName: "chevron.right")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(BrandTheme.textMuted)
                    }
                }

                if let pub = ep.pubDate {
                    Text(relativeDateString(for: pub))
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(BrandTheme.textMuted)
                }
            }

            Spacer()

            if let dur = ep.durationSecs {
                Text(formatTime(seconds: dur))
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                    .foregroundStyle(BrandTheme.textSecondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(BrandTheme.bgSecondary)
                    .clipShape(Capsule())
            }
        }
    }

    private func relativeDateString(for date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: date, relativeTo: Date())
    }

    private func cleanHTML(_ raw: String) -> String {
        raw.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression, range: nil)
            .replacingOccurrences(of: "&nbsp;", with: " ")
            .replacingOccurrences(of: "&#39;", with: "'")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
