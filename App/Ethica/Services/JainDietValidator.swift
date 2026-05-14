//
//  JainDietValidator.swift
//  Ethica
//
//  Client-side Jain diet validation layer.
//  Runs on ALL scan results (backend + fallback) to catch anything the backend misses.

import Foundation

struct JainViolation {
    let ingredient: String
    let prohibitedItem: String
    let category: String    // "root_vegetable", "derivative", "vegetable", "fungi", "animal", "fermented", "multi_organism"
    let severity: String    // "high", "medium"
    let explanation: String
}

final class JainDietValidator {
    static let shared = JainDietValidator()
    private init() {}

    // MARK: - Prohibited Lists

    private let prohibitedRootVegetables: [(term: String, explanation: String)] = [
        ("onion", "Root vegetable - prohibited in Jain diet"),
        ("garlic", "Root vegetable - prohibited in Jain diet"),
        ("potato", "Root vegetable/tuber - prohibited in Jain diet"),
        ("carrot", "Root vegetable - prohibited in Jain diet"),
        ("ginger", "Root/rhizome - prohibited in Jain diet"),
        ("turmeric", "Root/rhizome - prohibited in Jain diet"),
        ("radish", "Root vegetable - prohibited in Jain diet"),
        ("turnip", "Root vegetable - prohibited in Jain diet"),
        ("beet", "Root vegetable - prohibited in Jain diet"),
        ("beetroot", "Root vegetable - prohibited in Jain diet"),
        ("yam", "Root vegetable/tuber - prohibited in Jain diet"),
        ("sweet potato", "Root vegetable/tuber - prohibited in Jain diet"),
        ("tapioca", "Derived from cassava root - prohibited in Jain diet"),
        ("arrowroot", "Root-derived starch - prohibited in Jain diet"),
        ("taro", "Root vegetable - prohibited in Jain diet"),
        ("suran", "Elephant yam/root - prohibited in Jain diet"),
        ("elephant yam", "Root vegetable - prohibited in Jain diet"),

        ("lotus root", "Underground root - prohibited in Jain diet"),
        ("parsnip", "Root vegetable - prohibited in Jain diet"),
        ("celeriac", "Root vegetable - prohibited in Jain diet"),
        ("celery root", "Root vegetable - prohibited in Jain diet"),
        ("shallot", "Root vegetable (onion family) - prohibited in Jain diet"),
        ("leek", "Root vegetable (onion family) - prohibited in Jain diet"),
        ("chive", "Root vegetable (onion family) - prohibited in Jain diet"),
        ("scallion", "Root vegetable (onion family) - prohibited in Jain diet"),
        ("spring onion", "Root vegetable (onion family) - prohibited in Jain diet"),
        ("green onion", "Root vegetable (onion family) - prohibited in Jain diet"),
        ("daikon", "Root vegetable (radish) - prohibited in Jain diet"),
        ("rutabaga", "Root vegetable - prohibited in Jain diet"),
        ("jicama", "Root vegetable - prohibited in Jain diet"),
        ("horseradish", "Root vegetable - prohibited in Jain diet"),
        // Scientific names (international/pharma products)
        ("allium cepa", "Onion (scientific name) - prohibited in Jain diet"),
        ("allium sativum", "Garlic (scientific name) - prohibited in Jain diet"),
        ("allium porrum", "Leek (scientific name) - prohibited in Jain diet"),
        ("zingiber officinale", "Ginger (scientific name) - prohibited in Jain diet"),
        ("curcuma longa", "Turmeric (scientific name) - prohibited in Jain diet"),
        // Hindi/Gujarati transliterations
        ("sonth", "Dried ginger - prohibited in Jain diet"),
        ("saunth", "Dried ginger - prohibited in Jain diet"),
        ("haldi", "Turmeric - prohibited in Jain diet"),
        ("adrak", "Ginger - prohibited in Jain diet"),
    ]

    private let prohibitedDerivatives: [(term: String, explanation: String)] = [
        ("onion powder", "Derived from onion root - prohibited in Jain diet"),
        ("garlic powder", "Derived from garlic root - prohibited in Jain diet"),
        ("ginger powder", "Derived from ginger root - prohibited in Jain diet"),
        ("potato starch", "Derived from potato root - prohibited in Jain diet"),
        ("potato flour", "Derived from potato root - prohibited in Jain diet"),
        ("garlic salt", "Contains garlic - prohibited in Jain diet"),
        ("onion salt", "Contains onion - prohibited in Jain diet"),
        ("garlic extract", "Derived from garlic root - prohibited in Jain diet"),
        ("onion extract", "Derived from onion root - prohibited in Jain diet"),
        ("dehydrated onion", "Derived from onion root - prohibited in Jain diet"),
        ("dehydrated garlic", "Derived from garlic root - prohibited in Jain diet"),
        ("roasted garlic", "Derived from garlic root - prohibited in Jain diet"),
        ("modified food starch", "Often derived from potato - caution for Jain diet"),
        ("dextrose", "Can be derived from potato - caution for Jain diet"),
    ]

    private let prohibitedFungi: [(term: String, explanation: String)] = [
        ("mushroom", "Fungus - prohibited in Jain diet"),
        ("yeast", "Fungus - prohibited in Jain diet"),
        ("yeast extract", "Fungus-derived - prohibited in Jain diet"),
        ("nutritional yeast", "Fungus - prohibited in Jain diet"),
        ("autolyzed yeast", "Fungus-derived - prohibited in Jain diet"),
        ("brewer's yeast", "Fungus - prohibited in Jain diet"),
        ("baker's yeast", "Fungus - prohibited in Jain diet"),
        ("fungus", "Prohibited in Jain diet"),
        ("fungi", "Prohibited in Jain diet"),
        ("truffle", "Fungus - prohibited in Jain diet"),
        ("mycoprotein", "Fungus-derived protein - prohibited in Jain diet"),
        ("koji", "Fungus culture - prohibited in Jain diet"),
        ("sprouts", "Sprout/germinating - prohibited in Jain diet"),
        ("sprouted", "Sprouted/germinating - prohibited in Jain diet"),
    ]

    private let prohibitedVegetables: [(term: String, explanation: String)] = [
        ("eggplant", "Prohibited vegetable in Jain diet"),
        ("egg plant", "Prohibited vegetable in Jain diet"),
        ("aubergine", "Eggplant - prohibited vegetable in Jain diet"),
        ("brinjal", "Eggplant - prohibited vegetable in Jain diet"),
        ("baingan", "Eggplant - prohibited vegetable in Jain diet"),
        ("brussels sprouts", "Prohibited vegetable in Jain diet"),
    ]

    private let prohibitedAnimal: [(term: String, explanation: String)] = [
        ("meat", "Animal product - prohibited in Jain diet"),
        ("meatball", "Animal product - prohibited in Jain diet"),
        ("beef", "Animal product - prohibited in Jain diet"),
        ("pork", "Animal product - prohibited in Jain diet"),
        ("chicken", "Animal product - prohibited in Jain diet"),
        ("fish", "Animal product - prohibited in Jain diet"),
        ("swordfish", "Animal product - prohibited in Jain diet"),
        ("catfish", "Animal product - prohibited in Jain diet"),
        ("salmon", "Animal product - prohibited in Jain diet"),
        ("tuna", "Animal product - prohibited in Jain diet"),
        ("surimi", "Fish-derived - prohibited in Jain diet"),
        ("dashi", "Fish-derived broth - prohibited in Jain diet"),
        ("egg", "Animal product - prohibited in Jain diet"),
        ("eggnog", "Egg product - prohibited in Jain diet"),
        ("honey", "Insect product - prohibited in Jain diet"),
        ("gelatin", "Animal-derived - prohibited in Jain diet"),
        ("rennet", "Animal enzyme (cheese) - prohibited in Jain diet"),
        ("lard", "Animal fat - prohibited in Jain diet"),
        ("tallow", "Animal fat - prohibited in Jain diet"),
        ("carmine", "Insect-derived color - prohibited in Jain diet"),
        ("cochineal", "Insect-derived color - prohibited in Jain diet"),
        ("natural red 4", "Carmine (insect-derived dye) - prohibited in Jain diet"),
        ("shellac", "Insect secretion - prohibited in Jain diet"),
        ("isinglass", "Fish-derived - prohibited in Jain diet"),
        ("anchovies", "Animal product - prohibited in Jain diet"),
        ("mayo", "Egg-based - prohibited in Jain diet"),
        ("mayonnaise", "Egg-based - prohibited in Jain diet"),
    ]

    private let prohibitedFermented: [(term: String, explanation: String)] = [
        ("alcohol", "Fermented - prohibited in Jain diet"),
        ("wine", "Fermented - prohibited in Jain diet"),
        ("beer", "Fermented - prohibited in Jain diet"),
        ("miso", "Fermented with fungi - prohibited in Jain diet"),
        ("tempeh", "Fermented with fungi - prohibited in Jain diet"),
        ("soy sauce", "Fermented - prohibited in Jain diet"),
        ("tamari", "Fermented soy sauce - prohibited in Jain diet"),
        ("shoyu", "Fermented soy sauce - prohibited in Jain diet"),
        ("kombucha", "Fermented - prohibited in Jain diet"),
        ("malt", "Fermented with yeast - prohibited in Jain diet"),
        ("malt extract", "Fermented with yeast - prohibited in Jain diet"),
        ("barley malt", "Fermented with yeast - prohibited in Jain diet"),

        ("kimchi", "Fermented - prohibited in Jain diet"),
        ("sauerkraut", "Fermented - prohibited in Jain diet"),
    ]

    private let prohibitedMultiOrganism: [(term: String, explanation: String)] = [
        ("fig paste", "Derived from fig - prohibited in Jain diet"),
        ("fig extract", "Derived from fig - prohibited in Jain diet"),
        ("fig concentrate", "Derived from fig - prohibited in Jain diet"),
        ("fig", "Multi-organism fruit (contains wasps) - prohibited in Jain diet"),
    ]

    // MARK: - False Positives

    /// Ingredients that contain prohibited terms but are actually safe for Jain diet
    private let jainFalsePositives: Set<String> = [
        // Contains "fig" but not actual fig
        "configuration",
        "figure",
        "figment",
        "figurine",
        // Contains "yam" but not actual yam
        "yamaha",
        // Contains "honey" but not actual honey
        "honeydew",
        "honeycrisp",
        "honeybush",
        // Contains "beet" but safe
        "beetlejuice",
        // Contains "meat" but not actual meat
        "mincemeat",      // Traditional fruit-based filling
        "coconut meat",
        "jackfruit meat",
        // Contains "leek" but not actual leek
        "sleek",
        // Contains "wine" but not actual wine
        "wintergreen",
        // Plant-based items with "butter"/"milk" in name
        "cocoa butter",
        "cacao butter",
        "shea butter",
        "mango butter",
        "peanut butter",
        "almond butter",
        "cashew butter",
        "sunflower butter",
        "coconut butter",
        "coconut milk",
        "coconut cream",
        "almond milk",
        "oat milk",
        "soy milk",
        "rice milk",
        "cashew milk",
        "cream of tartar",
        // Contains "beer" but not actual beer
        "root beer",
        // "-free" suffix means item is ABSENT, not present
        "egg-free", "egg free",
        "dairy-free", "dairy free",
        "meat-free", "meat free",
        "fish-free", "fish free",
        "honey-free", "honey free",
        "gelatin-free", "gelatin free",
        "alcohol-free", "alcohol free",
        "yeast-free", "yeast free",
        // "non-X" means item is ABSENT, not present
        "non-gmo", "non gmo", "non-gmo verified", "non gmo verified", "nongmo",
        "non-bioengineered", "non bioengineered",
    ]

    // All prohibited terms (flat list) for filtering alternatives
    private lazy var allProhibitedTerms: [String] = {
        (prohibitedRootVegetables + prohibitedDerivatives + prohibitedFungi +
         prohibitedVegetables + prohibitedAnimal + prohibitedFermented +
         prohibitedMultiOrganism).map { $0.term }
    }()

    // Pre-compiled regex cache for performance
    private var regexCache: [String: NSRegularExpression] = [:]
    private let regexLock = NSLock()

    // MARK: - Matching

    /// Word-boundary match to prevent "fig" matching "configuration"
    func matchesProhibitedItem(_ ingredientText: String, term: String) -> Bool {
        let lower = ingredientText.lowercased()

        // Check false positives FIRST — if the ingredient text contains a known safe phrase, skip
        for fp in jainFalsePositives {
            if lower.contains(fp) {
                // Only skip if the false positive encompasses the prohibited term
                if fp.contains(term) || term.count <= 4 {
                    return false
                }
            }
        }

        // Use word-boundary regex
        let regex = getOrCreateRegex(for: term)
        let range = NSRange(lower.startIndex..<lower.endIndex, in: lower)
        return regex?.firstMatch(in: lower, range: range) != nil
    }

    private func getOrCreateRegex(for term: String) -> NSRegularExpression? {
        regexLock.lock()
        defer { regexLock.unlock() }

        if let cached = regexCache[term] {
            return cached
        }

        let escaped = NSRegularExpression.escapedPattern(for: term)
        let pattern = "(?<!\\w)(?<!non[- ])\(escaped)(?:s|es)?(?!\\w)"
        let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive)
        if let regex = regex {
            regexCache[term] = regex
        }
        return regex
    }

    // MARK: - Validation

    /// Validate a single ingredient against all Jain rules
    func validateIngredient(_ ingredient: String) -> [JainViolation] {
        // Check derivatives first (longer, more specific terms) to match before base terms
        let allProhibited: [(term: String, explanation: String, category: String)] =
            prohibitedDerivatives.map { ($0.term, $0.explanation, "derivative") } +
            prohibitedRootVegetables.map { ($0.term, $0.explanation, "root_vegetable") } +
            prohibitedVegetables.map { ($0.term, $0.explanation, "vegetable") } +
            prohibitedFungi.map { ($0.term, $0.explanation, "fungi") } +
            prohibitedAnimal.map { ($0.term, $0.explanation, "animal") } +
            prohibitedFermented.map { ($0.term, $0.explanation, "fermented") } +
            prohibitedMultiOrganism.map { ($0.term, $0.explanation, "multi_organism") }

        for item in allProhibited {
            if matchesProhibitedItem(ingredient, term: item.term) {
                let severity: String
                switch item.category {
                case "derivative":
                    // Derivatives like "modified food starch" are ambiguous source
                    let ambiguousTerms = Set(["modified food starch", "dextrose"])
                    severity = ambiguousTerms.contains(item.term) ? "medium" : "high"
                case "fermented":
                    severity = "medium" // Some Jain practitioners allow fermented
                default:
                    severity = "high"
                }
                return [JainViolation(
                    ingredient: ingredient,
                    prohibitedItem: item.term,
                    category: item.category,
                    severity: severity,
                    explanation: item.explanation
                )]
            }
        }

        return []
    }

    /// Filter alternatives that contain Jain-prohibited ingredients
    private func filterAlternativesForJain(_ alternatives: [AnalysisResult.Alternative]) -> [AnalysisResult.Alternative] {
        alternatives.filter { alt in
            let text = "\(alt.name) \(alt.reason ?? "") \(alt.brand ?? "")"
            return !allProhibitedTerms.contains { matchesProhibitedItem(text, term: $0) }
        }
    }

    /// Validate an AnalysisResult and return an augmented version with any additional Jain violations.
    /// This is the KEY method — runs on ALL results including backend to ensure nothing is missed.
    func validateResult(_ result: AnalysisResult) -> AnalysisResult {
        var additionalViolations: [String] = []
        var additionalWarnings: [String] = []
        var isSafe = result.isSafe

        // Collect existing violation text (lowercased) to avoid duplicates
        let existingViolationTexts = Set(
            (result.violations + result.warnings + result.cautionWarnings)
                .map { $0.lowercased() }
        )

        for ingredient in result.ingredients {
            let jainViolations = validateIngredient(ingredient)
            for jv in jainViolations {
                let message = "Not Jain-compatible (contains \(jv.prohibitedItem))"

                // Check if already reported by backend (fuzzy dedup)
                let isDuplicate = existingViolationTexts.contains(where: { existing in
                    existing.contains(jv.prohibitedItem.lowercased()) &&
                    (existing.contains("jain") || existing.contains(ingredient.lowercased()))
                })

                if !isDuplicate {
                    if jv.severity == "high" {
                        additionalViolations.append("⛔ \(message): \(jv.ingredient)")
                        isSafe = false
                    } else {
                        additionalWarnings.append("⚠️ \(message): \(jv.ingredient)")
                    }
                }
            }
        }

        // Filter alternatives for Jain-prohibited items
        let filteredAlternatives = filterAlternativesForJain(result.alternatives)

        // If no new violations/warnings AND alternatives unchanged, return original
        if additionalViolations.isEmpty && additionalWarnings.isEmpty
            && filteredAlternatives.count == result.alternatives.count {
            return result
        }

        // Reconstruct with augmented violations/warnings
        return AnalysisResult(
            id: result.id,
            productName: result.productName,
            overallScore: result.overallScore,
            isSafe: isSafe,
            confidence: result.confidence,
            confidenceFactors: result.confidenceFactors,
            violations: result.violations + additionalViolations,
            warnings: result.warnings + additionalWarnings,
            cautionWarnings: result.cautionWarnings,
            ingredients: result.ingredients,
            detectedAllergens: result.detectedAllergens,
            detectionEvidence: result.detectionEvidence,
            healthScore: result.healthScore,
            environmentalScore: result.environmentalScore,
            co2Emissions: result.co2Emissions,
            waterUsage: result.waterUsage,
            animalImpact: result.animalImpact,
            landUse: result.landUse,
            nutritionalHighlights: result.nutritionalHighlights,
            healthConcerns: result.healthConcerns,
            healthBenefits: result.healthBenefits,
            recommendations: result.recommendations,
            alternatives: filteredAlternatives,
            environmentalBreakdown: result.environmentalBreakdown,
            brand: result.brand,
            certifications: result.certifications,
            processingLevel: result.processingLevel,
            estimatedCO2: result.estimatedCO2,
            packagingScore: result.packagingScore,
            animalWelfareScore: result.animalWelfareScore,
            additives: result.additives,
            packageWeightGrams: result.packageWeightGrams,
            sourceBarcode: result.sourceBarcode,
            sourceType: result.sourceType,
            timestamp: result.timestamp,
            safetyLevel: isSafe ? result.safetyLevel : "avoid",
            gmoStatus: result.gmoStatus,
            nutriscoreGrade: result.nutriscoreGrade,
            ecoscoreGrade: result.ecoscoreGrade,
            novaGroup: result.novaGroup,
            isRestaurantMenu: result.isRestaurantMenu,
            menuDishes: result.menuDishes,
            safetyConfidenceExplanation: result.safetyConfidenceExplanation,
            ingredientEducation: result.ingredientEducation,
            crossContaminationRisks: result.crossContaminationRisks,
            alternativesMetadata: result.alternativesMetadata
        )
    }
}
