//
//  DashboardView-Modern.swift
//  Ethica
//
//  Modernized dashboard with premium design system
//  Replace DashboardView.swift with this file when ready
//

import SwiftUI

struct DashboardView: View {
    @State private var stats: ImpactStats?
    @State private var achievements: [Achievement] = []
    @State private var insights: [String] = []
    @State private var weeklyComparison: (thisWeek: ImpactStats, lastWeek: ImpactStats)?
    @State private var refreshing = false
    @State private var isStreakAnimating = false

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.backgroundPrimary
                    .ignoresSafeArea()

                if let stats = stats {
                    ScrollView {
                        LazyVStack(spacing: Spacing.lg) {
                            // Hero Section with score
                            heroSection(stats)

                            // Nudge to record purchase decisions
                            if stats.productsPurchased == 0 && stats.productsAvoided == 0 && stats.totalScans > 0 {
                                HStack(spacing: Spacing.sm) {
                                    Image(systemName: "info.circle.fill")
                                        .foregroundColor(Theme.info)
                                    Text("Record purchase decisions on scanned products to track your full impact")
                                        .textStyleBodySmall()
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                }
                                .padding(Spacing.md)
                                .background(
                                    RoundedRectangle(cornerRadius: Spacing.radiusSM)
                                        .fill(Theme.info.opacity(0.1))
                                )
                            }

                            // Quick Stats Grid
                            quickStatsGrid(stats)

                            // Environmental Impact
                            environmentalImpact(stats)

                            // Weekly Comparison
                            if let comparison = weeklyComparison {
                                weeklyComparisonSection(comparison)
                                }

                            // Achievements
                            if !achievements.isEmpty {
                                achievementsSection
                                }

                            // Insights
                            if !insights.isEmpty {
                                insightsSection
                                }
                        }
                        .padding(.horizontal, Spacing.screenHorizontal)
                        .padding(.vertical, Spacing.screenVertical)
                    }
                    .refreshable {
                        await refreshData()
                    }
                } else {
                    EmptyState(
                        icon: "chart.bar.fill",
                        title: "No Impact Data Yet",
                        message: "Start scanning products to see your environmental and health impact",
                        actionTitle: "Scan Product",
                        action: {
                            NotificationCenter.default.post(name: Notification.Name("switchToTab"), object: 0)
                        }
                    )
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel("No impact data yet. Start scanning products to see your environmental and health impact.")
                }
            }
            .navigationTitle("Your Impact")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: {
                        Task { await refreshData() }
                    }) {
                        Image(systemName: "arrow.clockwise")
                            .symbolEffect(.pulse, isActive: refreshing)
                    }
                    .accessibilityLabel(refreshing ? "Refreshing data" : "Refresh data")
                    .accessibilityHint("Double tap to reload your impact statistics")
                }
            }
        }
        .task { await loadDataAsync() }
        .onReceive(NotificationCenter.default.publisher(for: UIScene.willEnterForegroundNotification)) { _ in
            Task { await loadDataAsync() }
        }
    }

    // MARK: - Hero Section

    @ViewBuilder
    private func heroSection(_ stats: ImpactStats) -> some View {
        GlassCard.primary {
            VStack(spacing: Spacing.lg) {
                HStack {
                    VStack(alignment: .leading, spacing: Spacing.xs) {
                        Text("Total Impact")
                            .textStyleH2()
                        Text("Since \(stats.startDate.formatted(date: .abbreviated, time: .omitted))")
                            .textStyleCaption()
                    }

                    Spacer()

                    VStack(alignment: .trailing, spacing: Spacing.xs) {
                        Text("\(stats.totalScans)")
                            .font(Typography.numberMedium)
                            .foregroundColor(Theme.primary)
                        Text("scans")
                            .textStyleCaption()
                    }
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel("Total Impact since \(stats.startDate.formatted(date: .abbreviated, time: .omitted)), \(stats.totalScans) scans")

                // Score circle
                ScoreCircle(
                    score: stats.averageHealthScore,
                    size: .large,
                    showLabel: true,
                    label: "Average Health Score"
                )
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Average Health Score: \(Int(stats.averageHealthScore)) out of 100")

                // Healthy choices ratio bar
                let choiceRatio = stats.totalScans > 0 ? Double(stats.productsPurchased) / Double(max(stats.productsPurchased + stats.productsAvoided, 1)) : 0
                if stats.productsPurchased + stats.productsAvoided > 0 {
                    VStack(alignment: .leading, spacing: Spacing.xs) {
                        HStack {
                            Text("Healthy choices")
                                .textStyleCaption()
                            Spacer()
                            Text("\(Int(choiceRatio * 100))%")
                                .textStyleCaption()
                                .foregroundColor(Theme.success)
                        }
                        ProgressBar(progress: choiceRatio, height: 8, foregroundColor: Theme.success)
                    }
                }

                // Streak with animated flame
                if stats.currentStreak > 0 {
                    HStack {
                        Image(systemName: "flame.fill")
                            .font(.system(size: 20))
                            .foregroundColor(Theme.warning)
                            .symbolEffect(.pulse, isActive: isStreakAnimating)
                            .onAppear { isStreakAnimating = true }
                        Text("\(stats.currentStreak)-day streak!")
                            .textStyleH4(color: Theme.warning)
                        Spacer()
                        Text("Best: \(stats.longestStreak) days")
                            .textStyleCaption()
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel("Current streak: \(stats.currentStreak) days. Best streak: \(stats.longestStreak) days")
                }
            }
        }
    }

    // MARK: - Quick Stats Grid

    @ViewBuilder
    private func quickStatsGrid(_ stats: ImpactStats) -> some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: Spacing.md) {
            StatisticCard(
                title: "Avoided",
                value: "\(stats.productsAvoided)",
                icon: "xmark.circle.fill",
                variant: .error,
                size: .compact
            )
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Products avoided: \(stats.productsAvoided)")

            StatisticCard(
                title: "Purchased",
                value: "\(stats.productsPurchased)",
                icon: "checkmark.circle.fill",
                variant: .success,
                size: .compact
            )
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Products purchased: \(stats.productsPurchased)")

            StatisticCard(
                title: "Alternatives",
                value: "\(stats.alternativesChosen)",
                icon: "arrow.triangle.swap",
                variant: .warning,
                size: .compact
            )
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Alternatives chosen: \(stats.alternativesChosen)")

            StatisticCard(
                title: "Health Improvements",
                value: "\(stats.healthImprovements)",
                icon: "heart.fill",
                variant: .primary,
                size: .compact
            )
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Health improvements: \(stats.healthImprovements)")
        }
    }

    // MARK: - Environmental Impact

    @State private var showEnvRipple = false

    @ViewBuilder
    private func environmentalImpact(_ stats: ImpactStats) -> some View {
        GlassCard.primary {
            ZStack {
                // Subtle leaf particles
                LeafParticleEffect(count: 4)
                    .opacity(0.4)

                VStack(alignment: .leading, spacing: Spacing.lg) {
                    Text("Environmental Impact")
                        .textStyleH2()
                        .accessibilityAddTraits(.isHeader)

                    VStack(spacing: Spacing.md) {
                        impactRow(icon: "🌍", label: "CO₂ Saved", value: String(format: "%.1f kg", stats.totalCO2Saved), numericValue: stats.totalCO2Saved, unit: "kg", color: Theme.success)
                        impactRow(icon: "👤", label: "Your CO₂ Footprint", value: String(format: "%.1f kg", stats.yourCO2Footprint), numericValue: stats.yourCO2Footprint, unit: "kg", color: Theme.accent)
                        impactRow(icon: "💧", label: "Water Saved", value: "\(Int(stats.totalWaterSaved)) L", numericValue: stats.totalWaterSaved, unit: "L", color: Theme.info)
                        impactRow(icon: "🐮", label: "Est. Animals Spared", value: "\(stats.animalsSpared)", numericValue: Double(stats.animalsSpared), color: Theme.warning)
                    }
                }
            }
        }
        .background {
            ImpactRipple(trigger: showEnvRipple, color: Theme.primary)
                .frame(width: 200, height: 200)
        }
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                showEnvRipple = true
            }
        }
    }

    private func impactRow(icon: String, label: String, value: String, numericValue: Double? = nil, unit: String = "", color: Color) -> some View {
        HStack {
            Text(icon)
                .font(.system(size: 24))

            Text(label)
                .textStyleBody()

            Spacer()

            if let num = numericValue {
                HStack(alignment: .firstTextBaseline, spacing: 3) {
                    AnimatedNumber(value: num, formatter: {
                        let f = NumberFormatter()
                        f.numberStyle = .decimal
                        f.maximumFractionDigits = value.contains(".") ? 1 : 0
                        return f
                    }())
                        .font(Typography.h4)
                        .foregroundColor(color)
                    if !unit.isEmpty {
                        Text(unit)
                            .textStyleCaption()
                            .foregroundColor(color.opacity(0.7))
                    }
                }
            } else {
                Text(value)
                    .font(Typography.h4)
                    .foregroundColor(color)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(label): \(value)")
    }

    // MARK: - Weekly Comparison

    @ViewBuilder
    private func weeklyComparisonSection(_ comparison: (thisWeek: ImpactStats, lastWeek: ImpactStats)) -> some View {
        GlassCard.secondary {
            VStack(alignment: .leading, spacing: Spacing.lg) {
                Text("Weekly Progress")
                    .textStyleH2()
                    .accessibilityAddTraits(.isHeader)

                HStack(spacing: Spacing.lg) {
                    VStack(alignment: .leading, spacing: Spacing.sm) {
                        Text("This Week")
                            .textStyleCaption()
                        Text("\(comparison.thisWeek.totalScans)")
                            .font(Typography.h2)
                            .foregroundColor(Theme.primary)
                        Text("scans")
                            .textStyleCaption()
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel("This week: \(comparison.thisWeek.totalScans) scans")

                    Divider()

                    VStack(alignment: .leading, spacing: Spacing.sm) {
                        Text("Last Week")
                            .textStyleCaption()
                        Text("\(comparison.lastWeek.totalScans)")
                            .font(Typography.h2)
                            .foregroundColor(Theme.textSecondary)
                        Text("scans")
                            .textStyleCaption()
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel("Last week: \(comparison.lastWeek.totalScans) scans")

                    if comparison.thisWeek.totalScans > comparison.lastWeek.totalScans {
                        StatusBadge("📈 Up", variant: .success, size: .small)
                            .accessibilityLabel("Trending up from last week")
                    } else if comparison.thisWeek.totalScans < comparison.lastWeek.totalScans {
                        StatusBadge("📉 Down", variant: .error, size: .small)
                            .accessibilityLabel("Trending down from last week")
                    }
                }
            }
        }
    }

    // MARK: - Achievements

    @ViewBuilder
    private var achievementsSection: some View {
        GlassCard.accent {
            VStack(alignment: .leading, spacing: Spacing.md) {
                HStack {
                    Text("Achievements")
                        .textStyleH2()
                        .accessibilityAddTraits(.isHeader)
                    Spacer()
                    StatusBadge("\(achievements.count)", variant: .accent, size: .small)
                        .accessibilityLabel("\(achievements.count) achievements earned")
                }

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: Spacing.md) {
                        ForEach(achievements, id: \.title) { achievement in
                            achievementCard(achievement)
                        }
                    }
                }
                .accessibilityLabel("Achievements list")
            }
        }
    }

    private func achievementCard(_ achievement: Achievement) -> some View {
        VStack(spacing: Spacing.sm) {
            Text(achievement.icon)
                .font(.system(size: 40))

            Text(achievement.title)
                .textStyleBodySmall()
                .multilineTextAlignment(.center)
        }
        .frame(width: 100)
        .padding(Spacing.md)
        .background(
            RoundedRectangle(cornerRadius: Spacing.radiusMD)
                .fill(Color.white.opacity(0.05))
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Achievement: \(achievement.title)")
    }

    // MARK: - Insights

    @ViewBuilder
    private var insightsSection: some View {
        GlassCard.secondary {
            VStack(alignment: .leading, spacing: Spacing.md) {
                Text("Insights")
                    .textStyleH2()
                    .accessibilityAddTraits(.isHeader)

                ForEach(insights, id: \.self) { insight in
                    HStack(alignment: .top, spacing: Spacing.sm) {
                        Image(systemName: "lightbulb.fill")
                            .foregroundColor(Theme.warning)
                        Text(insight)
                            .textStyleBody()
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel("Insight: \(insight)")
                }
            }
        }
    }

    // MARK: - Data Loading

    private func loadDataAsync() async {
        let (s, a, i, w) = await Task.detached(priority: .userInitiated) {
            let s = ImpactCalculator.shared.calculateImpactStats()
            let a = ImpactCalculator.shared.checkAchievements()
            let i = ImpactCalculator.shared.generateInsights()
            let w = ImpactCalculator.shared.getWeeklyComparison()
            return (s, a, i, w)
        }.value
        self.stats = s
        self.achievements = a
        self.insights = i
        self.weeklyComparison = w
    }

    private func refreshData() async {
        refreshing = true
        await loadDataAsync()
        refreshing = false
    }
}

// NOTE: To use this modernized version, replace the contents of DashboardView.swift
// with this file, then rename struct to "DashboardView"
