import SwiftUI

public struct MiniPlayerBar: View {
    @Bindable var audioManager = AudioManager.shared
    @Binding var showFullPlayer: Bool

    public init(showFullPlayer: Binding<Bool>) {
        self._showFullPlayer = showFullPlayer
    }

    public var body: some View {
        if let episode = audioManager.currentEpisode {
            VStack(spacing: 0) {
                // Progress Line at Top
                GeometryReader { geo in
                    let progress = audioManager.duration > 0 ? (audioManager.currentTime / audioManager.duration) : 0
                    ZStack(alignment: .leading) {
                        Rectangle()
                            .fill(Color.white.opacity(0.1))
                        Rectangle()
                            .fill(BrandTheme.brandGradient)
                            .frame(width: geo.size.width * CGFloat(max(0, min(1, progress))))
                    }
                }
                .frame(height: 2.5)

                HStack(spacing: 12) {
                    // Artwork
                    AsyncArtworkView(urlString: episode.podcastArtworkUrl, size: 44, cornerRadius: 10)

                    // Episode Info
                    VStack(alignment: .leading, spacing: 2) {
                        Text(episode.episodeTitle)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(BrandTheme.textPrimary)
                            .lineLimit(1)

                        Text(episode.podcastTitle)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(BrandTheme.textSecondary)
                            .lineLimit(1)
                    }

                    Spacer()

                    // Quick Skip Backward
                    Button {
                        audioManager.skipBackward(seconds: 15)
                    } label: {
                        Image(systemName: "gobackward.15")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(BrandTheme.textSecondary)
                    }
                    .buttonStyle(.plain)

                    // Play / Pause Button
                    Button {
                        audioManager.togglePlayPause()
                    } label: {
                        ZStack {
                            Circle()
                                .fill(BrandTheme.cyan)
                                .frame(width: 38, height: 38)

                            if audioManager.isLoading {
                                ProgressView()
                                    .tint(.black)
                                    .scaleEffect(0.7)
                            } else {
                                Image(systemName: audioManager.isPlaying ? "pause.fill" : "play.fill")
                                    .font(.system(size: 16, weight: .bold))
                                    .foregroundStyle(Color.black)
                                    .offset(x: audioManager.isPlaying ? 0 : 1)
                            }
                        }
                    }
                    .buttonStyle(.plain)

                    // Quick Skip Forward
                    Button {
                        audioManager.skipForward(seconds: 30)
                    } label: {
                        Image(systemName: "goforward.30")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(BrandTheme.textSecondary)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
            }
            .background(BrandTheme.bgSecondary.opacity(0.96))
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(BrandTheme.border, lineWidth: 1)
            )
            .shadow(color: Color.black.opacity(0.4), radius: 12, x: 0, y: -2)
            .padding(.horizontal, 12)
            .padding(.bottom, 4)
            .contentShape(Rectangle())
            .onTapGesture {
                showFullPlayer = true
            }
            .transition(.move(edge: .bottom).combined(with: .opacity))
        }
    }
}
