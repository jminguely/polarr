import SwiftUI

public struct AudioEffectsSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Bindable var effectsManager = AudioEffectsManager.shared
    @Bindable var audioManager = AudioManager.shared

    public init() {}

    public var body: some View {
        NavigationStack {
            ZStack {
                BrandTheme.bgPrimary.ignoresSafeArea()

                VStack(spacing: 24) {
                    // Smart Speed Section
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Smart Speed")
                                    .font(.system(size: 17, weight: .bold))
                                    .foregroundStyle(Color.white)
                                Text("Shortens silence and pauses dynamically without altering pitch or vocal tone.")
                                    .font(.system(size: 13))
                                    .foregroundStyle(BrandTheme.textSecondary)
                            }
                            Spacer()
                            Toggle("", isOn: $effectsManager.isSilenceTrimmingEnabled)
                                .tint(audioManager.currentPalette.accent)
                                .labelsHidden()
                        }
                        .padding(18)
                        .background(BrandTheme.bgSecondary)
                        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .stroke(BrandTheme.border, lineWidth: 1)
                        )

                        // Lifetime Stats Badge
                        HStack(spacing: 8) {
                            Image(systemName: "bolt.fill")
                                .font(.system(size: 13))
                                .foregroundStyle(audioManager.currentPalette.accent)
                            Text("Total time saved: \(effectsManager.formattedTimeSaved)")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(BrandTheme.textSecondary)
                        }
                        .padding(.horizontal, 8)
                    }
                    .padding(.horizontal, 20)

                    // Voice Boost Section
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Voice Boost")
                                    .font(.system(size: 17, weight: .bold))
                                    .foregroundStyle(Color.white)
                                Text("Enhances vocal clarity and normalizes volume levels so quiet speakers remain clear in noisy environments.")
                                    .font(.system(size: 13))
                                    .foregroundStyle(BrandTheme.textSecondary)
                            }
                            Spacer()
                            Toggle("", isOn: $effectsManager.isVoiceBoostEnabled)
                                .tint(audioManager.currentPalette.accent)
                                .labelsHidden()
                        }
                        .padding(18)
                        .background(BrandTheme.bgSecondary)
                        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .stroke(BrandTheme.border, lineWidth: 1)
                        )
                    }
                    .padding(.horizontal, 20)

                    Spacer()
                }
                .padding(.top, 20)
            }
            .navigationTitle("Audio Effects")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                    .foregroundStyle(Color.white)
                }
            }
        }
    }
}
