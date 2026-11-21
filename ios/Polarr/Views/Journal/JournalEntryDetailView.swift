import SwiftUI
import SwiftData

public struct JournalEntryDetailView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Bindable var entry: JournalEntryItem

    @State private var rating: Int?
    @State private var personalNote: String = ""
    @State private var showBookmarkAlert: Bool = false
    @State private var newBookmarkLabel: String = ""
    @State private var newBookmarkTime: String = "0:00"

    public init(entry: JournalEntryItem) {
        self.entry = entry
    }

    public var body: some View {
        ZStack {
            BrandTheme.bgPrimary.ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    // Header Card
                    HStack(spacing: 14) {
                        AsyncArtworkView(urlString: entry.podcastArtworkUrl, size: 72, cornerRadius: 14)

                        VStack(alignment: .leading, spacing: 4) {
                            Text(entry.episodeTitle)
                                .font(.system(size: 16, weight: .bold))
                                .foregroundStyle(BrandTheme.textPrimary)
                                .lineLimit(2)

                            Text(entry.podcastTitle)
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(BrandTheme.cyan)

                            Text(entry.playedAt.formatted(date: .abbreviated, time: .shortened))
                                .font(.system(size: 11))
                                .foregroundStyle(BrandTheme.textMuted)
                        }
                    }
                    .padding(16)
                    .polarrCard(cornerRadius: 18)

                    // Listen Stats
                    HStack(spacing: 12) {
                        statPill(
                            title: "Listened",
                            value: formatTime(seconds: entry.timeListenedSecs ?? 0),
                            icon: "headphones"
                        )
                        statPill(
                            title: "Duration",
                            value: formatTime(seconds: entry.episodeDurationSecs ?? 0),
                            icon: "clock"
                        )
                        statPill(
                            title: "Status",
                            value: (entry.isSkipped || entry.completionType.lowercased() == "skipped") ? "Skipped" : entry.completionType.capitalized,
                            icon: (entry.isSkipped || entry.completionType.lowercased() == "skipped") ? "slash.circle.fill" : "checkmark.circle.fill"
                        )
                    }

                    // Rating Section
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Rating")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(BrandTheme.textSecondary)
                            .textCase(.uppercase)

                        HStack {
                            RatingView(rating: $rating, maxRating: 5, starSize: 26)
                            Spacer()
                            if let r = rating {
                                Text("\(r) out of 5")
                                    .font(.system(size: 13, weight: .bold))
                                    .foregroundStyle(BrandTheme.amber)
                            }
                        }
                        .padding(14)
                        .polarrCard(cornerRadius: 14)
                    }

                    // Personal Notes Section
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
                                .frame(minHeight: 100)

                            if personalNote.isEmpty {
                                Text("Add reflections or key takeaways...")
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

                    // Chapter Bookmarks Section
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("Chapter Bookmarks (\(entry.bookmarks.count))")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(BrandTheme.textSecondary)
                                .textCase(.uppercase)

                            Spacer()

                            Button {
                                newBookmarkLabel = ""
                                newBookmarkTime = "0:00"
                                showBookmarkAlert = true
                            } label: {
                                Label("Add", systemImage: "plus")
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundStyle(BrandTheme.cyan)
                            }
                        }

                        if entry.bookmarks.isEmpty {
                            Text("No bookmarks saved for this episode.")
                                .font(.system(size: 13))
                                .foregroundStyle(BrandTheme.textMuted)
                                .padding(14)
                                .polarrCard(cornerRadius: 14)
                        } else {
                            VStack(spacing: 8) {
                                ForEach(entry.bookmarks.sorted(by: { $0.timestampSecs < $1.timestampSecs })) { bm in
                                    HStack(spacing: 12) {
                                        Text(formatTime(seconds: bm.timestampSecs))
                                            .font(.system(size: 12, weight: .bold, design: .monospaced))
                                            .foregroundStyle(BrandTheme.cyan)
                                            .padding(.horizontal, 8)
                                            .padding(.vertical, 4)
                                            .background(BrandTheme.bgSecondary)
                                            .clipShape(Capsule())

                                        Text(bm.label)
                                            .font(.system(size: 13))
                                            .foregroundStyle(BrandTheme.textPrimary)

                                        Spacer()
                                    }
                                    .padding(10)
                                    .polarrCard(cornerRadius: 10)
                                }
                            }
                        }
                    }

                    // Save Changes Button
                    Button {
                        saveChanges()
                    } label: {
                        Text("Save Changes")
                            .font(.system(size: 15, weight: .bold))
                            .foregroundStyle(Color.black)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(BrandTheme.brandGradient)
                            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }
                    .padding(.top, 8)

                    // Delete Entry Button
                    Button(role: .destructive) {
                        deleteEntry()
                    } label: {
                        Text("Delete from Journal")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(BrandTheme.rose)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                    }
                }
                .padding(16)
                .padding(.bottom, 90)
            }
        }
        .navigationTitle("Journal Entry")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            self.rating = entry.rating
            self.personalNote = entry.personalNote ?? ""
        }
        .alert("Add Bookmark", isPresented: $showBookmarkAlert) {
            TextField("Label (e.g. Quote about AI)", text: $newBookmarkLabel)
            TextField("Timestamp (seconds or MM:SS)", text: $newBookmarkTime)
            Button("Add") {
                addManualBookmark()
            }
            Button("Cancel", role: .cancel) {}
        }
    }

    private func statPill(title: String, value: String, icon: String) -> some View {
        VStack(spacing: 4) {
            Label(title, systemImage: icon)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(BrandTheme.textMuted)

            Text(value)
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(BrandTheme.textPrimary)
        }
        .frame(maxWidth: .infinity)
        .padding(10)
        .polarrCard(cornerRadius: 12)
    }

    private func saveChanges() {
        entry.rating = rating
        entry.personalNote = personalNote.isEmpty ? nil : personalNote
        entry.isSynced = false
        try? modelContext.save()

        Task {
            _ = try? await APIClient.shared.updateJournalEntry(
                entryId: entry.id,
                rating: rating,
                personalNote: personalNote.isEmpty ? nil : personalNote
            )
        }
        dismiss()
    }

    private func deleteEntry() {
        let entryId = entry.id
        modelContext.delete(entry)
        try? modelContext.save()

        Task {
            try? await APIClient.shared.performVoid(endpoint: "/journal/\(entryId)", method: "DELETE")
        }
        dismiss()
    }

    private func addManualBookmark() {
        var seconds = 0
        if newBookmarkTime.contains(":") {
            let parts = newBookmarkTime.split(separator: ":").compactMap { Int($0) }
            if parts.count == 2 {
                seconds = parts[0] * 60 + parts[1]
            } else if parts.count == 3 {
                seconds = parts[0] * 3600 + parts[1] * 60 + parts[2]
            }
        } else if let s = Int(newBookmarkTime) {
            seconds = s
        }

        let label = newBookmarkLabel.isEmpty ? "Moment at \(formatTime(seconds: seconds))" : newBookmarkLabel
        let bm = ChapterBookmarkItem(
            id: Int.random(in: 100_000...999_999),
            journalEntryId: entry.id,
            timestampSecs: seconds,
            label: label
        )
        modelContext.insert(bm)
        entry.bookmarks.append(bm)
        entry.isSynced = false
        try? modelContext.save()

        Task {
            _ = try? await APIClient.shared.addBookmark(journalId: entry.id, timestampSecs: seconds, label: label)
        }
    }
}
