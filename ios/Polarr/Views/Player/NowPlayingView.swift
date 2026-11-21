import SwiftUI
import SwiftData

public struct NowPlayingView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Bindable var audioManager = AudioManager.shared

    @State private var isDraggingSlider: Bool = false
    @State private var sliderValue: Double = 0
    @State private var showNoteSheet: Bool = false
    @State private var showBookmarksSheet: Bool = false
    @State private var showCarMode: Bool = false
    @State private var showBookmarkAlert: Bool = false
    @State private var bookmarkLabel: String = ""

    public init() {}

    public var body: some View {
        ZStack {
            BrandTheme.bgPrimary.ignoresSafeArea()

            if let episode = audioManager.currentEpisode {
                VStack(spacing: 0) {
                    // Top Bar
                    HStack {
                        Button {
                            dismiss()
                        } label: {
                            Image(systemName: "chevron.down")
                                .font(.system(size: 18, weight: .bold))
                                .foregroundStyle(BrandTheme.textSecondary)
                                .frame(width: 44, height: 44)
                        }

                        Spacer()

                        VStack(spacing: 2) {
                            Text("NOW PLAYING")
                                .font(.system(size: 11, weight: .bold))
                                .tracking(1.5)
                                .foregroundStyle(BrandTheme.cyan)
                            Text(episode.podcastTitle)
                                .font(.system(size: 13, weight: .medium))
                                .foregroundStyle(BrandTheme.textSecondary)
                                .lineLimit(1)
                        }

                        Spacer()

                        HStack(spacing: 4) {
                            Button {
                                showCarMode = true
                            } label: {
                                Image(systemName: "car.fill")
                                    .font(.system(size: 16, weight: .semibold))
                                    .foregroundStyle(BrandTheme.cyan)
                                    .frame(width: 40, height: 44)
                            }

                            Button {
                                showNoteSheet = true
                            } label: {
                                Image(systemName: "square.and.pencil")
                                    .font(.system(size: 18, weight: .semibold))
                                    .foregroundStyle(BrandTheme.cyan)
                                    .frame(width: 40, height: 44)
                            }
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 12)

                    Spacer(minLength: 16)

                    // Large Album Artwork with Glow
                    ZStack {
                        AsyncArtworkView(urlString: episode.podcastArtworkUrl, size: 280, cornerRadius: 24)
                            .shadow(color: BrandTheme.cyan.opacity(0.25), radius: 30, x: 0, y: 10)
                            .shadow(color: Color.black.opacity(0.6), radius: 20, x: 0, y: 8)
                    }
                    .padding(.horizontal, 32)

                    Spacer(minLength: 24)

                    // Episode Title & Podcast Title
                    VStack(alignment: .leading, spacing: 6) {
                        Text(episode.episodeTitle)
                            .font(.system(size: 20, weight: .bold))
                            .foregroundStyle(BrandTheme.textPrimary)
                            .lineLimit(2)
                            .multilineTextAlignment(.leading)

                        Text(episode.podcastTitle)
                            .font(.system(size: 15, weight: .medium))
                            .foregroundStyle(BrandTheme.cyan)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 28)

                    Spacer(minLength: 16)

                    // Scrubber Slider
                    VStack(spacing: 6) {
                        Slider(
                            value: Binding(
                                get: { isDraggingSlider ? sliderValue : audioManager.currentTime },
                                set: { sliderValue = $0 }
                            ),
                            in: 0...max(1, audioManager.duration),
                            onEditingChanged: { editing in
                                isDraggingSlider = editing
                                if !editing {
                                    audioManager.seek(to: sliderValue)
                                }
                            }
                        )
                        .tint(BrandTheme.cyan)

                        HStack {
                            Text(formatTime(seconds: Int(isDraggingSlider ? sliderValue : audioManager.currentTime)))
                                .font(.system(size: 12, weight: .medium, design: .monospaced))
                                .foregroundStyle(BrandTheme.textSecondary)

                            Spacer()

                            let remaining = max(0, audioManager.duration - (isDraggingSlider ? sliderValue : audioManager.currentTime))
                            Text("-" + formatTime(seconds: Int(remaining)))
                                .font(.system(size: 12, weight: .medium, design: .monospaced))
                                .foregroundStyle(BrandTheme.textSecondary)
                        }
                    }
                    .padding(.horizontal, 28)

                    Spacer(minLength: 16)

                    // Main Playback Controls
                    HStack(spacing: 36) {
                        // 15s Back
                        Button {
                            audioManager.skipBackward(seconds: 15)
                        } label: {
                            Image(systemName: "gobackward.15")
                                .font(.system(size: 26, weight: .semibold))
                                .foregroundStyle(BrandTheme.textPrimary)
                        }

                        // Play / Pause Button
                        Button {
                            audioManager.togglePlayPause()
                        } label: {
                            ZStack {
                                Circle()
                                    .fill(BrandTheme.brandGradient)
                                    .frame(width: 72, height: 72)
                                    .shadow(color: BrandTheme.cyan.opacity(0.4), radius: 16, x: 0, y: 6)

                                if audioManager.isLoading {
                                    ProgressView().tint(.black).scaleEffect(1.2)
                                } else {
                                    Image(systemName: audioManager.isPlaying ? "pause.fill" : "play.fill")
                                        .font(.system(size: 30, weight: .bold))
                                        .foregroundStyle(Color.black)
                                        .offset(x: audioManager.isPlaying ? 0 : 2)
                                }
                            }
                        }

                        // 30s Forward
                        Button {
                            audioManager.skipForward(seconds: 30)
                        } label: {
                            Image(systemName: "goforward.30")
                                .font(.system(size: 26, weight: .semibold))
                                .foregroundStyle(BrandTheme.textPrimary)
                        }
                    }

                    Spacer(minLength: 24)

                    // Bottom Utility Row (Speed, Bookmarks Drawer, Skip, Mark Done)
                    HStack(spacing: 16) {
                        // Playback Speed
                        Button {
                            audioManager.cyclePlaybackRate()
                        } label: {
                            Text(String(format: "%.2fx", audioManager.playbackRate).replacingOccurrences(of: ".00", with: ""))
                                .font(.system(size: 13, weight: .bold, design: .monospaced))
                                .foregroundStyle(audioManager.playbackRate > 1.0 ? BrandTheme.cyan : BrandTheme.textSecondary)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .background(BrandTheme.bgCard)
                                .clipShape(Capsule())
                        }

                        // Bookmarks Drawer
                        Button {
                            showBookmarksSheet = true
                        } label: {
                            Label("Bookmarks", systemImage: "bookmark.fill")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(BrandTheme.cyan)
                        }

                        Spacer()

                        // Skip Episode
                        Button {
                            skipEpisode(episode)
                        } label: {
                            Label("Skip", systemImage: "slash.circle")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(BrandTheme.amber)
                        }

                        // Mark Finished
                        Button {
                            finishEpisode(episode)
                        } label: {
                            Label("Finished", systemImage: "checkmark.circle.fill")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(BrandTheme.emerald)
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 24)
                }
            } else {
                Text("No Episode Loaded")
                    .foregroundStyle(BrandTheme.textMuted)
            }
        }
        .sheet(isPresented: $showNoteSheet) {
            if let ep = audioManager.currentEpisode {
                JournalNoteSheet(episode: ep)
            }
        }
        .sheet(isPresented: $showBookmarksSheet) {
            BookmarksDrawerSheet()
        }
        .fullScreenCover(isPresented: $showCarMode) {
            CarDrivingModeView()
        }
        .alert("Add Chapter Bookmark", isPresented: $showBookmarkAlert) {
            TextField("Bookmark note", text: $bookmarkLabel)
            Button("Save Bookmark") {
                saveBookmark()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Save a bookmark for \(formatTime(seconds: Int(audioManager.currentTime))) into your listening journal.")
        }
    }

    private func finishEpisode(_ episode: PlayableEpisode) {
        audioManager.pause()
        SyncManager.shared.recordPlaybackFinished(
            episode: episode,
            timeListened: audioManager.currentTime,
            completionType: "finished",
            modelContext: modelContext
        )
        dismiss()
    }

    private func skipEpisode(_ episode: PlayableEpisode) {
        audioManager.pause()
        SyncManager.shared.recordPlaybackFinished(
            episode: episode,
            timeListened: audioManager.currentTime,
            completionType: "skipped",
            modelContext: modelContext
        )

        // Advance to next queued episode if available
        let queueDesc = FetchDescriptor<QueueEpisodeItem>(sortBy: [SortDescriptor(\.position, order: .forward)])
        if let nextQueued = try? modelContext.fetch(queueDesc).first(where: { $0.episodeGuid != episode.episodeGuid }),
           let enc = nextQueued.enclosureUrl, !enc.isEmpty {
            let nextPlayable = PlayableEpisode(
                podcastId: nextQueued.podcastId,
                podcastTitle: nextQueued.podcastTitle,
                podcastArtworkUrl: nextQueued.podcastArtworkUrl,
                episodeGuid: nextQueued.episodeGuid,
                episodeTitle: nextQueued.episodeTitle,
                enclosureUrl: enc,
                durationSecs: nextQueued.durationSecs
            )
            audioManager.play(episode: nextPlayable, startAt: Double(nextQueued.progressSecs))
        } else {
            dismiss()
        }
    }

    private func saveBookmark() {
        guard let ep = audioManager.currentEpisode else { return }
        let currentSeconds = Int(audioManager.currentTime)
        let label = bookmarkLabel.trimmingCharacters(in: .whitespacesAndNewlines)

        let epGuid = ep.episodeGuid
        var desc = FetchDescriptor<JournalEntryItem>(predicate: #Predicate { $0.episodeGuid == epGuid })
        desc.fetchLimit = 1

        let journalEntry: JournalEntryItem
        if let existing = try? modelContext.fetch(desc).first {
            journalEntry = existing
        } else {
            journalEntry = JournalEntryItem(
                id: Int.random(in: 100_000...999_999),
                podcastId: ep.podcastId,
                podcastTitle: ep.podcastTitle,
                podcastArtworkUrl: ep.podcastArtworkUrl,
                episodeGuid: ep.episodeGuid,
                episodeTitle: ep.episodeTitle,
                completionType: "finished",
                episodeDurationSecs: ep.durationSecs,
                timeListenedSecs: currentSeconds,
                playedAt: Date(),
                isSkipped: false,
                isSynced: false
            )
            modelContext.insert(journalEntry)
        }

        let newBookmark = ChapterBookmarkItem(
            id: Int.random(in: 100_000...999_999),
            journalEntryId: journalEntry.id,
            timestampSecs: currentSeconds,
            label: label.isEmpty ? "Moment at \(formatTime(seconds: currentSeconds))" : label
        )
        modelContext.insert(newBookmark)
        journalEntry.bookmarks.append(newBookmark)
        journalEntry.isSynced = false
        try? modelContext.save()

        Task {
            await SyncManager.shared.sync(modelContext: modelContext)
        }
    }
}
