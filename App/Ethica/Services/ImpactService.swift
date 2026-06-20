//
//  ImpactService.swift
//  Ethica
//
//  Service to calculate and track user's environmental impact
//

import Foundation

#if canImport(SQLite)
import SQLite
#endif

#if canImport(SQLite)
class ImpactService {
    static let shared = ImpactService()
    private let db: Connection?

    /// Read through to DatabaseManager so we pick up the lazy reconnection
    /// (the file may not exist until HistoryService creates it on first scan).
    private var historyDb: Connection? { DatabaseManager.shared.historyDb }

    private var isDbAvailable: Bool { db != nil }

    private init() {
        self.db = DatabaseManager.shared.db
    }

    // MARK: - Get Complete User Impact

    func getUserImpact() async throws -> UserImpact {
        let userId = AuthenticationService.shared.currentUserId ?? "anonymous"
        let weeklyTrend = calculateWeeklyTrend()
        let monthlyTrend = calculateMonthlyTrend()
        let streakDays = calculateStreakDays()
        let currentMonthStats = getCurrentMonthStats()
        _ = userId

        // No backend server: use local SQLite as the source of truth.
        let localTotals = calculateLocalTotals()
        let totalCO2 = localTotals.co2Saved
        let totalWater = localTotals.waterSaved
        let totalScans = localTotals.totalScans

        let milestones = calculateMilestones(
            totalCO2: totalCO2,
            totalWater: totalWater,
            totalScans: totalScans
        )

        // Count interactions
        let interactions = getAlternativeInteractions()
        let alternativesChosen = interactions.filter { $0 == "clicked" || $0 == "purchased" }.count
        let healthierChoices = countHealthierChoices()

        return UserImpact(
            totalCO2Saved: totalCO2,
            totalWaterSaved: totalWater,
            totalProductsScanned: totalScans,
            alternativesChosen: alternativesChosen,
            healthierChoices: healthierChoices,
            streakDays: streakDays,
            currentMonthCO2: currentMonthStats.co2,
            currentMonthWater: currentMonthStats.water,
            milestones: milestones,
            weeklyTrend: weeklyTrend,
            monthlyTrend: monthlyTrend
        )
    }

    // MARK: - Local Total Calculation

    private func calculateLocalTotals() -> (totalScans: Int, co2Saved: Double, waterSaved: Double) {
        guard let hdb = historyDb else { return (0, 0, 0) }

        do {
            // Count total scans
            let totalScans = try hdb.scalar(HistoryItem.table.count)

            // Sum up CO2 and water savings from all scans with decisions
            let items = try hdb.prepare(
                HistoryItem.table.filter(
                    HistoryItem.purchaseDecisionCol == "avoided" ||
                    HistoryItem.purchaseDecisionCol == "alternative"
                )
            )

            var totalCO2Saved: Double = 0
            var totalWaterSaved: Double = 0

            for row in items {
                let item = HistoryItem(
                    id: try row.get(HistoryItem.idCol),
                    productName: try row.get(HistoryItem.productNameCol),
                    barcode: try row.get(HistoryItem.barcodeCol),
                    timestamp: Date(timeIntervalSince1970: try row.get(HistoryItem.timestampCol)),
                    healthScore: try row.get(HistoryItem.healthScoreCol),
                    co2Emissions: try row.get(HistoryItem.co2EmissionsCol),
                    waterUsage: try row.get(HistoryItem.waterUsageCol),
                    purchaseDecision: try row.get(HistoryItem.purchaseDecisionCol),
                    alternativeName: try row.get(HistoryItem.alternativeNameCol),
                    alternativeCO2: try row.get(HistoryItem.alternativeCO2Col),
                    alternativeWater: try row.get(HistoryItem.alternativeWaterCol)
                )
                totalCO2Saved += item.co2Saved ?? 0.0
                totalWaterSaved += item.waterSaved ?? 0.0
            }

            return (totalScans, totalCO2Saved, totalWaterSaved)
        } catch {
            AppLogger.debug("Error calculating local totals: \(error)")
            return (0, 0, 0)
        }
    }

    // MARK: - Weekly Trend

    private func calculateWeeklyTrend() -> [UserImpact.DailyImpact] {
        var dailyImpacts: [UserImpact.DailyImpact] = []
        let calendar = Calendar.current
        let today = Date()

        // Calculate for last 7 days
        for daysAgo in (0..<7).reversed() {
            guard let date = calendar.date(byAdding: .day, value: -daysAgo, to: today) else { continue }
            let dateString = formatDate(date)

            let scans = getScansForDate(date)
            let co2Saved = scans.reduce(0.0) { $0 + ($1.co2Saved ?? 0.0) }
            let waterSaved = scans.reduce(0.0) { $0 + ($1.waterSaved ?? 0.0) }

            dailyImpacts.append(UserImpact.DailyImpact(
                date: dateString,
                co2Saved: co2Saved,
                waterSaved: waterSaved,
                scansCount: scans.count
            ))
        }

        return dailyImpacts
    }

    // MARK: - Monthly Trend

    private func calculateMonthlyTrend() -> [UserImpact.MonthlyImpact] {
        var monthlyImpacts: [UserImpact.MonthlyImpact] = []
        let calendar = Calendar.current
        let today = Date()

        // Calculate for last 6 months
        for monthsAgo in (0..<6).reversed() {
            guard let date = calendar.date(byAdding: .month, value: -monthsAgo, to: today) else { continue }
            let monthString = formatMonth(date)

            let scans = getScansForMonth(date)
            let co2Saved = scans.reduce(0.0) { $0 + ($1.co2Saved ?? 0.0) }
            let waterSaved = scans.reduce(0.0) { $0 + ($1.waterSaved ?? 0.0) }
            let alternativesChosen = countAlternativesForMonth(date)

            monthlyImpacts.append(UserImpact.MonthlyImpact(
                month: monthString,
                co2Saved: co2Saved,
                waterSaved: waterSaved,
                scansCount: scans.count,
                alternativesChosen: alternativesChosen
            ))
        }

        return monthlyImpacts
    }

    // MARK: - Milestones

    private func calculateMilestones(totalCO2: Double, totalWater: Double, totalScans: Int) -> [UserImpact.Milestone] {
        let streakDays = calculateStreakDays()

        return UserImpact.Milestone.predefinedMilestones.map { template in
            var milestone = template

            // Set current value based on category
            switch milestone.category {
            case "co2":
                milestone.currentValue = totalCO2
            case "water":
                milestone.currentValue = totalWater
            case "scans":
                milestone.currentValue = Double(totalScans)
            case "streak":
                milestone.currentValue = Double(streakDays)
            default:
                milestone.currentValue = 0
            }

            // Check if achieved
            if milestone.currentValue >= milestone.threshold {
                milestone.isAchieved = true
                // Set achieved date if not already set
                if milestone.achievedDate == nil {
                    milestone.achievedDate = ISO8601DateFormatter().string(from: Date())
                }
            }

            return milestone
        }
    }

    // MARK: - Streak Calculation

    private func calculateStreakDays() -> Int {
        let calendar = Calendar.current
        var streak = 0
        var currentDate = Date()

        // Check if user scanned today
        if getScansForDate(currentDate).isEmpty {
            // No scan today, check yesterday
            guard let yesterday = calendar.date(byAdding: .day, value: -1, to: currentDate) else {
                return 0
            }
            currentDate = yesterday
        }

        // Count consecutive days with scans
        while true {
            let scans = getScansForDate(currentDate)
            if scans.isEmpty {
                break
            }
            streak += 1
            guard let previousDay = calendar.date(byAdding: .day, value: -1, to: currentDate) else {
                break
            }
            currentDate = previousDay

            // Safety limit
            if streak > 365 {
                break
            }
        }

        return streak
    }

    // MARK: - Current Month Stats

    private func getCurrentMonthStats() -> (co2: Double, water: Double) {
        let calendar = Calendar.current
        let now = Date()
        let scans = getScansForMonth(now)

        let co2 = scans.reduce(0.0) { $0 + ($1.co2Saved ?? 0.0) }
        let water = scans.reduce(0.0) { $0 + ($1.waterSaved ?? 0.0) }

        return (co2, water)
    }

    // MARK: - Database Queries

    private func getScansForDate(_ date: Date) -> [HistoryItem] {
        guard let hdb = historyDb else { return [] }
        let calendar = Calendar.current
        let startOfDay = calendar.startOfDay(for: date)
        guard let endOfDay = calendar.date(byAdding: .day, value: 1, to: startOfDay) else {
            return []
        }
        let startInterval = startOfDay.timeIntervalSince1970
        let endInterval = endOfDay.timeIntervalSince1970

        do {
            let items = try hdb.prepare(
                HistoryItem.table
                    .filter(HistoryItem.timestampCol >= startInterval && HistoryItem.timestampCol < endInterval)
            )

            return try items.map { row in
                let ts = try row.get(HistoryItem.timestampCol)
                return HistoryItem(
                    id: try row.get(HistoryItem.idCol),
                    productName: try row.get(HistoryItem.productNameCol),
                    barcode: try row.get(HistoryItem.barcodeCol),
                    timestamp: Date(timeIntervalSince1970: ts),
                    healthScore: try row.get(HistoryItem.healthScoreCol),
                    co2Emissions: try row.get(HistoryItem.co2EmissionsCol),
                    waterUsage: try row.get(HistoryItem.waterUsageCol),
                    purchaseDecision: try row.get(HistoryItem.purchaseDecisionCol),
                    alternativeName: try row.get(HistoryItem.alternativeNameCol),
                    alternativeCO2: try row.get(HistoryItem.alternativeCO2Col),
                    alternativeWater: try row.get(HistoryItem.alternativeWaterCol)
                )
            }
        } catch {
            AppLogger.debug("Error fetching scans for date: \(error)")
            return []
        }
    }

    private func getScansForMonth(_ date: Date) -> [HistoryItem] {
        guard let hdb = historyDb else { return [] }
        let calendar = Calendar.current
        guard let startOfMonth = calendar.date(from: calendar.dateComponents([.year, .month], from: date)),
              let startOfNextMonth = calendar.date(byAdding: .month, value: 1, to: startOfMonth) else {
            return []
        }
        let startInterval = startOfMonth.timeIntervalSince1970
        let endInterval = startOfNextMonth.timeIntervalSince1970

        do {
            let items = try hdb.prepare(
                HistoryItem.table
                    .filter(HistoryItem.timestampCol >= startInterval && HistoryItem.timestampCol < endInterval)
            )

            return try items.map { row in
                let ts = try row.get(HistoryItem.timestampCol)
                return HistoryItem(
                    id: try row.get(HistoryItem.idCol),
                    productName: try row.get(HistoryItem.productNameCol),
                    barcode: try row.get(HistoryItem.barcodeCol),
                    timestamp: Date(timeIntervalSince1970: ts),
                    healthScore: try row.get(HistoryItem.healthScoreCol),
                    co2Emissions: try row.get(HistoryItem.co2EmissionsCol),
                    waterUsage: try row.get(HistoryItem.waterUsageCol),
                    purchaseDecision: try row.get(HistoryItem.purchaseDecisionCol),
                    alternativeName: try row.get(HistoryItem.alternativeNameCol),
                    alternativeCO2: try row.get(HistoryItem.alternativeCO2Col),
                    alternativeWater: try row.get(HistoryItem.alternativeWaterCol)
                )
            }
        } catch {
            AppLogger.debug("Error fetching scans for month: \(error)")
            return []
        }
    }

    private func getAlternativeInteractions() -> [String] {
        guard let db = self.db else { return [] }
        do {
            let interactions = try db.prepare(AlternativeInteraction.table)
            return try interactions.map { row in
                try row.get(AlternativeInteraction.actionCol)
            }
        } catch {
            AppLogger.debug("Error fetching interactions: \(error)")
            return []
        }
    }

    private func countAlternativesForMonth(_ date: Date) -> Int {
        guard let db = self.db else { return 0 }
        let calendar = Calendar.current
        guard let startOfMonth = calendar.date(from: calendar.dateComponents([.year, .month], from: date)),
              let startOfNextMonth = calendar.date(byAdding: .month, value: 1, to: startOfMonth) else {
            return 0
        }

        do {
            let count = try db.scalar(
                AlternativeInteraction.table
                    .filter(AlternativeInteraction.timestampCol >= startOfMonth &&
                           AlternativeInteraction.timestampCol < startOfNextMonth)
                    .filter(AlternativeInteraction.actionCol == "clicked" ||
                           AlternativeInteraction.actionCol == "purchased")
                    .count
            )
            return count
        } catch {
            AppLogger.debug("Error counting alternatives for month: \(error)")
            return 0
        }
    }

    private func countHealthierChoices() -> Int {
        guard let hdb = historyDb else { return 0 }
        do {
            let count = try hdb.scalar(
                HistoryItem.table
                    .filter(HistoryItem.healthScoreCol > 70)
                    .count
            )
            return count
        } catch {
            AppLogger.debug("Error counting healthier choices: \(error)")
            return 0
        }
    }

    // MARK: - Helper Functions

    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }

    private func formatMonth(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM"
        return formatter.string(from: date)
    }
}
#else
final class ImpactService {
    static let shared = ImpactService()

    private init() {
        AppLogger.warning("ImpactService: SQLite unavailable, impact tracking disabled")
    }

    func getUserImpact() async throws -> UserImpact {
        UserImpact(
            totalCO2Saved: 0,
            totalWaterSaved: 0,
            totalProductsScanned: 0,
            alternativesChosen: 0,
            healthierChoices: 0,
            streakDays: 0,
            currentMonthCO2: 0,
            currentMonthWater: 0,
            milestones: UserImpact.Milestone.predefinedMilestones.map { milestone in
                var copy = milestone
                copy.currentValue = 0
                copy.isAchieved = false
                copy.achievedDate = nil
                return copy
            },
            weeklyTrend: [],
            monthlyTrend: []
        )
    }
}
#endif
