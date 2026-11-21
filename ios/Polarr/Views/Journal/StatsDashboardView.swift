import SwiftUI
import Charts

public struct StatsDashboardView: View {
    @Environment(\.dismiss) private var dismiss

    @State private var overview: APIStatsOverview?
    @State private var topPodcasts: [APITopPodcast] = []
    @State private var completionRates: [APICompletionRate] = []
    @State private var selectedPeriod: String = "all"
    @State private var isLoading: Bool = true
    @State private var errorMessage: String?

    public init() {}

    public var body: some View {
        NavigationStack {
            ZStack {
                BrandTheme.bgPrimary.ignoresSafeArea()

                if isLoading {
                    ProgressView("Analyzing your listening journal...")
                        .tint(BrandTheme.cyan)
                        .foregroundStyle(BrandTheme.textSecondary)
                } else if let error = errorMessage {
                    VStack(spacing: 12) {
                        Image(systemName: "exclamationmark.triangle")
                            .font(.system(size: 36))
                            .foregroundStyle(BrandTheme.amber)
                        Text(error)
                            .font(.system(size: 14))
                            .foregroundStyle(BrandTheme.textSecondary)
                        Button("Retry") { Task { await loadStats() } }
                            .foregroundStyle(BrandTheme.cyan)
                    }
                } else {
                    ScrollView {
                        VStack(spacing: 20) {
                            // 1. KPI Cards Grid
                            if let ov = overview {
                                kpiGrid(ov)
                            }

                            // 2. Top Podcasts Bar Chart
                            topPodcastsCard

                            // 3. Listening Completion Rates
                            completionRatesCard
                        }
                        .padding(.horizontal, 16)
                        .padding(.top, 16)
                        .padding(.bottom, 40)
                    }
                    .refreshable {
                        await loadStats()
                    }
                }
            }
            .navigationTitle("Listening Insights")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        dismiss()
                    }
                    .foregroundStyle(BrandTheme.cyan)
                }
            }
            .task {
                await loadStats()
            }
        }
    }

    // MARK: - KPI Grid
    private func kpiGrid(_ ov: APIStatsOverview) -> some View {
        LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
            statCard(
                title: "TOTAL LISTENED",
                value: String(format: "%.1f", ov.total_hours_listened),
                unit: "hours",
                icon: "headphones",
                color: BrandTheme.cyan
            )

            statCard(
                title: "EPISODES",
                value: "\(ov.total_episodes_listened)",
                unit: "completed",
                icon: "checkmark.circle.fill",
                color: BrandTheme.emerald
            )

            statCard(
                title: "SHOWS TRACKED",
                value: "\(ov.total_podcasts_tracked)",
                unit: "podcasts",
                icon: "waveform",
                color: BrandTheme.indigo
            )

            let completionPct: Int = {
                let total = ov.total_episodes_listened + ov.total_episodes_skipped + ov.total_episodes_abandoned
                return total > 0 ? Int((Double(ov.total_episodes_listened) / Double(total)) * 100) : 100
            }()
            statCard(
                title: "COMPLETION",
                value: "\(completionPct)%",
                unit: "\(ov.total_episodes_skipped) skipped",
                icon: "chart.pie.fill",
                color: BrandTheme.amber
            )
        }
    }

    private func statCard(title: String, value: String, unit: String, icon: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(title)
                    .font(.system(size: 10, weight: .bold))
                    .tracking(1.1)
                    .foregroundStyle(BrandTheme.textMuted)
                Spacer()
                Image(systemName: icon)
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(color)
            }

            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(value)
                    .font(.system(size: 24, weight: .bold, design: .rounded))
                    .foregroundStyle(BrandTheme.textPrimary)
                Text(unit)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(BrandTheme.textSecondary)
            }
        }
        .padding(14)
        .polarrCard(cornerRadius: 16)
    }

    // MARK: - Top Podcasts Card
    private var topPodcastsCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("TOP PODCASTS")
                        .font(.system(size: 11, weight: .bold))
                        .tracking(1.2)
                        .foregroundStyle(BrandTheme.cyan)
                    Text("By hours listened")
                        .font(.system(size: 13))
                        .foregroundStyle(BrandTheme.textSecondary)
                }

                Spacer()

                // Period Picker
                Picker("Period", selection: $selectedPeriod) {
                    Text("All Time").tag("all")
                    Text("Year").tag("year")
                    Text("Month").tag("month")
                }
                .pickerStyle(.menu)
                .tint(BrandTheme.cyan)
                .onChange(of: selectedPeriod) { _, newPeriod in
                    Task { await loadTopPodcasts(period: newPeriod) }
                }
            }

            if topPodcasts.isEmpty {
                Text("No listening activity recorded for this period.")
                    .font(.system(size: 13))
                    .foregroundStyle(BrandTheme.textMuted)
                    .padding(.vertical, 16)
            } else {
                Chart(topPodcasts.prefix(6)) { item in
                    BarMark(
                        x: .value("Hours", item.hours_listened),
                        y: .value("Podcast", item.title.count > 22 ? String(item.title.prefix(20)) + "…" : item.title)
                    )
                    .foregroundStyle(BrandTheme.brandGradient)
                    .cornerRadius(5)
                    .annotation(position: .trailing) {
                        Text(String(format: "%.1fh", item.hours_listened))
                            .font(.system(size: 10, weight: .semibold, design: .monospaced))
                            .foregroundStyle(BrandTheme.textSecondary)
                    }
                }
                .chartYAxis {
                    AxisMarks { value in
                        AxisValueLabel {
                            if let str = value.as(String.self) {
                                Text(str)
                                    .font(.system(size: 11, weight: .medium))
                                    .foregroundStyle(BrandTheme.textPrimary)
                            }
                        }
                    }
                }
                .chartXAxis {
                    AxisMarks(position: .bottom)
                }
                .frame(height: CGFloat(max(180, min(6, topPodcasts.count) * 36)))
            }
        }
        .padding(16)
        .polarrCard(cornerRadius: 18)
    }

    // MARK: - Completion Rates Card
    private var completionRatesCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 2) {
                Text("SUBSCRIPTION COMPLETION")
                    .font(.system(size: 11, weight: .bold))
                    .tracking(1.2)
                    .foregroundStyle(BrandTheme.cyan)
                Text("How caught up you are on subscribed shows")
                    .font(.system(size: 13))
                    .foregroundStyle(BrandTheme.textSecondary)
            }

            if completionRates.isEmpty {
                Text("No active subscriptions.")
                    .font(.system(size: 13))
                    .foregroundStyle(BrandTheme.textMuted)
            } else {
                VStack(spacing: 12) {
                    ForEach(completionRates.prefix(8)) { sub in
                        VStack(spacing: 6) {
                            HStack {
                                Text(sub.title)
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundStyle(BrandTheme.textPrimary)
                                    .lineLimit(1)

                                Spacer()

                                Text("\(sub.listened_episodes)/\(sub.total_feed_episodes) (\(Int(sub.completion_rate_pct))%)")
                                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                                    .foregroundStyle(BrandTheme.textSecondary)
                            }

                            GeometryReader { geo in
                                ZStack(alignment: .leading) {
                                    Capsule()
                                        .fill(BrandTheme.bgSecondary)
                                        .frame(height: 6)

                                    Capsule()
                                        .fill(sub.completion_rate_pct >= 80 ? BrandTheme.emerald : BrandTheme.cyan)
                                        .frame(width: max(6, geo.size.width * CGFloat(sub.completion_rate_pct / 100.0)), height: 6)
                                }
                            }
                            .frame(height: 6)
                        }
                    }
                }
            }
        }
        .padding(16)
        .polarrCard(cornerRadius: 18)
    }

    // MARK: - Networking
    private func loadStats() async {
        isLoading = true
        defer { isLoading = false }
        do {
            async let fetchOv = APIClient.shared.fetchStatsOverview()
            async let fetchTop = APIClient.shared.fetchTopPodcasts(period: selectedPeriod, limit: 10)
            async let fetchComp = APIClient.shared.fetchCompletionRates()

            let (ov, top, comp) = try await (fetchOv, fetchTop, fetchComp)
            overview = ov
            topPodcasts = top
            completionRates = comp
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func loadTopPodcasts(period: String) async {
        do {
            topPodcasts = try await APIClient.shared.fetchTopPodcasts(period: period, limit: 10)
        } catch {
            print("Failed to fetch top podcasts: \(error)")
        }
    }
}
