//
//  TasteProfile.swift
//  Ethica
//
//  Taste profile model for learning user's food preferences
//

import Foundation
import SQLite

struct TasteProfile: Codable {
    // Taste dimensions (1-100 scale)
    let sweetnessPreference: Double // 0 = dislikes sweet, 100 = loves sweet
    let saltyPreference: Double
    let savoryPreference: Double  // Umami
    let sourPreference: Double
    let bitterPreference: Double
    let spicyPreference: Double

    // Texture preferences
    let crunchyPreference: Double
    let creamyPreference: Double
    let chewyPreference: Double

    // Food category preferences
    let meatAlternativesPreference: Double // How much they like meat alternatives
    let dairyAlternativesPreference: Double
    let processedFoodsPreference: Double // Prefer highly processed or minimally processed

    // Dietary patterns
    let organicPreference: Double // Prefer organic products
    let localPreference: Double // Prefer local/seasonal products

    // Learning metadata
    let totalScansAnalyzed: Int
    let lastUpdated: Date
    let confidence: Double // 0-1, based on number of data points

    // Computed properties
    var dominantTaste: String {
        let tastes = [
            ("Sweet", sweetnessPreference),
            ("Salty", saltyPreference),
            ("Savory", savoryPreference),
            ("Sour", sourPreference),
            ("Bitter", bitterPreference),
            ("Spicy", spicyPreference)
        ]
        return tastes.max(by: { $0.1 < $1.1 })?.0 ?? "Balanced"
    }

    var dominantTexture: String {
        let textures = [
            ("Crunchy", crunchyPreference),
            ("Creamy", creamyPreference),
            ("Chewy", chewyPreference)
        ]
        return textures.max(by: { $0.1 < $1.1 })?.0 ?? "Varied"
    }

    var profileSummary: String {
        var summary = "You prefer \(dominantTaste.lowercased()) flavors"

        if confidence > 0.7 {
            summary += " and \(dominantTexture.lowercased()) textures"
        }

        if organicPreference > 70 {
            summary += ". Strong preference for organic products"
        }

        return summary + "."
    }
}

// MARK: - Taste Profile Data Point (Individual Scan)

struct TasteDataPoint: Codable {
    let productName: String
    let timestamp: Date
    let userRating: Double? // If user reviewed/rated the product
    let userKept: Bool? // true if bought, false if avoided, nil if unknown

    // Extracted taste characteristics from product
    let sweetness: Double?
    let saltiness: Double?
    let savoriness: Double?
    let sourness: Double?
    let bitterness: Double?
    let spiciness: Double?

    // Texture characteristics
    let crunchiness: Double?
    let creaminess: Double?
    let chewiness: Double?

    // Category flags
    let isMeatAlternative: Bool
    let isDairyAlternative: Bool
    let isProcessed: Bool
    let isOrganic: Bool
    let isLocal: Bool

    // Nutrition summary
    let sugarContent: Double? // g per 100g
    let saltContent: Double? // mg per 100g
    let proteinContent: Double?
    let fiberContent: Double?

    static let table = Table("taste_data_points")
    static let productNameCol = Expression<String>("product_name")
    static let timestampCol = Expression<Date>("timestamp")
    static let userRatingCol = Expression<Double?>("user_rating")
    static let userKeptCol = Expression<Bool?>("user_kept")

    static let sweetnessCol = Expression<Double?>("sweetness")
    static let saltinessCol = Expression<Double?>("saltiness")
    static let savorinessCol = Expression<Double?>("savoriness")
    static let sournessCol = Expression<Double?>("sourness")
    static let bitternessCol = Expression<Double?>("bitterness")
    static let spicinessCol = Expression<Double?>("spiciness")

    static let crunchinessCol = Expression<Double?>("crunchiness")
    static let creaminessCol = Expression<Double?>("creaminess")
    static let chewinessCol = Expression<Double?>("chewiness")

    static let isMeatAlternativeCol = Expression<Bool>("is_meat_alternative")
    static let isDairyAlternativeCol = Expression<Bool>("is_dairy_alternative")
    static let isProcessedCol = Expression<Bool>("is_processed")
    static let isOrganicCol = Expression<Bool>("is_organic")
    static let isLocalCol = Expression<Bool>("is_local")

    static let sugarContentCol = Expression<Double?>("sugar_content")
    static let saltContentCol = Expression<Double?>("salt_content")
    static let proteinContentCol = Expression<Double?>("protein_content")
    static let fiberContentCol = Expression<Double?>("fiber_content")

    static func createTable(db: Connection) throws {
        try db.run(table.create(ifNotExists: true) { t in
            t.column(productNameCol)
            t.column(timestampCol)
            t.column(userRatingCol)
            t.column(userKeptCol)

            t.column(sweetnessCol)
            t.column(saltinessCol)
            t.column(savorinessCol)
            t.column(sournessCol)
            t.column(bitternessCol)
            t.column(spicinessCol)

            t.column(crunchinessCol)
            t.column(creaminessCol)
            t.column(chewinessCol)

            t.column(isMeatAlternativeCol, defaultValue: false)
            t.column(isDairyAlternativeCol, defaultValue: false)
            t.column(isProcessedCol, defaultValue: false)
            t.column(isOrganicCol, defaultValue: false)
            t.column(isLocalCol, defaultValue: false)

            t.column(sugarContentCol)
            t.column(saltContentCol)
            t.column(proteinContentCol)
            t.column(fiberContentCol)
        })

        // Index for faster queries
        try db.run(table.createIndex(timestampCol, ifNotExists: true))
    }
}

// MARK: - Default Profile

extension TasteProfile {
    static let `default` = TasteProfile(
        sweetnessPreference: 50,
        saltyPreference: 50,
        savoryPreference: 50,
        sourPreference: 50,
        bitterPreference: 50,
        spicyPreference: 50,
        crunchyPreference: 50,
        creamyPreference: 50,
        chewyPreference: 50,
        meatAlternativesPreference: 50,
        dairyAlternativesPreference: 50,
        processedFoodsPreference: 50,
        organicPreference: 50,
        localPreference: 50,
        totalScansAnalyzed: 0,
        lastUpdated: Date(),
        confidence: 0.0
    )
}
