import SwiftUI
import SwiftData

public struct LibraryView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(filter: #Predicate<PodcastItem> { $0.isSubscribed }, sort: \.title)
    private var podcasts: [PodcastItem]

    @State private var searchText: String = ""
    @State private var showSettings: Bool = false
    @Bindable var syncManager = SyncManager.shared

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
            .navigationTitle("Subscriptions")
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

    private func podcastCard(for pod: PodcastItem) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            GeometryReader { geo in
                AsyncArtworkView(urlString: pod.artworkUrl, size: geo.size.width, cornerRadius: 14)
            }
            .aspectRatio(1, contentMode: .fit)

            VStack(alignment: .leading, spacing: 2) {
                Text(pod.title)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(BrandTheme.textPrimary)
                    .lineLimit(1)

                Text("\(pod.listenedCount) listened")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(BrandTheme.textSecondary)
            }
            .padding(.horizontal, 4)
            .padding(.bottom, 4)
        }
        .padding(10)
        .polarrCard(cornerRadius: 16)
    }

    private var emptyLibraryView: some View {
        VStack(spacing: 16) {
            Image(systemName: "square.grid.2x2")
                .font(.system(size: 48, weight: .light))
                .foregroundStyle(BrandTheme.textMuted)

            Text("No Subscriptions Yet")
                .font(.system(size: 18, weight: .bold))
                .foregroundStyle(BrandTheme.textPrimary)

            Text("Discover podcasts using the Search tab or enter an RSS feed to start listening.")
                .font(.system(size: 14))
                .foregroundStyle(BrandTheme.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)

            Button {
                showSettings = true
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "gearshape.fill")
                    Text("Configure Polarr Server")
                }
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(BrandTheme.cyan)
                .padding(.horizontal, 20)
                .padding(.vertical, 10)
                .background(BrandTheme.bgSecondary)
                .clipShape(Capsule())
            }
            .padding(.top, 8)
        }
    }
}
