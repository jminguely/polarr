import SwiftUI
import SwiftData

public struct JournalView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \JournalEntryItem.playedAt, order: .reverse)
    private var allEntries: [JournalEntryItem]

    @State private var filterMode: JournalFilter = .all
    @State private var searchText: String = ""
    @State private var showSettings: Bool = false
    @Bindable var syncManager = SyncManager.shared

    public enum JournalFilter: String, CaseIterable {
        case all = "All"
        case finished = "Finished"
        case skipped = "Skipped"
        case rated = "Rated"
        case notes = "Notes"
    }

    public init() {}

    public var filteredEntries: [JournalEntryItem] {
        var list = allEntries

        switch filterMode {
        case .all:
            break
        case .finished:
            list = list.filter { $0.completionType == "finished" && !$0.isSkipped }
        case .skipped:
            list = list.filter { $0.completionType == "skipped" || $0.isSkipped }
        case .rated:
            list = list.filter { $0.rating != nil }
        case .notes:
            list = list.filter { $0.personalNote != nil && !($0.personalNote!.isEmpty) }
        }

        if !searchText.isEmpty {
            list = list.filter {
                $0.episodeTitle.localizedCaseInsensitiveContains(searchText) ||
                $0.podcastTitle.localizedCaseInsensitiveContains(searchText) ||
                ($0.personalNote?.localizedCaseInsensitiveContains(searchText) ?? false)
            }
        }
        return list
    }

    public var totalListenedHours: Double {
        let secs = allEntries.filter { !$0.isSkipped }.reduce(0) {
            $0 + ($1.timeListenedSecs ?? $1.episodeDurationSecs ?? 0)
        }
        return Double(secs) / 3600.0
    }

    public var body: some View {
        NavigationStack {
            ZStack {
                BrandTheme.bgPrimary.ignoresSafeArea()

                if allEntries.isEmpty {
                    emptyJournalView
                } else {
                    ScrollView {
                        VStack(spacing: 16) {
                            // Listening Summary Banner
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("LIFETIME JOURNAL")
                                        .font(.system(size: 11, weight: .bold))
                                        .tracking(1.2)
                                        .foregroundStyle(BrandTheme.cyan)

                                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                                        Text(String(format: "%.1f", totalListenedHours))
                                            .font(.system(size: 24, weight: .bold, design: .rounded))
                                            .foregroundStyle(BrandTheme.textPrimary)
                                        Text("hours listened")
                                            .font(.system(size: 13, weight: .medium))
                                            .foregroundStyle(BrandTheme.textSecondary)
                                    }
                                }

                                Spacer()

                                VStack(alignment: .trailing, spacing: 2) {
                                    Text("\(allEntries.count)")
                                        .font(.system(size: 20, weight: .bold, design: .rounded))
                                        .foregroundStyle(BrandTheme.brandGradient)
                                    Text("journal entries")
                                        .font(.system(size: 11, weight: .medium))
                                        .foregroundStyle(BrandTheme.textSecondary)
                                }
                            }
                            .padding(16)
                            .polarrCard(cornerRadius: 18)
                            .padding(.horizontal, 16)
                            .padding(.top, 12)

                            // Filter Chips
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 8) {
                                    ForEach(JournalFilter.allCases, id: \.self) { filter in
                                        Button {
                                            filterMode = filter
                                        } label: {
                                            Text(filter.rawValue)
                                                .font(.system(size: 13, weight: .semibold))
                                                .foregroundStyle(filterMode == filter ? Color.black : BrandTheme.textSecondary)
                                                .padding(.horizontal, 14)
                                                .padding(.vertical, 7)
                                                .background(filterMode == filter ? BrandTheme.cyan : BrandTheme.bgSecondary)
                                                .clipShape(Capsule())
                                        }
                                    }
                                }
                                .padding(.horizontal, 16)
                            }

                            // Entries List
                            LazyVStack(spacing: 12) {
                                ForEach(filteredEntries) { entry in
                                    NavigationLink(destination: JournalEntryDetailView(entry: entry)) {
                                        journalCard(for: entry)
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                            .padding(.horizontal, 16)
                            .padding(.bottom, 90)
                        }
                    }
                    .searchable(text: $searchText, prompt: "Search journal, reflections, notes")
                    .refreshable {
                        await syncManager.sync(modelContext: modelContext)
                    }
                }
            }
            .navigationTitle("Listening Journal")
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
                        Task { await syncManager.sync(modelContext: modelContext) }
                    } label: {
                        if syncManager.isSyncing {
                            ProgressView().tint(BrandTheme.cyan).scaleEffect(0.8)
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
        }
    }

    private func journalCard(for entry: JournalEntryItem) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            // Header Row: Artwork + Podcast Title + Date
            HStack(spacing: 10) {
                AsyncArtworkView(urlString: entry.podcastArtworkUrl, size: 42, cornerRadius: 10)

                VStack(alignment: .leading, spacing: 2) {
                    Text(entry.podcastTitle)
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(BrandTheme.cyan)
                        .lineLimit(1)

                    Text(entry.playedAt.formatted(date: .abbreviated, time: .omitted))
                        .font(.system(size: 11))
                        .foregroundStyle(BrandTheme.textMuted)
                }

                Spacer()

                // Star Rating
                if let r = entry.rating {
                    HStack(spacing: 2) {
                        ForEach(1...r, id: \.self) { _ in
                            Image(systemName: "star.fill")
                                .font(.system(size: 10))
                                .foregroundStyle(BrandTheme.amber)
                        }
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(BrandTheme.bgSecondary)
                    .clipShape(Capsule())
                }
            }

            // Episode Title
            Text(entry.episodeTitle)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(BrandTheme.textPrimary)
                .lineLimit(2)

            // Personal Reflection Note snippet
            if let note = entry.personalNote, !note.isEmpty {
                HStack(alignment: .top, spacing: 8) {
                    Rectangle()
                        .fill(BrandTheme.cyan)
                        .frame(width: 2)

                    Text("\"\(note)\"")
                        .font(.system(size: 13, weight: .regular))
                        .foregroundStyle(BrandTheme.textSecondary)
                        .italic()
                        .lineLimit(2)
                }
                .padding(.vertical, 2)
            }

            Divider().background(BrandTheme.border)

            // Footer info
            HStack {
                // Time listened
                let listened = entry.timeListenedSecs ?? entry.episodeDurationSecs ?? 0
                Label(formatTime(seconds: listened), systemImage: "headphones")
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundStyle(BrandTheme.textSecondary)

                // Chapter Bookmarks badge
                if !entry.bookmarks.isEmpty {
                    Label("\(entry.bookmarks.count) bookmarks", systemImage: "bookmark.fill")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(BrandTheme.cyan)
                }

                Spacer()

                // Status Badge
                Text(entry.completionType.uppercased())
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(entry.isSkipped ? BrandTheme.amber : BrandTheme.emerald)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 2)
                    .background(entry.isSkipped ? BrandTheme.amber.opacity(0.15) : BrandTheme.emerald.opacity(0.15))
                    .clipShape(Capsule())
            }
        }
        .padding(14)
        .polarrCard(cornerRadius: 16)
    }

    private var emptyJournalView: some View {
        VStack(spacing: 16) {
            Image(systemName: "book.pages")
                .font(.system(size: 48, weight: .light))
                .foregroundStyle(BrandTheme.textMuted)

            Text("Your Journal is Waiting")
                .font(.system(size: 18, weight: .bold))
                .foregroundStyle(BrandTheme.textPrimary)

            Text("As you listen to episodes, Polarr automatically builds your rich listening chronology with ratings, notes, and time listened.")
                .font(.system(size: 14))
                .foregroundStyle(BrandTheme.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
        }
    }
}
