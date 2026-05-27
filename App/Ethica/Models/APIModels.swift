//
//  APIModels.swift
//  Ethica
//
//  Created on 11/11/2025
//

import Foundation

struct BackendResponse: Codable {
    // Make most fields optional to be defensive against partial/incomplete backend responses
    let productName: String?
    let confidence: Double?
    let allergens: AllergenInfo?
    let dietary: DietaryInfo?
    let health: HealthInfo?
    let environmental: EnvironmentalInfo?
    let recommendations: RecommendationInfo?
    let alternatives: [RecommendationInfo.Alternative]?  // 🚨 FIX: Backend returns alternatives at TOP LEVEL
    let additives: [AdditiveResponse]?  // Additives from OpenFoodFacts enrichment
    let safetyConfidenceExplanation: SafetyConfidenceExplanation?
    let crossContaminationRisks: [CrossContaminationRisk]?
    let ingredientEducation: [IngredientEducation]?
    
    // FLAT-KEY FALLBACKS: Backend sends flatten_analysis_for_ios() with top-level keys
    // These take priority over nested structs above when present
    let healthScore: Double?
    let environmentalScore: Double?
    let co2Emissions: Double?
    let waterUsage: Double?
    let animalImpact: String?
    let isSafe: Bool?
    let overallScore: Double?
    let ingredients: [String]?
    let dietaryViolations: [String]?
    let cautionWarnings: [String]?
    let detectedAllergens: [String]?
    let healthConcerns: [String]?
    let healthBenefits: [String]?
    let nutritionalHighlights: [String]?
    let environmentalBreakdown: [EnvironmentalInfo.IngredientBreakdown]?
    let confidenceFactors: [String]?
    let detectionEvidence: [DetectionEvidence]?
    
    // FLAT-KEY FIELDS: Backend sends these at top level from flatten_analysis_for_ios()
    let violations: [String]?          // Pre-built violation messages (allergen + dietary + GMO)
    let warnings: [String]?            // Warning messages (separate from cautionWarnings)
    let flatRecommendations: [String]? // Backend sends flat array, not nested struct
    let brand: String?                 // Product brand from OpenFoodFacts
    let safetyLevel: String?           // "safe", "caution", or "avoid" — 3-state safety
    let certifications: [String]?      // Product certifications
    let processingLevel: String?       // NOVA group description
    let packagingScore: Double?        // Packaging sustainability score 0-100
    let animalWelfareScore: Double?    // Animal welfare score 0-100
    let sourceBarcode: String?         // Barcode used for lookup
    let sourceType: String?            // "cache", "openfoodfacts", "ocr"
    let packageWeightGrams: Double?    // Package weight in grams
    let landUse: String?               // Land use rating
    
    // Custom CodingKeys to map backend's "recommendations" (flat array) to flatRecommendations
    enum CodingKeys: String, CodingKey {
        case productName, confidence, allergens, dietary, health, environmental
        case recommendations  // Tries to decode as RecommendationInfo first
        case alternatives, additives, safetyConfidenceExplanation
        case crossContaminationRisks, ingredientEducation
        case healthScore, environmentalScore, co2Emissions, waterUsage, animalImpact
        case isSafe, overallScore, ingredients, dietaryViolations, cautionWarnings
        case detectedAllergens, healthConcerns, healthBenefits, nutritionalHighlights
        case environmentalBreakdown, confidenceFactors, detectionEvidence
        case gmoStatus, gmoStatusReason, highRiskIngredients, nonGmoCertified
        case violations, warnings, brand, safetyLevel, certifications, processingLevel
        case packagingScore, animalWelfareScore, sourceBarcode, sourceType
        case packageWeightGrams, landUse
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        productName = try container.decodeIfPresent(String.self, forKey: .productName)
        confidence = try container.decodeIfPresent(Double.self, forKey: .confidence)
        allergens = try container.decodeIfPresent(AllergenInfo.self, forKey: .allergens)
        dietary = try container.decodeIfPresent(DietaryInfo.self, forKey: .dietary)
        health = try container.decodeIfPresent(HealthInfo.self, forKey: .health)
        environmental = try container.decodeIfPresent(EnvironmentalInfo.self, forKey: .environmental)
        
        // Recommendations: try as RecommendationInfo struct first, then as flat [String]
        if let recStruct = try? container.decodeIfPresent(RecommendationInfo.self, forKey: .recommendations) {
            recommendations = recStruct
            flatRecommendations = nil
        } else if let recArray = try? container.decodeIfPresent([String].self, forKey: .recommendations) {
            recommendations = nil
            flatRecommendations = recArray
        } else {
            recommendations = nil
            flatRecommendations = nil
        }
        
        alternatives = try container.decodeIfPresent([RecommendationInfo.Alternative].self, forKey: .alternatives)
        additives = try container.decodeIfPresent([AdditiveResponse].self, forKey: .additives)
        safetyConfidenceExplanation = try container.decodeIfPresent(SafetyConfidenceExplanation.self, forKey: .safetyConfidenceExplanation)
        crossContaminationRisks = try container.decodeIfPresent([CrossContaminationRisk].self, forKey: .crossContaminationRisks)
        ingredientEducation = try container.decodeIfPresent([IngredientEducation].self, forKey: .ingredientEducation)
        healthScore = try container.decodeIfPresent(Double.self, forKey: .healthScore)
        environmentalScore = try container.decodeIfPresent(Double.self, forKey: .environmentalScore)
        co2Emissions = try container.decodeIfPresent(Double.self, forKey: .co2Emissions)
        waterUsage = try container.decodeIfPresent(Double.self, forKey: .waterUsage)
        animalImpact = try container.decodeIfPresent(String.self, forKey: .animalImpact)
        isSafe = try container.decodeIfPresent(Bool.self, forKey: .isSafe)
        overallScore = try container.decodeIfPresent(Double.self, forKey: .overallScore)
        ingredients = try container.decodeIfPresent([String].self, forKey: .ingredients)
        dietaryViolations = try container.decodeIfPresent([String].self, forKey: .dietaryViolations)
        cautionWarnings = try container.decodeIfPresent([String].self, forKey: .cautionWarnings)
        detectedAllergens = try container.decodeIfPresent([String].self, forKey: .detectedAllergens)
        healthConcerns = try container.decodeIfPresent([String].self, forKey: .healthConcerns)
        healthBenefits = try container.decodeIfPresent([String].self, forKey: .healthBenefits)
        nutritionalHighlights = try container.decodeIfPresent([String].self, forKey: .nutritionalHighlights)
        environmentalBreakdown = try container.decodeIfPresent([EnvironmentalInfo.IngredientBreakdown].self, forKey: .environmentalBreakdown)
        confidenceFactors = try container.decodeIfPresent([String].self, forKey: .confidenceFactors)
        detectionEvidence = try container.decodeIfPresent([DetectionEvidence].self, forKey: .detectionEvidence)
        gmoStatus = try container.decodeIfPresent(String.self, forKey: .gmoStatus)
        gmoStatusReason = try container.decodeIfPresent(String.self, forKey: .gmoStatusReason)
        highRiskIngredients = try container.decodeIfPresent([String].self, forKey: .highRiskIngredients)
        nonGmoCertified = try container.decodeIfPresent(Bool.self, forKey: .nonGmoCertified)
        violations = try container.decodeIfPresent([String].self, forKey: .violations)
        warnings = try container.decodeIfPresent([String].self, forKey: .warnings)
        brand = try container.decodeIfPresent(String.self, forKey: .brand)
        safetyLevel = try container.decodeIfPresent(String.self, forKey: .safetyLevel)
        certifications = try container.decodeIfPresent([String].self, forKey: .certifications)
        processingLevel = try container.decodeIfPresent(String.self, forKey: .processingLevel)
        packagingScore = try container.decodeIfPresent(Double.self, forKey: .packagingScore)
        animalWelfareScore = try container.decodeIfPresent(Double.self, forKey: .animalWelfareScore)
        sourceBarcode = try container.decodeIfPresent(String.self, forKey: .sourceBarcode)
        sourceType = try container.decodeIfPresent(String.self, forKey: .sourceType)
        packageWeightGrams = try container.decodeIfPresent(Double.self, forKey: .packageWeightGrams)
        landUse = try container.decodeIfPresent(String.self, forKey: .landUse)
    }
    
    // GMO 4-State Status (100% accuracy guarantee)
    let gmoStatus: String?           // "confirmed_gmo" | "non_gmo_certified" | "high_risk_unknown" | "no_risk"
    let gmoStatusReason: String?      // User-facing explanation
    let highRiskIngredients: [String]? // Which high-risk GMO ingredients were found
    let nonGmoCertified: Bool?        // Has Non-GMO Project / Organic certification
    
    struct DetectionEvidence: Codable {
        let ingredient: String?
        let matchedPreference: String?
        let reason: String?
        let source: String?
        let confidence: Double?
    }
    
    struct AdditiveResponse: Codable {
        let code: String?
        let name: String?
        let category: String?
        let riskLevel: String?
        let description: String?
        let source: String?
    }
    
    struct AllergenInfo: Codable {
        let definiteViolations: [AllergenViolation]?
        let cautionWarnings: [AllergenViolation]?
        let safe: Bool?
        
        struct AllergenViolation: Codable {
            let allergen: String?
            let severity: String?
            let source: String?
            let warning: String?
        }
    }
    
    struct DietaryInfo: Codable {
        let compatible: String?
        let violations: [String]?
        let tags: [String]?
    }
    
    struct HealthInfo: Codable {
        let score: Double?
        let concerns: [String]?
        let benefits: [String]?
    }
    
    struct EnvironmentalInfo: Codable {
        let totalCO2: Double?
        let waterUsage: Double?
        let animalImpact: String?
        let rating: String?
        let breakdown: [IngredientBreakdown]?
        
        struct IngredientBreakdown: Codable {
            let ingredient: String?
            let co2: Double?
            let percentage: Double?
        }
    }
    
    struct RecommendationInfo: Codable {
        let environmental: [String]?
        let health: [String]?
        let allergenFree: [String]?
        let alternatives: [Alternative]?
        let insights: [String]?
        
        struct Alternative: Codable {
            let name: String?
            let reason: String?
            let brand: String?
            let link: String?
            let estimatedCO2: Double?
            let estimatedWater: Double?
            let healthScore: Double?
            let environmentalScore: Double?
            let ethicsScore: Double?
            let dataSource: String?
            let imageURL: String?
            let price: Double?
            let priceSource: String?
            let nutrition: NutritionData?

            struct NutritionData: Codable {
                let calories: Double?
                let protein: Double?
                let carbs: Double?
                let sugar: Double?
                let fat: Double?
                let fiber: Double?
                let sodium: Double?
            }
        }
    }
    
    struct SafetyConfidenceExplanation: Codable {
        let overallConfidence: Double?
        let confidenceLevel: String?
        let detailedReasons: [String]?
        let whatThisMeans: String?
        let recommendedAction: String?
    }
    
    struct CrossContaminationRisk: Codable {
        let allergen: String?
        let riskLevel: String?
        let riskExplanation: String?
        let manufacturingDetails: String?
        let guidance: String?
    }
    
    struct IngredientEducation: Codable {
        let ingredient: String?
        let whatItIs: String?
        let hiddenSources: [String]?
        let whyItMatters: String?
        let isSafe: Bool?
        let confidence: Double?
    }
}

// Menu Analysis Response (for restaurant menus)
struct MenuAnalysisResponse: Codable {
    let ingredients: [String]?
    let menuAnalysis: [MenuDish]?
    let isRestaurantMenu: Bool?
    
    struct MenuDish: Codable {
        let dish: String?
        let ingredients: [String]?
        let safe: Bool?
        let warnings: [String]?
        let estimatedCO2: Double?

        // Custom decoder to handle nil values gracefully
        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            dish = try container.decodeIfPresent(String.self, forKey: .dish)
            ingredients = try container.decodeIfPresent([String].self, forKey: .ingredients)
            safe = try container.decodeIfPresent(Bool.self, forKey: .safe)
            warnings = try container.decodeIfPresent([String].self, forKey: .warnings)
            estimatedCO2 = try container.decodeIfPresent(Double.self, forKey: .estimatedCO2)
        }
    }
}

// AppConfig (backend URL) removed: the app is backend-less and uses Supabase + Gemini directly.
