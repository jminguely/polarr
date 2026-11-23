import Foundation
import SwiftUI

@Observable
public final class AudioEffectsManager {
    public static let shared = AudioEffectsManager()

    private let kVoiceBoostKey = "polarr_voice_boost_enabled"
    private let kSilenceTrimmingKey = "polarr_silence_trimming_enabled"
    private let kSavedSecondsKey = "polarr_smart_speed_seconds_saved"

    public var isVoiceBoostEnabled: Bool {
        didSet {
            UserDefaults.standard.set(isVoiceBoostEnabled, forKey: kVoiceBoostKey)
            AudioManager.shared.applyAudioEffects()
        }
    }

    public var isSilenceTrimmingEnabled: Bool {
        didSet {
            UserDefaults.standard.set(isSilenceTrimmingEnabled, forKey: kSilenceTrimmingKey)
            AudioManager.shared.applyAudioEffects()
        }
    }

    public private(set) var secondsSavedWithSmartSpeed: Double {
        didSet {
            UserDefaults.standard.set(secondsSavedWithSmartSpeed, forKey: kSavedSecondsKey)
        }
    }

    private init() {
        self.isVoiceBoostEnabled = UserDefaults.standard.bool(forKey: kVoiceBoostKey)
        self.isSilenceTrimmingEnabled = UserDefaults.standard.bool(forKey: kSilenceTrimmingKey)
        self.secondsSavedWithSmartSpeed = UserDefaults.standard.double(forKey: kSavedSecondsKey)
    }

    public func addSavedSilence(seconds: Double) {
        guard seconds > 0 else { return }
        secondsSavedWithSmartSpeed += seconds
    }

    public var formattedTimeSaved: String {
        let total = Int(secondsSavedWithSmartSpeed)
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        if hours > 0 {
            return "\(hours)h \(minutes)m saved"
        } else if minutes > 0 {
            return "\(minutes) min saved"
        } else {
            return "\(total)s saved"
        }
    }
}
