import SwiftUI
import SwiftData

public struct CarDrivingModeView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Bindable var audioManager = AudioManager.shared

    @State private var showSavedBanner: Bool = false

    public init() {}

    public var body: some View {
        let palette = audioManager.currentPalette

        ZStack {
            Color.black.ignoresSafeArea()

            if let ep = audioManager.currentEpisode {
                VStack(spacing: 24) {
                    // Top Bar: Exit button & Car status
                    HStack {
                        Label("CAR DRIVING MODE", systemImage: "car.fill")
                            .font(.system(size: 13, weight: .bold))
                            .tracking(1.2)
                            .foregroundStyle(palette.accent)

                        Spacer()

                        Button {
                            dismiss()
                        } label: {
                            HStack(spacing: 6) {
                                Text("Exit")
                                    .font(.system(size: 15, weight: .bold))
                                Image(systemName: "xmark.circle.fill")
                                    .font(.system(size: 20))
                            }
                            .foregroundStyle(BrandTheme.textSecondary)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 8)
                            .background(Color.white.opacity(0.1))
                            .clipShape(Capsule())
                        }
                    }
                    .padding(.horizontal, 24)
                    .padding(.top, 16)

                    Spacer()

                    // Episode & Podcast Titles (High contrast, large font)
                    VStack(alignment: .leading, spacing: 8) {
                        Text(ep.podcastTitle)
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundStyle(palette.accent)
                            .lineLimit(1)

                        Text(ep.episodeTitle)
                            .font(.system(size: 26, weight: .bold))
                            .foregroundStyle(Color.white)
                            .lineLimit(2)
                            .minimumScaleFactor(0.8)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 24)

                    // Big Progress Scrubber Bar
                    VStack(spacing: 8) {
                        GeometryReader { geo in
                            ZStack(alignment: .leading) {
                                Capsule()
                                    .fill(Color.white.opacity(0.15))
                                    .frame(height: 12)

                                let pct = audioManager.duration > 0 ? (audioManager.currentTime / audioManager.duration) : 0
                                Capsule()
                                    .fill(palette.accent)
                                    .frame(width: max(12, geo.size.width * CGFloat(pct)), height: 12)
                            }
                        }
                        .frame(height: 12)

                        HStack {
                            Text(formatTime(seconds: Int(audioManager.currentTime)))
                                .font(.system(size: 15, weight: .bold, design: .monospaced))
                                .foregroundStyle(Color.white)

                            Spacer()

                            let remaining = max(0, audioManager.duration - audioManager.currentTime)
                            Text("-" + formatTime(seconds: Int(remaining)))
                                .font(.system(size: 15, weight: .bold, design: .monospaced))
                                .foregroundStyle(BrandTheme.textSecondary)
                        }
                    }
                    .padding(.horizontal, 24)

                    Spacer()

                    // Massive Playback Controls (15s back, giant play/pause, 30s forward)
                    HStack(spacing: 40) {
                        Button {
                            audioManager.skipBackward(seconds: 15)
                            triggerHaptic()
                        } label: {
                            VStack(spacing: 4) {
                                Image(systemName: "gobackward.15")
                                    .font(.system(size: 38, weight: .bold))
                                    .foregroundStyle(Color.white)
                                Text("15s")
                                    .font(.system(size: 11, weight: .bold))
                                    .foregroundStyle(BrandTheme.textSecondary)
                            }
                            .frame(width: 80, height: 80)
                            .background(Color.white.opacity(0.08))
                            .clipShape(Circle())
                        }

                        Button {
                            audioManager.togglePlayPause()
                            triggerHaptic()
                        } label: {
                            ZStack {
                                Circle()
                                    .fill(palette.accent)
                                    .frame(width: 104, height: 104)
                                    .shadow(color: palette.accent.opacity(0.5), radius: 20, x: 0, y: 8)

                                Image(systemName: audioManager.isPlaying ? "pause.fill" : "play.fill")
                                    .font(.system(size: 44, weight: .bold))
                                    .foregroundStyle(palette.controlOnAccent)
                                    .offset(x: audioManager.isPlaying ? 0 : 4)
                            }
                        }

                        Button {
                            audioManager.skipForward(seconds: 30)
                            triggerHaptic()
                        } label: {
                            VStack(spacing: 4) {
                                Image(systemName: "goforward.30")
                                    .font(.system(size: 38, weight: .bold))
                                    .foregroundStyle(Color.white)
                                Text("30s")
                                    .font(.system(size: 11, weight: .bold))
                                    .foregroundStyle(BrandTheme.textSecondary)
                            }
                            .frame(width: 80, height: 80)
                            .background(Color.white.opacity(0.08))
                            .clipShape(Circle())
                        }
                    }

                    Spacer()

                    // Oversized Utility Actions: 1-Tap Bookmark, Skip, & Speed
                    HStack(spacing: 12) {
                        Button {
                            quickCarBookmark(ep)
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: "bookmark.fill")
                                    .font(.system(size: 15, weight: .bold))
                                Text("Bookmark")
                                    .font(.system(size: 14, weight: .bold))
                            }
                            .foregroundStyle(Color.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                            .background(BrandTheme.bgSecondary)
                            .clipShape(RoundedRectangle(cornerRadius: 16))
                        }

                        Button {
                            skipCarEpisode(ep)
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: "slash.circle")
                                    .font(.system(size: 15, weight: .bold))
                                Text("Skip")
                                    .font(.system(size: 14, weight: .bold))
                            }
                            .foregroundStyle(BrandTheme.amber)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                            .background(BrandTheme.bgSecondary)
                            .clipShape(RoundedRectangle(cornerRadius: 16))
                        }

                        Button {
                            audioManager.cyclePlaybackRate()
                            triggerHaptic()
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: "speedometer")
                                    .font(.system(size: 14, weight: .semibold))
                                Text(String(format: "%.2fx", audioManager.playbackRate).replacingOccurrences(of: ".00", with: ""))
                                    .font(.system(size: 14, weight: .bold, design: .monospaced))
                            }
                            .foregroundStyle(BrandTheme.cyan)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 16)
                            .background(BrandTheme.bgSecondary)
                            .clipShape(RoundedRectangle(cornerRadius: 16))
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 24)
                }

                // Banner alert when bookmark saved
                if showSavedBanner {
                    VStack {
                        HStack(spacing: 8) {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(BrandTheme.emerald)
                            Text("Bookmark saved at \(formatTime(seconds: Int(audioManager.currentTime)))")
                                .font(.system(size: 14, weight: .bold))
                                .foregroundStyle(Color.white)
                        }
                        .padding(.horizontal, 20)
                        .padding(.vertical, 12)
                        .background(BrandTheme.bgCard)
                        .clipShape(Capsule())
                        .shadow(radius: 10)
                        .padding(.top, 60)
                        Spacer()
                    }
                    .transition(.move(edge: .top).combined(with: .opacity))
                }
            } else {
                VStack(spacing: 16) {
                    Text("No episode playing")
                        .foregroundStyle(BrandTheme.textMuted)
                    Button("Exit") { dismiss() }
                        .foregroundStyle(BrandTheme.cyan)
                }
            }
        }
    }

    private func triggerHaptic() {
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
    }

    private func skipCarEpisode(_ ep: PlayableEpisode) {
        triggerHaptic()
        audioManager.pause()
        SyncManager.shared.recordPlaybackFinished(
            episode: ep,
            timeListened: audioManager.currentTime,
            completionType: "skipped",
            modelContext: modelContext
        )

        // Advance to next queued episode if available
        let queueDesc = FetchDescriptor<QueueEpisodeItem>(sortBy: [SortDescriptor(\.position, order: .forward)])
        if let nextQueued = try? modelContext.fetch(queueDesc).first(where: { $0.episodeGuid != ep.episodeGuid }),
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

    private func quickCarBookmark(_ ep: PlayableEpisode) {
        triggerHaptic()
        let currentSecs = Int(audioManager.currentTime)
        let label = "Car Bookmark at \(formatTime(seconds: currentSecs))"

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
                timeListenedSecs: currentSecs,
                playedAt: Date(),
                isSkipped: false,
                isSynced: false
            )
            modelContext.insert(journalEntry)
        }

        let newBookmark = ChapterBookmarkItem(
            id: Int.random(in: 100_000...999_999),
            journalEntryId: journalEntry.id,
            timestampSecs: currentSecs,
            label: label
        )
        modelContext.insert(newBookmark)
        journalEntry.bookmarks.append(newBookmark)
        journalEntry.isSynced = false
        try? modelContext.save()

        withAnimation {
            showSavedBanner = true
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
            withAnimation {
                showSavedBanner = false
            }
        }

        Task {
            await SyncManager.shared.sync(modelContext: modelContext)
        }
    }
}
