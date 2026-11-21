import Foundation
import AVFoundation
import MediaPlayer
import SwiftUI

public struct PlayableEpisode: Equatable, Identifiable {
    public var id: String { episodeGuid }
    public let podcastId: Int
    public let podcastTitle: String
    public let podcastArtworkUrl: String?
    public let episodeGuid: String
    public let episodeTitle: String
    public let enclosureUrl: String
    public let durationSecs: Int?

    public init(
        podcastId: Int,
        podcastTitle: String,
        podcastArtworkUrl: String? = nil,
        episodeGuid: String,
        episodeTitle: String,
        enclosureUrl: String,
        durationSecs: Int? = nil
    ) {
        self.podcastId = podcastId
        self.podcastTitle = podcastTitle
        self.podcastArtworkUrl = podcastArtworkUrl
        self.episodeGuid = episodeGuid
        self.episodeTitle = episodeTitle
        self.enclosureUrl = enclosureUrl
        self.durationSecs = durationSecs
    }
}

@Observable
public final class AudioManager {
    public static let shared = AudioManager()

    public var currentEpisode: PlayableEpisode?
    public var isPlaying: Bool = false
    public var isLoading: Bool = false
    public var currentTime: Double = 0
    public var duration: Double = 0
    public var playbackRate: Float = 1.0

    public var onEpisodeFinished: ((PlayableEpisode, Double) -> Void)?
    public var onProgressUpdate: ((PlayableEpisode, Double) -> Void)?

    private var player: AVPlayer?
    private var timeObserverToken: Any?
    private var endObserverToken: Any?
    private var progressCounter: Int = 0

    private init() {
        setupAudioSession()
        setupRemoteCommands()
    }

    // MARK: - Audio Session Setup
    private func setupAudioSession() {
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .spokenAudio, policy: .longFormAudio)
            try session.setActive(true)
        } catch {
            print("Failed to configure AVAudioSession: \(error)")
        }
    }

    // MARK: - Playback Control
    public func play(episode: PlayableEpisode, startAt: Double = 0) {
        if currentEpisode?.episodeGuid == episode.episodeGuid, let player = player {
            if !isPlaying {
                resume()
            }
            return
        }

        cleanupPlayer()
        currentEpisode = episode
        isLoading = true
        currentTime = startAt
        duration = Double(episode.durationSecs ?? 0)

        guard let url = URL(string: episode.enclosureUrl) else {
            isLoading = false
            return
        }

        let playerItem = AVPlayerItem(url: url)
        player = AVPlayer(playerItem: playerItem)
        player?.automaticallyWaitsToMinimizeStalling = true

        if startAt > 0 {
            player?.seek(to: CMTime(seconds: startAt, preferredTimescale: 1))
        }

        setupObservers(for: playerItem)
        resume()
        updateNowPlayingInfo()
    }

    public func resume() {
        guard let player = player else { return }
        player.rate = playbackRate
        isPlaying = true
        updateNowPlayingPlaybackState()
    }

    public func pause() {
        guard let player = player else { return }
        player.pause()
        isPlaying = false
        updateNowPlayingPlaybackState()
    }

    public func togglePlayPause() {
        if isPlaying {
            pause()
        } else {
            resume()
        }
    }

    public func seek(to seconds: Double) {
        guard let player = player else { return }
        let clamped = max(0, min(seconds, duration > 0 ? duration : Double.infinity))
        currentTime = clamped
        player.seek(to: CMTime(seconds: clamped, preferredTimescale: 1)) { [weak self] _ in
            self?.updateNowPlayingInfo()
        }
    }

    public func skipForward(seconds: Double = 30) {
        seek(to: currentTime + seconds)
    }

    public func skipBackward(seconds: Double = 15) {
        seek(to: currentTime - seconds)
    }

    public func setRate(_ rate: Float) {
        playbackRate = rate
        if isPlaying {
            player?.rate = rate
        }
        updateNowPlayingInfo()
    }

    public func cyclePlaybackRate() {
        let rates: [Float] = [1.0, 1.25, 1.5, 2.0]
        if let idx = rates.firstIndex(of: playbackRate) {
            let nextIdx = (idx + 1) % rates.count
            setRate(rates[nextIdx])
        } else {
            setRate(1.0)
        }
    }

    // MARK: - Observers
    private func setupObservers(for item: AVPlayerItem) {
        // Time observer (every 0.5s)
        let interval = CMTime(seconds: 0.5, preferredTimescale: CMTimeScale(NSEC_PER_SEC))
        timeObserverToken = player?.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] time in
            guard let self = self else { return }
            self.currentTime = time.seconds
            self.isLoading = false

            if let itemDuration = self.player?.currentItem?.duration.seconds, !itemDuration.isNaN, itemDuration > 0 {
                self.duration = itemDuration
            }

            self.progressCounter += 1
            if self.progressCounter % 20 == 0, let ep = self.currentEpisode {
                self.onProgressUpdate?(ep, self.currentTime)
            }
        }

        // End of playback observer
        endObserverToken = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: item,
            queue: .main
        ) { [weak self] _ in
            guard let self = self, let ep = self.currentEpisode else { return }
            self.isPlaying = false
            self.onEpisodeFinished?(ep, self.currentTime)
        }
    }

    private func cleanupPlayer() {
        if let token = timeObserverToken {
            player?.removeTimeObserver(token)
            timeObserverToken = nil
        }
        if let token = endObserverToken {
            NotificationCenter.default.removeObserver(token)
            endObserverToken = nil
        }
        player?.pause()
        player = nil
    }

    // MARK: - Lock Screen & Control Center
    private func setupRemoteCommands() {
        let center = MPRemoteCommandCenter.shared()

        center.playCommand.addTarget { [weak self] _ in
            self?.resume()
            return .success
        }
        center.pauseCommand.addTarget { [weak self] _ in
            self?.pause()
            return .success
        }
        center.togglePlayPauseCommand.addTarget { [weak self] _ in
            self?.togglePlayPause()
            return .success
        }
        center.skipForwardCommand.preferredIntervals = [30]
        center.skipForwardCommand.addTarget { [weak self] _ in
            self?.skipForward(seconds: 30)
            return .success
        }
        center.skipBackwardCommand.preferredIntervals = [15]
        center.skipBackwardCommand.addTarget { [weak self] _ in
            self?.skipBackward(seconds: 15)
            return .success
        }
        center.changePlaybackPositionCommand.addTarget { [weak self] event in
            guard let posEvent = event as? MPChangePlaybackPositionCommandEvent else { return .commandFailed }
            self?.seek(to: posEvent.positionTime)
            return .success
        }
    }

    private func updateNowPlayingInfo() {
        guard let ep = currentEpisode else {
            MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
            return
        }

        var info: [String: Any] = [
            MPMediaItemPropertyTitle: ep.episodeTitle,
            MPMediaItemPropertyArtist: ep.podcastTitle,
            MPMediaItemPropertyPlaybackDuration: duration > 0 ? duration : (Double(ep.durationSecs ?? 0)),
            MPNowPlayingInfoPropertyElapsedPlaybackTime: currentTime,
            MPNowPlayingInfoPropertyPlaybackRate: isPlaying ? Double(playbackRate) : 0.0
        ]

        if let artUrlStr = ep.podcastArtworkUrl, let url = URL(string: artUrlStr) {
            Task {
                if let (data, _) = try? await URLSession.shared.data(from: url), let img = UIImage(data: data) {
                    let artwork = MPMediaItemArtwork(boundsSize: img.size) { _ in img }
                    var current = MPNowPlayingInfoCenter.default().nowPlayingInfo ?? [:]
                    current[MPMediaItemPropertyArtwork] = artwork
                    MPNowPlayingInfoCenter.default().nowPlayingInfo = current
                }
            }
        }

        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
    }

    private func updateNowPlayingPlaybackState() {
        guard var info = MPNowPlayingInfoCenter.default().nowPlayingInfo else { return }
        info[MPNowPlayingInfoPropertyElapsedPlaybackTime] = currentTime
        info[MPNowPlayingInfoPropertyPlaybackRate] = isPlaying ? Double(playbackRate) : 0.0
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
    }
}
