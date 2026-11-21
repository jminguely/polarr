import SwiftUI
import SwiftData

public struct JournalNoteSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    public let episode: PlayableEpisode
    @State private var rating: Int?
    @State private var personalNote: String = ""
    @State private var isSaved: Bool = false

    public init(episode: PlayableEpisode) {
        self.episode = episode
    }

    public var body: some View {
        NavigationStack {
            ZStack {
                BrandTheme.bgPrimary.ignoresSafeArea()

                VStack(alignment: .leading, spacing: 20) {
                    // Episode Header
                    HStack(spacing: 14) {
                        AsyncArtworkView(urlString: episode.podcastArtworkUrl, size: 56, cornerRadius: 12)

                        VStack(alignment: .leading, spacing: 4) {
                            Text(episode.episodeTitle)
                                .font(.system(size: 15, weight: .bold))
                                .foregroundStyle(BrandTheme.textPrimary)
                                .lineLimit(2)

                            Text(episode.podcastTitle)
                                .font(.system(size: 13, weight: .medium))
                                .foregroundStyle(BrandTheme.cyan)
                        }
                    }
                    .padding(.top, 8)

                    Divider().background(BrandTheme.border)

                    // Star Rating
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Rating")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(BrandTheme.textSecondary)
                            .textCase(.uppercase)

                        HStack {
                            RatingView(rating: $rating, maxRating: 5, starSize: 28)
                            Spacer()
                            if let r = rating {
                                Text("\(r) / 5")
                                    .font(.system(size: 14, weight: .bold))
                                    .foregroundStyle(BrandTheme.amber)
                            }
                        }
                        .padding(14)
                        .polarrCard(cornerRadius: 14)
                    }

                    // Personal Notes & Journal Entry
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Personal Journal Notes")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(BrandTheme.textSecondary)
                            .textCase(.uppercase)

                        ZStack(alignment: .topLeading) {
                            TextEditor(text: $personalNote)
                                .scrollContentBackground(.hidden)
                                .background(Color.clear)
                                .foregroundStyle(BrandTheme.textPrimary)
                                .font(.system(size: 15))
                                .frame(minHeight: 120)

                            if personalNote.isEmpty {
                                Text("What were your key takeaways, favorite ideas, or quotes?")
                                    .font(.system(size: 15))
                                    .foregroundStyle(BrandTheme.textMuted)
                                    .padding(.top, 8)
                                    .padding(.leading, 5)
                                    .allowsHitTesting(false)
                            }
                        }
                        .padding(12)
                        .polarrCard(cornerRadius: 14)
                    }

                    Spacer()

                    // Save Button
                    Button {
                        saveEntry()
                        dismiss()
                    } label: {
                        HStack {
                            Image(systemName: "checkmark.circle.fill")
                            Text("Save to Listening Journal")
                        }
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(Color.black)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(BrandTheme.brandGradient)
                        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    }
                }
                .padding(20)
            }
            .navigationTitle("Journal Note")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                        .foregroundStyle(BrandTheme.textSecondary)
                }
            }
            .onAppear {
                loadExistingEntry()
            }
        }
    }

    private func loadExistingEntry() {
        let epGuid = episode.episodeGuid
        var desc = FetchDescriptor<JournalEntryItem>(predicate: #Predicate { $0.episodeGuid == epGuid })
        desc.fetchLimit = 1
        if let existing = try? modelContext.fetch(desc).first {
            self.rating = existing.rating
            self.personalNote = existing.personalNote ?? ""
        }
    }

    private func saveEntry() {
        let epGuid = episode.episodeGuid
        var desc = FetchDescriptor<JournalEntryItem>(predicate: #Predicate { $0.episodeGuid == epGuid })
        desc.fetchLimit = 1

        if let existing = try? modelContext.fetch(desc).first {
            existing.rating = rating
            existing.personalNote = personalNote.isEmpty ? nil : personalNote
            existing.isSynced = false
        } else {
            let newEntry = JournalEntryItem(
                id: Int.random(in: 100_000...999_999),
                podcastId: episode.podcastId,
                podcastTitle: episode.podcastTitle,
                podcastArtworkUrl: episode.podcastArtworkUrl,
                episodeGuid: episode.episodeGuid,
                episodeTitle: episode.episodeTitle,
                completionType: "finished",
                episodeDurationSecs: episode.durationSecs,
                timeListenedSecs: Int(AudioManager.shared.currentTime),
                rating: rating,
                personalNote: personalNote.isEmpty ? nil : personalNote,
                playedAt: Date(),
                isSkipped: false,
                isSynced: false
            )
            modelContext.insert(newEntry)
        }

        try? modelContext.save()
        Task {
            await SyncManager.shared.sync(modelContext: modelContext)
        }
    }
}
