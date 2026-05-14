//
//  UserImpact.swift
//  Ethica
//
//  User impact tracking and milestone models
//

import Foundation

struct UserImpact: Codable {
    let totalCO2Saved: Double          // kg CO2 saved from choosing alternatives
    let totalWaterSaved: Double        // Liters water saved
    let totalProductsScanned: Int      // Number of products analyzed
    let alternativesChosen: Int        // Number of alternatives clicked/purchased
    let healthierChoices: Int          // Products with better health scores
    let streakDays: Int                // Consecutive days of scanning
    let currentMonthCO2: Double        // This month's CO2 savings
    let currentMonthWater: Double      // This month's water savings
    let milestones: [Milestone]        // Achieved milestones
    let weeklyTrend: [DailyImpact]     // Last 7 days of data
    let monthlyTrend: [MonthlyImpact]  // Last 6 months of data

    struct DailyImpact: Codable, Identifiable {
        var id: String { date }
        let date: String               // "2024-01-15"
        let co2Saved: Double
        let waterSaved: Double
        let scansCount: Int
    }

    struct MonthlyImpact: Codable, Identifiable {
        var id: String { month }
        let month: String              // "2024-01"
        let co2Saved: Double
        let waterSaved: Double
        let scansCount: Int
        let alternativesChosen: Int
    }

    struct Milestone: Codable, Identifiable {
        var id: String { title }
        let title: String
        let description: String
        let icon: String               // SF Symbol name
        var achievedDate: String?      // ISO8601 date when achieved
        var isAchieved: Bool
        let threshold: Double          // The value needed to achieve
        var currentValue: Double       // User's current progress
        let category: String           // "co2", "water", "scans", "streak"
    }

    // Computed properties for display
    var co2SavedEquivalent: String {
        if totalCO2Saved < 1 {
            return "\(Int(totalCO2Saved * 1000))g"
        } else if totalCO2Saved < 1000 {
            return String(format: "%.1fkg", totalCO2Saved)
        } else {
            return String(format: "%.1ft", totalCO2Saved / 1000)
        }
    }

    var waterSavedEquivalent: String {
        if totalWaterSaved < 1000 {
            return String(format: "%.0fL", totalWaterSaved)
        } else {
            return String(format: "%.1fk L", totalWaterSaved / 1000)
        }
    }

    // Real-world equivalents for better understanding
    var co2Comparison: String {
        let miles = totalCO2Saved / 0.404 // 0.404 kg CO2 per mile driven
        if miles < 1 {
            return "Less than 1 mile of driving saved"
        } else if miles < 100 {
            return String(format: "%.0f miles of driving saved", miles)
        } else {
            return String(format: "%.0f miles of driving saved", miles)
        }
    }

    var waterComparison: String {
        let showers = totalWaterSaved / 65 // 65L per 10-min shower
        if showers < 1 {
            return "Less than 1 shower worth of water"
        } else if showers < 10 {
            return String(format: "%.0f showers worth of water", showers)
        } else {
            return String(format: "%.0f showers worth of water", showers)
        }
    }
}

// Predefined milestones
extension UserImpact.Milestone {
    static let predefinedMilestones: [UserImpact.Milestone] = [
        // CO2 Milestones
        UserImpact.Milestone(
            title: "First Step",
            description: "Save 1kg of CO2 emissions",
            icon: "leaf.circle.fill",
            achievedDate: nil,
            isAchieved: false,
            threshold: 1.0,
            currentValue: 0,
            category: "co2"
        ),
        UserImpact.Milestone(
            title: "Climate Warrior",
            description: "Save 10kg of CO2 emissions",
            icon: "leaf.fill",
            achievedDate: nil,
            isAchieved: false,
            threshold: 10.0,
            currentValue: 0,
            category: "co2"
        ),
        UserImpact.Milestone(
            title: "Planet Protector",
            description: "Save 50kg of CO2 emissions",
            icon: "globe.americas.fill",
            achievedDate: nil,
            isAchieved: false,
            threshold: 50.0,
            currentValue: 0,
            category: "co2"
        ),
        UserImpact.Milestone(
            title: "Eco Champion",
            description: "Save 100kg of CO2 emissions",
            icon: "star.fill",
            achievedDate: nil,
            isAchieved: false,
            threshold: 100.0,
            currentValue: 0,
            category: "co2"
        ),

        // Water Milestones
        UserImpact.Milestone(
            title: "Water Saver",
            description: "Save 100L of water",
            icon: "drop.circle.fill",
            achievedDate: nil,
            isAchieved: false,
            threshold: 100.0,
            currentValue: 0,
            category: "water"
        ),
        UserImpact.Milestone(
            title: "Hydro Hero",
            description: "Save 1,000L of water",
            icon: "drop.fill",
            achievedDate: nil,
            isAchieved: false,
            threshold: 1000.0,
            currentValue: 0,
            category: "water"
        ),

        // Scan Milestones
        UserImpact.Milestone(
            title: "Curious Mind",
            description: "Scan 10 products",
            icon: "eye.circle.fill",
            achievedDate: nil,
            isAchieved: false,
            threshold: 10.0,
            currentValue: 0,
            category: "scans"
        ),
        UserImpact.Milestone(
            title: "Info Seeker",
            description: "Scan 50 products",
            icon: "eye.fill",
            achievedDate: nil,
            isAchieved: false,
            threshold: 50.0,
            currentValue: 0,
            category: "scans"
        ),
        UserImpact.Milestone(
            title: "Conscious Consumer",
            description: "Scan 100 products",
            icon: "checkmark.seal.fill",
            achievedDate: nil,
            isAchieved: false,
            threshold: 100.0,
            currentValue: 0,
            category: "scans"
        ),

        // Streak Milestones
        UserImpact.Milestone(
            title: "Building Habits",
            description: "7-day scanning streak",
            icon: "flame.circle.fill",
            achievedDate: nil,
            isAchieved: false,
            threshold: 7.0,
            currentValue: 0,
            category: "streak"
        ),
        UserImpact.Milestone(
            title: "Dedicated",
            description: "30-day scanning streak",
            icon: "flame.fill",
            achievedDate: nil,
            isAchieved: false,
            threshold: 30.0,
            currentValue: 0,
            category: "streak"
        )
    ]
}
