//
//  TasteProfileService.swift
//  Ethica
//
//  Service to learn and predict user's taste preferences
//

import Foundation
import SQLite

class TasteProfileService {
    static let shared = TasteProfileService()
    private let db: Connection?
    
    private func requireDb() throws -> Connection {
        guard let db = db else {
            throw NSError(domain: "TasteProfileService", code: -1, userInfo: [NSLocalizedDescriptionKey: "Database unavailable"])
        }
        return db
    }
    private var cachedProfile: TasteProfile?

    private init() {
        self.db = DatabaseManager.shared.db
        guard let db = db else {
            AppLogger.warning("⚠️ TasteProfileService: Database unavailable, taste profiling disabled")
            return
        }
        do {
            try TasteDataPoint.createTable(db: db)
        } catch {
            AppLogger.error("❌ Error creating taste profile tables: \(error)")
        }
    }

    // MARK: - Record Taste Data

    func recordTasteData(from result: AnalysisResult, userKept: Bool? = nil) async {
        do {
            let dataPoint = extractTasteCharacteristics(from: result, userKept: userKept)
            try saveTasteDataPoint(dataPoint)

            // Update profile asynchronously
            Task {
                await updateTasteProfile()
            }
        } catch {
            AppLogger.error("❌ Error recording taste data: \(error)")
        }
    }

    private func extractTasteCharacteristics(from result: AnalysisResult, userKept: Bool?) -> TasteDataPoint {
        // Extract taste characteristics from product analysis
        // This uses heuristics based on ingredients, nutrition, and categories

        var sweetness: Double? = nil
        var saltiness: Double? = nil
        var savoriness: Double? = nil
        var sourness: Double? = nil
        var bitterness: Double? = nil
        var spiciness: Double? = nil

        // No nutrition data on AnalysisResult - taste estimates from keywords only



        // Extract from product name/ingredients keywords
        let productNameLower = result.productName.lowercased()
        let ingredientsLower = result.ingredients.joined(separator: ", ").lowercased()

        // Spicy indicators
        if productNameLower.contains("spicy") || productNameLower.contains("hot") ||
           ingredientsLower.contains("chili") || ingredientsLower.contains("pepper") {
            spiciness = 70
        }

        // Sour indicators
        if productNameLower.contains("sour") || productNameLower.contains("lemon") ||
           productNameLower.contains("vinegar") || ingredientsLower.contains("citric acid") {
            sourness = 70
        }

        // Bitter indicators
        if productNameLower.contains("coffee") || productNameLower.contains("dark chocolate") ||
           ingredientsLower.contains("cocoa") {
            bitterness = 70
        }

        // Texture estimation
        var crunchiness: Double? = nil
        var creaminess: Double? = nil
        var chewiness: Double? = nil

        if productNameLower.contains("crispy") || productNameLower.contains("crunchy") ||
           productNameLower.contains("chips") {
            crunchiness = 80
        }

        if productNameLower.contains("cream") || productNameLower.contains("smooth") ||
           productNameLower.contains("yogurt") || ingredientsLower.contains("cream") {
            creaminess = 80
        }

        if productNameLower.contains("chewy") || productNameLower.contains("gummy") ||
           productNameLower.contains("jerky") {
            chewiness = 80
        }

        // Category detection
        let isMeatAlternative = productNameLower.contains("beyond") ||
                                productNameLower.contains("impossible") ||
                                productNameLower.contains("tofu") ||
                                productNameLower.contains("tempeh") ||
                                result.productName.lowercased().contains("veggie burger")

        let isDairyAlternative = productNameLower.contains("almond milk") ||
                                 productNameLower.contains("oat milk") ||
                                 productNameLower.contains("soy milk") ||
                                 productNameLower.contains("coconut milk") ||
                                 productNameLower.contains("vegan cheese")

        let isOrganic = productNameLower.contains("organic") ||
                       result.certifications?.contains { $0.lowercased().contains("organic") } ?? false

        let isLocal = result.productName.lowercased().contains("local") ||
                     result.productName.lowercased().contains("farm")

        // Processed food estimation (higher NOVA group = more processed)
        let isProcessed = result.processingLevel?.lowercased().contains("ultra") == true

        return TasteDataPoint(
            productName: result.productName,
            timestamp: Date(),
            userRating: nil, // Will be updated when user leaves a review
            userKept: userKept,
            sweetness: sweetness,
            saltiness: saltiness,
            savoriness: savoriness,
            sourness: sourness,
            bitterness: bitterness,
            spiciness: spiciness,
            crunchiness: crunchiness,
            creaminess: creaminess,
            chewiness: chewiness,
            isMeatAlternative: isMeatAlternative,
            isDairyAlternative: isDairyAlternative,
            isProcessed: isProcessed,
            isOrganic: isOrganic,
            isLocal: isLocal,
            sugarContent: nil,
            saltContent: nil,
            proteinContent: nil,
            fiberContent: nil
        )
    }

    private func saveTasteDataPoint(_ dataPoint: TasteDataPoint) throws {
        guard let db = self.db else { return }
        let insert = TasteDataPoint.table.insert(
            TasteDataPoint.productNameCol <- dataPoint.productName,
            TasteDataPoint.timestampCol <- dataPoint.timestamp,
            TasteDataPoint.userRatingCol <- dataPoint.userRating,
            TasteDataPoint.userKeptCol <- dataPoint.userKept,
            TasteDataPoint.sweetnessCol <- dataPoint.sweetness,
            TasteDataPoint.saltinessCol <- dataPoint.saltiness,
            TasteDataPoint.savorinessCol <- dataPoint.savoriness,
            TasteDataPoint.sournessCol <- dataPoint.sourness,
            TasteDataPoint.bitternessCol <- dataPoint.bitterness,
            TasteDataPoint.spicinessCol <- dataPoint.spiciness,
            TasteDataPoint.crunchinessCol <- dataPoint.crunchiness,
            TasteDataPoint.creaminessCol <- dataPoint.creaminess,
            TasteDataPoint.chewinessCol <- dataPoint.chewiness,
            TasteDataPoint.isMeatAlternativeCol <- dataPoint.isMeatAlternative,
            TasteDataPoint.isDairyAlternativeCol <- dataPoint.isDairyAlternative,
            TasteDataPoint.isProcessedCol <- dataPoint.isProcessed,
            TasteDataPoint.isOrganicCol <- dataPoint.isOrganic,
            TasteDataPoint.isLocalCol <- dataPoint.isLocal,
            TasteDataPoint.sugarContentCol <- dataPoint.sugarContent,
            TasteDataPoint.saltContentCol <- dataPoint.saltContent,
            TasteDataPoint.proteinContentCol <- dataPoint.proteinContent,
            TasteDataPoint.fiberContentCol <- dataPoint.fiberContent
        )

        try db.run(insert)
        AppLogger.debug("✅ Taste data point saved: \(dataPoint.productName)")
    }

    // MARK: - Update Taste Profile

    func updateTasteProfile() async {
        do {
            let dataPoints = try fetchAllTasteDataPoints()

            guard !dataPoints.isEmpty else {
                cachedProfile = TasteProfile.default
                return
            }

            // Only consider products user kept or rated highly
            let positiveDataPoints = dataPoints.filter { point in
                if let kept = point.userKept, kept { return true }
                if let rating = point.userRating, rating >= 4.0 { return true }
                return false
            }

            // If no positive feedback yet, use all data points with less confidence
            let relevantDataPoints = positiveDataPoints.isEmpty ? dataPoints : positiveDataPoints

            // Calculate preferences based on weighted averages
            let profile = calculateTasteProfile(from: relevantDataPoints, allDataPoints: dataPoints)
            cachedProfile = profile

            AppLogger.debug("✅ Taste profile updated: \(profile.profileSummary)")

        } catch {
            AppLogger.error("❌ Error updating taste profile: \(error)")
        }
    }

    private func fetchAllTasteDataPoints() throws -> [TasteDataPoint] {
        guard let db = self.db else { return [] }
        let rows = try db.prepare(TasteDataPoint.table.order(TasteDataPoint.timestampCol.desc))

        return try rows.map { row in
            TasteDataPoint(
                productName: try row.get(TasteDataPoint.productNameCol),
                timestamp: try row.get(TasteDataPoint.timestampCol),
                userRating: try row.get(TasteDataPoint.userRatingCol),
                userKept: try row.get(TasteDataPoint.userKeptCol),
                sweetness: try row.get(TasteDataPoint.sweetnessCol),
                saltiness: try row.get(TasteDataPoint.saltinessCol),
                savoriness: try row.get(TasteDataPoint.savorinessCol),
                sourness: try row.get(TasteDataPoint.sournessCol),
                bitterness: try row.get(TasteDataPoint.bitternessCol),
                spiciness: try row.get(TasteDataPoint.spicinessCol),
                crunchiness: try row.get(TasteDataPoint.crunchinessCol),
                creaminess: try row.get(TasteDataPoint.creaminessCol),
                chewiness: try row.get(TasteDataPoint.chewinessCol),
                isMeatAlternative: try row.get(TasteDataPoint.isMeatAlternativeCol),
                isDairyAlternative: try row.get(TasteDataPoint.isDairyAlternativeCol),
                isProcessed: try row.get(TasteDataPoint.isProcessedCol),
                isOrganic: try row.get(TasteDataPoint.isOrganicCol),
                isLocal: try row.get(TasteDataPoint.isLocalCol),
                sugarContent: try row.get(TasteDataPoint.sugarContentCol),
                saltContent: try row.get(TasteDataPoint.saltContentCol),
                proteinContent: try row.get(TasteDataPoint.proteinContentCol),
                fiberContent: try row.get(TasteDataPoint.fiberContentCol)
            )
        }
    }

    private func calculateTasteProfile(from positivePoints: [TasteDataPoint], allDataPoints: [TasteDataPoint]) -> TasteProfile {
        let totalScans = allDataPoints.count

        // Calculate weighted averages for each dimension
        func weightedAverage(_ values: [Double?]) -> Double {
            let validValues = values.compactMap { $0 }
            guard !validValues.isEmpty else { return 50.0 } // Neutral default
            return validValues.reduce(0, +) / Double(validValues.count)
        }

        let sweetnessPreference = weightedAverage(positivePoints.map { $0.sweetness })
        let saltyPreference = weightedAverage(positivePoints.map { $0.saltiness })
        let savoryPreference = weightedAverage(positivePoints.map { $0.savoriness })
        let sourPreference = weightedAverage(positivePoints.map { $0.sourness })
        let bitterPreference = weightedAverage(positivePoints.map { $0.bitterness })
        let spicyPreference = weightedAverage(positivePoints.map { $0.spiciness })

        let crunchyPreference = weightedAverage(positivePoints.map { $0.crunchiness })
        let creamyPreference = weightedAverage(positivePoints.map { $0.creaminess })
        let chewyPreference = weightedAverage(positivePoints.map { $0.chewiness })

        // Category preferences (% of kept products that fall into category)
        let meatAltPreference = (Double(positivePoints.filter { $0.isMeatAlternative }.count) / Double(max(1, positivePoints.count))) * 100
        let dairyAltPreference = (Double(positivePoints.filter { $0.isDairyAlternative }.count) / Double(max(1, positivePoints.count))) * 100
        let processedPreference = (Double(positivePoints.filter { $0.isProcessed }.count) / Double(max(1, positivePoints.count))) * 100
        let organicPreference = (Double(positivePoints.filter { $0.isOrganic }.count) / Double(max(1, positivePoints.count))) * 100
        let localPreference = (Double(positivePoints.filter { $0.isLocal }.count) / Double(max(1, positivePoints.count))) * 100

        // Confidence based on number of data points (sigmoid curve)
        let confidence = 1.0 / (1.0 + exp(-Double(totalScans) / 10.0 + 2.0)) // Reaches ~0.9 at 50 scans

        return TasteProfile(
            sweetnessPreference: sweetnessPreference,
            saltyPreference: saltyPreference,
            savoryPreference: savoryPreference,
            sourPreference: sourPreference,
            bitterPreference: bitterPreference,
            spicyPreference: spicyPreference,
            crunchyPreference: crunchyPreference,
            creamyPreference: creamyPreference,
            chewyPreference: chewyPreference,
            meatAlternativesPreference: meatAltPreference,
            dairyAlternativesPreference: dairyAltPreference,
            processedFoodsPreference: processedPreference,
            organicPreference: organicPreference,
            localPreference: localPreference,
            totalScansAnalyzed: totalScans,
            lastUpdated: Date(),
            confidence: confidence
        )
    }

    // MARK: - Get Taste Profile

    func getTasteProfile() async -> TasteProfile {
        if let cached = cachedProfile {
            // Return cached if recent (< 1 hour old)
            if Date().timeIntervalSince(cached.lastUpdated) < 3600 {
                return cached
            }
        }

        await updateTasteProfile()
        return cachedProfile ?? TasteProfile.default
    }

    // MARK: - Taste Compatibility Score

    func calculateTasteCompatibility(for alternative: AnalysisResult.Alternative, userProfile: TasteProfile) -> Double {
        // Create a temporary datapoint for the alternative
        // In production, this would be fetched from backend or calculated more accurately
        let productNameLower = alternative.name.lowercased()

        var compatibilityScore: Double = 50.0 // Start neutral

        // Check category compatibility
        if productNameLower.contains("beyond") || productNameLower.contains("impossible") {
            // Meat alternative
            compatibilityScore += (userProfile.meatAlternativesPreference - 50) * 0.3
        }

        if productNameLower.contains("almond milk") || productNameLower.contains("oat milk") {
            // Dairy alternative
            compatibilityScore += (userProfile.dairyAlternativesPreference - 50) * 0.3
        }

        if productNameLower.contains("organic") {
            compatibilityScore += (userProfile.organicPreference - 50) * 0.2
        }

        // Ensure score is in 0-100 range
        compatibilityScore = max(0, min(100, compatibilityScore))

        return compatibilityScore
    }

    // MARK: - Adjust Alternative Ranking

    func adjustAlternativeRankings(alternatives: [AnalysisResult.Alternative]) async -> [AnalysisResult.Alternative] {
        let profile = await getTasteProfile()

        // Only apply if confidence is high enough
        guard profile.confidence > 0.3 else {
            return alternatives // Not enough data yet
        }

        // Calculate taste compatibility for each alternative
        var rankedAlternatives = alternatives.map { alternative in
            (alternative: alternative, tasteScore: calculateTasteCompatibility(for: alternative, userProfile: profile))
        }

        // Sort by taste score (higher = better match)
        rankedAlternatives.sort { $0.tasteScore > $1.tasteScore }

        AppLogger.debug("🎯 Adjusted alternative rankings based on taste profile (confidence: \(Int(profile.confidence * 100))%)")

        return rankedAlternatives.map { $0.alternative }
    }
}
