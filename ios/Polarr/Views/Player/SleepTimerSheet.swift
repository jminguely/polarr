import SwiftUI

public struct SleepTimerSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Bindable var timerManager = SleepTimerManager.shared
    @Bindable var audioManager = AudioManager.shared

    let presets = [15, 30, 45, 60]

    public init() {}

    public var body: some View {
        NavigationStack {
            ZStack {
                BrandTheme.bgPrimary.ignoresSafeArea()

                VStack(spacing: 24) {
                    // Active Timer Status Card
                    if timerManager.isActive {
                        VStack(spacing: 8) {
                            Text("TIMER RUNNING")
                                .font(.system(size: 11, weight: .bold))
                                .tracking(1.5)
                                .foregroundStyle(audioManager.currentPalette.accent)

                            Text(timerManager.formattedRemainingTime)
                                .font(.system(size: 40, weight: .bold, design: .rounded))
                                .foregroundStyle(Color.white)

                            Button(role: .destructive) {
                                timerManager.cancelTimer()
                            } label: {
                                Label("Turn Off Timer", systemImage: "xmark.circle.fill")
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundStyle(BrandTheme.rose)
                                    .padding(.horizontal, 16)
                                    .padding(.vertical, 8)
                                    .background(BrandTheme.rose.opacity(0.12))
                                    .clipShape(Capsule())
                            }
                            .padding(.top, 4)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 24)
                        .background(BrandTheme.bgSecondary)
                        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 20, style: .continuous)
                                .stroke(BrandTheme.border, lineWidth: 1)
                        )
                        .padding(.horizontal, 20)
                    }

                    // Preset Duration Buttons
                    VStack(alignment: .leading, spacing: 12) {
                        Text("SET TIMER DURATION")
                            .font(.system(size: 11, weight: .bold))
                            .tracking(1.2)
                            .foregroundStyle(BrandTheme.textSecondary)
                            .padding(.horizontal, 20)

                        VStack(spacing: 8) {
                            ForEach(presets, id: \.self) { minutes in
                                Button {
                                    timerManager.setTimer(minutes: minutes)
                                    dismiss()
                                } label: {
                                    HStack {
                                        Text("\(minutes) Minutes")
                                            .font(.system(size: 16, weight: .semibold))
                                            .foregroundStyle(Color.white)
                                        Spacer()
                                        Image(systemName: "chevron.right")
                                            .font(.system(size: 13, weight: .semibold))
                                            .foregroundStyle(BrandTheme.textMuted)
                                    }
                                    .padding(.horizontal, 18)
                                    .padding(.vertical, 16)
                                    .background(BrandTheme.bgSecondary)
                                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                                            .stroke(BrandTheme.border, lineWidth: 1)
                                    )
                                }
                                .buttonStyle(.plain)
                            }

                            // End of Episode Option
                            Button {
                                timerManager.setEndOfEpisode()
                                dismiss()
                            } label: {
                                HStack {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text("End of Current Episode")
                                            .font(.system(size: 16, weight: .semibold))
                                            .foregroundStyle(Color.white)
                                        Text("Pauses as soon as this episode finishes")
                                            .font(.system(size: 12))
                                            .foregroundStyle(BrandTheme.textSecondary)
                                    }
                                    Spacer()
                                    Image(systemName: "flag.checkered")
                                        .font(.system(size: 16, weight: .semibold))
                                        .foregroundStyle(audioManager.currentPalette.accent)
                                }
                                .padding(.horizontal, 18)
                                .padding(.vertical, 14)
                                .background(BrandTheme.bgSecondary)
                                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                                        .stroke(BrandTheme.border, lineWidth: 1)
                                    )
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(.horizontal, 20)
                    }

                    Spacer()

                    // Shake to Extend Tip
                    HStack(spacing: 10) {
                        Image(systemName: "iphone.gen3.radiowaves.left.and.right")
                            .font(.system(size: 20))
                            .foregroundStyle(audioManager.currentPalette.accent)

                        Text("Gently shake your iPhone at night to extend by 15 minutes without turning on your screen.")
                            .font(.system(size: 12))
                            .foregroundStyle(BrandTheme.textSecondary)
                    }
                    .padding(16)
                    .background(BrandTheme.bgCard)
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .padding(.horizontal, 20)
                    .padding(.bottom, 16)
                }
                .padding(.top, 16)
            }
            .navigationTitle("Sleep Timer")
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
