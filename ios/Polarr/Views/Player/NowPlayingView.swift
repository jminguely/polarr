import SwiftUI
import SwiftData

public struct NowPlayingView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Bindable var audioManager = AudioManager.shared
    @Bindable var sleepTimerManager = SleepTimerManager.shared
    @Bindable var effectsManager = AudioEffectsManager.shared
    @Bindable var playlistManager = PlaylistManager.shared

    @Query private var allPodcasts: [PodcastItem]

    @State private var isDraggingSlider: Bool = false
    @State private var sliderValue: Double = 0
    @State private var showNoteSheet: Bool = false
    @State private var showBookmarksSheet: Bool = false
    @State private var showCarMode: Bool = false
    @State private var showBookmarkAlert: Bool = false
    @State private var bookmarkLabel: String = ""

    // Sheet states for top-podcast features
    @State private var showSleepTimerSheet: Bool = false
    @State private var showAudioEffectsSheet: Bool = false
    @State private var showTranscriptSheet: Bool = false
    @State private var showUpNextSheet: Bool = false
    @State private var showAddToPlaylistSheet: Bool = false
    @State private var selectedPodcastForDetail: PodcastItem? = nil

    public init() {}

    public var body: some View {
        let palette = audioManager.currentPalette

        ZStack {
            LinearGradient(
                colors: [palette.dominant, palette.dominantDark],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            if let episode = audioManager.currentEpisode {
                VStack(spacing: 0) {
                    // Top Bar
                    HStack {
                        Button {
                            dismiss()
                        } label: {
                            Image(systemName: "chevron.down")
                                .font(.system(size: 18, weight: .bold))
                                .foregroundStyle(palette.textSecondary)
                                .frame(width: 44, height: 44)
                        }

                        Spacer()

                        // Tappable Podcast Navigation in Center
                        Button {
                            if let found = allPodcasts.first(where: { $0.id == episode.podcastId }) {
                                selectedPodcastForDetail = found
                            }
                        } label: {
                            VStack(spacing: 2) {
                                Text("NOW PLAYING")
                                    .font(.system(size: 11, weight: .bold))
                                    .tracking(1.5)
                                    .foregroundStyle(palette.accent)
                                HStack(spacing: 4) {
                                    Text(episode.podcastTitle)
                                        .font(.system(size: 13, weight: .medium))
                                        .foregroundStyle(palette.textSecondary)
                                        .lineLimit(1)
                                    Image(systemName: "chevron.right")
                                        .font(.system(size: 9, weight: .semibold))
                                        .foregroundStyle(palette.textMuted)
                                }
                            }
                        }
                        .buttonStyle(.plain)

                        Spacer()

                        HStack(spacing: 6) {
                            // Synced Transcript
                            Button {
                                showTranscriptSheet = true
                            } label: {
                                Image(systemName: "quote.bubble.fill")
                                    .font(.system(size: 15, weight: .semibold))
                                    .foregroundStyle(palette.accent)
                                    .frame(width: 36, height: 44)
                            }

                            // Audio Effects (Voice Boost & Silence Trimming)
                            Button {
                                showAudioEffectsSheet = true
                            } label: {
                                Image(systemName: "waveform")
                                    .font(.system(size: 16, weight: .semibold))
                                    .foregroundStyle(effectsManager.isSilenceTrimmingEnabled || effectsManager.isVoiceBoostEnabled ? palette.accent : palette.textSecondary)
                                    .frame(width: 36, height: 44)
                            }

                            // More Options Menu
                            Menu {
                                Button {
                                    showAddToPlaylistSheet = true
                                } label: {
                                    Label("Add to Playlist", systemImage: "music.note.list")
                                }

                                Button {
                                    showCarMode = true
                                } label: {
                                    Label("Car Driving Mode", systemImage: "car.fill")
                                }

                                Button {
                                    showNoteSheet = true
                                } label: {
                                    Label("Listening Journal", systemImage: "square.and.pencil")
                                }

                                Button {
                                    showBookmarkAlert = true
                                } label: {
                                    Label("Add Chapter Bookmark", systemImage: "bookmark.badge.plus")
                                }
                            } label: {
                                Image(systemName: "ellipsis.circle")
                                    .font(.system(size: 17, weight: .semibold))
                                    .foregroundStyle(palette.accent)
                                    .frame(width: 36, height: 44)
                            }
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 12)

                    Spacer(minLength: 12)

                    // Large Album Artwork with Glow
                    ZStack {
                        AsyncArtworkView(urlString: episode.podcastArtworkUrl, size: 280, cornerRadius: 24)
                            .shadow(color: palette.accent.opacity(0.35), radius: 30, x: 0, y: 10)
                            .shadow(color: Color.black.opacity(0.6), radius: 20, x: 0, y: 8)
                    }
                    .padding(.horizontal, 32)

                    if let plTitle = playlistManager.activePlaylistTitle {
                        HStack(spacing: 5) {
                            Image(systemName: "music.note.list")
                                .font(.system(size: 10, weight: .bold))
                            Text("Playing from: \(plTitle)")
                                .font(.system(size: 11, weight: .semibold))
                        }
                        .foregroundStyle(palette.accent)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 3)
                        .background(palette.secondary.opacity(0.4))
                        .clipShape(Capsule())
                        .padding(.top, 8)
                    }

                    Spacer(minLength: 20)

                    // Episode Title & Podcast Title
                    VStack(alignment: .leading, spacing: 6) {
                        Text(episode.episodeTitle)
                            .font(.system(size: 20, weight: .bold))
                            .foregroundStyle(palette.textPrimary)
                            .lineLimit(2)
                            .multilineTextAlignment(.leading)

                        Text(episode.podcastTitle)
                            .font(.system(size: 15, weight: .medium))
                            .foregroundStyle(palette.accent)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 28)

                    Spacer(minLength: 14)

                    // Scrubber with Chapter Marks and Dragging Popover Tooltip
                    VStack(spacing: 6) {
                        // Current Chapter Pill (when not dragging, if chapter exists)
                        if !isDraggingSlider, let chapter = audioManager.currentChapter {
                            HStack(spacing: 5) {
                                Image(systemName: "bookmark.circle.fill")
                                    .font(.system(size: 11))
                                    .foregroundStyle(palette.accent)
                                Text(chapter.title)
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundStyle(palette.textPrimary)
                                    .lineLimit(1)
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 3)
                            .background(palette.secondary.opacity(0.4))
                            .clipShape(Capsule())
                        }

                        // Floating tooltip while dragging slider
                        if isDraggingSlider {
                            let dragSecs = sliderValue
                            let chapterAtDrag = audioManager.currentChapters.last(where: { dragSecs >= $0.startTime })
                            VStack(spacing: 2) {
                                if let ch = chapterAtDrag {
                                    Text(ch.title)
                                        .font(.system(size: 11, weight: .bold))
                                        .foregroundStyle(palette.accent)
                                        .lineLimit(1)
                                }
                                Text(formatTime(seconds: Int(dragSecs)))
                                    .font(.system(size: 13, weight: .heavy, design: .monospaced))
                                    .foregroundStyle(palette.textPrimary)
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 5)
                            .background(
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .fill(Color.black.opacity(0.85))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                                            .stroke(palette.accent.opacity(0.6), lineWidth: 1)
                                    )
                            )
                            .shadow(color: Color.black.opacity(0.4), radius: 6, x: 0, y: 3)
                            .transition(.opacity.combined(with: .scale(scale: 0.95)))
                        }

                        // Scrubber Slider + Chapter Markers
                        ZStack {
                            Slider(
                                value: Binding(
                                    get: { isDraggingSlider ? sliderValue : audioManager.currentTime },
                                    set: { sliderValue = $0 }
                                ),
                                in: 0...max(1, audioManager.duration),
                                onEditingChanged: { editing in
                                    withAnimation(.easeOut(duration: 0.15)) {
                                        isDraggingSlider = editing
                                    }
                                    if !editing {
                                        audioManager.seek(to: sliderValue)
                                    }
                                }
                            )
                            .tint(palette.accent)

                            // Visual chapter tick marks along the track
                            if !audioManager.currentChapters.isEmpty && audioManager.duration > 0 {
                                GeometryReader { geo in
                                    let width = geo.size.width
                                    ForEach(audioManager.currentChapters) { ch in
                                        if ch.startTime > 0 && ch.startTime < audioManager.duration {
                                            let ratio = ch.startTime / audioManager.duration
                                            Rectangle()
                                                .fill(Color.white.opacity(0.6))
                                                .frame(width: 2, height: 8)
                                                .position(x: CGFloat(ratio) * width, y: geo.size.height / 2)
                                        }
                                    }
                                }
                                .allowsHitTesting(false)
                            }
                        }
                        .frame(height: 28)

                        HStack {
                            Text(formatTime(seconds: Int(isDraggingSlider ? sliderValue : audioManager.currentTime)))
                                .font(.system(size: 12, weight: .medium, design: .monospaced))
                                .foregroundStyle(palette.textSecondary)

                            Spacer()

                            let remaining = max(0, audioManager.duration - (isDraggingSlider ? sliderValue : audioManager.currentTime))
                            Text("-" + formatTime(seconds: Int(remaining)))
                                .font(.system(size: 12, weight: .medium, design: .monospaced))
                                .foregroundStyle(palette.textSecondary)
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
                                .foregroundStyle(palette.textPrimary)
                        }

                        // Play / Pause Button
                        Button {
                            audioManager.togglePlayPause()
                        } label: {
                            ZStack {
                                Circle()
                                    .fill(palette.accent)
                                    .frame(width: 72, height: 72)
                                    .shadow(color: palette.accent.opacity(0.4), radius: 16, x: 0, y: 6)

                                if audioManager.isLoading {
                                    ProgressView().tint(palette.controlOnAccent).scaleEffect(1.2)
                                } else {
                                    Image(systemName: audioManager.isPlaying ? "pause.fill" : "play.fill")
                                        .font(.system(size: 30, weight: .bold))
                                        .foregroundStyle(palette.controlOnAccent)
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
                                .foregroundStyle(palette.textPrimary)
                        }
                    }

                    Spacer(minLength: 22)

                    // Bottom Utility Row: Speed Stepper, Sleep Timer, Up Next, Bookmarks
                    HStack(spacing: 12) {
                        // Inline Speed Stepper: [-] 1.2x [+]
                        HStack(spacing: 2) {
                            Button {
                                audioManager.adjustPlaybackRate(by: -0.1)
                            } label: {
                                Image(systemName: "minus")
                                    .font(.system(size: 11, weight: .bold))
                                    .foregroundStyle(palette.textSecondary)
                                    .frame(width: 28, height: 32)
                                    .contentShape(Rectangle())
                            }

                            // Tapping center displays a quick speed menu or resets to 1.0x
                            Menu {
                                Button("0.8x") { audioManager.setRate(0.8) }
                                Button("1.0x (Normal)") { audioManager.setRate(1.0) }
                                Button("1.1x") { audioManager.setRate(1.1) }
                                Button("1.2x") { audioManager.setRate(1.2) }
                                Button("1.3x") { audioManager.setRate(1.3) }
                                Button("1.5x") { audioManager.setRate(1.5) }
                                Button("1.75x") { audioManager.setRate(1.75) }
                                Button("2.0x") { audioManager.setRate(2.0) }
                                Button("2.5x") { audioManager.setRate(2.5) }
                                Button("3.0x") { audioManager.setRate(3.0) }
                                Divider()
                                Button("Reset to 1.0x") { audioManager.setRate(1.0) }
                            } label: {
                                Text(String(format: "%.1fx", audioManager.playbackRate))
                                    .font(.system(size: 12, weight: .bold, design: .monospaced))
                                    .foregroundStyle(abs(audioManager.playbackRate - 1.0) > 0.05 ? palette.accent : palette.textSecondary)
                                    .frame(minWidth: 42, minHeight: 32)
                                    .contentShape(Rectangle())
                            }

                            Button {
                                audioManager.adjustPlaybackRate(by: +0.1)
                            } label: {
                                Image(systemName: "plus")
                                    .font(.system(size: 11, weight: .bold))
                                    .foregroundStyle(palette.textSecondary)
                                    .frame(width: 28, height: 32)
                                    .contentShape(Rectangle())
                            }
                        }
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(palette.secondary.opacity(0.4))
                        .clipShape(Capsule())

                        Spacer()

                        // Sleep Timer with live countdown badge
                        Button {
                            showSleepTimerSheet = true
                        } label: {
                            HStack(spacing: 5) {
                                Image(systemName: sleepTimerManager.isActive ? "moon.zzz.fill" : "moon.zzz")
                                    .font(.system(size: 13, weight: .semibold))
                                if sleepTimerManager.isActive {
                                    Text(sleepTimerManager.formattedRemainingTime)
                                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                                }
                            }
                            .foregroundStyle(sleepTimerManager.isActive ? palette.controlOnAccent : palette.textSecondary)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 7)
                            .background(sleepTimerManager.isActive ? palette.accent : palette.secondary.opacity(0.4))
                            .clipShape(Capsule())
                        }

                        Spacer()

                        // Up Next Drawer
                        Button {
                            showUpNextSheet = true
                        } label: {
                            Image(systemName: "list.bullet")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(palette.textSecondary)
                                .frame(width: 36, height: 36)
                                .background(palette.secondary.opacity(0.4))
                                .clipShape(Circle())
                        }

                        // Bookmarks Drawer
                        Button {
                            showBookmarksSheet = true
                        } label: {
                            Image(systemName: "bookmark.fill")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(palette.textSecondary)
                                .frame(width: 36, height: 36)
                                .background(palette.secondary.opacity(0.4))
                                .clipShape(Circle())
                        }
                    }
                    .padding(.horizontal, 24)
                    .padding(.bottom, 24)
                }
            } else {
                Text("No Episode Loaded")
                    .foregroundStyle(palette.textMuted)
            }
        }
        .sheet(isPresented: $showSleepTimerSheet) {
            SleepTimerSheet()
        }
        .sheet(isPresented: $showAudioEffectsSheet) {
            AudioEffectsSheet()
        }
        .sheet(isPresented: $showTranscriptSheet) {
            TranscriptSheet()
        }
        .sheet(isPresented: $showUpNextSheet) {
            UpNextDrawerSheet()
        }
        .sheet(isPresented: $showBookmarksSheet) {
            BookmarksDrawerSheet()
        }
        .sheet(isPresented: $showNoteSheet) {
            if let ep = audioManager.currentEpisode {
                JournalNoteSheet(episode: ep)
            }
        }
        .sheet(item: $selectedPodcastForDetail) { pod in
            NavigationStack {
                PodcastDetailView(podcast: pod)
                    .toolbar {
                        ToolbarItem(placement: .topBarLeading) {
                            Button("Done") {
                                selectedPodcastForDetail = nil
                            }
                            .foregroundStyle(BrandTheme.textSecondary)
                        }
                    }
            }
        }
        .sheet(isPresented: $showAddToPlaylistSheet) {
            if let ep = audioManager.currentEpisode {
                AddToPlaylistSheet(
                    episodeGuid: ep.episodeGuid,
                    episodeTitle: ep.episodeTitle,
                    podcastId: ep.podcastId,
                    podcastTitle: ep.podcastTitle,
                    podcastArtworkUrl: ep.podcastArtworkUrl,
                    enclosureUrl: ep.enclosureUrl,
                    durationSecs: ep.durationSecs
                )
            }
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
