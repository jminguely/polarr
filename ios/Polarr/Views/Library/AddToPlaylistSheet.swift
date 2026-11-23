import SwiftUI
import SwiftData

public struct AddToPlaylistSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \PlaylistItem.updatedAt, order: .reverse) private var playlists: [PlaylistItem]

    public let episodeGuid: String
    public let episodeTitle: String
    public let podcastId: Int?
    public let podcastTitle: String
    public let podcastArtworkUrl: String?
    public let enclosureUrl: String?
    public let durationSecs: Int?

    @State private var showCreateAlert: Bool = false
    @State private var newPlaylistTitle: String = ""

    public init(
        episodeGuid: String,
        episodeTitle: String,
        podcastId: Int? = nil,
        podcastTitle: String,
        podcastArtworkUrl: String? = nil,
        enclosureUrl: String? = nil,
        durationSecs: Int? = nil
    ) {
        self.episodeGuid = episodeGuid
        self.episodeTitle = episodeTitle
        self.podcastId = podcastId
        self.podcastTitle = podcastTitle
        self.podcastArtworkUrl = podcastArtworkUrl
        self.enclosureUrl = enclosureUrl
        self.durationSecs = durationSecs
    }

    public var body: some View {
        NavigationStack {
            ZStack {
                BrandTheme.bgPrimary.ignoresSafeArea()

                VStack(spacing: 0) {
                    // Episode preview banner
                    HStack(spacing: 12) {
                        AsyncArtworkView(urlString: podcastArtworkUrl, size: 48, cornerRadius: 10)

                        VStack(alignment: .leading, spacing: 3) {
                            Text(episodeTitle)
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(Color.white)
                                .lineLimit(1)
                            Text(podcastTitle)
                                .font(.system(size: 12))
                                .foregroundStyle(BrandTheme.textSecondary)
                                .lineLimit(1)
                        }
                        Spacer()
                    }
                    .padding(16)
                    .background(BrandTheme.bgSecondary)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .stroke(BrandTheme.border, lineWidth: 1)
                    )
                    .padding(.horizontal, 16)
                    .padding(.top, 12)

                    if playlists.isEmpty {
                        Spacer()
                        VStack(spacing: 12) {
                            Image(systemName: "music.note.list")
                                .font(.system(size: 36))
                                .foregroundStyle(BrandTheme.textMuted)
                            Text("No Playlists Yet")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundStyle(Color.white)
                            Text("Create your first custom playlist to save this episode.")
                                .font(.system(size: 13))
                                .foregroundStyle(BrandTheme.textSecondary)
                                .multilineTextAlignment(.center)
                                .padding(.horizontal, 32)

                            Button {
                                newPlaylistTitle = ""
                                showCreateAlert = true
                            } label: {
                                Label("Create Playlist", systemImage: "plus.circle.fill")
                                    .font(.system(size: 14, weight: .bold))
                                    .foregroundStyle(Color.black)
                                    .padding(.horizontal, 16)
                                    .padding(.vertical, 10)
                                    .background(Color.white)
                                    .clipShape(Capsule())
                            }
                            .padding(.top, 6)
                        }
                        Spacer()
                    } else {
                        List {
                            Section {
                                ForEach(playlists) { pl in
                                    let isInPlaylist = pl.episodeGuids.contains(episodeGuid)

                                    Button {
                                        togglePlaylistMembership(pl)
                                    } label: {
                                        HStack(spacing: 14) {
                                            Image(systemName: isInPlaylist ? "checkmark.circle.fill" : "circle")
                                                .font(.system(size: 20))
                                                .foregroundStyle(isInPlaylist ? Color.white : BrandTheme.textMuted)

                                            VStack(alignment: .leading, spacing: 2) {
                                                HStack(spacing: 6) {
                                                    Text(pl.title)
                                                        .font(.system(size: 15, weight: .semibold))
                                                        .foregroundStyle(Color.white)
                                                    if pl.isSmart {
                                                        Text("Smart")
                                                            .font(.system(size: 9, weight: .bold))
                                                            .foregroundStyle(Color.black)
                                                            .padding(.horizontal, 5)
                                                            .padding(.vertical, 1.5)
                                                            .background(Color.white)
                                                            .clipShape(Capsule())
                                                    }
                                                }
                                                Text("\(pl.episodeGuids.count) episodes")
                                                    .font(.system(size: 12))
                                                    .foregroundStyle(BrandTheme.textSecondary)
                                            }

                                            Spacer()
                                        }
                                        .padding(.vertical, 4)
                                    }
                                    .buttonStyle(.plain)
                                    .listRowBackground(BrandTheme.bgSecondary)
                                }
                            } header: {
                                Text("Choose Playlists")
                                    .font(.system(size: 11, weight: .bold))
                                    .foregroundStyle(BrandTheme.textMuted)
                            }
                        }
                        .listStyle(.insetGrouped)
                        .scrollContentBackground(.hidden)
                    }
                }
            }
            .navigationTitle("Add to Playlist")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        newPlaylistTitle = ""
                        showCreateAlert = true
                    } label: {
                        Image(systemName: "plus")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(Color.white)
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Color.white)
                }
            }
            .alert("Create New Playlist", isPresented: $showCreateAlert) {
                TextField("Playlist Name", text: $newPlaylistTitle)
                Button("Create and Add") {
                    createAndAdd()
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Enter a name for your new playlist.")
            }
        }
    }

    private func togglePlaylistMembership(_ pl: PlaylistItem) {
        if pl.episodeGuids.contains(episodeGuid) {
            PlaylistManager.shared.removeEpisode(guid: episodeGuid, from: pl, modelContext: modelContext)
        } else {
            PlaylistManager.shared.addEpisode(
                guid: episodeGuid,
                title: episodeTitle,
                podcastId: podcastId,
                podcastTitle: podcastTitle,
                podcastArtworkUrl: podcastArtworkUrl,
                enclosureUrl: enclosureUrl,
                durationSecs: durationSecs,
                to: pl,
                modelContext: modelContext
            )
        }
    }

    private func createAndAdd() {
        let title = newPlaylistTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { return }

        let newPl = PlaylistItem(
            title: title,
            isSmart: false,
            autoRemoveFinished: false
        )
        modelContext.insert(newPl)
        try? modelContext.save()

        Task {
            _ = try? await APIClient.shared.createPlaylist(
                title: title,
                isSmart: false,
                autoRemoveFinished: false,
                uuid: newPl.id
            )
        }

        togglePlaylistMembership(newPl)
    }
}
