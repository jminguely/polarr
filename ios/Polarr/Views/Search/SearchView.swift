import SwiftUI
import SwiftData

public struct SearchView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(filter: #Predicate<PodcastItem> { $0.isSubscribed }) private var subscribedPodcasts: [PodcastItem]

    @State private var queryText: String = ""
    @State private var results: [APISearchResult] = []
    @State private var isSearching: Bool = false
    @State private var errorMessage: String?
    @State private var showRSSSheet: Bool = false
    @State private var showSettings: Bool = false
    @State private var directRSSUrl: String = ""
    @State private var isSubscribing: Bool = false

    public init() {}

    public var body: some View {
        NavigationStack {
            ZStack {
                BrandTheme.bgPrimary.ignoresSafeArea()

                VStack(spacing: 0) {
                    if isSearching {
                        ProgressView("Searching PodcastIndex...")
                            .tint(BrandTheme.cyan)
                            .foregroundStyle(BrandTheme.textSecondary)
                            .padding(.top, 40)
                        Spacer()
                    } else if results.isEmpty && !queryText.isEmpty {
                        VStack(spacing: 12) {
                            Image(systemName: "magnifyingglass")
                                .font(.system(size: 40))
                                .foregroundStyle(BrandTheme.textMuted)
                            Text("No podcasts found for \"\(queryText)\"")
                                .font(.system(size: 15))
                                .foregroundStyle(BrandTheme.textSecondary)
                        }
                        .padding(.top, 60)
                        Spacer()
                    } else if results.isEmpty {
                        emptyStateView
                    } else {
                        ScrollView {
                            LazyVStack(spacing: 12) {
                                ForEach(results) { item in
                                    searchResultCard(item)
                                }
                            }
                            .padding(.horizontal, 16)
                            .padding(.top, 12)
                            .padding(.bottom, 90)
                        }
                    }
                }
            }
            .navigationTitle("Discover")
            .searchable(text: $queryText, prompt: "Search podcast directory...")
            .onSubmit(of: .search) {
                performSearch()
            }
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
                        showRSSSheet = true
                    } label: {
                        Label("Add RSS", systemImage: "link.badge.plus")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(BrandTheme.cyan)
                    }
                }
            }
            .sheet(isPresented: $showRSSSheet) {
                directRSSSheet
            }
            .sheet(isPresented: $showSettings) {
                SettingsView()
            }
        }
    }

    private func searchResultCard(_ item: APISearchResult) -> some View {
        let isAlreadySubscribed = subscribedPodcasts.contains {
            $0.feedUrl.trimmingCharacters(in: CharacterSet(charactersIn: "/")) == item.feed_url.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        }

        return HStack(spacing: 12) {
            AsyncArtworkView(urlString: item.artwork_url, size: 56, cornerRadius: 12)

            VStack(alignment: .leading, spacing: 3) {
                Text(item.title ?? "Untitled")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(BrandTheme.textPrimary)
                    .lineLimit(1)

                if let author = item.author, !author.isEmpty {
                    Text(author)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(BrandTheme.textSecondary)
                        .lineLimit(1)
                }

                if let epCount = item.episode_count {
                    Text("\(epCount) episodes")
                        .font(.system(size: 11))
                        .foregroundStyle(BrandTheme.textMuted)
                }
            }

            Spacer()

            if isAlreadySubscribed {
                Label("Subscribed", systemImage: "checkmark")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(BrandTheme.emerald)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(BrandTheme.emerald.opacity(0.15))
                    .clipShape(Capsule())
            } else {
                Button {
                    subscribe(to: item)
                } label: {
                    Text("Subscribe")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(Color.black)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 6)
                        .background(BrandTheme.brandGradient)
                        .clipShape(Capsule())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(12)
        .polarrCard(cornerRadius: 16)
    }

    private var emptyStateView: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "waveform.and.magnifyingglass")
                .font(.system(size: 52, weight: .light))
                .foregroundStyle(BrandTheme.textMuted)

            Text("Find Your Next Favorite Podcast")
                .font(.system(size: 18, weight: .bold))
                .foregroundStyle(BrandTheme.textPrimary)

            Text("Search across millions of podcasts powered by the open PodcastIndex directory, or add any private RSS feed directly.")
                .font(.system(size: 14))
                .foregroundStyle(BrandTheme.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)

            Button {
                showRSSSheet = true
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "link")
                    Text("Subscribe by RSS Feed URL")
                }
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(BrandTheme.cyan)
                .padding(.horizontal, 18)
                .padding(.vertical, 10)
                .background(BrandTheme.bgSecondary)
                .clipShape(Capsule())
            }
            .padding(.top, 8)
            Spacer()
        }
    }

    private var directRSSSheet: some View {
        NavigationStack {
            ZStack {
                BrandTheme.bgPrimary.ignoresSafeArea()

                VStack(alignment: .leading, spacing: 20) {
                    Text("Enter the RSS Feed URL of any podcast to subscribe directly.")
                        .font(.system(size: 14))
                        .foregroundStyle(BrandTheme.textSecondary)

                    TextField("https://example.com/podcast.xml", text: $directRSSUrl)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                        .keyboardType(.URL)
                        .padding(14)
                        .background(BrandTheme.bgCard)
                        .foregroundStyle(BrandTheme.textPrimary)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(BrandTheme.border, lineWidth: 1)
                        )

                    Spacer()

                    Button {
                        subscribeDirectRSS()
                    } label: {
                        HStack {
                            if isSubscribing {
                                ProgressView().tint(.black)
                            } else {
                                Text("Subscribe")
                            }
                        }
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(Color.black)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(BrandTheme.brandGradient)
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                    }
                    .disabled(directRSSUrl.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isSubscribing)
                }
                .padding(20)
            }
            .navigationTitle("Add RSS Feed")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { showRSSSheet = false }
                        .foregroundStyle(BrandTheme.textSecondary)
                }
            }
        }
    }

    private func performSearch() {
        guard !queryText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        isSearching = true
        errorMessage = nil

        Task {
            do {
                results = try await APIClient.shared.searchDirectory(query: queryText)
                isSearching = false
            } catch {
                isSearching = false
                errorMessage = error.localizedDescription
            }
        }
    }

    private func subscribe(to item: APISearchResult) {
        Task {
            do {
                _ = try await APIClient.shared.subscribePodcast(
                    feedUrl: item.feed_url,
                    title: item.title,
                    artworkUrl: item.artwork_url
                )
                await SyncManager.shared.sync(modelContext: modelContext)
            } catch {
                print("Failed to subscribe: \(error)")
            }
        }
    }

    private func subscribeDirectRSS() {
        let url = directRSSUrl.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !url.isEmpty else { return }
        isSubscribing = true

        Task {
            do {
                _ = try await APIClient.shared.subscribePodcast(feedUrl: url)
                await SyncManager.shared.sync(modelContext: modelContext)
                isSubscribing = false
                showRSSSheet = false
                directRSSUrl = ""
            } catch {
                isSubscribing = false
                print("Failed direct subscribe: \(error)")
            }
        }
    }
}
