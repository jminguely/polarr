import SwiftUI
import SwiftData

public struct EpisodeDetailSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    public let podcast: PodcastItem
    public let episode: APIEpisode

    @Bindable var audioManager = AudioManager.shared
    @Bindable var downloadManager = DownloadManager.shared

    @State private var isQueued: Bool = false
    @State private var isSkipped: Bool = false
    @State private var isPlayed: Bool = false
    @State private var showAddToPlaylistSheet: Bool = false

    public init(podcast: PodcastItem, episode: APIEpisode) {
        self.podcast = podcast
        self.episode = episode
        self._isQueued = State(initialValue: episode.is_queued)
        self._isSkipped = State(initialValue: episode.skipped)
        self._isPlayed = State(initialValue: episode.played)
    }

    private var isCurrentPlaying: Bool {
        audioManager.currentEpisode?.episodeGuid == episode.guid
    }

    private var currentProgress: Double {
        if isCurrentPlaying {
            return audioManager.currentTime
        }
        return audioManager.getSavedProgress(for: episode.guid) ?? 0
    }

    public var body: some View {
        NavigationStack {
            ZStack {
                BrandTheme.bgPrimary.ignoresSafeArea()

                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        // Header: Artwork + Titles
                        HStack(alignment: .top, spacing: 16) {
                            AsyncArtworkView(urlString: podcast.artworkUrl, size: 84, cornerRadius: 16)
                                .shadow(color: BrandTheme.cyan.opacity(0.2), radius: 10, x: 0, y: 4)

                            VStack(alignment: .leading, spacing: 6) {
                                Text(podcast.title)
                                    .font(.system(size: 13, weight: .bold))
                                    .foregroundStyle(BrandTheme.cyan)
                                    .lineLimit(1)

                                Text(episode.title)
                                    .font(.system(size: 17, weight: .bold))
                                    .foregroundStyle(BrandTheme.textPrimary)
                                    .lineLimit(3)
                            }
                        }

                        // Metadata Badges (Duration, Date, Status, Offline)
                        HStack(spacing: 8) {
                            if let dur = episode.durationSecs {
                                Label(formatTime(seconds: dur), systemImage: "clock")
                                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                                    .foregroundStyle(BrandTheme.textSecondary)
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 5)
                                    .background(BrandTheme.bgSecondary)
                                    .clipShape(Capsule())
                            }

                            if let pub = episode.pub_date, let date = parseServerDate(pub) {
                                Label(date.formatted(date: .abbreviated, time: .omitted), systemImage: "calendar")
                                    .font(.system(size: 11, weight: .medium))
                                    .foregroundStyle(BrandTheme.textSecondary)
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 5)
                                    .background(BrandTheme.bgSecondary)
                                    .clipShape(Capsule())
                            }

                            if episode.played && !isSkipped {
                                Label("Listened", systemImage: "checkmark.circle.fill")
                                    .font(.system(size: 11, weight: .medium))
                                    .foregroundStyle(BrandTheme.emerald)
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 5)
                                    .background(BrandTheme.emerald.opacity(0.12))
                                    .clipShape(Capsule())
                            } else if isSkipped {
                                Label("Skipped", systemImage: "slash.circle.fill")
                                    .font(.system(size: 11, weight: .medium))
                                    .foregroundStyle(BrandTheme.amber)
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 5)
                                    .background(BrandTheme.amber.opacity(0.15))
                                    .clipShape(Capsule())
                            }

                            if downloadManager.isDownloaded(guid: episode.guid) {
                                Label("Downloaded", systemImage: "arrow.down.circle.fill")
                                    .font(.system(size: 11, weight: .semibold))
                                    .foregroundStyle(BrandTheme.cyan)
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 5)
                                    .background(BrandTheme.cyan.opacity(0.15))
                                    .clipShape(Capsule())
                            }
                        }

                        // Playback Action Buttons (Resume vs Play from Start)
                        let savedProgress = currentProgress
                        if savedProgress > 10 && !(episode.played || isSkipped) {
                            HStack(spacing: 10) {
                                // Resume Button
                                Button {
                                    playEpisode(startAt: savedProgress)
                                    dismiss()
                                } label: {
                                    HStack(spacing: 6) {
                                        Image(systemName: "play.fill")
                                            .font(.system(size: 13, weight: .bold))
                                        Text("Resume (\(formatTime(seconds: Int(savedProgress))))")
                                            .font(.system(size: 14, weight: .bold))
                                    }
                                    .foregroundStyle(Color.black)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 12)
                                    .background(BrandTheme.brandGradient)
                                    .clipShape(Capsule())
                                }

                                // Play from Start
                                Button {
                                    playEpisode(startAt: 0)
                                    dismiss()
                                } label: {
                                    HStack(spacing: 5) {
                                        Image(systemName: "backward.end.fill")
                                            .font(.system(size: 12, weight: .bold))
                                        Text("From Start")
                                            .font(.system(size: 13, weight: .semibold))
                                    }
                                    .foregroundStyle(BrandTheme.textPrimary)
                                    .padding(.horizontal, 14)
                                    .padding(.vertical, 12)
                                    .background(BrandTheme.bgCard)
                                    .clipShape(Capsule())
                                    .overlay(
                                        Capsule().stroke(BrandTheme.border, lineWidth: 1)
                                    )
                                }
                            }
                        } else {
                            Button {
                                playEpisode(startAt: 0)
                                dismiss()
                            } label: {
                                HStack(spacing: 6) {
                                    Image(systemName: "play.fill")
                                        .font(.system(size: 13, weight: .bold))
                                    Text("Play")
                                        .font(.system(size: 14, weight: .bold))
                                }
                                .foregroundStyle(Color.black)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 12)
                                .background(BrandTheme.brandGradient)
                                .clipShape(Capsule())
                            }
                        }

                        // Secondary Action Buttons: Listened, Queue, Download, and Skip
                        HStack(spacing: 8) {
                            // Mark Listened Toggle
                            Button {
                                toggleListened()
                            } label: {
                                HStack(spacing: 4) {
                                    Image(systemName: isPlayed ? "checkmark.circle.fill" : "checkmark.circle")
                                        .font(.system(size: 11, weight: .bold))
                                    Text(isPlayed ? "Listened" : "Listen")
                                        .font(.system(size: 12, weight: .semibold))
                                }
                                .foregroundStyle(isPlayed ? BrandTheme.emerald : BrandTheme.textPrimary)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 10)
                                .background(BrandTheme.bgCard)
                                .clipShape(Capsule())
                                .overlay(
                                    Capsule().stroke(isPlayed ? BrandTheme.emerald.opacity(0.5) : BrandTheme.border, lineWidth: 1)
                                )
                            }

                            // Queue Toggle
                            Button {
                                toggleQueue()
                            } label: {
                                HStack(spacing: 4) {
                                    Image(systemName: isQueued ? "checkmark" : "plus")
                                        .font(.system(size: 11, weight: .bold))
                                    Text(isQueued ? "Queued" : "Queue")
                                        .font(.system(size: 12, weight: .semibold))
                                }
                                .foregroundStyle(isQueued ? BrandTheme.emerald : BrandTheme.textPrimary)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 10)
                                .background(BrandTheme.bgCard)
                                .clipShape(Capsule())
                                .overlay(
                                    Capsule().stroke(BrandTheme.border, lineWidth: 1)
                                )
                            }

                            // Download Toggle
                            Button {
                                toggleDownload()
                            } label: {
                                HStack(spacing: 4) {
                                    if let state = downloadManager.downloadStates[episode.guid], case .downloading(let pct) = state {
                                        ProgressView()
                                            .tint(BrandTheme.cyan)
                                            .scaleEffect(0.6)
                                        Text("\(Int(pct * 100))%")
                                            .font(.system(size: 11, weight: .bold))
                                    } else {
                                        Image(systemName: downloadManager.isDownloaded(guid: episode.guid) ? "arrow.down.circle.fill" : "arrow.down.circle")
                                            .font(.system(size: 11, weight: .bold))
                                        Text(downloadManager.isDownloaded(guid: episode.guid) ? "Offline" : "Download")
                                            .font(.system(size: 12, weight: .semibold))
                                    }
                                }
                                .foregroundStyle(downloadManager.isDownloaded(guid: episode.guid) ? BrandTheme.emerald : BrandTheme.textPrimary)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 10)
                                .background(BrandTheme.bgCard)
                                .clipShape(Capsule())
                                .overlay(
                                    Capsule().stroke(BrandTheme.border, lineWidth: 1)
                                )
                            }

                            // Skip Toggle
                            Button {
                                toggleSkip()
                            } label: {
                                HStack(spacing: 4) {
                                    Image(systemName: isSkipped ? "arrow.uturn.backward" : "slash.circle")
                                        .font(.system(size: 11, weight: .bold))
                                    Text(isSkipped ? "Unskip" : "Skip")
                                        .font(.system(size: 12, weight: .semibold))
                                }
                                .foregroundStyle(isSkipped ? BrandTheme.cyan : BrandTheme.amber)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 10)
                                .background(BrandTheme.bgCard)
                                .clipShape(Capsule())
                                .overlay(
                                    Capsule().stroke(BrandTheme.border, lineWidth: 1)
                                )
                            }
                        }

                        // Add to Playlist Button
                        Button {
                            showAddToPlaylistSheet = true
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: "music.note.list")
                                    .font(.system(size: 13, weight: .bold))
                                Text("Add to Playlist")
                                    .font(.system(size: 13, weight: .semibold))
                            }
                            .foregroundStyle(Color.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                            .background(BrandTheme.bgCard)
                            .clipShape(Capsule())
                            .overlay(
                                Capsule().stroke(BrandTheme.border, lineWidth: 1)
                            )
                        }

                        Divider().background(BrandTheme.border)

                        // Episode Description
                        VStack(alignment: .leading, spacing: 8) {
                            Text("EPISODE DESCRIPTION")
                                .font(.system(size: 11, weight: .bold))
                                .tracking(1.2)
                                .foregroundStyle(BrandTheme.textMuted)

                            if let desc = episode.description, !desc.isEmpty {
                                Text(cleanHTML(desc))
                                    .font(.system(size: 14, weight: .regular))
                                    .lineSpacing(4)
                                    .foregroundStyle(BrandTheme.textPrimary)
                            } else {
                                Text("No description available for this episode.")
                                    .font(.system(size: 14))
                                    .foregroundStyle(BrandTheme.textMuted)
                            }
                        }
                    }
                    .padding(20)
                    .padding(.bottom, 40)
                }
            }
            .navigationTitle("Episode Details")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") {
                        dismiss()
                    }
                    .foregroundStyle(BrandTheme.cyan)
                }
            }
            .sheet(isPresented: $showAddToPlaylistSheet) {
                AddToPlaylistSheet(
                    episodeGuid: episode.guid,
                    episodeTitle: episode.title,
                    podcastId: podcast.id,
                    podcastTitle: podcast.title,
                    podcastArtworkUrl: podcast.artworkUrl,
                    enclosureUrl: episode.enclosure_url,
                    durationSecs: episode.duration_secs
                )
            }
        }
    }

    private func playEpisode(startAt: Double = 0) {
        guard let enc = episode.enclosure_url, !enc.isEmpty else { return }
        let playable = PlayableEpisode(
            podcastId: podcast.id,
            podcastTitle: podcast.title,
            podcastArtworkUrl: podcast.artworkUrl,
            episodeGuid: episode.guid,
            episodeTitle: episode.title,
            enclosureUrl: enc,
            durationSecs: episode.durationSecs
        )
        audioManager.play(episode: playable, startAt: startAt)
    }

    private func toggleDownload() {
        if downloadManager.isDownloaded(guid: episode.guid) {
            downloadManager.deleteDownload(guid: episode.guid)
        } else if let enc = episode.enclosure_url, !enc.isEmpty {
            downloadManager.startDownload(guid: episode.guid, urlString: enc)
        }
    }

    private func toggleQueue() {
        isQueued.toggle()
        if isQueued {
            let qItem = QueueEpisodeItem(
                id: Int.random(in: 100_000...999_999),
                podcastId: podcast.id,
                podcastTitle: podcast.title,
                podcastArtworkUrl: podcast.artworkUrl,
                episodeGuid: episode.guid,
                episodeTitle: episode.title,
                enclosureUrl: episode.enclosure_url,
                durationSecs: episode.durationSecs
            )
            modelContext.insert(qItem)
            try? modelContext.save()

            Task {
                try? await APIClient.shared.addToQueue(
                    podcastId: podcast.id,
                    episodeGuid: episode.guid,
                    episodeTitle: episode.title,
                    enclosureUrl: episode.enclosure_url,
                    durationSecs: episode.durationSecs
                )
            }
        }
    }

    private func toggleListened() {
        isPlayed.toggle()
        if isPlayed {
            isSkipped = false
            let playable = PlayableEpisode(
                podcastId: podcast.id,
                podcastTitle: podcast.title,
                podcastArtworkUrl: podcast.artworkUrl,
                episodeGuid: episode.guid,
                episodeTitle: episode.title,
                enclosureUrl: episode.enclosure_url ?? "",
                durationSecs: episode.durationSecs
            )
            audioManager.clearSavedProgress(for: episode.guid)
            SyncManager.shared.recordPlaybackFinished(
                episode: playable,
                timeListened: Double(episode.durationSecs ?? 0),
                completionType: "finished",
                modelContext: modelContext
            )
        } else {
            let epGuid = episode.guid
            let jDesc = FetchDescriptor<JournalEntryItem>(predicate: #Predicate { $0.episodeGuid == epGuid })
            if let entries = try? modelContext.fetch(jDesc) {
                for item in entries { modelContext.delete(item) }
                try? modelContext.save()
            }
        }
    }

    private func toggleSkip() {
        isSkipped.toggle()
        Task {
            _ = try? await APIClient.shared.toggleEpisodeSkipped(podcastId: podcast.id, episodeGuid: episode.guid)
            await SyncManager.shared.sync(modelContext: modelContext)
        }
    }

    private func parseServerDate(_ str: String) -> Date? {
        SyncManager.parseServerDate(str)
    }
}
