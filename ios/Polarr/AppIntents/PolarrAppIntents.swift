import Foundation
import AppIntents

public struct SetSleepTimerIntent: AppIntent {
    public static var title: LocalizedStringResource = "Set Sleep Timer"
    public static var description = IntentDescription("Sets a sleep timer in Polarr to automatically pause audio.")

    @Parameter(title: "Duration (Minutes)", default: 30)
    var minutes: Int

    public init() {}

    public init(minutes: Int) {
        self.minutes = minutes
    }

    public func perform() async throws -> some IntentResult & ProvidesDialog {
        await MainActor.run {
            SleepTimerManager.shared.setTimer(minutes: minutes)
        }
        return .result(dialog: "Polarr sleep timer set for \(minutes) minutes.")
    }
}

public struct ToggleSleepTimerIntent: AppIntent {
    public static var title: LocalizedStringResource = "Toggle Sleep Timer"
    public static var description = IntentDescription("Toggles the 30-minute sleep timer in Polarr on or off.")

    public init() {}

    public func perform() async throws -> some IntentResult & ProvidesDialog {
        let isNowActive = await MainActor.run { () -> Bool in
            if SleepTimerManager.shared.isActive {
                SleepTimerManager.shared.cancelTimer()
                return false
            } else {
                SleepTimerManager.shared.setTimer(minutes: 30)
                return true
            }
        }
        let msg = isNowActive ? "Sleep timer started for 30 minutes." : "Sleep timer cancelled."
        return .result(dialog: IntentDialog(stringLiteral: msg))
    }
}

public struct ToggleVoiceBoostIntent: AppIntent {
    public static var title: LocalizedStringResource = "Toggle Voice Boost"
    public static var description = IntentDescription("Toggles vocal clarity enhancement in Polarr.")

    public init() {}

    public func perform() async throws -> some IntentResult & ProvidesDialog {
        let state = await MainActor.run { () -> Bool in
            AudioEffectsManager.shared.isVoiceBoostEnabled.toggle()
            return AudioEffectsManager.shared.isVoiceBoostEnabled
        }
        let msg = state ? "Voice Boost enabled." : "Voice Boost disabled."
        return .result(dialog: IntentDialog(stringLiteral: msg))
    }
}

public struct ToggleSmartSpeedIntent: AppIntent {
    public static var title: LocalizedStringResource = "Toggle Smart Speed"
    public static var description = IntentDescription("Toggles silence trimming in Polarr.")

    public init() {}

    public func perform() async throws -> some IntentResult & ProvidesDialog {
        let state = await MainActor.run { () -> Bool in
            AudioEffectsManager.shared.isSilenceTrimmingEnabled.toggle()
            return AudioEffectsManager.shared.isSilenceTrimmingEnabled
        }
        let msg = state ? "Smart Speed silence trimming enabled." : "Smart Speed silence trimming disabled."
        return .result(dialog: IntentDialog(stringLiteral: msg))
    }
}

public struct SetPlaybackSpeedIntent: AppIntent {
    public static var title: LocalizedStringResource = "Set Playback Speed"
    public static var description = IntentDescription("Sets playback speed rate in Polarr (0.5x to 3.0x).")

    @Parameter(title: "Speed (e.g. 1.2)", default: 1.2)
    var speed: Double

    public init() {}

    public init(speed: Double) {
        self.speed = speed
    }

    public func perform() async throws -> some IntentResult & ProvidesDialog {
        await MainActor.run {
            let clamped = Float(max(0.5, min(3.0, speed)))
            AudioManager.shared.setRate(clamped)
        }
        return .result(dialog: "Polarr speed set to \(String(format: "%.1fx", speed)).")
    }
}

public struct ResumePlaybackIntent: AudioPlaybackIntent {
    public static var title: LocalizedStringResource = "Resume Polarr Playback"
    public static var description = IntentDescription("Resumes playback of the current episode in Polarr.")

    public init() {}

    public func perform() async throws -> some IntentResult {
        await MainActor.run {
            AudioManager.shared.resume()
        }
        return .result()
    }
}

public struct PolarrShortcutsProvider: AppShortcutsProvider {
    public static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: ResumePlaybackIntent(),
            phrases: [
                "Resume \(.applicationName)",
                "Play \(.applicationName)"
            ],
            shortTitle: "Resume Playback",
            systemImageName: "play.fill"
        )
        AppShortcut(
            intent: ToggleSleepTimerIntent(),
            phrases: [
                "Set a sleep timer in \(.applicationName)",
                "Sleep timer on \(.applicationName)"
            ],
            shortTitle: "Sleep Timer",
            systemImageName: "moon.zzz.fill"
        )
        AppShortcut(
            intent: ToggleVoiceBoostIntent(),
            phrases: [
                "Toggle Voice Boost in \(.applicationName)"
            ],
            shortTitle: "Toggle Voice Boost",
            systemImageName: "waveform"
        )
    }
}
