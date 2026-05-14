//
//  ImpactCalculator.swift
//  Ethica
//
//  Calculate environmental and health impact from scan history

import Foundation

class ImpactCalculator {
    static let shared = ImpactCalculator()
    
    private init() {}
    
    // MARK: - Calculate Impact Stats
    
    func calculateImpactStats() -> ImpactStats {
        let allScans = HistoryService.shared.fetchAllScans()
        
        #if DEBUG
        AppLogger.debug("🔢 === IMPACT CALCULATION START ===")
        AppLogger.debug("   Total Scans: \(allScans.count)")
        #endif
        
        let totalScans = allScans.count
        let safeProducts = allScans.filter { $0.isSafe }.count
        let violatedProducts = totalScans - safeProducts
        
        // Count purchases by decision type
        let purchased = allScans.filter { $0.purchaseDecision == .purchased }
        let avoided = allScans.filter { $0.purchaseDecision == .avoided }
        let alternatives = allScans.filter { $0.purchaseDecision == .alternative }
        
        #if DEBUG
        AppLogger.debug("   Purchase Breakdown:")
        AppLogger.debug("      🛒 Purchased: \(purchased.count)")
        AppLogger.error("      🚫 Avoided: \(avoided.count)")
        AppLogger.debug("      🔄 Alternatives: \(alternatives.count)")
        #endif
        
        // ACCURATE CO2 SAVED CALCULATION:
        // 1. Products you avoided = their full CO2 impact saved
        let co2FromAvoided = avoided.reduce(0.0) { $0 + $1.co2Emissions }
        
        // 2. Alternatives chosen = ACTUAL difference (original - alternative)
        let co2FromAlternatives = alternatives.reduce(0.0) { sum, scan in
            if let alternativeCO2 = scan.alternativeCO2 {
                // Use real alternative CO2 data
                let savings = max(0, scan.co2Emissions - alternativeCO2)
                AppLogger.debug("   💡 Alternative '\(scan.alternativeName ?? "unknown")': saved \(String(format: "%.2f", savings))kg CO2 (original: \(scan.co2Emissions), alt: \(alternativeCO2))")
                return sum + savings
            } else {
                // No alternative CO2 data available — conservatively assume 0 savings
                // rather than fabricating a 50% estimate
                AppLogger.warning("   ⚠️ Alternative '\(scan.alternativeName ?? "unknown")': NO CO2 data, assuming 0 savings (conservative)")
                return sum
            }
        }
        
        let totalCO2Saved = co2FromAvoided + co2FromAlternatives
        
        // ACCURATE WATER SAVED CALCULATION: Same logic
        let waterFromAvoided = avoided.reduce(0.0) { $0 + $1.waterUsage }
        let waterFromAlternatives = alternatives.reduce(0.0) { sum, scan in
            if let alternativeWater = scan.alternativeWater {
                let savings = max(0, scan.waterUsage - alternativeWater)
                AppLogger.debug("   💧 Alternative '\(scan.alternativeName ?? "unknown")': saved \(String(format: "%.0f", savings))L water (original: \(scan.waterUsage), alt: \(alternativeWater))")
                return sum + savings
            } else {
                // No alternative water data — conservatively assume 0 savings
                AppLogger.warning("   ⚠️ Alternative '\(scan.alternativeName ?? "unknown")': NO water data, assuming 0 savings (conservative)")
                return sum
            }
        }
        let totalWaterSaved = waterFromAvoided + waterFromAlternatives
        
        // YOUR ACTUAL FOOTPRINT (products you bought):
        let yourCO2Footprint = purchased.reduce(0.0) { $0 + $1.co2Emissions }
        let yourWaterFootprint = purchased.reduce(0.0) { $0 + $1.waterUsage }
        
        // HEALTH METRICS
        // When user has purchase decisions, use purchased items; otherwise fall back to all scans
        let healthBasis = purchased.isEmpty ? allScans : purchased
        let averageHealthScore: Double
        if healthBasis.isEmpty {
            averageHealthScore = 0.0
        } else {
            let totalHealthScore = healthBasis.reduce(0.0) { $0 + $1.healthScore }
            averageHealthScore = totalHealthScore / Double(healthBasis.count)
        }

        let healthyChoicesCount = healthBasis.filter { $0.healthScore >= 70.0 }.count  // 70+ on 0-100 scale
        let unhealthyChoicesCount = healthBasis.filter { $0.healthScore < 50.0 }.count  // <50 on 0-100 scale

        AppLogger.debug("   📊 Health Stats (based on \(purchased.isEmpty ? "all scans" : "purchased")):")
        AppLogger.debug("      Average Health Score: \(String(format: "%.1f", averageHealthScore))")
        AppLogger.debug("      Healthy Choices (≥70.0): \(healthyChoicesCount)")
        AppLogger.debug("      Unhealthy Choices (<50.0): \(unhealthyChoicesCount)")
        
        // Calculate animals spared based on avoided high-impact products
        let highImpactAvoided = avoided.filter { $0.animalImpact.lowercased() == "high" }.count
        let animalsSpared = highImpactAvoided / 5 // Rough estimate: 1 animal per 5 avoided meat products
        
        // Health improvements (avoided concerning ingredients)
        let healthImprovements = avoided.reduce(0) { $0 + $1.concernsCount }
        
        // Calculate streaks
        let currentStreak = calculateCurrentStreak(from: allScans)
        let longestStreak = calculateLongestStreak(from: allScans)
        
        let startDate = HistoryService.shared.getFirstScanDate() ?? Date()
        
        #if DEBUG
        AppLogger.debug("📈 ACCURATE Impact:")
        AppLogger.debug("   ├─ Purchased: \(purchased.count) (CO2: \(String(format: "%.1f", yourCO2Footprint))kg)")
        AppLogger.debug("   ├─ Avoided: \(avoided.count) (Saved CO2: \(String(format: "%.1f", co2FromAvoided))kg)")
        AppLogger.debug("   └─ Alternatives: \(alternatives.count) (Saved CO2: \(String(format: "%.1f", co2FromAlternatives))kg)")
        let co2Text = String(format: "%.1f", totalCO2Saved)
        let waterText = String(format: "%.1f", totalWaterSaved)
        AppLogger.debug("   🌍 Total CO2 Saved: \(co2Text)kg, Water: \(waterText)L")
        #endif
        
        return ImpactStats(
            totalScans: totalScans,
            safeProducts: safeProducts,
            violatedProducts: violatedProducts,
            productsPurchased: purchased.count,
            productsAvoided: avoided.count,
            alternativesChosen: alternatives.count,
            totalCO2Saved: totalCO2Saved,
            totalWaterSaved: totalWaterSaved,
            yourCO2Footprint: yourCO2Footprint,
            yourWaterFootprint: yourWaterFootprint,
            averageHealthScore: averageHealthScore,
            healthyChoicesCount: healthyChoicesCount,
            unhealthyChoicesCount: unhealthyChoicesCount,
            animalsSpared: animalsSpared,
            healthImprovements: healthImprovements,
            currentStreak: currentStreak,
            longestStreak: longestStreak,
            startDate: startDate
        )
    }
    
    // MARK: - Streak Calculation
    
    private func calculateCurrentStreak(from scans: [ScanHistory]) -> Int {
        guard !scans.isEmpty else { return 0 }
        
        let calendar = Calendar.current
        let sortedScans = scans.sorted { $0.timestamp > $1.timestamp }
        
        var streak = 0
        var currentDate = calendar.startOfDay(for: Date())
        
        for scan in sortedScans {
            let scanDate = calendar.startOfDay(for: scan.timestamp)
            
            if scanDate == currentDate {
                streak = max(streak, 1)
            } else if let previousDay = calendar.date(byAdding: .day, value: -1, to: currentDate),
                      scanDate == previousDay {
                streak += 1
                currentDate = scanDate
            } else {
                break
            }
        }
        
        return streak
    }
    
    private func calculateLongestStreak(from scans: [ScanHistory]) -> Int {
        guard !scans.isEmpty else { return 0 }
        
        let calendar = Calendar.current
        let sortedScans = scans.sorted { $0.timestamp < $1.timestamp }
        
        var longestStreak = 0
        var currentStreak = 0
        var previousDate: Date?
        
        for scan in sortedScans {
            let scanDate = calendar.startOfDay(for: scan.timestamp)
            
            if let prev = previousDate {
                let daysDiff = calendar.dateComponents([.day], from: prev, to: scanDate).day ?? 0
                if daysDiff == 0 {
                    // Same day, continue streak
                    continue
                } else if daysDiff == 1 {
                    // Next day, increment streak
                    currentStreak += 1
                } else {
                    // Streak broken
                    longestStreak = max(longestStreak, currentStreak)
                    currentStreak = 1
                }
            } else {
                currentStreak = 1
            }
            
            previousDate = scanDate
        }
        
        longestStreak = max(longestStreak, currentStreak)
        return longestStreak
    }
    
    // MARK: - Achievements
    
    func checkAchievements() -> [Achievement] {
        let stats = calculateImpactStats()
        let allScans = HistoryService.shared.fetchAllScans()
        var earned: [Achievement] = []
        
        // Scan count achievements
        if stats.totalScans >= 1 { earned.append(.firstScan) }
        if stats.totalScans >= 10 { earned.append(.tenScans) }
        if stats.totalScans >= 50 { earned.append(.fiftyScans) }
        if stats.totalScans >= 100 { earned.append(.hundredScans) }
        
        // Streak achievements
        if stats.currentStreak >= 7 { earned.append(.weekStreak) }
        if stats.longestStreak >= 30 { earned.append(.monthStreak) }
        
        // Plant-based achievement
        let lowImpactCount = allScans.filter { $0.animalImpact.lowercased().contains("low") }.count
        if lowImpactCount >= 10 { earned.append(.plantPioneer) }
        
        // Environmental achievement
        if stats.totalCO2Saved >= 100 { earned.append(.ecoWarrior) }
        
        // Health achievement
        if stats.healthImprovements >= 50 { earned.append(.healthChampion) }
        
        // Perfect week achievement
        let last7Days = Calendar.current.date(byAdding: .day, value: -7, to: Date()) ?? Date()
        let recentScans = allScans.filter { $0.timestamp >= last7Days }
        if recentScans.count >= 7 && recentScans.allSatisfy({ $0.isSafe }) {
            earned.append(.perfectWeek)
        }
        
        return earned
    }
    
    // MARK: - Weekly Comparison
    
    func getWeeklyComparison() -> (thisWeek: ImpactStats, lastWeek: ImpactStats)? {
        let calendar = Calendar.current
        let now = Date()
        
        // This week
        guard let startOfThisWeek = calendar.date(from: calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: now)),
              let startOfLastWeek = calendar.date(byAdding: .weekOfYear, value: -1, to: startOfThisWeek),
              let endOfLastWeek = calendar.date(byAdding: .day, value: -1, to: startOfThisWeek) else {
            return nil
        }
        let thisWeekScans = HistoryService.shared.fetchScans(from: startOfThisWeek, to: now)
        let lastWeekScans = HistoryService.shared.fetchScans(from: startOfLastWeek, to: endOfLastWeek)
        
        // Only show comparison if we have data for both weeks
        if thisWeekScans.isEmpty || lastWeekScans.isEmpty {
            return nil
        }
        
        return (
            thisWeek: calculateStatsForScans(thisWeekScans),
            lastWeek: calculateStatsForScans(lastWeekScans)
        )
    }
    
    private func calculateStatsForScans(_ scans: [ScanHistory]) -> ImpactStats {
        let totalScans = scans.count
        let safeProducts = scans.filter { $0.isSafe }.count
        let violatedProducts = totalScans - safeProducts
        
        // Count purchases by decision type
        let purchased = scans.filter { $0.purchaseDecision == .purchased }
        let avoided = scans.filter { $0.purchaseDecision == .avoided }
        let alternatives = scans.filter { $0.purchaseDecision == .alternative }
        
        // ACCURATE CO2 SAVED CALCULATION
        let co2FromAvoided = avoided.reduce(0.0) { $0 + $1.co2Emissions }
        let co2FromAlternatives = alternatives.reduce(0.0) { sum, scan in
            if let alternativeCO2 = scan.alternativeCO2 {
                return sum + max(0, scan.co2Emissions - alternativeCO2)
            } else {
                return sum // No data — conservatively assume 0 savings
            }
        }
        let totalCO2Saved = co2FromAvoided + co2FromAlternatives

        // ACCURATE WATER SAVED CALCULATION
        let waterFromAvoided = avoided.reduce(0.0) { $0 + $1.waterUsage }
        let waterFromAlternatives = alternatives.reduce(0.0) { sum, scan in
            if let alternativeWater = scan.alternativeWater {
                return sum + max(0, scan.waterUsage - alternativeWater)
            } else {
                return sum // No data — conservatively assume 0 savings
            }
        }
        let totalWaterSaved = waterFromAvoided + waterFromAlternatives
        
        // YOUR ACTUAL FOOTPRINT
        let yourCO2Footprint = purchased.reduce(0.0) { $0 + $1.co2Emissions }
        let yourWaterFootprint = purchased.reduce(0.0) { $0 + $1.waterUsage }
        
        // HEALTH METRICS
        let averageHealthScore: Double
        if purchased.isEmpty {
            averageHealthScore = 0.0
        } else {
            let totalHealthScore = purchased.reduce(0.0) { $0 + $1.healthScore }
            averageHealthScore = totalHealthScore / Double(purchased.count)
        }
        
        let healthyChoicesCount = purchased.filter { $0.healthScore >= 70.0 }.count  // 70+ on 0-100 scale
        let unhealthyChoicesCount = purchased.filter { $0.healthScore < 50.0 }.count  // <50 on 0-100 scale

        #if DEBUG
        AppLogger.debug("   📊 Health Stats:")
        let healthScoreText = String(format: "%.1f", averageHealthScore)
        AppLogger.debug("      Average Health Score: \(healthScoreText)")
        AppLogger.debug("      Healthy Choices (≥70.0): \(healthyChoicesCount)")
        AppLogger.debug("      Unhealthy Choices (<50.0): \(unhealthyChoicesCount)")
        #endif
        
        let lowImpactScans = scans.filter { $0.animalImpact.lowercased().contains("low") }.count
        let animalsSpared = lowImpactScans / 10
        
        let healthImprovements = scans.reduce(0) { $0 + $1.concernsCount }
        
        let currentStreak = calculateCurrentStreak(from: scans)
        let longestStreak = calculateLongestStreak(from: scans)
        
        let startDate = scans.min(by: { $0.timestamp < $1.timestamp })?.timestamp ?? Date()
        
        return ImpactStats(
            totalScans: totalScans,
            safeProducts: safeProducts,
            violatedProducts: violatedProducts,
            productsPurchased: purchased.count,
            productsAvoided: avoided.count,
            alternativesChosen: alternatives.count,
            totalCO2Saved: totalCO2Saved,
            totalWaterSaved: totalWaterSaved,
            yourCO2Footprint: yourCO2Footprint,
            yourWaterFootprint: yourWaterFootprint,
            averageHealthScore: averageHealthScore,
            healthyChoicesCount: healthyChoicesCount,
            unhealthyChoicesCount: unhealthyChoicesCount,
            animalsSpared: animalsSpared,
            healthImprovements: healthImprovements,
            currentStreak: currentStreak,
            longestStreak: longestStreak,
            startDate: startDate
        )
    }
    
    // MARK: - Insights
    
    func generateInsights() -> [String] {
        let stats = calculateImpactStats()
        let allScans = HistoryService.shared.fetchAllScans()
        var insights: [String] = []
        
        // Compliance insight
        if stats.complianceRate > 80 {
            insights.append("🎉 You're making great choices! \(Int(stats.complianceRate))% of products match your preferences")
        } else if stats.complianceRate > 50 {
            insights.append("💪 You're on the right track! Keep scanning to find more compatible products")
        }
        
        // Streak insight
        if stats.currentStreak > 0 {
            insights.append("🔥 \(stats.currentStreak)-day streak! Keep it going!")
        }
        
        // Environmental insight
        if stats.totalCO2Saved > 10 {
            let treesEquivalent = Int(stats.totalCO2Saved / 20) // 1 tree absorbs ~20kg CO2/year
            insights.append("🌳 You've saved \(String(format: "%.1f", stats.totalCO2Saved))kg of CO₂ - equivalent to \(treesEquivalent) trees!")
        }
        
        // Water insight
        if stats.totalWaterSaved > 1000 {
            let poolsEquivalent = stats.totalWaterSaved / 50000 // Average pool ~50,000L
            insights.append("💧 You've saved \(Int(stats.totalWaterSaved))L of water - enough to fill \(String(format: "%.1f", poolsEquivalent)) swimming pools!")
        }
        
        // Animal impact insight
        if stats.animalsSpared > 0 {
            insights.append("🐮 Your plant-based choices have spared approximately \(stats.animalsSpared) animals")
        }
        
        // Health insight
        if stats.healthImprovements > 20 {
            insights.append("💪 You've avoided \(stats.healthImprovements) concerning ingredients - your body thanks you!")
        }
        
        // Most scanned day pattern
        let calendar = Calendar.current
        let dayOfWeekCounts = allScans.reduce(into: [Int: Int]()) { counts, scan in
            let dayOfWeek = calendar.component(.weekday, from: scan.timestamp)
            counts[dayOfWeek, default: 0] += 1
        }
        if let mostScannedDay = dayOfWeekCounts.max(by: { $0.value < $1.value }) {
            let dayName = calendar.weekdaySymbols[mostScannedDay.key - 1]
            insights.append("📊 You scan most often on \(dayName)s - planning ahead pays off!")
        }
        
        return insights
    }
}
