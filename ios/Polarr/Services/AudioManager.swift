import Foundation
import AVFoundation
import MediaPlayer
import SwiftUI
import Observation

public struct PlayableEpisode: Codable, Equatable, Identifiable {
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
    public var currentPalette: ArtworkPalette = .default
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
    private var hasAutoCompletedCurrentEpisode: Bool = false

    // MARK: - Persistence Keys
    private let kLastEpisodeKey = "polarr_last_played_episode"
    private let kLastTimeKey = "polarr_last_played_time"
    private let kEpisodeProgressKey = "polarr_episode_progress"

    private var episodeProgressDict: [String: Double] = [:]

    private init() {
        setupAudioSession()
        setupRemoteCommands()
        loadSavedProgressDict()
        restorePlaybackState()
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

    // MARK: - Playback Progress Persistence
    private func loadSavedProgressDict() {
        if let dict = UserDefaults.standard.dictionary(forKey: kEpisodeProgressKey) as? [String: Double] {
            episodeProgressDict = dict
        }
    }

    public func getSavedProgress(for guid: String) -> Double? {
        return episodeProgressDict[guid]
    }

    public func saveSavedProgress(for guid: String, time: Double) {
        episodeProgressDict[guid] = time
        UserDefaults.standard.set(episodeProgressDict, forKey: kEpisodeProgressKey)
    }

    public func clearSavedProgress(for guid: String) {
        episodeProgressDict.removeValue(forKey: guid)
        UserDefaults.standard.set(episodeProgressDict, forKey: kEpisodeProgressKey)
        if currentEpisode?.episodeGuid == guid {
            UserDefaults.standard.removeObject(forKey: kLastEpisodeKey)
            UserDefaults.standard.removeObject(forKey: kLastTimeKey)
        }
    }

    public func savePlaybackState() {
        guard let ep = currentEpisode else { return }
        if let data = try? JSONEncoder().encode(ep) {
            UserDefaults.standard.set(data, forKey: kLastEpisodeKey)
        }
        UserDefaults.standard.set(currentTime, forKey: kLastTimeKey)
        if currentTime > 5 {
            saveSavedProgress(for: ep.episodeGuid, time: currentTime)
        }
    }

    public func restorePlaybackState() {
        guard let data = UserDefaults.standard.data(forKey: kLastEpisodeKey),
              let ep = try? JSONDecoder().decode(PlayableEpisode.self, from: data) else {
            return
        }

        let savedTime = UserDefaults.standard.double(forKey: kLastTimeKey)
        currentEpisode = ep
        currentTime = savedTime
        duration = Double(ep.durationSecs ?? 0)
        isPlaying = false
        isLoading = false

        // Determine audio URL (local download prioritized for offline playback)
        let targetURL: URL?
        if let localURL = DownloadManager.shared.localFileURL(for: ep.episodeGuid) {
            targetURL = localURL
        } else {
            targetURL = URL(string: ep.enclosureUrl)
        }

        guard let url = targetURL else { return }

        let playerItem = AVPlayerItem(url: url)
        player = AVPlayer(playerItem: playerItem)
        player?.automaticallyWaitsToMinimizeStalling = true

        if savedTime > 0 {
            player?.seek(to: CMTime(seconds: savedTime, preferredTimescale: 1))
        }

        setupObservers(for: playerItem)
        updateNowPlayingInfo()
        updatePalette(for: ep)
    }

    // MARK: - Playback Control
    public func play(episode: PlayableEpisode, startAt: Double = -1) {
        if currentEpisode?.episodeGuid == episode.episodeGuid, let _ = player {
            if !isPlaying {
                resume()
            }
            return
        }

        cleanupPlayer()
        currentEpisode = episode
        hasAutoCompletedCurrentEpisode = false
        isLoading = true

        // Determine resume timestamp
        let resolvedStartAt: Double
        if startAt >= 0 {
            resolvedStartAt = startAt
        } else if let saved = getSavedProgress(for: episode.episodeGuid), saved > 10 {
            if let dur = episode.durationSecs, saved >= Double(dur - 15) {
                resolvedStartAt = 0
            } else {
                resolvedStartAt = saved
            }
        } else {
            resolvedStartAt = 0
        }

        currentTime = resolvedStartAt
        duration = Double(episode.durationSecs ?? 0)

        // Prioritize offline downloaded audio file if available
        let audioURL: URL?
        if let local = DownloadManager.shared.localFileURL(for: episode.episodeGuid) {
            audioURL = local
        } else {
            audioURL = URL(string: episode.enclosureUrl)
        }

        guard let url = audioURL else {
            isLoading = false
            return
        }

        let playerItem = AVPlayerItem(url: url)
        player = AVPlayer(playerItem: playerItem)
        player?.automaticallyWaitsToMinimizeStalling = true

        if resolvedStartAt > 0 {
            player?.seek(to: CMTime(seconds: resolvedStartAt, preferredTimescale: 1))
        }

        setupObservers(for: playerItem)
        resume()
        savePlaybackState()
        updateNowPlayingInfo()
        updatePalette(for: episode)
    }

    private func updatePalette(for episode: PlayableEpisode?) {
        guard let ep = episode else {
            Task { @MainActor in
                withAnimation(.easeInOut(duration: 0.35)) {
                    self.currentPalette = .default
                }
            }
            return
        }

        Task { @MainActor in
            let palette = await ArtworkColorExtractor.shared.extractPalette(from: ep.podcastArtworkUrl)
            withAnimation(.easeInOut(duration: 0.35)) {
                self.currentPalette = palette
            }
        }
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
        savePlaybackState()
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
            self?.savePlaybackState()
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
            // Save state to disk every 2 seconds (4 * 0.5s)
            if self.progressCounter % 4 == 0 {
                self.savePlaybackState()
            }
            // Trigger remote progress update every 10 seconds (20 * 0.5s)
            if self.progressCounter % 20 == 0, let ep = self.currentEpisode {
                self.onProgressUpdate?(ep, self.currentTime)
            }

            // Auto-complete episode when reaching >= 92% of duration or within 20s of the end
            if self.duration > 60 && self.currentTime >= max(self.duration - 20, self.duration * 0.92) {
                if !self.hasAutoCompletedCurrentEpisode, let ep = self.currentEpisode {
                    self.hasAutoCompletedCurrentEpisode = true
                    self.clearSavedProgress(for: ep.episodeGuid)
                    self.onEpisodeFinished?(ep, self.currentTime)
                }
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
            self.clearSavedProgress(for: ep.episodeGuid)
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
