//
//  ImpactDashboardView.swift
//  Ethica
//
//  Impact Dashboard showing user's cumulative environmental impact
//

import SwiftUI
import Charts

struct ImpactDashboardView: View {
    @State private var userImpact: UserImpact?
    @State private var isLoading = true
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.backgroundPrimary.ignoresSafeArea()

                if isLoading {
                    ProgressView("Loading your impact...")
                        .foregroundColor(.white)
                        .breathingAnimation()
                        .accessibilityLabel("Loading your impact data")
                } else if let error = errorMessage {
                    VStack(spacing: 16) {
                        Image(systemName: "exclamationmark.triangle")
                            .font(.system(size: 50))
                            .foregroundColor(Theme.warning)
                            .accessibilityHidden(true)
                        Text("Unable to load impact data")
                            .font(.headline)
                            .foregroundColor(.white)
                            .accessibilityAddTraits(.isHeader)
                        Text(error)
                            .font(.subheadline)
                            .foregroundColor(Theme.textMuted)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal)

                        Button(action: loadImpactData) {
                            Text("Retry")
                                .fontWeight(.semibold)
                                .foregroundColor(.white)
                                .padding(.horizontal, 30)
                                .padding(.vertical, 12)
                                .background(Theme.primary)
                                .clipShape(RoundedRectangle(cornerRadius: 25))
                        }
                        .accessibilityLabel("Retry")
                        .accessibilityHint("Attempts to load impact data again")
                    }
                } else if let impact = userImpact {
                    ScrollView {
                        VStack(spacing: 24) {
                            // Header with total impact
                            impactHeaderCard(impact: impact)
                                .slideInFromBottom(delay: 0.1)

                            // Current month summary
                            currentMonthCard(impact: impact)
                                .slideInFromBottom(delay: 0.2)

                            // Real-world equivalents
                            equivalentsCard(impact: impact)
                                .slideInFromBottom(delay: 0.3)

                            // Weekly trend chart
                            if !impact.weeklyTrend.isEmpty {
                                weeklyTrendCard(impact: impact)
                                    .slideInFromBottom(delay: 0.4)
                            }

                            // Monthly trend chart
                            if !impact.monthlyTrend.isEmpty {
                                monthlyTrendCard(impact: impact)
                                    .slideInFromBottom(delay: 0.5)
                            }

                            // Milestones
                            if !impact.milestones.isEmpty {
                                milestonesCard(impact: impact)
                                    .slideInFromBottom(delay: 0.6)
                            }

                            // Stats grid
                            statsGrid(impact: impact)
                                .slideInFromBottom(delay: 0.7)
                        }
                        .padding()
                        .padding(.bottom, 30)
                    }
                } else {
                    emptyStateView()
                }
            }
            .navigationTitle("Your Impact")
            .navigationBarTitleDisplayMode(.large)
        }
        .onAppear {
            loadImpactData()
        }
    }

    // MARK: - Impact Header Card

    @ViewBuilder
    func impactHeaderCard(impact: UserImpact) -> some View {
        VStack(spacing: 20) {
            // Title
            HStack {
                Image(systemName: "leaf.circle.fill")
                    .font(.system(size: 24))
                    .foregroundColor(Theme.success)
                    .accessibilityHidden(true)
                Text("Total Environmental Impact")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundColor(.white)
                    .accessibilityAddTraits(.isHeader)
                Spacer()
            }

            // CO2 Saved
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Image(systemName: "cloud.fill")
                        .foregroundColor(Theme.primary)
                    Text("CO₂ Emissions Saved")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(Theme.textSecondary)
                }

                Text(impact.co2SavedEquivalent)
                    .font(.system(size: 36, weight: .bold))
                    .foregroundColor(.white)
                    .scaleIn(delay: 0.2)

                Text(impact.co2Comparison)
                    .font(.system(size: 12))
                    .foregroundColor(Theme.textSecondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding()
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Theme.primary.opacity(0.1))
            )
            .accessibilityElement(children: .combine)
            .accessibilityLabel("CO2 Emissions Saved: \(impact.co2SavedEquivalent). \(impact.co2Comparison)")

            // Water Saved
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Image(systemName: "drop.fill")
                        .foregroundColor(Theme.info)
                    Text("Water Usage Saved")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(Theme.textSecondary)
                }

                Text(impact.waterSavedEquivalent)
                    .font(.system(size: 36, weight: .bold))
                    .foregroundColor(.white)
                    .scaleIn(delay: 0.3)

                Text(impact.waterComparison)
                    .font(.system(size: 12))
                    .foregroundColor(Theme.textSecondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding()
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Theme.info.opacity(0.1))
            )
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Water Usage Saved: \(impact.waterSavedEquivalent). \(impact.waterComparison)")
        }
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Theme.surfaceBase)
                .shadow(color: Color.black.opacity(0.3), radius: 10)
                .accessibilityHidden(true)
        )
    }

    // MARK: - Current Month Card

    @ViewBuilder
    func currentMonthCard(impact: UserImpact) -> some View {
        VStack(spacing: 16) {
            HStack {
                Image(systemName: "calendar")
                    .foregroundColor(Theme.primary)
                    .accessibilityHidden(true)
                Text("This Month")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundColor(.white)
                    .accessibilityAddTraits(.isHeader)
                Spacer()
            }

            HStack(spacing: 20) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("CO₂ Saved")
                        .font(.system(size: 12))
                        .foregroundColor(Theme.textSecondary)
                    Text(String(format: "%.1f kg", impact.currentMonthCO2))
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundColor(Theme.success)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityElement(children: .combine)
                .accessibilityLabel("CO2 saved this month: \(String(format: "%.1f", impact.currentMonthCO2)) kilograms")

                Divider()
                    .background(Theme.textSecondary.opacity(0.3))
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 4) {
                    Text("Water Saved")
                        .font(.system(size: 12))
                        .foregroundColor(Theme.textSecondary)
                    Text(String(format: "%.0f L", impact.currentMonthWater))
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundColor(Theme.info)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityElement(children: .combine)
                .accessibilityLabel("Water saved this month: \(String(format: "%.0f", impact.currentMonthWater)) liters")
            }

            if impact.streakDays > 0 {
                HStack {
                    Image(systemName: "flame.fill")
                        .foregroundColor(Theme.warning)
                        .accessibilityHidden(true)
                    Text("\(impact.streakDays) day streak")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.white)
                    Spacer()
                    Text("Keep it up!")
                        .font(.system(size: 12))
                        .foregroundColor(Theme.textSecondary)
                }
                .padding()
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Theme.warning.opacity(0.1))
                )
                .accessibilityElement(children: .combine)
                .accessibilityLabel("\(impact.streakDays) day streak. Keep it up!")
            }
        }
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Theme.surfaceBase)
                .shadow(color: Color.black.opacity(0.3), radius: 10)
                .accessibilityHidden(true)
        )
    }

    // MARK: - Equivalents Card

    @ViewBuilder
    func equivalentsCard(impact: UserImpact) -> some View {
        VStack(spacing: 16) {
            HStack {
                Image(systemName: "chart.bar.fill")
                    .foregroundColor(Theme.primary)
                    .accessibilityHidden(true)
                Text("Real-World Impact")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundColor(.white)
                    .accessibilityAddTraits(.isHeader)
                Spacer()
            }

            VStack(spacing: 12) {
                equivalentRow(
                    icon: "car.fill",
                    color: Theme.error,
                    title: "Driving Avoided",
                    value: impact.co2Comparison
                )

                equivalentRow(
                    icon: "shower.fill",
                    color: Theme.info,
                    title: "Showers Worth",
                    value: impact.waterComparison
                )

                equivalentRow(
                    icon: "tree.fill",
                    color: Theme.success,
                    title: "Products Analyzed",
                    value: "\(impact.totalProductsScanned) scanned"
                )

                equivalentRow(
                    icon: "checkmark.circle.fill",
                    color: Theme.success,
                    title: "Better Choices",
                    value: "\(impact.healthierChoices) healthier options"
                )
            }
        }
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Theme.surfaceBase)
                .shadow(color: Color.black.opacity(0.3), radius: 10)
                .accessibilityHidden(true)
        )
    }

    @ViewBuilder
    func equivalentRow(icon: String, color: Color, title: String, value: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 20))
                .foregroundColor(color)
                .frame(width: 30)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 13))
                    .foregroundColor(Theme.textSecondary)
                Text(value)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(.white)
            }

            Spacer()
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(color.opacity(0.08))
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title): \(value)")
    }

    // MARK: - Weekly Trend Card

    @ViewBuilder
    func weeklyTrendCard(impact: UserImpact) -> some View {
        VStack(spacing: 16) {
            HStack {
                Image(systemName: "chart.line.uptrend.xyaxis")
                    .foregroundColor(Theme.primary)
                    .accessibilityHidden(true)
                Text("Last 7 Days")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundColor(.white)
                    .accessibilityAddTraits(.isHeader)
                Spacer()
            }

            if #available(iOS 16.0, *) {
                Chart {
                    ForEach(impact.weeklyTrend) { day in
                        BarMark(
                            x: .value("Date", formatDate(day.date)),
                            y: .value("CO₂", day.co2Saved)
                        )
                        .foregroundStyle(Theme.success.gradient)
                    }
                }
                .frame(height: 200)
                .chartXAxis {
                    AxisMarks(values: .automatic) { _ in
                        AxisValueLabel()
                            .foregroundStyle(Theme.textSecondary)
                    }
                }
                .chartYAxis {
                    AxisMarks(position: .leading) { _ in
                        AxisValueLabel()
                            .foregroundStyle(Theme.textSecondary)
                    }
                }
                .accessibilityLabel("Bar chart showing daily CO2 savings over the last 7 days")
                .accessibilityHint("Shows CO2 saved in kilograms for each day of the past week")
            } else {
                // Fallback for iOS 15
                Text("Weekly trend chart available on iOS 16+")
                    .font(.caption)
                    .foregroundColor(Theme.textSecondary)
                    .frame(height: 200)
            }

            Text("Daily CO₂ savings (kg)")
                .font(.caption)
                .foregroundColor(Theme.textSecondary)
                .accessibilityLabel("Daily CO2 savings in kilograms")
        }
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Theme.surfaceBase)
                .shadow(color: Color.black.opacity(0.3), radius: 10)
                .accessibilityHidden(true)
        )
    }

    // MARK: - Monthly Trend Card

    @ViewBuilder
    func monthlyTrendCard(impact: UserImpact) -> some View {
        VStack(spacing: 16) {
            HStack {
                Image(systemName: "calendar.badge.clock")
                    .foregroundColor(Theme.primary)
                    .accessibilityHidden(true)
                Text("Monthly Progress")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundColor(.white)
                    .accessibilityAddTraits(.isHeader)
                Spacer()
            }

            if #available(iOS 16.0, *) {
                Chart {
                    ForEach(impact.monthlyTrend) { month in
                        LineMark(
                            x: .value("Month", formatMonth(month.month)),
                            y: .value("CO₂", month.co2Saved)
                        )
                        .foregroundStyle(Theme.primary.gradient)
                        .symbol(Circle())

                        AreaMark(
                            x: .value("Month", formatMonth(month.month)),
                            y: .value("CO₂", month.co2Saved)
                        )
                        .foregroundStyle(Theme.primary.opacity(0.2).gradient)
                    }
                }
                .frame(height: 200)
                .chartXAxis {
                    AxisMarks(values: .automatic) { _ in
                        AxisValueLabel()
                            .foregroundStyle(Theme.textSecondary)
                    }
                }
                .chartYAxis {
                    AxisMarks(position: .leading) { _ in
                        AxisValueLabel()
                            .foregroundStyle(Theme.textSecondary)
                    }
                }
                .accessibilityLabel("Line chart showing monthly CO2 savings trend")
                .accessibilityHint("Shows CO2 saved in kilograms for each month")
            } else {
                Text("Monthly trend chart available on iOS 16+")
                    .font(.caption)
                    .foregroundColor(Theme.textSecondary)
                    .frame(height: 200)
            }

            Text("Monthly CO₂ savings (kg)")
                .font(.caption)
                .foregroundColor(Theme.textSecondary)
                .accessibilityLabel("Monthly CO2 savings in kilograms")
        }
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Theme.surfaceBase)
                .shadow(color: Color.black.opacity(0.3), radius: 10)
                .accessibilityHidden(true)
        )
    }

    // MARK: - Milestones Card

    @ViewBuilder
    func milestonesCard(impact: UserImpact) -> some View {
        VStack(spacing: 16) {
            HStack {
                Image(systemName: "trophy.fill")
                    .foregroundColor(Theme.warning)
                    .accessibilityHidden(true)
                Text("Milestones")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundColor(.white)
                    .accessibilityAddTraits(.isHeader)
                Spacer()
            }

            VStack(spacing: 12) {
                ForEach(impact.milestones.prefix(6)) { milestone in
                    milestoneRow(milestone: milestone)
                }
            }
        }
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Theme.surfaceBase)
                .shadow(color: Color.black.opacity(0.3), radius: 10)
                .accessibilityHidden(true)
        )
    }

    @ViewBuilder
    func milestoneRow(milestone: UserImpact.Milestone) -> some View {
        HStack(spacing: 12) {
            // Icon
            ZStack {
                Circle()
                    .fill(milestone.isAchieved ? Theme.warning.opacity(0.2) : Theme.textMuted.opacity(0.1))
                    .frame(width: 44, height: 44)
                    .accessibilityHidden(true)

                Image(systemName: milestone.icon)
                    .font(.system(size: 20))
                    .foregroundColor(milestone.isAchieved ? Theme.warning : Theme.textMuted)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(milestone.title)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(milestone.isAchieved ? .white : Theme.textSecondary)

                Text(milestone.description)
                    .font(.system(size: 12))
                    .foregroundColor(Theme.textSecondary)
                    .lineLimit(1)

                if !milestone.isAchieved {
                    // Progress bar
                    GeometryReader { geometry in
                        ZStack(alignment: .leading) {
                            RoundedRectangle(cornerRadius: 2)
                                .fill(Theme.textMuted.opacity(0.2))
                                .frame(height: 4)

                            RoundedRectangle(cornerRadius: 2)
                                .fill(Theme.primary)
                                .frame(
                                    width: geometry.size.width * min(milestone.currentValue / milestone.threshold, 1.0),
                                    height: 4
                                )
                        }
                    }
                    .frame(height: 4)
                    .accessibilityHidden(true)
                }
            }

            Spacer()

            if milestone.isAchieved {
                VStack(spacing: 2) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(Theme.success)
                        .font(.system(size: 18))

                    if let date = milestone.achievedDate {
                        Text(formatAchievedDate(date))
                            .font(.system(size: 9))
                            .foregroundColor(Theme.textSecondary)
                    }
                }
            } else {
                Text("\(Int((milestone.currentValue / milestone.threshold) * 100))%")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(Theme.textSecondary)
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(milestone.isAchieved ? Theme.warning.opacity(0.05) : Theme.textMuted.opacity(0.05))
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Milestone: \(milestone.title), \(milestone.isAchieved ? "achieved" : "not yet achieved"). \(milestone.description)\(milestone.isAchieved ? "" : ". \(Int((milestone.currentValue / milestone.threshold) * 100)) percent complete")")
    }

    // MARK: - Stats Grid

    @ViewBuilder
    func statsGrid(impact: UserImpact) -> some View {
        VStack(spacing: 16) {
            HStack {
                Image(systemName: "chart.pie.fill")
                    .foregroundColor(Theme.primary)
                    .accessibilityHidden(true)
                Text("Quick Stats")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundColor(.white)
                    .accessibilityAddTraits(.isHeader)
                Spacer()
            }

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                statCard(
                    icon: "barcode.viewfinder",
                    color: Theme.primary,
                    value: "\(impact.totalProductsScanned)",
                    label: "Products Scanned"
                )
                .staggerAnimation(index: 0)

                statCard(
                    icon: "arrow.triangle.branch",
                    color: Theme.warning,
                    value: "\(impact.alternativesChosen)",
                    label: "Alternatives Chosen"
                )
                .staggerAnimation(index: 1)

                statCard(
                    icon: "heart.fill",
                    color: Theme.error,
                    value: "\(impact.healthierChoices)",
                    label: "Healthier Choices"
                )
                .staggerAnimation(index: 2)

                statCard(
                    icon: "flame.fill",
                    color: Theme.warning,
                    value: "\(impact.streakDays)",
                    label: "Day Streak"
                )
                .staggerAnimation(index: 3)
            }
        }
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Theme.surfaceBase)
                .shadow(color: Color.black.opacity(0.3), radius: 10)
                .accessibilityHidden(true)
        )
    }

    @ViewBuilder
    func statCard(icon: String, color: Color, value: String, label: String) -> some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 24))
                .foregroundColor(color)

            Text(value)
                .font(.system(size: 24, weight: .bold))
                .foregroundColor(.white)

            Text(label)
                .font(.system(size: 11))
                .foregroundColor(Theme.textSecondary)
                .multilineTextAlignment(.center)
                .lineLimit(2)
        }
        .frame(maxWidth: .infinity)
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(color.opacity(0.08))
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(label): \(value)")
    }

    // MARK: - Empty State

    @ViewBuilder
    func emptyStateView() -> some View {
        VStack(spacing: 20) {
            Image(systemName: "leaf.circle")
                .font(.system(size: 80))
                .foregroundColor(Theme.primary.opacity(0.5))
                .accessibilityHidden(true)

            Text("Start Your Impact Journey")
                .font(.system(size: 24, weight: .bold))
                .foregroundColor(.white)
                .accessibilityAddTraits(.isHeader)

            Text("Scan products to see your environmental impact and discover better alternatives")
                .font(.system(size: 15))
                .foregroundColor(Theme.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)

            Button(action: {
                NotificationCenter.default.post(name: Notification.Name("switchToTab"), object: 0)
            }) {
                HStack {
                    Image(systemName: "camera.fill")
                    Text("Scan Your First Product")
                }
                .font(.body.weight(.semibold))
                .foregroundColor(.white)
                .padding(.horizontal, 30)
                .padding(.vertical, 14)
                .background(Theme.primary)
                .clipShape(RoundedRectangle(cornerRadius: 25))
            }
            .padding(.top, 20)
            .accessibilityLabel("Scan Your First Product")
            .accessibilityHint("Opens the camera to scan a product barcode")
        }
    }

    // MARK: - Helper Functions

    func loadImpactData() {
        isLoading = true
        errorMessage = nil

        Task {
            do {
                let impact = try await ImpactService.shared.getUserImpact()
                await MainActor.run {
                    self.userImpact = impact
                    self.isLoading = false
                }
            } catch {
                await MainActor.run {
                    self.errorMessage = UserFacingError.message(from: error)
                    self.isLoading = false
                }
            }
        }
    }

    func formatDate(_ dateString: String) -> String {
        // Input: "2024-01-15"
        // Output: "Jan 15"
        let components = dateString.split(separator: "-")
        guard components.count == 3,
              let month = Int(components[1]),
              let day = Int(components[2]),
              month >= 1, month <= 12 else {
            return dateString
        }

        let monthNames = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]
        return "\(monthNames[month - 1]) \(day)"
    }

    func formatMonth(_ monthString: String) -> String {
        // Input: "2024-01"
        // Output: "Jan '24"
        let components = monthString.split(separator: "-")
        guard components.count == 2,
              let year = Int(components[0]),
              let month = Int(components[1]),
              month >= 1, month <= 12 else {
            return monthString
        }

        let monthNames = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]
        return "\(monthNames[month - 1]) '\(String(year).suffix(2))"
    }

    func formatAchievedDate(_ dateString: String) -> String {
        // Input: ISO8601 date
        // Output: "Jan 15"
        let formatter = ISO8601DateFormatter()
        guard let date = formatter.date(from: dateString) else {
            return ""
        }

        let displayFormatter = DateFormatter()
        displayFormatter.dateFormat = "MMM d"
        return displayFormatter.string(from: date)
    }
}

// MARK: - Preview

struct ImpactDashboardView_Previews: PreviewProvider {
    static var previews: some View {
        ImpactDashboardView()
    }
}
