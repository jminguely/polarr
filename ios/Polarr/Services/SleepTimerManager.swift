import Foundation
import SwiftUI
import CoreMotion
import AVFoundation

@Observable
public final class SleepTimerManager {
    public static let shared = SleepTimerManager()

    public private(set) var timeRemaining: TimeInterval = 0
    public private(set) var isEndOfEpisode: Bool = false
    public private(set) var isActive: Bool = false

    private var timer: Timer?
    private let motionManager = CMMotionManager()
    private var lastShakeTime = Date.distantPast

    private init() {
        startMotionMonitoring()
    }

    public func setTimer(minutes: Int) {
        stopTimer()
        isEndOfEpisode = false
        timeRemaining = TimeInterval(minutes * 60)
        isActive = true
        startTicker()
    }

    public func setEndOfEpisode() {
        stopTimer()
        isEndOfEpisode = true
        isActive = true
        // Set time remaining to current episode remaining time if known
        let remaining = max(0, AudioManager.shared.duration - AudioManager.shared.currentTime)
        timeRemaining = remaining > 0 ? remaining : 1800
        startTicker()
    }

    public func cancelTimer() {
        stopTimer()
    }

    public func extendTimer(by seconds: TimeInterval = 15 * 60) {
        timeRemaining += seconds
        isActive = true
        AudioManager.shared.setVolume(1.0)
        if timer == nil {
            startTicker()
        }
    }

    private func stopTimer() {
        timer?.invalidate()
        timer = nil
        timeRemaining = 0
        isEndOfEpisode = false
        isActive = false
        AudioManager.shared.setVolume(1.0)
    }

    private func startTicker() {
        timer?.invalidate()
        AudioManager.shared.setVolume(1.0)

        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            guard let self = self else { return }

            if self.isEndOfEpisode {
                let remaining = max(0, AudioManager.shared.duration - AudioManager.shared.currentTime)
                self.timeRemaining = remaining
                if remaining <= 5.0 && remaining > 0 {
                    let vol = Float(max(0, remaining / 5.0))
                    AudioManager.shared.setVolume(vol)
                }
                if remaining <= 0.5 {
                    self.timerExpired()
                }
            } else {
                if self.timeRemaining > 1 {
                    self.timeRemaining -= 1
                    if self.timeRemaining <= 5.0 {
                        let vol = Float(max(0, self.timeRemaining / 5.0))
                        AudioManager.shared.setVolume(vol)
                    }
                } else {
                    self.timerExpired()
                }
            }
        }
    }

    private func timerExpired() {
        stopTimer()
        AudioManager.shared.pause()
    }

    // MARK: - Accelerometer Shake Detection
    private func startMotionMonitoring() {
        guard motionManager.isAccelerometerAvailable else { return }
        motionManager.accelerometerUpdateInterval = 0.2
        motionManager.startAccelerometerUpdates(to: .main) { [weak self] data, _ in
            guard let self = self, let data = data, self.isActive else { return }
            let magnitude = sqrt(data.acceleration.x * data.acceleration.x +
                                 data.acceleration.y * data.acceleration.y +
                                 data.acceleration.z * data.acceleration.z)

            if magnitude > 2.3 && Date().timeIntervalSince(self.lastShakeTime) > 4.0 {
                self.lastShakeTime = Date()
                self.extendTimer(by: 15 * 60)
                let generator = UIImpactFeedbackGenerator(style: .medium)
                generator.impactOccurred()
            }
        }
    }

    public var formattedRemainingTime: String {
        guard isActive else { return "" }
        if isEndOfEpisode {
            return "End of Ep"
        }
        let total = Int(timeRemaining)
        let m = total / 60
        let s = total % 60
        if m >= 60 {
            let h = m / 60
            return String(format: "%dh %dm", h, m % 60)
        }
        return String(format: "%02d:%02d", m, s)
    }
}
