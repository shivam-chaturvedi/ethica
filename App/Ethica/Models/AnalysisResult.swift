//  AnalysisResult.swift
//  Ethica
//
//  Created on 11/11/2025
//

import Foundation

struct AnalysisResult: Identifiable, Codable, Equatable {
    static func == (lhs: AnalysisResult, rhs: AnalysisResult) -> Bool {
        return lhs.id == rhs.id &&
            lhs.productName == rhs.productName &&
            lhs.overallScore == rhs.overallScore &&
            lhs.isSafe == rhs.isSafe &&
            lhs.confidence == rhs.confidence &&
            lhs.confidenceFactors == rhs.confidenceFactors &&
            lhs.violations == rhs.violations &&
            lhs.warnings == rhs.warnings &&
            lhs.cautionWarnings == rhs.cautionWarnings &&
            lhs.ingredients == rhs.ingredients &&
            lhs.detectedAllergens == rhs.detectedAllergens &&
            lhs.detectionEvidence == rhs.detectionEvidence &&
            lhs.healthScore == rhs.healthScore &&
            lhs.environmentalScore == rhs.environmentalScore &&
            lhs.co2Emissions == rhs.co2Emissions &&
            lhs.waterUsage == rhs.waterUsage &&
            lhs.animalImpact == rhs.animalImpact &&
            lhs.landUse == rhs.landUse &&
            lhs.nutritionalHighlights == rhs.nutritionalHighlights &&
            lhs.healthConcerns == rhs.healthConcerns &&
            lhs.healthBenefits == rhs.healthBenefits &&
            lhs.recommendations == rhs.recommendations &&
            lhs.alternatives == rhs.alternatives &&
            lhs.environmentalBreakdown == rhs.environmentalBreakdown &&
            lhs.brand == rhs.brand &&
            lhs.certifications == rhs.certifications &&
            lhs.processingLevel == rhs.processingLevel &&
            lhs.estimatedCO2 == rhs.estimatedCO2 &&
            lhs.packagingScore == rhs.packagingScore &&
            lhs.animalWelfareScore == rhs.animalWelfareScore &&
            lhs.packageWeightGrams == rhs.packageWeightGrams &&
            lhs.sourceBarcode == rhs.sourceBarcode &&
            lhs.sourceType == rhs.sourceType &&
            lhs.isRestaurantMenu == rhs.isRestaurantMenu &&
            lhs.menuDishes == rhs.menuDishes &&
            lhs.safetyConfidenceExplanation == rhs.safetyConfidenceExplanation &&
            lhs.ingredientEducation == rhs.ingredientEducation &&
            lhs.crossContaminationRisks == rhs.crossContaminationRisks &&
            lhs.safetyLevel == rhs.safetyLevel &&
            lhs.gmoStatus == rhs.gmoStatus &&
            lhs.nutriscoreGrade == rhs.nutriscoreGrade &&
            lhs.ecoscoreGrade == rhs.ecoscoreGrade &&
            lhs.novaGroup == rhs.novaGroup &&
            lhs.openFoodFactsDetails == rhs.openFoodFactsDetails
    }

    // MARK: - OpenFoodFacts Transparency (raw fields)
    struct OpenFoodFactsDetails: Codable, Equatable {
        struct NutriscoreData: Codable, Equatable {
            struct Components: Codable, Equatable {
                struct ComponentItem: Codable, Equatable {
                    let id: String?
                    let points: Int?
                    let value: Double?
                    let unit: String?
                }
                let negative: [ComponentItem]?
                let positive: [ComponentItem]?
            }

            let negativePoints: Int?
            let positivePoints: Int?
            let components: Components?

            enum CodingKeys: String, CodingKey {
                case negativePoints = "negative_points"
                case positivePoints = "positive_points"
                case components
            }
        }

        let allergens: String?
        let allergensTags: [String]?
        let allergensFromIngredients: String?
        let traces: String?
        let tracesTags: [String]?
        let ingredientsText: String?
        let ingredientsTextEn: String?
        let nutriscoreData: NutriscoreData?

        enum CodingKeys: String, CodingKey {
            case allergens
            case allergensTags = "allergens_tags"
            case allergensFromIngredients = "allergens_from_ingredients"
            case traces
            case tracesTags = "traces_tags"
            case ingredientsText = "ingredients_text"
            case ingredientsTextEn = "ingredients_text_en"
            case nutriscoreData = "nutriscore_data"
        }
    }
    var id: UUID
    let productName: String
    let overallScore: Double
    let isSafe: Bool
    let confidence: Double
    let confidenceFactors: [String]
    let safetyConfidenceExplanation: SafetyConfidenceExplanation?
    let ingredientEducation: [IngredientEducation]?
    let crossContaminationRisks: [CrossContaminationRisk]?
    let violations: [String]
    let warnings: [String]
    let cautionWarnings: [String]
    let ingredients: [String]
    let detectedAllergens: [String]
    let detectionEvidence: [DetectionEvidence]
    let healthScore: Double
    let environmentalScore: Double
    let co2Emissions: Double
    let waterUsage: Double
    let animalImpact: String
    let landUse: String
    let nutritionalHighlights: [String]
    let healthConcerns: [String]
    let healthBenefits: [String]
    let recommendations: [String]
    let alternatives: [Alternative]
    let environmentalBreakdown: [EnvironmentalBreakdown]

    // Additional product metadata
    let brand: String?
    let certifications: [String]?
    let processingLevel: String?

    // Additional environmental metrics
    let estimatedCO2: Double
    let packagingScore: Double
    let animalWelfareScore: Double

    // Detailed additives breakdown (Yuka-style)
    let additives: [AdditiveInfo]
    
    // Package weight for accurate total CO2 calculations
    let packageWeightGrams: Double?
    
    // Product database tracking
    let sourceBarcode: String?
    let sourceType: String? // "cache", "openfoodfacts", "ocr"
    let timestamp: Date?
    
    // Backend-authoritative safety & nutrition metadata
    let safetyLevel: String?      // "safe" | "caution" | "avoid"
    let gmoStatus: String?        // "confirmed_gmo" | "non_gmo_certified" | "high_risk_unknown" | "no_risk"
    let nutriscoreGrade: String?  // "a" through "e"
    let ecoscoreGrade: String?    // "a" through "e"
    let novaGroup: Int?           // 1-4 (food processing level)

    // Optional OpenFoodFacts raw fields for transparency/debugging
    let openFoodFactsDetails: OpenFoodFactsDetails?

    // Restaurant menu tracking
    let isRestaurantMenu: Bool?
    let menuDishes: [MenuDish]?

    // Lazy-loading metadata for alternatives (when alternatives are deferred)
    let alternativesMetadata: AlternativesMetadata?
    
    // Memberwise initializer
    init(id: UUID = UUID(), productName: String, overallScore: Double, isSafe: Bool,
         confidence: Double, confidenceFactors: [String], violations: [String],
         warnings: [String], cautionWarnings: [String], ingredients: [String],
         detectedAllergens: [String], detectionEvidence: [DetectionEvidence],
         healthScore: Double, environmentalScore: Double, co2Emissions: Double,
         waterUsage: Double, animalImpact: String, landUse: String,
         nutritionalHighlights: [String], healthConcerns: [String], healthBenefits: [String],
         recommendations: [String], alternatives: [Alternative], environmentalBreakdown: [EnvironmentalBreakdown],
         brand: String? = nil, certifications: [String]? = nil, processingLevel: String? = nil,
         estimatedCO2: Double = 0, packagingScore: Double = 0, animalWelfareScore: Double = 0,
         additives: [AdditiveInfo] = [],
         packageWeightGrams: Double? = nil,
         sourceBarcode: String? = nil, sourceType: String? = nil, timestamp: Date? = nil,
         safetyLevel: String? = nil, gmoStatus: String? = nil,
         nutriscoreGrade: String? = nil, ecoscoreGrade: String? = nil, novaGroup: Int? = nil,
         openFoodFactsDetails: OpenFoodFactsDetails? = nil,
         isRestaurantMenu: Bool? = nil, menuDishes: [MenuDish]? = nil,
         safetyConfidenceExplanation: SafetyConfidenceExplanation? = nil,
         ingredientEducation: [IngredientEducation]? = nil,
         crossContaminationRisks: [CrossContaminationRisk]? = nil,
         alternativesMetadata: AlternativesMetadata? = nil) {
        self.id = id
        self.productName = productName
        self.overallScore = overallScore
        self.isSafe = isSafe
        self.confidence = confidence
        self.confidenceFactors = confidenceFactors
        self.violations = violations
        self.warnings = warnings
        self.cautionWarnings = cautionWarnings
        self.ingredients = ingredients
        self.detectedAllergens = detectedAllergens
        self.detectionEvidence = detectionEvidence
        self.healthScore = healthScore
        self.environmentalScore = environmentalScore
        self.co2Emissions = co2Emissions
        self.waterUsage = waterUsage
        self.animalImpact = animalImpact
        self.landUse = landUse
        self.nutritionalHighlights = nutritionalHighlights
        self.healthConcerns = healthConcerns
        self.healthBenefits = healthBenefits
        self.recommendations = recommendations
        self.alternatives = alternatives
        self.environmentalBreakdown = environmentalBreakdown
        self.brand = brand
        self.certifications = certifications
        self.processingLevel = processingLevel
        self.estimatedCO2 = estimatedCO2
        self.packagingScore = packagingScore
        self.animalWelfareScore = animalWelfareScore
        self.additives = additives
        self.packageWeightGrams = packageWeightGrams
        self.sourceBarcode = sourceBarcode
        self.sourceType = sourceType
        self.timestamp = timestamp
        self.safetyLevel = safetyLevel
        self.gmoStatus = gmoStatus
        self.nutriscoreGrade = nutriscoreGrade
        self.ecoscoreGrade = ecoscoreGrade
        self.novaGroup = novaGroup
        self.openFoodFactsDetails = openFoodFactsDetails
        self.isRestaurantMenu = isRestaurantMenu
        self.menuDishes = menuDishes
        self.safetyConfidenceExplanation = safetyConfidenceExplanation
        self.ingredientEducation = ingredientEducation
        self.crossContaminationRisks = crossContaminationRisks
        self.alternativesMetadata = alternativesMetadata
    }

    /// Return a copy with lazy-loaded alternatives merged in
    func withAlternatives(_ alts: [Alternative]) -> AnalysisResult {
        AnalysisResult(
            id: id, productName: productName, overallScore: overallScore, isSafe: isSafe,
            confidence: confidence, confidenceFactors: confidenceFactors, violations: violations,
            warnings: warnings, cautionWarnings: cautionWarnings, ingredients: ingredients,
            detectedAllergens: detectedAllergens, detectionEvidence: detectionEvidence,
            healthScore: healthScore, environmentalScore: environmentalScore, co2Emissions: co2Emissions,
            waterUsage: waterUsage, animalImpact: animalImpact, landUse: landUse,
            nutritionalHighlights: nutritionalHighlights, healthConcerns: healthConcerns,
            healthBenefits: healthBenefits, recommendations: recommendations,
            alternatives: alts, environmentalBreakdown: environmentalBreakdown,
            brand: brand, certifications: certifications, processingLevel: processingLevel,
            estimatedCO2: estimatedCO2, packagingScore: packagingScore, animalWelfareScore: animalWelfareScore,
            additives: additives, packageWeightGrams: packageWeightGrams,
            sourceBarcode: sourceBarcode, sourceType: sourceType, timestamp: timestamp,
            safetyLevel: safetyLevel, gmoStatus: gmoStatus,
            nutriscoreGrade: nutriscoreGrade, ecoscoreGrade: ecoscoreGrade, novaGroup: novaGroup,
            openFoodFactsDetails: openFoodFactsDetails,
            isRestaurantMenu: isRestaurantMenu, menuDishes: menuDishes,
            safetyConfidenceExplanation: safetyConfidenceExplanation,
            ingredientEducation: ingredientEducation,
            crossContaminationRisks: crossContaminationRisks,
            alternativesMetadata: nil
        )
    }

    /// Merge enrichment from enhanced result while preserving safety fields from preliminary (self).
    func mergingEnrichment(from enhanced: AnalysisResult) -> AnalysisResult {
        AnalysisResult(
            id: self.id,
            productName: enhanced.productName,
            overallScore: enhanced.overallScore,
            // Safety — keep from preliminary
            isSafe: self.isSafe,
            confidence: self.confidence,
            confidenceFactors: self.confidenceFactors,
            violations: self.violations,
            warnings: self.warnings,
            cautionWarnings: self.cautionWarnings,
            ingredients: !enhanced.ingredients.isEmpty ? enhanced.ingredients : self.ingredients,
            detectedAllergens: self.detectedAllergens,
            detectionEvidence: self.detectionEvidence,
            // Enrichment — take from enhanced
            healthScore: enhanced.healthScore,
            environmentalScore: enhanced.environmentalScore > 0 ? enhanced.environmentalScore : self.environmentalScore,
            co2Emissions: enhanced.co2Emissions > 0 ? enhanced.co2Emissions : self.co2Emissions,
            waterUsage: enhanced.waterUsage > 0 ? enhanced.waterUsage : self.waterUsage,
            animalImpact: (!enhanced.animalImpact.isEmpty && enhanced.animalImpact != "Unknown") ? enhanced.animalImpact : self.animalImpact,
            landUse: (!enhanced.landUse.isEmpty && enhanced.landUse != "Unknown") ? enhanced.landUse : self.landUse,
            nutritionalHighlights: enhanced.nutritionalHighlights,
            healthConcerns: enhanced.healthConcerns,
            healthBenefits: enhanced.healthBenefits,
            recommendations: enhanced.recommendations,
            alternatives: !enhanced.alternatives.isEmpty ? enhanced.alternatives : self.alternatives,
            environmentalBreakdown: enhanced.environmentalBreakdown,
            brand: enhanced.brand,
            certifications: enhanced.certifications,
            processingLevel: enhanced.processingLevel,
            estimatedCO2: enhanced.estimatedCO2,
            packagingScore: enhanced.packagingScore,
            animalWelfareScore: enhanced.animalWelfareScore,
            additives: enhanced.additives,
            packageWeightGrams: enhanced.packageWeightGrams,
            sourceBarcode: self.sourceBarcode,
            sourceType: enhanced.sourceType,
            timestamp: self.timestamp,
            // Safety — keep from preliminary
            safetyLevel: self.safetyLevel,
            gmoStatus: self.gmoStatus,
            // Data — keep from preliminary (already from OFF)
            nutriscoreGrade: self.nutriscoreGrade,
            ecoscoreGrade: self.ecoscoreGrade,
            novaGroup: self.novaGroup,
            openFoodFactsDetails: self.openFoodFactsDetails ?? enhanced.openFoodFactsDetails,
            isRestaurantMenu: self.isRestaurantMenu,
            menuDishes: self.menuDishes,
            safetyConfidenceExplanation: enhanced.safetyConfidenceExplanation,
            ingredientEducation: enhanced.ingredientEducation,
            crossContaminationRisks: self.crossContaminationRisks,
            alternativesMetadata: enhanced.alternativesMetadata ?? self.alternativesMetadata
        )
    }

    // MARK: - Safety Confidence Explanation
    struct SafetyConfidenceExplanation: Codable, Equatable {
        let overallConfidence: Double
        let confidenceLevel: String  // "Very High", "High", "Medium", "Low", "Very Low"
        let detailedReasons: [String]
        let whatThisMeans: String
        let recommendedAction: String
    }
    
    // MARK: - Ingredient Education
    struct IngredientEducation: Identifiable, Codable, Equatable {
        var id: String { ingredient }
        let ingredient: String
        let whatItIs: String
        let hiddenSources: [String]
        let whyItMatters: String
        let isSafe: Bool?  // true, false, or nil (uncertain)
        let confidence: Double
    }
    
    // MARK: - Cross Contamination Risk
    struct CrossContaminationRisk: Identifiable, Codable, Equatable {
        var id: String { allergen }
        let allergen: String
        let riskLevel: String  // "Low", "Medium", "High", "Very High"
        let riskExplanation: String
        let manufacturingDetails: String
        let guidance: String
    }
    
    // MARK: - Additive Info (Yuka-style breakdown)
    struct AdditiveInfo: Identifiable, Codable, Equatable {
        var id: String { code }
        let code: String           // E.g., "E621", "E250"
        let name: String           // E.g., "MSG (E621)"
        let category: String       // E.g., "Flavor Enhancer", "Preservative"
        let riskLevel: String      // "high", "moderate", "low"
        let description: String    // E.g., "May cause headaches in sensitive individuals"
        let source: String         // E.g., "EFSA", "FDA", "IARC"
        
        // Computed property for color-coding
        var riskColor: String {
            switch riskLevel.lowercased() {
            case "high": return "EF4444"    // Red
            case "moderate": return "F59E0B" // Orange/Amber
            case "low": return "22C55E"     // Green
            default: return "6B7280"        // Gray
            }
        }
        
        var riskIcon: String {
            switch riskLevel.lowercased() {
            case "high": return "exclamationmark.triangle.fill"
            case "moderate": return "exclamationmark.circle.fill"
            case "low": return "checkmark.circle.fill"
            default: return "questionmark.circle.fill"
            }
        }
    }

    struct DetectionEvidence: Codable, Equatable {
        let ingredient: String
        let matchedPreference: String
        let reason: String
        let source: String
        let confidence: Double
        let riskLevel: String?  // "Low", "Medium", "High", "Very High"
        let riskExplanation: String?
        let manufacturingDetails: String?
        let guidance: String?
    }

    struct NutritionFacts: Codable, Equatable {
        let calories: Double?
        let protein: Double?
        let carbs: Double?
        let sugar: Double?
        let fat: Double?
        let fiber: Double?
        let sodium: Double?
    }

    struct Alternative: Identifiable, Codable, Equatable {
        var id: String { "\(name)_\(brand ?? "")" }
        let name: String
        let brand: String?
        let reason: String?
        let imageURL: String?
        let link: String?

        // Environmental data for accurate impact tracking
        let estimatedCO2: Double?  // Estimated CO2 per 100g
        let estimatedWater: Double?  // Estimated water usage per 100g

        // Enriched data from OpenFoodFacts (optional, loaded on-demand)
        let healthScore: Double?  // 0-100 from Nutri-Score or Yuka
        let environmentalScore: Double?  // 0-100 from Eco-Score
        let ethicsScore: Double?  // 0-100 computed from certifications
        let barcode: String?  // For OpenFoodFacts lookup
        let isEnriched: Bool  // True if data from OpenFoodFacts, false if AI estimate
        let dataSource: String?  // "openfoodfacts", "ai_estimate", "cache"

        // Price data
        let price: Double?
        let priceSource: String?  // "openfoodfacts", "estimated", "user_reported"

        // Nutrition comparison
        let nutrition: NutritionFacts?

        enum CodingKeys: String, CodingKey {
            case name, brand, reason, imageURL, link, estimatedCO2, estimatedWater
            case healthScore, environmentalScore, ethicsScore, barcode, isEnriched, dataSource
            case price, priceSource, nutrition
        }

        init(name: String, brand: String?, reason: String?, imageURL: String? = nil, link: String? = nil, estimatedCO2: Double? = nil, estimatedWater: Double? = nil, healthScore: Double? = nil, environmentalScore: Double? = nil, ethicsScore: Double? = nil, barcode: String? = nil, isEnriched: Bool = false, dataSource: String? = nil, price: Double? = nil, priceSource: String? = nil, nutrition: NutritionFacts? = nil) {
            self.name = name
            self.brand = brand
            self.reason = reason
            self.imageURL = imageURL
            self.link = link
            self.estimatedCO2 = estimatedCO2
            self.estimatedWater = estimatedWater
            self.healthScore = healthScore
            self.environmentalScore = environmentalScore
            self.ethicsScore = ethicsScore
            self.barcode = barcode
            self.isEnriched = isEnriched
            self.dataSource = dataSource
            self.price = price
            self.priceSource = priceSource
            self.nutrition = nutrition
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            name = try container.decode(String.self, forKey: .name)
            brand = try container.decodeIfPresent(String.self, forKey: .brand)
            reason = try container.decodeIfPresent(String.self, forKey: .reason)
            imageURL = try container.decodeIfPresent(String.self, forKey: .imageURL)
            link = try container.decodeIfPresent(String.self, forKey: .link)

            // Try to decode environmental data, or estimate if not provided
            if let co2 = try container.decodeIfPresent(Double.self, forKey: .estimatedCO2) {
                estimatedCO2 = co2
            } else {
                // Estimate based on product name
                estimatedCO2 = Self.estimateCO2(from: name)
            }

            if let water = try container.decodeIfPresent(Double.self, forKey: .estimatedWater) {
                estimatedWater = water
            } else {
                estimatedWater = Self.estimateWater(from: name)
            }

            // Decode enriched OpenFoodFacts data
            healthScore = try container.decodeIfPresent(Double.self, forKey: .healthScore)
            environmentalScore = try container.decodeIfPresent(Double.self, forKey: .environmentalScore)
            ethicsScore = try container.decodeIfPresent(Double.self, forKey: .ethicsScore)
            barcode = try container.decodeIfPresent(String.self, forKey: .barcode)
            isEnriched = try container.decodeIfPresent(Bool.self, forKey: .isEnriched) ?? false
            dataSource = try container.decodeIfPresent(String.self, forKey: .dataSource)

            // Decode price and nutrition data
            price = try container.decodeIfPresent(Double.self, forKey: .price)
            priceSource = try container.decodeIfPresent(String.self, forKey: .priceSource)
            nutrition = try container.decodeIfPresent(NutritionFacts.self, forKey: .nutrition)

        }
        
        // Smart estimation based on product type
        static func estimateCO2(from name: String) -> Double {
            let lowercaseName = name.lowercased()
            
            // Plant-based alternatives (lowest impact)
            if lowercaseName.contains("tofu") || lowercaseName.contains("tempeh") ||
               lowercaseName.contains("seitan") || lowercaseName.contains("beans") ||
               lowercaseName.contains("lentil") || lowercaseName.contains("chickpea") ||
               lowercaseName.contains("plant-based") || lowercaseName.contains("vegan") {
                return 0.3 // 0.1-0.5 kg CO2 per 100g
            }
            
            // Nuts, seeds, plant milk
            if lowercaseName.contains("almond") || lowercaseName.contains("oat") ||
               lowercaseName.contains("soy milk") || lowercaseName.contains("nut") {
                return 0.4
            }
            
            // Dairy alternatives
            if lowercaseName.contains("dairy-free") || lowercaseName.contains("cheese alternative") {
                return 0.5
            }
            
            // Fish/seafood (moderate)
            if lowercaseName.contains("fish") || lowercaseName.contains("salmon") ||
               lowercaseName.contains("tuna") || lowercaseName.contains("seafood") {
                return 3.0
            }
            
            // Poultry (moderate-high)
            if lowercaseName.contains("chicken") || lowercaseName.contains("turkey") {
                return 4.0
            }
            
            // Default for unknown alternatives (assume better than original)
            return 1.0
        }
        
        static func estimateWater(from name: String) -> Double {
            let lowercaseName = name.lowercased()
            
            // Plant-based (lowest water use)
            if lowercaseName.contains("tofu") || lowercaseName.contains("tempeh") ||
               lowercaseName.contains("plant-based") || lowercaseName.contains("vegan") ||
               lowercaseName.contains("beans") || lowercaseName.contains("lentil") {
                return 100.0 // 50-200 L per 100g
            }
            
            // Nuts (higher water use)
            if lowercaseName.contains("almond") || lowercaseName.contains("nut") {
                return 250.0
            }
            
            // Oat, soy milk (low-moderate)
            if lowercaseName.contains("oat") || lowercaseName.contains("soy") {
                return 150.0
            }
            
            // Fish/seafood
            if lowercaseName.contains("fish") || lowercaseName.contains("seafood") {
                return 800.0
            }
            
            // Poultry
            if lowercaseName.contains("chicken") || lowercaseName.contains("turkey") {
                return 1200.0
            }
            
            // Default
            return 300.0
        }
    }

    struct EnvironmentalBreakdown: Identifiable, Codable, Equatable {
        var id: String { ingredient }
        let ingredient: String
        let co2: Double?
        let percentage: Double?

        enum CodingKeys: String, CodingKey {
            case ingredient, co2, percentage
        }
    }
    
    struct MenuDish: Identifiable, Codable, Equatable {
        var id: String { dish }
        let dish: String
        let ingredients: [String]
        let safe: Bool
        let warnings: [String]
        let estimatedCO2: Double?

        enum CodingKeys: String, CodingKey {
            case dish, ingredients, safe, warnings, estimatedCO2
        }
    }

    struct AlternativesMetadata: Codable, Equatable {
        let productName: String
        let category: String
        let categoriesTags: [String]
        let sourceBarcode: String?
        let sourceBrand: String?

        init(productName: String, category: String, categoriesTags: [String],
             sourceBarcode: String? = nil, sourceBrand: String? = nil) {
            self.productName = productName
            self.category = category
            self.categoriesTags = categoriesTags
            self.sourceBarcode = sourceBarcode
            self.sourceBrand = sourceBrand
        }
    }

	    enum CodingKeys: String, CodingKey {
	        case id
	        case productName, overallScore, isSafe, violations, warnings, cautionWarnings
	        case confidence, confidenceFactors, safetyConfidenceExplanation
	        case ingredients, detectedAllergens, detectionEvidence, healthScore
	        case environmentalScore, co2Emissions, waterUsage, animalImpact, landUse
	        case nutritionalHighlights, healthConcerns, healthBenefits, recommendations, alternatives
	        case environmentalBreakdown, brand, certifications, processingLevel
	        case estimatedCO2, packagingScore, animalWelfareScore
	        case additives, packageWeightGrams
	        case sourceBarcode, sourceType, timestamp
	        case safetyLevel, gmoStatus, nutriscoreGrade, ecoscoreGrade, novaGroup
	        case openFoodFactsDetails
	        case isRestaurantMenu, menuDishes
	        case ingredientEducation, crossContaminationRisks
	        case alternativesMetadata
	    }

    init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
    productName = try container.decodeIfPresent(String.self, forKey: .productName) ?? "Unknown Product"
    overallScore = try container.decodeIfPresent(Double.self, forKey: .overallScore) ?? 0
    isSafe = try container.decodeIfPresent(Bool.self, forKey: .isSafe) ?? false
        confidence = try container.decodeIfPresent(Double.self, forKey: .confidence) ?? 0
        confidenceFactors = try container.decodeIfPresent([String].self, forKey: .confidenceFactors) ?? []
        safetyConfidenceExplanation = try container.decodeIfPresent(SafetyConfidenceExplanation.self, forKey: .safetyConfidenceExplanation)
        ingredientEducation = try container.decodeIfPresent([IngredientEducation].self, forKey: .ingredientEducation)
        crossContaminationRisks = try container.decodeIfPresent([CrossContaminationRisk].self, forKey: .crossContaminationRisks)
        violations = try container.decodeIfPresent([String].self, forKey: .violations) ?? []
        warnings = try container.decodeIfPresent([String].self, forKey: .warnings) ?? []
        cautionWarnings = try container.decodeIfPresent([String].self, forKey: .cautionWarnings) ?? []
        ingredients = try container.decodeIfPresent([String].self, forKey: .ingredients) ?? []
        detectedAllergens = try container.decodeIfPresent([String].self, forKey: .detectedAllergens) ?? []
        detectionEvidence = try container.decodeIfPresent([DetectionEvidence].self, forKey: .detectionEvidence) ?? []
        healthScore = try container.decodeIfPresent(Double.self, forKey: .healthScore) ?? 0
        environmentalScore = try container.decodeIfPresent(Double.self, forKey: .environmentalScore) ?? 0
        co2Emissions = try container.decodeIfPresent(Double.self, forKey: .co2Emissions) ?? 0
        waterUsage = try container.decodeIfPresent(Double.self, forKey: .waterUsage) ?? 0
        animalImpact = try container.decodeIfPresent(String.self, forKey: .animalImpact) ?? "Medium"
        landUse = try container.decodeIfPresent(String.self, forKey: .landUse) ?? "Medium"
        nutritionalHighlights = try container.decodeIfPresent([String].self, forKey: .nutritionalHighlights) ?? []
        healthConcerns = try container.decodeIfPresent([String].self, forKey: .healthConcerns) ?? []
        healthBenefits = try container.decodeIfPresent([String].self, forKey: .healthBenefits) ?? []
        
        // Recommendations can be either array of strings or dict with categories
        do {
            if let recArray = try container.decodeIfPresent([String].self, forKey: .recommendations) {
                recommendations = recArray
            } else if let recDict = try container.decodeIfPresent([String: [String]].self, forKey: .recommendations) {
                // It's a dict with categories (environmental, health, insights, etc.)
                // Flatten all recommendations into single array
                var allRecs: [String] = []
                if let insights = recDict["insights"] {
                    allRecs += insights
                }
                if let health = recDict["health"] {
                    allRecs += health
                }
                if let environmental = recDict["environmental"] {
                    allRecs += environmental
                }
                if let allergenFree = recDict["allergenFree"] {
                    allRecs += allergenFree
                }
                recommendations = allRecs
            } else {
                recommendations = []
            }
        } catch {
            recommendations = []
        }
        
        // Alternatives may be either array of Alternative objects or array of strings (legacy)
        do {
            if let altObjs = try container.decodeIfPresent([Alternative].self, forKey: .alternatives) {
                alternatives = altObjs
            } else if let altStrings = try container.decodeIfPresent([String].self, forKey: .alternatives) {
                alternatives = altStrings.map { Alternative(name: $0, brand: nil, reason: nil) }
            } else {
                alternatives = []
            }
        } catch {
            if let altStrings = (try? container.decodeIfPresent([String].self, forKey: .alternatives)) ?? nil {
                alternatives = altStrings.map { Alternative(name: $0, brand: nil, reason: nil) }
            } else {
                alternatives = []
            }
        }
        environmentalBreakdown = (try container.decodeIfPresent([EnvironmentalBreakdown].self, forKey: .environmentalBreakdown)) ?? []

        // Product metadata
        brand = try container.decodeIfPresent(String.self, forKey: .brand)
        certifications = try container.decodeIfPresent([String].self, forKey: .certifications)
        processingLevel = try container.decodeIfPresent(String.self, forKey: .processingLevel)

        // Additional environmental metrics
        estimatedCO2 = try container.decodeIfPresent(Double.self, forKey: .estimatedCO2) ?? 0
        packagingScore = try container.decodeIfPresent(Double.self, forKey: .packagingScore) ?? 0
        animalWelfareScore = try container.decodeIfPresent(Double.self, forKey: .animalWelfareScore) ?? 0

        // Additives (Yuka-style breakdown)
        additives = (try container.decodeIfPresent([AdditiveInfo].self, forKey: .additives)) ?? []
        
        packageWeightGrams = try container.decodeIfPresent(Double.self, forKey: .packageWeightGrams)
        
        // Database tracking fields
        sourceBarcode = try container.decodeIfPresent(String.self, forKey: .sourceBarcode)
        sourceType = try container.decodeIfPresent(String.self, forKey: .sourceType)
        timestamp = try container.decodeIfPresent(Date.self, forKey: .timestamp)
        
        // Backend-authoritative safety & nutrition metadata
        safetyLevel = try container.decodeIfPresent(String.self, forKey: .safetyLevel)
        gmoStatus = try container.decodeIfPresent(String.self, forKey: .gmoStatus)
        nutriscoreGrade = try container.decodeIfPresent(String.self, forKey: .nutriscoreGrade)
        ecoscoreGrade = try container.decodeIfPresent(String.self, forKey: .ecoscoreGrade)
        // novaGroup can come as Int or String from backend
        if let novaInt = try? container.decodeIfPresent(Int.self, forKey: .novaGroup) {
            novaGroup = novaInt
        } else if let novaStr = try? container.decodeIfPresent(String.self, forKey: .novaGroup),
                  let novaInt = Int(novaStr) {
            novaGroup = novaInt
        } else {
            novaGroup = nil
        }

	        // Restaurant menu fields
	        isRestaurantMenu = try container.decodeIfPresent(Bool.self, forKey: .isRestaurantMenu)
	        menuDishes = try container.decodeIfPresent([MenuDish].self, forKey: .menuDishes)
	        openFoodFactsDetails = try container.decodeIfPresent(OpenFoodFactsDetails.self, forKey: .openFoodFactsDetails)
	        alternativesMetadata = try container.decodeIfPresent(AlternativesMetadata.self, forKey: .alternativesMetadata)
	    }
}
