import SwiftUI
import SwiftData

public struct BookmarksDrawerSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Bindable var audioManager = AudioManager.shared

    @Query(sort: \ChapterBookmarkItem.timestampSecs, order: .forward)
    private var allBookmarks: [ChapterBookmarkItem]

    @State private var newBookmarkLabel: String = ""

    public init() {}

    private var currentEpisodeBookmarks: [ChapterBookmarkItem] {
        guard let ep = audioManager.currentEpisode else { return allBookmarks }
        let epGuid = ep.episodeGuid
        var desc = FetchDescriptor<JournalEntryItem>(predicate: #Predicate { $0.episodeGuid == epGuid })
        desc.fetchLimit = 1
        if let entry = try? modelContext.fetch(desc).first {
            return entry.bookmarks.sorted(by: { $0.timestampSecs < $1.timestampSecs })
        }
        return []
    }

    public var body: some View {
        NavigationStack {
            ZStack {
                BrandTheme.bgPrimary.ignoresSafeArea()

                VStack(spacing: 0) {
                    if let ep = audioManager.currentEpisode {
                        // Current timestamp quick add banner
                        HStack(spacing: 12) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("CURRENT TIME")
                                    .font(.system(size: 10, weight: .bold))
                                    .tracking(1.1)
                                    .foregroundStyle(BrandTheme.cyan)
                                Text(formatTime(seconds: Int(audioManager.currentTime)))
                                    .font(.system(size: 18, weight: .bold, design: .monospaced))
                                    .foregroundStyle(BrandTheme.textPrimary)
                            }

                            Spacer()

                            Button {
                                quickAddBookmark()
                            } label: {
                                Label("Add Here", systemImage: "plus.circle.fill")
                                    .font(.system(size: 13, weight: .bold))
                                    .foregroundStyle(Color.black)
                                    .padding(.horizontal, 14)
                                    .padding(.vertical, 8)
                                    .background(BrandTheme.cyan)
                                    .clipShape(Capsule())
                            }
                        }
                        .padding(14)
                        .polarrCard(cornerRadius: 14)
                        .padding(.horizontal, 16)
                        .padding(.top, 16)
                        .padding(.bottom, 12)
                    }

                    if currentEpisodeBookmarks.isEmpty {
                        VStack(spacing: 12) {
                            Spacer()
                            Image(systemName: "bookmark")
                                .font(.system(size: 40))
                                .foregroundStyle(BrandTheme.textMuted)
                            Text("No Bookmarks Yet")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundStyle(BrandTheme.textPrimary)
                            Text("Save interesting points in this episode to jump back to them anytime.")
                                .font(.system(size: 13))
                                .foregroundStyle(BrandTheme.textSecondary)
                                .multilineTextAlignment(.center)
                                .padding(.horizontal, 32)
                            Spacer()
                        }
                    } else {
                        List {
                            ForEach(currentEpisodeBookmarks) { bm in
                                Button {
                                    audioManager.seek(to: Double(bm.timestampSecs))
                                    dismiss()
                                } label: {
                                    HStack(spacing: 12) {
                                        Text(formatTime(seconds: bm.timestampSecs))
                                            .font(.system(size: 12, weight: .bold, design: .monospaced))
                                            .foregroundStyle(BrandTheme.cyan)
                                            .padding(.horizontal, 8)
                                            .padding(.vertical, 4)
                                            .background(BrandTheme.cyan.opacity(0.12))
                                            .clipShape(RoundedRectangle(cornerRadius: 6))

                                        Text(bm.label)
                                            .font(.system(size: 14, weight: .medium))
                                            .foregroundStyle(BrandTheme.textPrimary)
                                            .lineLimit(2)

                                        Spacer()

                                        Image(systemName: "play.circle.fill")
                                            .font(.system(size: 18))
                                            .foregroundStyle(BrandTheme.cyan)
                                    }
                                    .padding(.vertical, 4)
                                }
                                .listRowBackground(BrandTheme.bgCard)
                                .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                    Button(role: .destructive) {
                                        deleteBookmark(bm)
                                    } label: {
                                        Label("Delete", systemImage: "trash")
                                    }
                                }
                            }
                        }
                        .listStyle(.plain)
                        .scrollContentBackground(.hidden)
                    }
                }
            }
            .navigationTitle("Chapter Bookmarks")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .foregroundStyle(BrandTheme.cyan)
                }
            }
        }
    }

    private func quickAddBookmark() {
        guard let ep = audioManager.currentEpisode else { return }
        let currentSecs = Int(audioManager.currentTime)
        let label = "Bookmark at \(formatTime(seconds: currentSecs))"

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

        Task {
            await SyncManager.shared.sync(modelContext: modelContext)
        }
    }

    private func deleteBookmark(_ bm: ChapterBookmarkItem) {
        modelContext.delete(bm)
        try? modelContext.save()
    }
}
