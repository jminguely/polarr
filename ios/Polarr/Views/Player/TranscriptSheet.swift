import SwiftUI

public struct TranscriptSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Bindable var transcriptService = TranscriptService.shared
    @Bindable var audioManager = AudioManager.shared

    @State private var searchText: String = ""

    public init() {}

    private var filteredLines: [TranscriptLine] {
        if searchText.trimmingCharacters(in: .whitespaces).isEmpty {
            return transcriptService.lines
        }
        return transcriptService.lines.filter {
            $0.text.localizedCaseInsensitiveContains(searchText)
        }
    }

    private var currentLineId: String? {
        let t = audioManager.currentTime
        return transcriptService.lines.first(where: { t >= $0.startSeconds && t <= $0.endSeconds })?.id
    }

    public var body: some View {
        NavigationStack {
            ZStack {
                BrandTheme.bgPrimary.ignoresSafeArea()

                VStack(spacing: 0) {
                    // Search Bar
                    HStack(spacing: 8) {
                        Image(systemName: "magnifyingglass")
                            .font(.system(size: 14))
                            .foregroundStyle(BrandTheme.textMuted)

                        TextField("Search transcript...", text: $searchText)
                            .font(.system(size: 14))
                            .foregroundStyle(Color.white)

                        if !searchText.isEmpty {
                            Button {
                                searchText = ""
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .font(.system(size: 14))
                                    .foregroundStyle(BrandTheme.textMuted)
                            }
                        }
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(BrandTheme.bgSecondary)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)

                    Divider().background(BrandTheme.border)

                    // Transcript List
                    if transcriptService.isLoading {
                        Spacer()
                        ProgressView().tint(audioManager.currentPalette.accent)
                        Spacer()
                    } else if filteredLines.isEmpty {
                        Spacer()
                        Text("No transcript lines found.")
                            .font(.system(size: 14))
                            .foregroundStyle(BrandTheme.textMuted)
                        Spacer()
                    } else {
                        ScrollViewReader { proxy in
                            ScrollView {
                                LazyVStack(alignment: .leading, spacing: 14) {
                                    ForEach(filteredLines) { line in
                                        let isCurrent = currentLineId == line.id

                                        Button {
                                            audioManager.seek(to: line.startSeconds)
                                        } label: {
                                            HStack(alignment: .top, spacing: 12) {
                                                Text(formatTimestamp(line.startSeconds))
                                                    .font(.system(size: 12, weight: .bold, design: .monospaced))
                                                    .foregroundStyle(isCurrent ? audioManager.currentPalette.accent : BrandTheme.textMuted)
                                                    .frame(width: 48, alignment: .leading)

                                                Text(line.text)
                                                    .font(.system(size: 15, weight: isCurrent ? .bold : .regular))
                                                    .foregroundStyle(isCurrent ? Color.white : BrandTheme.textSecondary)
                                                    .multilineTextAlignment(.leading)
                                                    .frame(maxWidth: .infinity, alignment: .leading)
                                            }
                                            .padding(.horizontal, 12)
                                            .padding(.vertical, 8)
                                            .background(isCurrent ? audioManager.currentPalette.accent.opacity(0.12) : Color.clear)
                                            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                                        }
                                        .buttonStyle(.plain)
                                        .id(line.id)
                                    }
                                }
                                .padding(.horizontal, 16)
                                .padding(.vertical, 16)
                            }
                            .onChange(of: currentLineId) { _, newId in
                                if let target = newId, searchText.isEmpty {
                                    withAnimation(.easeInOut(duration: 0.3)) {
                                        proxy.scrollTo(target, anchor: .center)
                                    }
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("Transcript")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                    .foregroundStyle(Color.white)
                }
            }
            .task {
                if let ep = audioManager.currentEpisode {
                    await transcriptService.loadTranscript(for: ep)
                }
            }
        }
    }

    private func formatTimestamp(_ secs: Double) -> String {
        let s = Int(secs)
        let m = s / 60
        return String(format: "%d:%02d", m, s % 60)
    }
}
