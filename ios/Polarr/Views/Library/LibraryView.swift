import SwiftUI
import SwiftData

public struct LibraryView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(filter: #Predicate<PodcastItem> { $0.isSubscribed }, sort: \.title)
    private var podcasts: [PodcastItem]

    @Query(sort: \PlaylistItem.updatedAt, order: .reverse)
    private var playlists: [PlaylistItem]

    @Query(sort: \PlaylistEpisodeItem.position, order: .forward)
    private var allPlaylistEpisodes: [PlaylistEpisodeItem]

    @State private var selectedSection: LibrarySection = .subscriptions
    @State private var searchText: String = ""
    @State private var showSettings: Bool = false
    @State private var showNewPlaylistAlert: Bool = false
    @State private var newPlaylistTitle: String = ""

    @Bindable var syncManager = SyncManager.shared
    @Bindable var playlistManager = PlaylistManager.shared

    public enum LibrarySection: Int, CaseIterable {
        case subscriptions = 0
        case playlists = 1
    }

    private let columns = [
        GridItem(.flexible(), spacing: 14),
        GridItem(.flexible(), spacing: 14)
    ]

    public init() {}

    public var filteredPodcasts: [PodcastItem] {
        if searchText.isEmpty {
            return podcasts
        }
        return podcasts.filter { $0.title.localizedCaseInsensitiveContains(searchText) }
    }

    public var body: some View {
        NavigationStack {
            ZStack {
                BrandTheme.bgPrimary.ignoresSafeArea()

                VStack(spacing: 0) {
                    // Top Segmented Control (Subscriptions vs Playlists)
                    Picker("Library Section", selection: $selectedSection) {
                        Text("Subscriptions (\(podcasts.count))").tag(LibrarySection.subscriptions)
                        Text("Playlists (\(playlists.count))").tag(LibrarySection.playlists)
                    }
                    .pickerStyle(.segmented)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)

                    if selectedSection == .subscriptions {
                        subscriptionsContent
                    } else {
                        PlaylistsContentView(
                            playlists: playlists,
                            allEpisodes: allPlaylistEpisodes,
                            showNewPlaylistAlert: $showNewPlaylistAlert,
                            newPlaylistTitle: $newPlaylistTitle
                        )
                    }
                }
            }
            .navigationTitle(selectedSection == .subscriptions ? "Subscriptions" : "Playlists")
            .navigationBarTitleDisplayMode(.inline)
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
                    HStack(spacing: 12) {
                        if selectedSection == .playlists {
                            Button {
                                newPlaylistTitle = ""
                                showNewPlaylistAlert = true
                            } label: {
                                Image(systemName: "plus")
                                    .font(.system(size: 16, weight: .bold))
                                    .foregroundStyle(Color.white)
                            }
                        }

                        Button {
                            Task {
                                await syncManager.sync(modelContext: modelContext)
                                await playlistManager.syncPlaylists(modelContext: modelContext)
                            }
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
            }
            .sheet(isPresented: $showSettings) {
                SettingsView()
            }
            .alert("New Playlist", isPresented: $showNewPlaylistAlert) {
                TextField("Playlist title", text: $newPlaylistTitle)
                Button("Create") {
                    createPlaylist()
                }
                Button("Cancel", role: .cancel) {}
            }
        }
    }

    private var subscriptionsContent: some View {
        Group {
            if podcasts.isEmpty {
                emptyLibraryView
            } else {
                ScrollView {
                    LazyVGrid(columns: columns, spacing: 16) {
                        ForEach(filteredPodcasts) { pod in
                            NavigationLink(destination: PodcastDetailView(podcast: pod)) {
                                podcastCard(for: pod)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 12)
                    .padding(.bottom, 90)
                }
                .searchable(text: $searchText, prompt: "Filter subscriptions")
                .refreshable {
                    await syncManager.sync(modelContext: modelContext)
                }
            }
        }
    }

    private func createPlaylist() {
        let title = newPlaylistTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { return }
        let playlist = PlaylistItem(title: title)
        modelContext.insert(playlist)
        try? modelContext.save()

        Task {
            _ = try? await APIClient.shared.createPlaylist(
                title: title,
                uuid: playlist.id
            )
        }
    }

    private var emptyLibraryView: some View {
        VStack(spacing: 16) {
            Image(systemName: "square.grid.2x2")
                .font(.system(size: 48, weight: .light))
                .foregroundStyle(BrandTheme.textMuted)

            Text("No Subscriptions")
                .font(.system(size: 18, weight: .bold))
                .foregroundStyle(BrandTheme.textPrimary)

            Text("Search or discover podcasts to add subscriptions.")
                .font(.system(size: 14))
                .foregroundStyle(BrandTheme.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
        }
        .frame(maxHeight: .infinity)
    }

    private func podcastCard(for pod: PodcastItem) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            AsyncArtworkView(urlString: pod.artworkUrl, size: nil, cornerRadius: 14)
                .aspectRatio(1, contentMode: .fit)

            VStack(alignment: .leading, spacing: 2) {
                Text(pod.title)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(BrandTheme.textPrimary)
                    .lineLimit(1)

                Text(pod.syncOrder == "oldest_first" ? "Chronological" : "Latest First")
                    .font(.system(size: 11))
                    .foregroundStyle(BrandTheme.textMuted)
            }
        }
        .padding(10)
        .polarrCard(cornerRadius: 16)
    }
}
