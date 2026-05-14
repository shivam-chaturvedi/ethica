//
//  ScanHistory.swift
//  Ethica
//
//  Scan history data model for impact tracking

import Foundation

// Purchase decision tracking
enum PurchaseDecision: String, Codable {
    case scanned = "scanned"           // Just scanned, no decision yet
    case purchased = "purchased"       // User bought this product
    case avoided = "avoided"           // User chose NOT to buy (violations found)
    case alternative = "alternative"   // User bought an alternative instead
}

struct ScanHistory: Identifiable, Codable, Equatable {
    let id: UUID
    let timestamp: Date
    let productName: String
    let barcode: String?
    let sourceType: String // "barcode", "ocr"
    
    // Dietary compliance
    let isSafe: Bool
    let violationsCount: Int
    let violations: [String]
    
    // Environmental impact
    let co2Emissions: Double
    let waterUsage: Double
    let animalImpact: String // "Low", "Medium", "High"
    
    // Health metrics
    let healthScore: Double
    let concernsCount: Int
    
    // Purchase decision (key for accurate impact tracking)
    let purchaseDecision: PurchaseDecision // Did user buy, avoid, or choose alternative?
    let alternativeName: String?
    let alternativeCO2: Double?           // Actual CO2 of alternative (for accurate savings)
    let alternativeWater: Double?         // Actual water usage of alternative
    let selectedAlternativeIndex: Int?    // Which alternative user chose (0, 1, 2, etc.)
    let priceComparison: String?          // "similar", "higher", "lower" or actual price difference
    let decisionTimestamp: Date?          // When user made the purchase decision
    let needsReview: Bool                 // Flag for untracked scans (batch review)
    
    init(id: UUID = UUID(),
         timestamp: Date = Date(),
         productName: String,
         barcode: String?,
         sourceType: String,
         isSafe: Bool,
         violationsCount: Int,
         violations: [String],
         co2Emissions: Double,
         waterUsage: Double,
         animalImpact: String,
         healthScore: Double,
         concernsCount: Int,
         purchaseDecision: PurchaseDecision,
         alternativeName: String? = nil,
         alternativeCO2: Double? = nil,
         alternativeWater: Double? = nil,
         selectedAlternativeIndex: Int? = nil,
         priceComparison: String? = nil,
         decisionTimestamp: Date? = nil,
         needsReview: Bool = false) {
        self.id = id
        self.timestamp = timestamp
        self.productName = productName
        self.barcode = barcode
        self.sourceType = sourceType
        self.isSafe = isSafe
        self.violationsCount = violationsCount
        self.violations = violations
        self.co2Emissions = co2Emissions
        self.waterUsage = waterUsage
        self.animalImpact = animalImpact
        self.healthScore = healthScore
        self.concernsCount = concernsCount
        self.purchaseDecision = purchaseDecision
        self.alternativeName = alternativeName
        self.alternativeCO2 = alternativeCO2
        self.alternativeWater = alternativeWater
        self.selectedAlternativeIndex = selectedAlternativeIndex
        self.priceComparison = priceComparison
        self.decisionTimestamp = decisionTimestamp
        self.needsReview = needsReview
    }
    
    // Create from AnalysisResult
    init(from result: AnalysisResult) {
        self.id = result.id  // ✅ Use the same ID from AnalysisResult
        self.timestamp = result.timestamp ?? Date()
        self.productName = result.productName
        self.barcode = result.sourceBarcode
        self.sourceType = result.sourceType ?? "ocr"
        self.isSafe = result.isSafe
        self.violationsCount = result.violations.count
        self.violations = result.violations
        self.co2Emissions = result.co2Emissions
        self.waterUsage = result.waterUsage
        self.animalImpact = result.animalImpact
        self.healthScore = result.healthScore
        self.concernsCount = result.healthConcerns.count
        // Default: just scanned, no purchase decision yet
        self.purchaseDecision = .scanned
        self.alternativeName = nil
        self.alternativeCO2 = nil
        self.alternativeWater = nil
        self.selectedAlternativeIndex = nil
        self.priceComparison = nil
        self.decisionTimestamp = nil
        self.needsReview = true  // Mark for batch review
    }
}

// Impact statistics
struct ImpactStats: Codable, Equatable {
    let totalScans: Int
    let safeProducts: Int
    let violatedProducts: Int
    
    // Purchase-based metrics
    let productsPurchased: Int    // Actual purchases
    let productsAvoided: Int       // Avoided due to violations
    let alternativesChosen: Int    // Switched to alternatives
    
    // Accurate environmental impact
    let totalCO2Saved: Double      // CO2 from avoided + alternative savings
    let totalWaterSaved: Double    // Water from avoided + alternative savings
    let yourCO2Footprint: Double   // CO2 from products you bought
    let yourWaterFootprint: Double // Water from products you bought
    
    // Health metrics
    let averageHealthScore: Double  // Average health score of purchased products
    let healthyChoicesCount: Int    // Products with health score >= 7.0
    let unhealthyChoicesCount: Int  // Products with health score < 5.0
    
    // Legacy metrics
    let animalsSpared: Int
    let healthImprovements: Int
    let currentStreak: Int
    let longestStreak: Int
    let startDate: Date
    
    var complianceRate: Double {
        guard totalScans > 0 else { return 0 }
        return Double(safeProducts) / Double(totalScans) * 100
    }
    
    var averageCO2PerScan: Double {
        guard totalScans > 0 else { return 0 }
        // If user has purchased products, show average footprint per purchase
        // Otherwise, show average CO2 saved per avoided/alternative scan
        if productsPurchased > 0 {
            return yourCO2Footprint / Double(productsPurchased)
        } else if (productsAvoided + alternativesChosen) > 0 {
            return totalCO2Saved / Double(productsAvoided + alternativesChosen)
        } else {
            return 0
        }
    }
    
    var averageWaterPerScan: Double {
        guard totalScans > 0 else { return 0 }
        // If user has purchased products, show average water footprint per purchase
        // Otherwise, show average water saved per avoided/alternative scan
        if productsPurchased > 0 {
            return yourWaterFootprint / Double(productsPurchased)
        } else if (productsAvoided + alternativesChosen) > 0 {
            return totalWaterSaved / Double(productsAvoided + alternativesChosen)
        } else {
            return 0
        }
    }
}

// Achievement types
enum Achievement: String, CaseIterable {
    case firstScan = "First Scan"
    case tenScans = "Explorer"
    case fiftyScans = "Analyzer"
    case hundredScans = "Master Scanner"
    case weekStreak = "7-Day Streak"
    case monthStreak = "Monthly Dedication"
    case plantPioneer = "Plant Pioneer"
    case ecoWarrior = "Eco Warrior"
    case healthChampion = "Health Champion"
    case perfectWeek = "Perfect Week"
    
    var title: String {
        return self.rawValue
    }
    
    var icon: String {
        switch self {
        case .firstScan: return "🎉"
        case .tenScans: return "🔍"
        case .fiftyScans: return "⭐"
        case .hundredScans: return "👑"
        case .weekStreak: return "🔥"
        case .monthStreak: return "💎"
        case .plantPioneer: return "🌱"
        case .ecoWarrior: return "🌍"
        case .healthChampion: return "💪"
        case .perfectWeek: return "✨"
        }
    }
    
    var description: String {
        switch self {
        case .firstScan: return "Completed your first scan"
        case .tenScans: return "Scanned 10 products"
        case .fiftyScans: return "Scanned 50 products"
        case .hundredScans: return "Scanned 100 products"
        case .weekStreak: return "Scanned products for 7 days in a row"
        case .monthStreak: return "Scanned products for 30 days in a row"
        case .plantPioneer: return "Made 10 plant-based choices"
        case .ecoWarrior: return "Saved 100kg of CO₂"
        case .healthChampion: return "Avoided 50 concerning ingredients"
        case .perfectWeek: return "7 days with only safe products"
        }
    }
}
