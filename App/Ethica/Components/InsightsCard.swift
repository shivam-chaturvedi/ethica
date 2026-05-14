//
//  InsightsCard.swift
//  Ethica
//
//  Behavioral insights and analytics card for scan history
//

import SwiftUI

struct InsightsCard: View {
    let scans: [ScanHistory]

    var body: some View {
        GlassCard.primary {
            VStack(alignment: .leading, spacing: Spacing.lg) {
                // Header
                HStack {
                    Image(systemName: "brain.head.profile")
                        .font(.system(size: 24))
                        .foregroundStyle(Theme.gradientHero)

                    Text("Your Insights")
                        .textStyleH3()

                    Spacer()
                }

                if scans.isEmpty {
                    emptyState
                } else {
                    insightsContent
                }
            }
        }
        .padding(.horizontal, Spacing.screenHorizontal)
    }

    // MARK: - Insights Content

    private var insightsContent: some View {
        VStack(spacing: Spacing.md) {
            // This week's summary
            weekSummaryInsight

            Divider()
                .background(Theme.textMuted.opacity(0.3))

            // Behavioral insights (2-3 personalized messages)
            ForEach(generateInsights(), id: \.text) { insight in
                insightRow(insight)
            }
        }
    }

    private var weekSummaryInsight: some View {
        let thisWeekScans = scansThisWeek()
        let safeCount = thisWeekScans.filter { $0.isSafe }.count
        let percentage = thisWeekScans.isEmpty ? 0 : Double(safeCount) / Double(thisWeekScans.count) * 100

        return VStack(alignment: .leading, spacing: Spacing.sm) {
            HStack {
                Text("This Week")
                    .textStyleH4()
                Spacer()
                Text("\(thisWeekScans.count) scans")
                    .textStyleCaption()
                    .foregroundColor(Theme.textSecondary)
            }

            HStack(spacing: Spacing.md) {
                // Safe percentage circle
                ZStack {
                    Circle()
                        .stroke(Theme.textMuted.opacity(0.2), lineWidth: 6)
                        .frame(width: 60, height: 60)

                    Circle()
                        .trim(from: 0, to: percentage / 100.0)
                        .stroke(Theme.success, style: StrokeStyle(lineWidth: 6, lineCap: .round))
                        .frame(width: 60, height: 60)
                        .rotationEffect(.degrees(-90))
                        .animation(AnimationSystem.springSmooth, value: percentage)

                    VStack(spacing: 2) {
                        Text("\(Int(percentage))%")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundColor(Theme.success)
                    }
                }

                VStack(alignment: .leading, spacing: Spacing.xs) {
                    Text("\(safeCount)/\(thisWeekScans.count) Safe Products")
                        .textStyleBody()
                        .foregroundColor(Theme.textPrimary)

                    Text(trendMessage(for: percentage))
                        .textStyleCaption()
                        .foregroundColor(Theme.textSecondary)
                }

                Spacer()
            }
        }
    }

    @ViewBuilder
    private func insightRow(_ insight: Insight) -> some View {
        HStack(alignment: .top, spacing: Spacing.sm) {
            Image(systemName: insight.icon)
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(insight.color)
                .frame(width: 24, height: 24)

            Text(insight.text)
                .textStyleBody()
                .foregroundColor(Theme.textPrimary)
                .fixedSize(horizontal: false, vertical: true)

            Spacer()
        }
        .padding(.vertical, Spacing.xs)
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: Spacing.md) {
            Image(systemName: "chart.xyaxis.line")
                .font(.system(size: 48))
                .foregroundColor(Theme.textMuted)

            Text("Start Scanning Products")
                .textStyleH4()

            Text("Your personalized insights will appear here")
                .textStyleBody()
                .foregroundColor(Theme.textSecondary)
                .multilineTextAlignment(.center)
        }
        .padding(.vertical, Spacing.lg)
        .frame(maxWidth: .infinity)
    }

    // MARK: - Insight Generation

    struct Insight: Hashable {
        let text: String
        let icon: String
        let color: Color
    }

    private func generateInsights() -> [Insight] {
        var insights: [Insight] = []
        let thisWeekScans = scansThisWeek()
        let lastWeekScans = scansLastWeek()

        // Insight 1: Avoidance behavior
        let avoidsThisWeek = thisWeekScans.filter { $0.purchaseDecision == .avoided }.count
        if avoidsThisWeek > 0 {
            insights.append(Insight(
                text: "You avoided \(avoidsThisWeek) product\(avoidsThisWeek == 1 ? "" : "s") with violations this week!",
                icon: "shield.checkered",
                color: Theme.success
            ))
        }

        // Insight 2: Environmental impact
        let co2Saved = thisWeekScans
            .filter { $0.purchaseDecision == .avoided || $0.purchaseDecision == .alternative }
            .reduce(0.0) { sum, scan in
                if scan.purchaseDecision == .avoided {
                    return sum + scan.co2Emissions
                } else if let altCO2 = scan.alternativeCO2 {
                    return sum + max(0, scan.co2Emissions - altCO2)
                }
                return sum
            }

        if co2Saved > 0.5 {
            insights.append(Insight(
                text: String(format: "You saved %.1fkg of CO₂ by choosing better alternatives!", co2Saved),
                icon: "leaf.fill",
                color: Theme.success
            ))
        }

        // Insight 3: Health trend
        if !thisWeekScans.isEmpty && !lastWeekScans.isEmpty {
            let avgHealthThisWeek = thisWeekScans.map { $0.healthScore }.reduce(0, +) / Double(thisWeekScans.count)
            let avgHealthLastWeek = lastWeekScans.map { $0.healthScore }.reduce(0, +) / Double(lastWeekScans.count)
            let improvement = avgHealthThisWeek - avgHealthLastWeek

            if improvement > 0.5 {
                let percentage = Int((improvement / avgHealthLastWeek) * 100)
                insights.append(Insight(
                    text: "Your average health score improved by \(percentage)% compared to last week!",
                    icon: "arrow.up.circle.fill",
                    color: Theme.success
                ))
            } else if improvement < -0.5 {
                insights.append(Insight(
                    text: "Consider choosing healthier options this week to maintain your progress.",
                    icon: "info.circle",
                    color: Theme.warning
                ))
            }
        }

        // Insight 4: Streak achievement
        if scans.count >= 7 {
            let last7Days = Array(scans.prefix(7))
            let allSafe = last7Days.allSatisfy { $0.isSafe }
            if allSafe {
                insights.append(Insight(
                    text: "Perfect streak! All products scanned in the last 7 days were safe!",
                    icon: "flame.fill",
                    color: Theme.accent
                ))
            }
        }

        // Insight 5: Alternative adoption
        let alternativesChosen = thisWeekScans.filter { $0.purchaseDecision == .alternative }.count
        if alternativesChosen >= 3 {
            insights.append(Insight(
                text: "You chose \(alternativesChosen) better alternative\(alternativesChosen == 1 ? "" : "s") this week!",
                icon: "arrow.triangle.swap",
                color: Theme.accent
            ))
        }

        // Return top 3 insights
        return Array(insights.prefix(3))
    }

    // MARK: - Helper Functions

    private func scansThisWeek() -> [ScanHistory] {
        let weekAgo = Calendar.current.date(byAdding: .day, value: -7, to: Date()) ?? Date()
        return scans.filter { $0.timestamp >= weekAgo }
    }

    private func scansLastWeek() -> [ScanHistory] {
        let twoWeeksAgo = Calendar.current.date(byAdding: .day, value: -14, to: Date()) ?? Date()
        let weekAgo = Calendar.current.date(byAdding: .day, value: -7, to: Date()) ?? Date()
        return scans.filter { $0.timestamp >= twoWeeksAgo && $0.timestamp < weekAgo }
    }

    private func trendMessage(for percentage: Double) -> String {
        if percentage >= 90 {
            return "Excellent! Keep it up 🌟"
        } else if percentage >= 70 {
            return "Great progress! 💪"
        } else if percentage >= 50 {
            return "You're making good choices"
        } else {
            return "Room for improvement"
        }
    }
}

// MARK: - Preview

#Preview("With Scans") {
    InsightsCard(scans: [
        ScanHistory(
            productName: "Organic Almond Milk",
            barcode: nil,
            sourceType: "ocr",
            isSafe: true,
            violationsCount: 0,
            violations: [],
            co2Emissions: 0.5,
            waterUsage: 150,
            animalImpact: "Low",
            healthScore: 8.5,
            concernsCount: 0,
            purchaseDecision: .purchased
        ),
        ScanHistory(
            productName: "Beef Jerky",
            barcode: nil,
            sourceType: "ocr",
            isSafe: false,
            violationsCount: 2,
            violations: ["Contains animal products", "High sodium"],
            co2Emissions: 15.0,
            waterUsage: 8000,
            animalImpact: "High",
            healthScore: 3.5,
            concernsCount: 3,
            purchaseDecision: .avoided
        )
    ])
    .padding(.vertical, Spacing.lg)
    .background(Theme.backgroundPrimary)
    .preferredColorScheme(.dark)
}

#Preview("Empty") {
    InsightsCard(scans: [])
        .padding(.vertical, Spacing.lg)
        .background(Theme.backgroundPrimary)
        .preferredColorScheme(.dark)
}
