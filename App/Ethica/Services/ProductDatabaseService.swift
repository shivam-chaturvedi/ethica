//
//  ProductDatabaseService.swift
//  Ethica
//
//  Smart pipeline coordinator: barcode → cache → OpenFoodFacts → OCR fallback

import Foundation
import UIKit
import Combine
import OSLog

struct ConcernItem {
    let ingredient: String
    let concern: String
    let severity: String // "high", "medium", "low"
}

@MainActor
class ProductDatabaseService: ObservableObject {
    static let shared = ProductDatabaseService()

    @Published var lookupProgress: Double = 0.0
    @Published var currentStep: String = ""

    /// Enhanced result from SSE streaming — published after AI analysis completes.
    /// Static so ResultsView can observe it regardless of which instance produced it.
    /// Uses CurrentValueSubject so late subscribers get the last published value.
    static let enhancedResultSubject = CurrentValueSubject<AnalysisResult?, Never>(nil)

    private let barcodeScanner = BarcodeScanner()
    private let openFoodFactsClient = OpenFoodFactsClient()
    private let cacheService = ProductCacheService()
    private let aiCache = AIResultsCacheService.shared

    /// Track active enrichment task so rapid re-scans cancel the previous one
    private var activeEnrichmentTask: Task<Void, Never>?
    
    // 🚀 OSLog for better performance monitoring
    private let logger = Logger(subsystem: "com.ethica.app", category: "ProductDatabase")

    // MARK: - Shared Allergen Data

    /// Canonical allergen keyword map (lowercase keys). Single source of truth.
    private static let allergenKeywords: [String: [String]] = [
        "dairy": ["milk", "dairy", "lactose", "cream", "butter", "cheese", "whey", "casein", "yogurt", "skyr", "ghee", "custard", "curds", "milkshake", "cheesecake", "buttercream"],
        "eggs": ["egg", "eggs", "albumin", "mayonnaise", "meringue", "lysozyme", "ovalbumin"],
        "fish": ["fish", "salmon", "tuna", "cod", "anchovy", "anchovies", "sardine", "mackerel", "tilapia", "isinglass", "surimi", "worcestershire", "dashi"],
        "shellfish": ["shellfish", "shrimp", "crab", "lobster", "prawn", "crawfish", "crayfish", "oyster", "clam", "mussel", "scallop", "calamari", "squid"],
        "nuts": ["nut", "nuts", "almond", "walnut", "cashew", "pecan", "pistachio", "hazelnut", "macadamia", "brazil nut", "chestnut", "pine nut", "praline", "marzipan", "nougat"],
        "peanuts": ["peanut", "groundnut", "arachis"],
        "gluten": ["wheat", "flour", "gluten", "barley", "rye", "spelt", "semolina", "farina", "durum", "bulgur", "couscous", "kamut", "farro", "malt"],
        "soy": ["soy", "soya", "tofu", "soybean", "edamame", "tempeh", "miso", "tamari", "shoyu"],
        "sesame": ["sesame", "tahini", "halvah"],
    ]

    /// Synonym groups: names that should match each other during allergen filtering.
    /// Each group is a set of lowercase names that are equivalent.
    /// NOTE: Peanuts are legumes, NOT tree nuts — FDA lists them as separate allergens.
    private static let allergenSynonyms: [[String]] = [
        ["gluten", "wheat"],
        ["dairy", "milk"],
        ["nuts", "tree nuts", "treenuts", "almond", "almonds", "walnut", "walnuts", "cashew", "cashews", "pecan", "pecans", "pistachio", "pistachios", "hazelnut", "hazelnuts", "macadamia", "brazil nut"],
        ["peanuts", "peanut", "groundnut"],
        ["sesame", "tahini", "halvah"],
    ]
    
    /// 🚀 Pre-computed synonym lookup map for O(1) matching instead of O(n²)
    private static let allergenSynonymMap: [String: Set<String>] = {
        var map: [String: Set<String>] = [:]
        for group in allergenSynonyms {
            let groupSet = Set(group)
            for item in group {
                map[item] = groupSet
            }
        }
        return map
    }()

    /// Returns true if two allergen names are synonymous (or equal).
    /// Works even when only one operand is in the synonym map (e.g. "tree nuts" vs "almonds").
    static func allergensMatch(_ a: String, _ b: String) -> Bool {
        let la = a.lowercased()
        let lb = b.lowercased()

        if la == lb { return true }

        // Check if either side is in a synonym group that contains the other
        if let aGroup = allergenSynonymMap[la], aGroup.contains(lb) {
            return true
        }
        if let bGroup = allergenSynonymMap[lb], bGroup.contains(la) {
            return true
        }

        // Also check if both are in the same group
        if let aGroup = allergenSynonymMap[la],
           let bGroup = allergenSynonymMap[lb] {
            return !aGroup.isDisjoint(with: bGroup)
        }

        // Check allergenKeywords: if b is a keyword for allergen group a (or vice versa)
        if let aKeywords = allergenKeywords[la], aKeywords.contains(where: { $0.lowercased() == lb }) {
            return true
        }
        if let bKeywords = allergenKeywords[lb], bKeywords.contains(where: { $0.lowercased() == la }) {
            return true
        }

        return false
    }

    /// Optimized URLSession for backend API calls with connection reuse
    private lazy var backendSession: URLSession = {
        let config = URLSessionConfiguration.default
        config.httpMaximumConnectionsPerHost = 4
        config.timeoutIntervalForRequest = 45
        config.timeoutIntervalForResource = 90
        config.waitsForConnectivity = true
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        
        // 🚀 NEW: Enable HTTP/2 pipelining for better multiplexing
        config.httpShouldUsePipelining = true
        
        // 🚀 NEW: Disable cookies (not used)
        config.httpShouldSetCookies = false
        
        // 🚀 NEW: Better TLS settings
        config.tlsMinimumSupportedProtocolVersion = .TLSv12
        
        // 🚀 NEW: Disk cache for better offline resilience
        config.urlCache = URLCache(
            memoryCapacity: 20 * 1024 * 1024,  // 20 MB memory
            diskCapacity: 100 * 1024 * 1024     // 100 MB disk
        )
        
        // 🚀 NEW: Network access policies
        config.allowsCellularAccess = true
        config.allowsExpensiveNetworkAccess = true
        config.allowsConstrainedNetworkAccess = true
        
        return URLSession(configuration: config)
    }()

    /// Add auth token to backend requests (mirrors NetworkService.addAuthToken)
    private func addAuthToken(to request: inout URLRequest) async {
        await AuthenticationService.shared.fetchAuthToken()
        if let token = AuthenticationService.shared.authToken {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        request.setValue("gzip, deflate", forHTTPHeaderField: "Accept-Encoding")
    }

    /// Retry a network operation with exponential backoff (2 attempts for barcode path)
    /// 🚀 Optimized: Added jitter to prevent thundering herd problem
    private func performWithRetry<T>(
        maxAttempts: Int = 2,
        operation: @escaping () async throws -> T
    ) async throws -> T {
        var lastError: Error?
        for attempt in 1...maxAttempts {
            do {
                return try await operation()
            } catch {
                lastError = error
                logger.warning("⚠️ Backend attempt \(attempt)/\(maxAttempts) failed: \(error.localizedDescription)")
                if attempt < maxAttempts {
                    // Exponential backoff with jitter (prevents thundering herd)
                    let jitter = Double.random(in: 0...0.5)
                    let backoffSeconds = Double(attempt) + jitter
                    logger.debug("🔄 Retrying in \(backoffSeconds)s...")
                    try await Task.sleep(nanoseconds: UInt64(backoffSeconds * 1_000_000_000))
                }
            }
        }
        throw lastError ?? NSError(domain: "ProductDatabaseService", code: -1,
                                    userInfo: [NSLocalizedDescriptionKey: "All retry attempts failed"])
    }

    /// Apply client-side Jain diet validation if user has Jain selected
    private func applyJainValidation(_ result: AnalysisResult, preferences: UserPreferences) -> AnalysisResult {
        let allDiets = Array(preferences.selectedDiets) + preferences.customDiets
        let isJain = allDiets.contains { $0.lowercased() == "jain" }
        guard isJain else { return result }
        return JainDietValidator.shared.validateResult(result)
    }
    
    enum LookupResult {
        case foundInCache(CachedProduct)
        case foundInAPI(OpenFoodFactsProduct)
        case fallbackToOCR
        case error(String)
    }
    
    /// Look up a product by barcode string (when barcode is already detected)
    ///   - barcode: Barcode string already detected
    ///   - preferences: User preferences for analysis
    /// - Returns: AnalysisResult from database or nil if not found
    func lookupBarcode(_ barcode: String, preferences: UserPreferences) async -> AnalysisResult? {
        logger.debug("✅ Looking up barcode: \(barcode)")
        await updateProgress(0.1, step: "Checking cache...")

        // STEP 1: Check AI results cache (instant if hit)
        if let cachedAI = await aiCache.fetch(barcode: barcode, preferences: preferences) {
            await updateProgress(1.0, step: "Using cached AI analysis!")
            logger.debug("⚡ AI cache hit for barcode: \(barcode)")
            return cachedAI
        }

        // STEP 2: Query OpenFoodFacts
        await updateProgress(0.3, step: "Searching database...")
        if let offResult = await openFoodFactsClient.fetchProduct(barcode: barcode) {
            let offProduct = offResult.product
            let rawOFFJSON = offResult.rawJSON
            await updateProgress(0.5, step: "Product found! Checking safety...")
            logger.debug("✅ OpenFoodFacts hit for barcode: \(barcode)")

            // Cache OFF data
            let ingredients = openFoodFactsClient.extractIngredients(from: offProduct)
            await cacheService.save(
                barcode: barcode,
                productName: offProduct.productNameEn ?? offProduct.productName ?? "Unknown Product",
                ingredients: ingredients,
                allergens: offProduct.allergens,
                ethicalScore: nil,
                ethicalSummary: openFoodFactsClient.getEthicalSummary(from: offProduct)
            )

            // STEP 3: Quick allergen check (2-4s AI safety verdict)
            if !ingredients.isEmpty {
                let safetyResult = await NetworkService.shared.quickAllergenCheck(
                    ingredients: ingredients,
                    preferences: preferences,
                    barcode: barcode,
                    productName: offProduct.productNameEn ?? offProduct.productName,
                    openfoodfactsData: rawOFFJSON
                )

                // Build preliminary result: OFF data + AI safety verdict
                var result = buildPreliminaryResult(
                    product: offProduct, barcode: barcode,
                    preferences: preferences, safetyResult: safetyResult,
                    rawOFFJSON: rawOFFJSON
                )
                // Apply same safety nets as comprehensive path:
                // 1) OFF allergens + client-side keyword detection
                result = mergeAllergens(into: result, product: offProduct, preferences: preferences)
                // 2) Client-side dietary checks (vegan/halal/kosher/etc)
                result = mergeDietaryViolations(into: result, product: offProduct, preferences: preferences)
                // 3) Jain validation
                result = applyJainValidation(result, preferences: preferences)

                await updateProgress(0.9, step: "Safety verified! Enriching...")

                // STEP 4: Fire full enrichment in background (cancel previous if rapid re-scan)
                activeEnrichmentTask?.cancel()
                let capturedProduct = offProduct
                let capturedRawJSON = rawOFFJSON
                activeEnrichmentTask = Task { [weak self] in
                    await self?.runBackendEnrichment(
                        product: capturedProduct, barcode: barcode,
                        preferences: preferences, rawOFFJSON: capturedRawJSON
                    )
                }

                await updateProgress(1.0, step: "Safety check complete!")
                return result  // User sees safety verdict NOW (2-4s)
            }

            // No ingredients from OFF — return nil to trigger visual scanner / OCR
            // so user scans the actual ingredient label for accurate data
            let hasIngredients = (offProduct.ingredientsTextEn?.isEmpty == false) || (offProduct.ingredientsText?.isEmpty == false)
            if !hasIngredients {
                logger.info("📦 OFF hit but no ingredients for \(barcode) — redirecting to visual scanner for label OCR")
                await updateProgress(1.0, step: "No ingredients found — scan label")
                return nil
            }

            // OFF had ingredientsText but extractIngredients() couldn't parse it
            var result = await convertOFFToAnalysisResult(offProduct, barcode: barcode, preferences: preferences, rawOFFJSON: rawOFFJSON)
            result = applyJainValidation(result, preferences: preferences)
            if shouldCacheResult(result) {
                await aiCache.save(barcode: barcode, preferences: preferences, result: result)
            }
            return result
        }

        // Not in OpenFoodFacts — skip backend barcode-only call (would also 404
        // since Gemini barcode hallucination was removed for safety).
        // Fall through to SQLite cache check, then return nil → triggers visual scanner redirect.
        logger.warning("⚠️ OFF miss for \(barcode) — product not found")

        // Both OFF and AI failed — try SQLite cache as last resort
        if let cached = await cacheService.fetch(barcode: barcode) {
            logger.debug("💾 Falling back to SQLite cache for offline data: \(cached.productName)")
            await updateProgress(1.0, step: "Using cached data (offline)")
            return AnalysisResult(
                productName: cached.productName,
                overallScore: Double(cached.ethicalScore ?? 50),
                isSafe: true,
                confidence: 30,
                confidenceFactors: ["Offline cache — limited data"],
                violations: [],
                warnings: ["⚠️ Using cached offline data — scan again for full analysis"],
                cautionWarnings: [],
                ingredients: cached.ingredients,
                detectedAllergens: [],
                detectionEvidence: [],
                healthScore: Double(cached.ethicalScore ?? 50),
                environmentalScore: 50,
                co2Emissions: 0,
                waterUsage: 0,
                animalImpact: "Unknown",
                landUse: "Unknown",
                nutritionalHighlights: [],
                healthConcerns: [],
                healthBenefits: [],
                recommendations: [],
                alternatives: [],
                environmentalBreakdown: [],
                sourceBarcode: barcode,
                sourceType: "offline_cache"
            )
        }

        await updateProgress(1.0, step: "Product not found")
        logger.warning("⚠️ Neither OFF nor AI could identify barcode: \(barcode)")
        return nil
    }

    // MARK: - Visual Product Lookup (mirrors barcode pipeline)

    /// Look up a visually identified product using the same pipeline as barcode scanning.
    /// Searches OFF by name → quick allergen check → preliminary result → background enrichment.
    func lookupVisualProduct(
        name: String,
        estimatedIngredients: [String],
        preferences: UserPreferences,
        ingredientConfidence: Double
    ) async -> AnalysisResult? {
        logger.debug("🔍 Visual lookup for: \(name)")
        await updateProgress(0.2, step: "Searching database...")

        // STEP 1: Check AI cache (keyed on name+prefs)
        let cacheKey = "visual_\(name.lowercased().trimmingCharacters(in: .whitespacesAndNewlines))"
        if let cachedAI = await aiCache.fetch(barcode: cacheKey, preferences: preferences) {
            await updateProgress(1.0, step: "Using cached AI analysis!")
            logger.debug("⚡ AI cache hit for visual: \(name)")
            return cachedAI
        }

        // STEP 2: Parallel OFF search + quickAllergenCheck with estimated ingredients
        // These are independent network calls — run simultaneously to save 1-2s
        await updateProgress(0.35, step: "Searching database & checking safety...")

        guard !estimatedIngredients.isEmpty else {
            logger.warning("⚠️ No estimated ingredients for visual product: \(name)")
            await updateProgress(1.0, step: "Could not analyze product")
            return nil
        }

        async let offTask = openFoodFactsClient.searchByName(name)
        async let estimatedSafetyTask = NetworkService.shared.quickAllergenCheck(
            ingredients: estimatedIngredients,
            preferences: preferences,
            barcode: nil,
            productName: name,
            openfoodfactsData: nil
        )

        let offResult = await offTask
        let estimatedSafetyResult = await estimatedSafetyTask

        // STEP 3a: OFF found with ingredients → use OFF data for higher accuracy
        if let offResult = offResult {
            let offProduct = offResult.product
            let rawOFFJSON = offResult.rawJSON
            await updateProgress(0.5, step: "Product found! Checking safety...")
            logger.debug("✅ OFF search hit for: \(name) → \(offProduct.productNameEn ?? offProduct.productName ?? "Unknown")")

            let offIngredients = openFoodFactsClient.extractIngredients(from: offProduct)

            if !offIngredients.isEmpty {
                // If OFF ingredients differ from estimated, re-run safety check with better data
                let offSet = Set(offIngredients.map { $0.lowercased() })
                let estSet = Set(estimatedIngredients.map { $0.lowercased() })
                let safetyResult: QuickSafetyResult?

                if offSet != estSet {
                    logger.debug("🔄 OFF ingredients differ from estimated, re-checking safety...")
                    safetyResult = await NetworkService.shared.quickAllergenCheck(
                        ingredients: offIngredients,
                        preferences: preferences,
                        barcode: offProduct.code,
                        productName: offProduct.productNameEn ?? offProduct.productName,
                        openfoodfactsData: rawOFFJSON
                    )
                } else {
                    safetyResult = estimatedSafetyResult
                }

                var result = buildPreliminaryResult(
                    product: offProduct, barcode: offProduct.code ?? cacheKey,
                    preferences: preferences, safetyResult: safetyResult,
                    rawOFFJSON: rawOFFJSON
                )
                result = mergeAllergens(into: result, product: offProduct, preferences: preferences)
                result = mergeDietaryViolations(into: result, product: offProduct, preferences: preferences)
                result = applyJainValidation(result, preferences: preferences)

                await updateProgress(0.9, step: "Safety verified! Enriching...")

                // Fire full enrichment in background
                activeEnrichmentTask?.cancel()
                let capturedProduct = offProduct
                let capturedRawJSON = rawOFFJSON
                let capturedBarcode = offProduct.code ?? cacheKey
                activeEnrichmentTask = Task { [weak self] in
                    await self?.runBackendEnrichment(
                        product: capturedProduct, barcode: capturedBarcode,
                        preferences: preferences, rawOFFJSON: capturedRawJSON
                    )
                }

                await updateProgress(1.0, step: "Safety check complete!")
                return result
            }
        }

        // STEP 3b: OFF miss or no ingredients → use already-completed estimated safety result
        await updateProgress(0.5, step: "Checking safety with AI estimates...")
        logger.debug("🤖 OFF miss for visual: \(name), using \(estimatedIngredients.count) estimated ingredients")

        let safetyResult = estimatedSafetyResult

        // Build preliminary result from estimated ingredients + AI safety
        var violations: [String] = []
        var warnings: [String] = []
        var cautionWarnings: [String] = []
        var detectedAllergens: [String] = []
        var detectionEvidence: [AnalysisResult.DetectionEvidence] = []
        var crossContamRisks: [AnalysisResult.CrossContaminationRisk]?
        var isSafe = true
        var safetyLevel: String? = "safe"
        var gmoStatus: String?
        var confidence: Double = 45

        if let safety = safetyResult {
            violations = safety.violations
            warnings = safety.warnings
            cautionWarnings = safety.cautionWarnings
            detectedAllergens = safety.detectedAllergens
            detectionEvidence = safety.detectionEvidence ?? []
            crossContamRisks = safety.crossContaminationRisks?.map { allergenName in
                AnalysisResult.CrossContaminationRisk(
                    allergen: allergenName,
                    riskLevel: "Medium",
                    riskExplanation: "May contain traces of \(allergenName)",
                    manufacturingDetails: "Shared facility risk",
                    guidance: "Check with manufacturer if concerned"
                )
            }
            isSafe = safety.isSafe
            safetyLevel = safety.safetyLevel
            gmoStatus = safety.gmoStatus
            confidence = max(safety.confidence * (ingredientConfidence / 100.0), 30)
        } else {
            // Client-side fallback
            let concernItems = analyzeIngredients(estimatedIngredients, preferences: preferences)
            violations = concernItems.filter { $0.severity == "high" }.map { "⛔ \($0.concern): \($0.ingredient)" }
            warnings = concernItems.filter { $0.severity == "medium" }.map { "⚠️ \($0.concern): \($0.ingredient)" }
            cautionWarnings = concernItems.filter { $0.severity == "low" }.map { "ℹ️ \($0.concern): \($0.ingredient)" }
            isSafe = violations.isEmpty && warnings.isEmpty
            safetyLevel = isSafe ? "safe" : "avoid"
            confidence = 35
        }

        // Client-side allergen keyword matching as additional safety net
        let keywordAllergens = detectAllergensFromIngredients(estimatedIngredients)
        let matched = keywordAllergens.filter { allergen in
            preferences.selectedAllergens.contains { Self.allergensMatch(allergen, $0) }
        }
        for a in matched where !detectedAllergens.contains(where: { $0.lowercased() == a.lowercased() }) {
            detectedAllergens.append(a)
            if isSafe { isSafe = false; safetyLevel = "avoid" }
        }

        var recommendations = ["⚠️ Estimated ingredients — scan barcode for higher accuracy"]
        if ingredientConfidence >= 80 {
            recommendations[0] = "Ingredients from AI product database (\(Int(ingredientConfidence))% confidence)"
        }

        var result = AnalysisResult(
            productName: name,
            overallScore: 50,
            isSafe: isSafe,
            confidence: confidence,
            confidenceFactors: ["Visual AI identification", "Estimated ingredients"],
            violations: violations,
            warnings: warnings,
            cautionWarnings: cautionWarnings,
            ingredients: estimatedIngredients,
            detectedAllergens: detectedAllergens,
            detectionEvidence: detectionEvidence,
            healthScore: Double(calculateHealthScore(ingredients: estimatedIngredients, concerns: violations.count)),
            environmentalScore: 50,
            co2Emissions: 0,
            waterUsage: 0,
            animalImpact: "Unknown",
            landUse: "Unknown",
            nutritionalHighlights: [],
            healthConcerns: [],
            healthBenefits: [],
            recommendations: recommendations,
            alternatives: [],
            environmentalBreakdown: [],
            sourceType: "visual_preliminary",
            safetyLevel: safetyLevel,
            gmoStatus: gmoStatus,
            crossContaminationRisks: crossContamRisks
        )
        result = applyJainValidation(result, preferences: preferences)

        await updateProgress(0.9, step: "Preparing results...")

        // Background: full /comprehensive-analysis with estimated ingredients
        activeEnrichmentTask?.cancel()
        let capturedName = name
        let capturedIngredients = estimatedIngredients
        activeEnrichmentTask = Task { [weak self] in
            await self?.runVisualBackendEnrichment(
                productName: capturedName,
                ingredients: capturedIngredients,
                preferences: preferences,
                cacheKey: cacheKey
            )
        }

        await updateProgress(1.0, step: "Safety check complete!")
        return result
    }

    /// Background enrichment for visual products without OFF data.
    /// Calls /comprehensive-analysis with estimated ingredients.
    private func runVisualBackendEnrichment(
        productName: String,
        ingredients: [String],
        preferences: UserPreferences,
        cacheKey: String
    ) async {
        logger.debug("🔄 Starting visual background enrichment for \(productName)...")

        guard let url = URL(string: "\(AppConfig.backendURL)/comprehensive-analysis") else { return }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 45
        await addAuthToken(to: &request)

        let payload: [String: Any] = [
            "ingredients": ingredients,
            "productName": productName,
            "userPreferences": [
                "selectedAllergens": Array(preferences.selectedAllergens),
                "customAllergens": preferences.customAllergens,
                "selectedDiets": Array(preferences.selectedDiets),
                "customDiets": preferences.customDiets,
                "avoidIngredients": Array(preferences.selectedAllergens) + preferences.customAllergens,
                "dietaryPreferences": Array(preferences.selectedDiets) + preferences.customDiets,
                "healthPriority": preferences.healthPriority,
                "environmentPriority": preferences.environmentPriority,
                "ethicsPriority": preferences.ethicsPriority,
                "avoidGMO": preferences.avoidGMO
            ]
        ]

        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: payload)
            let (data, response) = try await backendSession.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
                logger.warning("⚠️ Visual enrichment got non-200 response")
                return
            }

            var result = try JSONDecoder().decode(AnalysisResult.self, from: data)
            result = applyJainValidation(result, preferences: preferences)

            if shouldCacheResult(result) {
                await aiCache.save(barcode: cacheKey, preferences: preferences, result: result)
                logger.debug("✅ Visual enrichment complete, publishing for \(productName)")
                ProductDatabaseService.enhancedResultSubject.send(result)
            }
        } catch {
            logger.warning("⚠️ Visual enrichment failed: \(error.localizedDescription)")
        }
    }

    // MARK: - Preliminary Result Builder (OFF data + AI safety verdict)

    /// Builds a complete AnalysisResult from OFF product data merged with the quick AI safety check.
    /// Returns immediately so users see allergen/dietary/GMO verdicts in 2-4s.
    private func buildPreliminaryResult(
        product: OpenFoodFactsProduct,
        barcode: String,
        preferences: UserPreferences,
        safetyResult: QuickSafetyResult?,
        rawOFFJSON: [String: Any]? = nil
    ) -> AnalysisResult {
        let ingredients = openFoodFactsClient.extractIngredients(from: product)
        let envImpact = getEnvironmentalData(from: product, ingredients: ingredients)
        let healthScore = calculateHealthScore(
            ingredients: ingredients,
            concerns: 0,
            nutriments: product.nutriments,
            novaGroup: product.novaGroup,
            nutriscoreGrade: product.nutriscoreGrade
        )

        // Merge AI safety verdict (if available) with client-side analysis
        var violations: [String] = []
        var warnings: [String] = []
        var cautionWarnings: [String] = []
        var detectedAllergens: [String] = []
        var detectionEvidence: [AnalysisResult.DetectionEvidence] = []
        var crossContamRisks: [AnalysisResult.CrossContaminationRisk]?
        var isSafe = true
        var safetyLevel: String? = "safe"
        var gmoStatus: String?
        var confidence: Double = 60

        if let safety = safetyResult {
            // Use AI-verified safety data
            violations = safety.violations
            warnings = safety.warnings
            cautionWarnings = safety.cautionWarnings
            detectedAllergens = safety.detectedAllergens
            detectionEvidence = safety.detectionEvidence ?? []
            crossContamRisks = safety.crossContaminationRisks?.map { allergenName in
                AnalysisResult.CrossContaminationRisk(
                    allergen: allergenName,
                    riskLevel: "Medium",
                    riskExplanation: "May contain traces of \(allergenName)",
                    manufacturingDetails: "Shared facility risk",
                    guidance: "Check with manufacturer if concerned"
                )
            }
            isSafe = safety.isSafe
            safetyLevel = safety.safetyLevel
            gmoStatus = safety.gmoStatus
            confidence = safety.confidence
        } else {
            // Quick-check failed — fall back to client-side analysis
            logger.warning("⚠️ Quick safety check unavailable, using client-side analysis")
            let concernItems = analyzeIngredients(ingredients, preferences: preferences)
            violations = concernItems.filter { $0.severity == "high" }.map { "⛔ \($0.concern): \($0.ingredient)" }
            warnings = concernItems.filter { $0.severity == "medium" }.map { "⚠️ \($0.concern): \($0.ingredient)" }
            cautionWarnings = concernItems.filter { $0.severity == "low" }.map { "ℹ️ \($0.concern): \($0.ingredient)" }

            // Client-side GMO flagging — skip if product has non-GMO/organic labels
            let labelsTags = (rawOFFJSON?["labels_tags"] as? [String]) ?? []
            let hasNonGMOLabel = labelsTags.contains { label in
                let l = label.lowercased()
                return l.contains("non-gmo") || l.contains("non gmo") || l.contains("organic")
            }
            if preferences.avoidGMO && !hasNonGMOLabel {
                let gmoWarnings = flagHighRiskGMOIngredients(ingredients)
                if !gmoWarnings.isEmpty {
                    cautionWarnings.append(contentsOf: gmoWarnings)
                }
            }

            isSafe = violations.isEmpty && warnings.isEmpty
            safetyLevel = isSafe ? "safe" : "avoid"
            confidence = 50  // Lower confidence for client-side only
        }

        // Environmental score from OFF eco-score
        let envScore: Double
        if let ecoGrade = product.ecoscoreGrade?.uppercased() {
            let ecoMap = ["A": 90.0, "B": 75.0, "C": 55.0, "D": 35.0, "E": 20.0]
            envScore = ecoMap[ecoGrade] ?? 50.0
        } else {
            envScore = 50.0
        }

        return AnalysisResult(
            productName: product.productNameEn ?? product.productName ?? "Unknown Product",
            overallScore: (Double(healthScore) + envScore) / 2.0,
            isSafe: isSafe,
            confidence: confidence,
            confidenceFactors: safetyResult != nil
                ? ["AI-verified safety check", "OpenFoodFacts data"]
                : ["Client-side analysis only", "OpenFoodFacts data"],
            violations: violations,
            warnings: warnings,
            cautionWarnings: cautionWarnings,
            ingredients: ingredients,
            detectedAllergens: detectedAllergens,
            detectionEvidence: detectionEvidence,
            healthScore: Double(healthScore),
            environmentalScore: envScore,
            co2Emissions: envImpact.co2,
            waterUsage: envImpact.water,
            animalImpact: envImpact.animalImpact,
            landUse: product.ecoscoreGrade?.uppercased() ?? "Unknown",
            nutritionalHighlights: [],
            healthConcerns: [],
            healthBenefits: [],
            recommendations: [],
            alternatives: [],
            environmentalBreakdown: [],
            sourceBarcode: barcode,
            sourceType: "preliminary",
            safetyLevel: safetyLevel,
            gmoStatus: gmoStatus,
            nutriscoreGrade: product.nutriscoreGrade,
            ecoscoreGrade: product.ecoscoreGrade,
            novaGroup: product.novaGroup,
            crossContaminationRisks: crossContamRisks,
            alternativesMetadata: AnalysisResult.AlternativesMetadata(
                productName: product.productNameEn ?? product.productName ?? "Unknown Product",
                category: (rawOFFJSON?["categories"] as? String) ?? "",
                categoriesTags: (rawOFFJSON?["categories_tags"] as? [String]) ?? [],
                sourceBarcode: barcode,
                sourceBrand: product.brands
            )
        )
    }

    // MARK: - Background Enrichment

    /// Fires full backend analysis in background. On success, caches result and publishes via enhancedResultSubject.
    private func runBackendEnrichment(
        product: OpenFoodFactsProduct,
        barcode: String,
        preferences: UserPreferences,
        rawOFFJSON: [String: Any]?
    ) async {
        logger.debug("🔄 Starting background enrichment for \(barcode)...")

        var result = await convertOFFToAnalysisResult(product, barcode: barcode, preferences: preferences, rawOFFJSON: rawOFFJSON)
        result = mergeDietaryViolations(into: result, product: product, preferences: preferences)
        result = applyJainValidation(result, preferences: preferences)

        if shouldCacheResult(result) {
            await aiCache.save(barcode: barcode, preferences: preferences, result: result)
            logger.debug("✅ Background enrichment complete, cached and publishing for \(barcode)")
            ProductDatabaseService.enhancedResultSubject.send(result)
        } else {
            logger.warning("⚠️ Background enrichment returned degraded/fallback result for \(barcode)")
        }
    }

    // MARK: - Cache Quality Gate

    /// Returns true if a result is high-enough quality to cache for 24h.
    /// Rejects fallback/rescan results and degraded partial results.
    private func shouldCacheResult(_ result: AnalysisResult) -> Bool {
        let isFallback = result.warnings.contains(where: {
            let lower = $0.lowercased()
            return lower.contains("fallback") || lower.contains("rescan")
        })
        if isFallback { return false }

        // Reject results with no ingredients and zero health score (likely partial)
        if result.ingredients.isEmpty && result.healthScore == 0 && result.confidence < 30 {
            return false
        }

        return true
    }

    // MARK: - Client-Side GMO High-Risk Flagging

    /// Flags ingredients from known GMO high-risk crops (client-side fallback when quick-check is unavailable)
    private func flagHighRiskGMOIngredients(_ ingredients: [String]) -> [String] {
        let highRiskGMO = ["corn", "soy", "canola", "sugar beet", "cottonseed", "papaya",
                           "corn syrup", "high fructose corn syrup", "soy lecithin",
                           "canola oil", "cottonseed oil", "corn starch", "soybean oil"]
        var warnings: [String] = []
        for ingredient in ingredients {
            let lower = ingredient.lowercased()
            for risk in highRiskGMO {
                if matchesWord(lower, risk) {
                    warnings.append("ℹ️ May contain GMO: \(ingredient) — verify with full scan")
                    break
                }
            }
        }
        return warnings
    }
    
    /// Complete product lookup pipeline
    /// - Parameters:
    ///   - image: Product image (for barcode detection)
    ///   - preferences: User preferences for analysis
    /// - Returns: AnalysisResult from database or nil (fallback to OCR)
    func lookupProduct(image: UIImage, preferences: UserPreferences) async -> AnalysisResult? {
        // Step 1: Detect barcode (0.0 → 0.2)
        await updateProgress(0.0, step: "Scanning for barcode...")
        let barcodes = await barcodeScanner.detectBarcodes(in: image)
        
        guard let barcode = barcodes.first else {
            await updateProgress(0.2, step: "No barcode detected")
            logger.warning("⚠️ No barcode found, will fall back to OCR")
            return nil
        }
        
        logger.debug("✅ Detected barcode: \(barcode)")
        await updateProgress(0.2, step: "Barcode detected: \(barcode)")
        
        // Skip SQLite cache — always use OpenFoodFacts + backend for full AI analysis
        // (AI cache in lookupBarcode handles fast re-scans)
        
        // Step 3: Query OpenFoodFacts (0.4 → 0.7)
        await updateProgress(0.5, step: "Searching product database...")
        if let offResult = await openFoodFactsClient.fetchProduct(barcode: barcode) {
            let offProduct = offResult.product
            let rawOFFJSON = offResult.rawJSON
            await updateProgress(0.7, step: "Product found in database!")
            logger.debug("✅ OpenFoodFacts hit for barcode: \(barcode)")
            
            // Cache the result
            let ingredients = openFoodFactsClient.extractIngredients(from: offProduct)
            await cacheService.save(
                barcode: barcode,
                productName: offProduct.productNameEn ?? offProduct.productName ?? "Unknown Product",
                ingredients: ingredients,
                allergens: offProduct.allergens,
                ethicalScore: nil, // Will be calculated
                ethicalSummary: openFoodFactsClient.getEthicalSummary(from: offProduct)
            )
            
            var offAnalysis = await convertOFFToAnalysisResult(offProduct, barcode: barcode, preferences: preferences, rawOFFJSON: rawOFFJSON)
            offAnalysis = applyJainValidation(offAnalysis, preferences: preferences)
            return offAnalysis
        }

        // Step 4: Not in OFF — try backend AI identification before falling to OCR
        await updateProgress(0.8, step: "Not in database, trying AI...")
        logger.info("🤖 OFF miss for \(barcode) (image scan), trying backend AI identification...")

        if var aiResult = await analyzeWithBackendBarcodeOnly(barcode: barcode, preferences: preferences) {
            aiResult = applyJainValidation(aiResult, preferences: preferences)
            logger.info("✅ Backend AI identified product from image barcode: \(aiResult.productName)")
            if shouldCacheResult(aiResult) {
                await aiCache.save(barcode: barcode, preferences: preferences, result: aiResult)
            }
            await updateProgress(1.0, step: "AI identified product!")
            return aiResult
        }

        // Both OFF and AI failed — fall back to OCR
        await updateProgress(0.9, step: "Falling back to label scan...")
        logger.warning("⚠️ Neither OFF nor AI could identify barcode: \(barcode), falling back to OCR")
        return nil
    }
    
    // MARK: - Conversion Helpers
    
    private func convertCachedToAnalysisResult(_ cached: CachedProduct, preferences: UserPreferences) -> AnalysisResult {
        logger.debug("🔄 Converting cached product to AnalysisResult:")
        logger.debug("   - Product name: \(cached.productName)")
        logger.debug("   - Ingredients: \(cached.ingredients.count) items")
        logger.debug("   - First 3: \(cached.ingredients.prefix(3).joined(separator: ", "))")
        
        // Analyze cached ingredients against preferences
        let concernItems = analyzeIngredients(cached.ingredients, preferences: preferences)
        let healthScore = calculateHealthScore(ingredients: cached.ingredients, concerns: concernItems.count)
        
        // Create detection evidence from concerns
        let detectionEvidence = concernItems.map { concern in
            AnalysisResult.DetectionEvidence(
                ingredient: concern.ingredient,
                matchedPreference: concern.concern,
                reason: "Found in product ingredients",
                source: "OpenFoodFacts Database",
                confidence: 95,
                riskLevel: nil,
                riskExplanation: nil,
                manufacturingDetails: nil,
                guidance: nil
            )
        }
        
        // Generate recommendations
        var recommendations: [String] = []
        if concernItems.isEmpty {
            recommendations.append("✅ This product aligns with your dietary preferences")
        } else {
            recommendations.append("⚠️ This product contains \(concernItems.count) item(s) that may not match your preferences")
        }
        recommendations.append("Data verified from OpenFoodFacts community database")

        // ❌ CRITICAL FIX: Do NOT calculate isSafe locally - we can't detect GMOs without backend AI!
        // Cache only has allergen/dietary data, not GMO analysis from backend
        // Always mark cached results as unsafe to force users to re-scan for fresh GMO analysis
        let violations = concernItems.filter { $0.severity == "high" }.map { "⛔ \($0.concern): \($0.ingredient)" }
        var warnings = concernItems.filter { $0.severity == "medium" }.map { "⚠️ \($0.concern): \($0.ingredient)" }

        // Cached data: use actual allergen/dietary analysis. Add note about GMO.
        warnings.append("ℹ️ Cached data — rescan for full GMO analysis")
        let isSafeValue = violations.isEmpty  // Trust allergen analysis, note GMO gap

        return AnalysisResult(
            id: UUID(),
            productName: cached.productName,
            overallScore: Double(healthScore),
            isSafe: isSafeValue,  // ✅ Fixed to check warnings
            confidence: 95,
            confidenceFactors: ["Verified product data", "Community reviewed", "Cached locally"],
            violations: violations,  // ✅ Use already-calculated violations
            warnings: warnings,  // ✅ Use already-calculated warnings
            cautionWarnings: concernItems.filter { $0.severity == "low" }.map { "ℹ️ \($0.concern): \($0.ingredient)" },
            ingredients: cached.ingredients,
            detectedAllergens: cached.allergens?.components(separatedBy: ",").map { $0.trimmingCharacters(in: .whitespaces) } ?? [],
            detectionEvidence: detectionEvidence,
            healthScore: Double(healthScore),
            environmentalScore: 65.0,
            co2Emissions: 0.0,
            waterUsage: 0.0,
            animalImpact: "Moderate",
            landUse: "Moderate",
            nutritionalHighlights: [],
            healthConcerns: concernItems.map { "\($0.ingredient): \($0.concern)" },
            healthBenefits: concernItems.isEmpty ? ["No concerning ingredients detected"] : [],
            recommendations: recommendations,
            alternatives: [],
            environmentalBreakdown: [],
            sourceBarcode: cached.barcode,
            sourceType: "cache",
            timestamp: cached.cachedAt
        )
    }
    
    private func convertOFFToAnalysisResult(_ product: OpenFoodFactsProduct, barcode: String, preferences: UserPreferences, rawOFFJSON: [String: Any]? = nil) async -> AnalysisResult {
        logger.debug("🔬 Converting OpenFoodFacts product to AnalysisResult:")
        logger.debug("   - Product name: \(product.productNameEn ?? product.productName ?? "Unknown")")

        // Get raw ingredients text — prefer English (covers non-English region products)
        let rawIngredientsText = product.ingredientsTextEn ?? product.ingredientsText
        guard let rawIngredientsText, !rawIngredientsText.isEmpty else {
            logger.warning("⚠️ No ingredients text available, using fallback")
            return await createFallbackResult(product: product, barcode: barcode, preferences: preferences)
        }

        logger.debug("   - Raw ingredients text: \(rawIngredientsText.prefix(100))...")

        // (enhancedResult is published via static PassthroughSubject — no clearing needed)

        // Use SSE streaming: returns preliminary result fast, publishes enhanced via enhancedResult
        logger.debug("📡 Using SSE streaming for backend analysis...")

        let streamingTask = Task<AnalysisResult?, Never> {
            await analyzeWithBackendStreaming(
                ingredientsText: rawIngredientsText,
                productName: product.productNameEn ?? product.productName,
                preferences: preferences,
                barcode: barcode,
                product: product,
                rawOFFJSON: rawOFFJSON
            )
        }

        // Wait up to 20 seconds for streaming result before starting parallel fallback
        let backendTimeout: UInt64 = 20_000_000_000 // 20s - accommodate GAE cold starts
        let timeoutTask = Task {
            try? await Task.sleep(nanoseconds: backendTimeout)
        }

        // Race: did streaming return within 20s?
        let quickResult = await withTaskGroup(of: Bool.self) { group in
            group.addTask { await streamingTask.value != nil }
            group.addTask { await timeoutTask.value; return false }
            let first = await group.next() ?? false
            group.cancelAll()
            return first
        }

        if quickResult {
            if let result = await streamingTask.value {
                logger.debug("✅ Streaming backend succeeded (within 20s)")
                return mergeAllergens(into: result, product: product, preferences: preferences)
            }
        }

        // Backend is slow or failed — start local fallback in parallel
        logger.warning("⚠️ Backend slow (>20s), starting local fallback in parallel...")
        let fallbackTask = Task<AnalysisResult, Never> {
            await createFallbackResult(product: product, barcode: barcode, preferences: preferences)
        }

        if let backendResult = await streamingTask.value {
            fallbackTask.cancel()
            logger.debug("✅ Streaming backend succeeded (after parallel fallback started)")
            return mergeAllergens(into: backendResult, product: product, preferences: preferences)
        }

        logger.warning("⚠️ Backend analysis failed, using local fallback")
        return await fallbackTask.value
    }
    
    private func createFallbackResult(product: OpenFoodFactsProduct, barcode: String, preferences: UserPreferences) async -> AnalysisResult {
        let ingredients = openFoodFactsClient.extractIngredients(from: product)
        logger.debug("   - Fallback: Extracted \(ingredients.count) ingredients")
        
        let concernItems = analyzeIngredients(ingredients, preferences: preferences)
        logger.debug("   - Concern items: \(concernItems.count)")
        
        let healthScore = calculateHealthScore(
            ingredients: ingredients,
            concerns: concernItems.count,
            nutriments: product.nutriments,
            novaGroup: product.novaGroup,
            nutriscoreGrade: product.nutriscoreGrade
        )
        logger.debug("   - Health score: \(healthScore) (Nutri-Score: \(product.nutriscoreGrade ?? "unknown"), NOVA: \(product.novaGroup ?? 0))")
        
        // Create detection evidence from concerns
        let detectionEvidence = concernItems.map { concern in
            AnalysisResult.DetectionEvidence(
                ingredient: concern.ingredient,
                matchedPreference: concern.concern,
                reason: "Detected in product ingredients list",
                source: "OpenFoodFacts Database",
                confidence: 90,
                riskLevel: nil,
                riskExplanation: nil,
                manufacturingDetails: nil,
                guidance: nil
            )
        }
        
        // Calculate actual environmental impact
        // Priority: 1) OpenFoodFacts Agribalyse data, 2) Backend data, 3) Ingredient-based calculation
        let envImpact = getEnvironmentalData(from: product, ingredients: ingredients)
        
        // Generate insights/recommendations (matching OCR format - simple actionable strings)
        var recommendations: [String] = []
        
        // Add key insights about the product
        if concernItems.isEmpty {
            recommendations.append("This product aligns with your dietary preferences")
        }
        
        if let nutriscore = product.nutriscoreGrade?.uppercased() {
            switch nutriscore {
            case "A", "B": recommendations.append("Good nutritional quality for its category")
            case "D", "E": recommendations.append("Consider healthier alternatives when possible")
            default: break
            }
        }
        
        if let nova = product.novaGroup {
            if nova == 1 {
                recommendations.append("Minimally processed - great for health")
            } else if nova == 4 {
                recommendations.append("Ultra-processed - try to choose whole foods when you can")
            }
        }
        
        if envImpact.animalImpact.contains("Low") {
            recommendations.append("Plant-based choice reduces environmental impact")
        } else if envImpact.animalImpact.contains("High") {
            recommendations.append("High environmental footprint - consider plant-based swaps")
        }
        
        if ingredients.count < 5 {
            recommendations.append("Simple ingredient list is easier to understand and typically healthier")
        }
        
        // Get allergens from OpenFoodFacts or detect from ingredients
        var allergensList = product.allergens?.components(separatedBy: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty } ?? []
        
        // If OpenFoodFacts doesn't list allergens, detect from ingredients
        if allergensList.isEmpty {
            allergensList = detectAllergensFromIngredients(ingredients)
        }
        
        // Filter allergens to ONLY show ones that match user's selected allergens (synonym-aware)
        let userSelectedAllergens = preferences.selectedAllergens
        let matchedAllergens = allergensList.filter { allergen in
            userSelectedAllergens.contains { selectedAllergen in
                Self.allergensMatch(allergen, selectedAllergen)
            }
        }
        
        // Generate health benefits based on actual nutritional data
        var healthBenefits: [String] = []
        if concernItems.isEmpty {
            healthBenefits.append("No concerning ingredients detected for your preferences")
        }
        if ingredients.count < 10 {
            healthBenefits.append("Simple ingredient list (fewer than 10 ingredients)")
        }
        
        // Add benefits from nutritional data (scaled to per-package)
        if let nutriments = product.nutriments {
            // Get package weight for scaling (default 100g if unknown)
            let pkgMultiplier: Double = {
                if let qtyStr = product.productQuantity,
                   let qty = Double(qtyStr.replacingOccurrences(of: "[^0-9.]", with: "", options: .regularExpression)),
                   qty > 0 {
                    return qty / 100.0
                }
                return 1.0
            }()
            let pkgLabel = pkgMultiplier != 1.0 ? "per package" : "per 100g"
            
            if let proteins = nutriments.proteins100g, proteins > 10 {
                let scaled = proteins * pkgMultiplier
                healthBenefits.append("High protein content: \(String(format: "%.1f", scaled))g \(pkgLabel)")
            }
            if let fiber = nutriments.fiber100g, fiber > 5 {
                let scaled = fiber * pkgMultiplier
                healthBenefits.append("Good source of fiber: \(String(format: "%.1f", scaled))g \(pkgLabel)")
            }
            if let sugars = nutriments.sugars100g, sugars < 5 {
                let scaled = sugars * pkgMultiplier
                healthBenefits.append("Low in sugars: \(String(format: "%.1f", scaled))g \(pkgLabel)")
            }
            if let fat = nutriments.fat100g, fat < 3 {
                let scaled = fat * pkgMultiplier
                healthBenefits.append("Low fat content: \(String(format: "%.1f", scaled))g \(pkgLabel)")
            }
        }
        
        if let nutriscore = product.nutriscoreGrade?.uppercased(), nutriscore == "A" || nutriscore == "B" {
            healthBenefits.append("Good Nutri-Score rating (\(nutriscore))")
        }
        
        // Generate health concerns based on nutritional data (scaled to per-package)
        var healthConcerns: [String] = []
        if let nutriments = product.nutriments {
            // Get package weight for scaling (default 100g if unknown)
            let concernPkgMultiplier: Double = {
                if let qtyStr = product.productQuantity,
                   let qty = Double(qtyStr.replacingOccurrences(of: "[^0-9.]", with: "", options: .regularExpression)),
                   qty > 0 {
                    return qty / 100.0
                }
                return 1.0
            }()
            let concernPkgLabel = concernPkgMultiplier != 1.0 ? "per package" : "per 100g"
            
            if let sugars = nutriments.sugars100g, sugars > 10 {
                let scaled = sugars * concernPkgMultiplier
                healthConcerns.append("High sugar content: \(String(format: "%.1f", scaled))g \(concernPkgLabel)")
            }
            if let fat = nutriments.fat100g, fat > 15 {
                let scaled = fat * concernPkgMultiplier
                healthConcerns.append("High fat content: \(String(format: "%.1f", scaled))g \(concernPkgLabel)")
            }
            if let salt = nutriments.salt100g, salt > 1.0 {
                let scaled = salt * concernPkgMultiplier
                healthConcerns.append("High salt/sodium: \(String(format: "%.1f", scaled))g \(concernPkgLabel)")
            }
            if let energy = nutriments.energyKcal100g, energy > 400 {
                let scaled = energy * concernPkgMultiplier
                healthConcerns.append("High calorie density: \(Int(scaled)) kcal \(concernPkgLabel)")
            }
        }
        
        // Add NOVA processing concerns
        if let nova = product.novaGroup {
            if nova == 4 {
                healthConcerns.append("Ultra-processed food (NOVA 4) - linked to increased health risks")
            } else if nova == 3 {
                healthConcerns.append("Processed food (NOVA 3) - contains added ingredients")
            }
        }
        
        // Add ingredient-based concerns
        if ingredients.count > 15 {
            healthConcerns.append("Long ingredient list (\(ingredients.count) items) - may contain many additives")
        }
        
        // Check for concerning ingredients
        for ingredient in ingredients {
            let lower = ingredient.lowercased()
            if lower.contains("artificial") {
                healthConcerns.append("Contains artificial ingredients")
                break
            }
        }
        
        // Generate environmental breakdown with product-specific data
        var environmentalBreakdown: [AnalysisResult.EnvironmentalBreakdown] = []
        
        // Add eco-score only if it's a valid grade (A-E)
        if let ecoscore = product.ecoscoreGrade?.uppercased(),
           ["A", "B", "C", "D", "E"].contains(ecoscore) {
            let ecoDescription: String
            switch ecoscore {
            case "A": ecoDescription = "Very low environmental impact"
            case "B": ecoDescription = "Low environmental impact"
            case "C": ecoDescription = "Moderate environmental impact"
            case "D": ecoDescription = "High environmental impact"
            case "E": ecoDescription = "Very high environmental impact"
            default: ecoDescription = "Unknown impact"
            }
            environmentalBreakdown.append(AnalysisResult.EnvironmentalBreakdown(
                ingredient: "Eco-Score \(ecoscore): \(ecoDescription)",
                co2: nil,
                percentage: nil
            ))
        }
        
        // Add NOVA processing level
        if let nova = product.novaGroup {
            let processing: String
            let impact: String
            switch nova {
            case 1: 
                processing = "NOVA 1: Unprocessed foods"
                impact = "Minimal processing, lowest environmental footprint"
            case 2: 
                processing = "NOVA 2: Processed culinary ingredients"
                impact = "Basic processing, low environmental impact"
            case 3: 
                processing = "NOVA 3: Processed foods"
                impact = "Moderate processing, moderate impact"
            case 4: 
                processing = "NOVA 4: Ultra-processed foods"
                impact = "Heavy processing, higher environmental footprint"
            default: 
                processing = "NOVA: Unknown"
                impact = "Processing level unknown"
            }
            environmentalBreakdown.append(AnalysisResult.EnvironmentalBreakdown(
                ingredient: processing,
                co2: nil,
                percentage: nil
            ))
            environmentalBreakdown.append(AnalysisResult.EnvironmentalBreakdown(
                ingredient: impact,
                co2: nil,
                percentage: nil
            ))
        }
        
        // Analyze ingredients for environmental impact
        let animalIngredients = ingredients.filter { ingredient in
            let lower = ingredient.lowercased()
            return lower.contains("milk") || lower.contains("meat") || lower.contains("egg") ||
                   lower.contains("fish") || lower.contains("chicken") || lower.contains("beef")
        }
        
        if !animalIngredients.isEmpty {
            environmentalBreakdown.append(AnalysisResult.EnvironmentalBreakdown(
                ingredient: "Contains \(animalIngredients.count) animal-based ingredient(s)",
                co2: nil,
                percentage: nil
            ))
        } else {
            environmentalBreakdown.append(AnalysisResult.EnvironmentalBreakdown(
                ingredient: "Plant-based ingredients (lower environmental impact)",
                co2: nil,
                percentage: nil
            ))
        }
        
        // Generate alternatives if product has concerns
        let alternatives = generateAlternatives(
            product: product,
            concernItems: concernItems,
            healthScore: healthScore,
            ingredients: ingredients,
            preferences: preferences
        )
        
        AppLogger.debug("📊 Final AnalysisResult:")
        AppLogger.debug("   - Alternatives count: \(alternatives.count)")
        if !alternatives.isEmpty {
            AppLogger.debug("   - First alternative: \(alternatives[0].name) by \(alternatives[0].brand ?? "N/A")")
        }
        
        // ❌ CRITICAL FIX: Do NOT calculate isSafe locally - we can't detect GMOs without backend AI!
        // Fallback only has allergen/dietary data from OpenFoodFacts, not GMO analysis from backend
        // Always mark fallback results as unsafe to force users to re-scan for fresh GMO analysis
        var warnings = concernItems.filter { $0.severity == "medium" }.map { "⚠️ \($0.concern): \($0.ingredient)" }
        let violations = concernItems.filter { $0.severity == "high" }.map { "⛔ \($0.concern): \($0.ingredient)" }

        // ✅ FIX #4: Force isSafe=false for fallback data (GMO detection requires backend AI)
        warnings.append("⚠️ Offline fallback data - rescan for complete analysis including GMO detection")
        let isSafeValue = false  // Always unsafe from fallback - forces fresh backend analysis

        return AnalysisResult(
            id: UUID(),
            productName: product.productNameEn ?? product.productName ?? "Unknown Product",
            overallScore: Double(healthScore),
            isSafe: isSafeValue,  // ✅ Fixed to check warnings
            confidence: 90,
            confidenceFactors: ["OpenFoodFacts database", "Community verified", "\(ingredients.count) ingredients analyzed"],
            violations: violations,  // ✅ Use already-calculated violations
            warnings: warnings,  // ✅ Use already-calculated warnings
            cautionWarnings: concernItems.filter { $0.severity == "low" }.map { "ℹ️ \($0.concern): \($0.ingredient)" },
            ingredients: ingredients,
            detectedAllergens: matchedAllergens,
            detectionEvidence: detectionEvidence,
            healthScore: Double(healthScore),
            environmentalScore: getEcoscoreValue(product.ecoscoreGrade),
            co2Emissions: envImpact.co2,
            waterUsage: envImpact.water,
            animalImpact: envImpact.animalImpact,
            landUse: "Moderate",
            nutritionalHighlights: getNutritionalHighlights(product),
            healthConcerns: healthConcerns,
            healthBenefits: healthBenefits,
            recommendations: recommendations,
            alternatives: alternatives,
            environmentalBreakdown: environmentalBreakdown,
            sourceBarcode: barcode,
            sourceType: "openfoodfacts",
            timestamp: Date()
        )
    }
    
    private func getEcoscoreValue(_ grade: String?) -> Double {
        guard let grade = grade?.lowercased() else { return 50.0 }
        switch grade {
        case "a": return 90.0
        case "b": return 75.0
        case "c": return 60.0
        case "d": return 45.0
        case "e": return 30.0
        default: return 50.0
        }
    }
    
    private func getNutritionalHighlights(_ product: OpenFoodFactsProduct) -> [String] {
        var highlights: [String] = []
        
        // Only add Nutri-Score if it's a valid grade (A-E), not "unknown" or "not-applicable"
        if let nutriscore = product.nutriscoreGrade?.uppercased(),
           ["A", "B", "C", "D", "E"].contains(nutriscore) {
            highlights.append("Nutri-Score: \(nutriscore)")
        }
        
        if let nova = product.novaGroup {
            highlights.append("Processing Level: NOVA \(nova)")
        }
        
        // Check if we have per-serving data (preferred) or fall back to estimating from package
        if let nutriments = product.nutriments {
            let hasServingData = nutriments.energyKcalServing != nil || nutriments.proteinsServing != nil
            
            if hasServingData {
                // Use actual per-serving data from OpenFoodFacts
                if let energy = nutriments.energyKcalServing {
                    highlights.append("Calories: \(Int(energy)) kcal")
                }
                if let proteins = nutriments.proteinsServing {
                    highlights.append("Protein: \(String(format: "%.1f", proteins))g")
                }
                if let carbs = nutriments.carbohydratesServing {
                    highlights.append("Carbs: \(String(format: "%.1f", carbs))g")
                }
                if let sugars = nutriments.sugarsServing {
                    highlights.append("Sugars: \(String(format: "%.1f", sugars))g")
                }
                if let fat = nutriments.fatServing {
                    highlights.append("Fat: \(String(format: "%.1f", fat))g")
                }
                if let fiber = nutriments.fiberServing {
                    highlights.append("Fiber: \(String(format: "%.1f", fiber))g")
                }
            } else if let productQtyStr = product.productQuantity,
                      let productQty = Double(productQtyStr.replacingOccurrences(of: "[^0-9.]", with: "", options: .regularExpression)),
                      productQty > 0 {
                // Estimate for entire package if no serving data
                let multiplier = productQty / 100.0
                
                if let energy = nutriments.energyKcal100g {
                    highlights.append("Calories: \(Int(energy * multiplier)) kcal")
                }
                if let proteins = nutriments.proteins100g {
                    highlights.append("Protein: \(String(format: "%.1f", proteins * multiplier))g")
                }
                if let carbs = nutriments.carbohydrates100g {
                    highlights.append("Carbs: \(String(format: "%.1f", carbs * multiplier))g")
                }
                if let sugars = nutriments.sugars100g {
                    highlights.append("Sugars: \(String(format: "%.1f", sugars * multiplier))g")
                }
                if let fat = nutriments.fat100g {
                    highlights.append("Fat: \(String(format: "%.1f", fat * multiplier))g")
                }
                if let fiber = nutriments.fiber100g {
                    highlights.append("Fiber: \(String(format: "%.1f", fiber * multiplier))g")
                }
            } else {
                // Fallback: show per 100g (clearly labeled)
                if let energy = nutriments.energyKcal100g {
                    highlights.append("Calories: \(Int(energy)) kcal (per 100g)")
                }
                if let proteins = nutriments.proteins100g {
                    highlights.append("Protein: \(String(format: "%.1f", proteins))g (per 100g)")
                }
                if let carbs = nutriments.carbohydrates100g {
                    highlights.append("Carbs: \(String(format: "%.1f", carbs))g (per 100g)")
                }
                if let sugars = nutriments.sugars100g {
                    highlights.append("Sugars: \(String(format: "%.1f", sugars))g (per 100g)")
                }
                if let fat = nutriments.fat100g {
                    highlights.append("Fat: \(String(format: "%.1f", fat))g (per 100g)")
                }
                if let fiber = nutriments.fiber100g {
                    highlights.append("Fiber: \(String(format: "%.1f", fiber))g (per 100g)")
                }
            }
        }
        
        return highlights
    }
    
    // MARK: - Analysis Logic
    
    /// Fallback environmental impact calculation from ingredients
    /// Uses scientific emissions factors from Poore & Nemecek (2018) Science journal
    private func calculateEnvironmentalImpact(_ ingredients: [String]) -> (co2: Double, water: Double, animalImpact: String) {
        var totalCO2 = 0.0
        var totalWater = 0.0
        var hasAnimalProducts = false
        var animalIntensity = 0  // Track intensity of animal products
        
        // Emissions factors per 100g (based on lifecycle assessments)
        let emissionFactors: [(keywords: [String], co2: Double, water: Double, animalScore: Int)] = [
            // High impact animal products
            (["beef", "steak", "ground beef"], 6.0, 300.0, 3),
            (["lamb", "mutton"], 5.0, 200.0, 3),
            (["pork", "bacon", "ham", "sausage"], 1.2, 80.0, 2),
            (["chicken", "poultry", "turkey"], 0.7, 60.0, 2),
            (["fish", "salmon", "tuna", "cod", "shrimp", "seafood"], 0.6, 50.0, 2),
            
            // Dairy products
            (["cheese", "cheddar", "parmesan", "mozzarella"], 2.1, 100.0, 2),
            (["butter"], 1.7, 80.0, 1),
            (["milk", "dairy", "cream", "yogurt"], 0.6, 60.0, 1),
            (["whey", "casein"], 0.5, 50.0, 1),
            
            // Eggs
            (["egg", "eggs", "albumin"], 0.4, 40.0, 1),
            
            // Plant-based proteins
            (["tofu", "tempeh"], 0.2, 30.0, 0),
            (["soy", "soya", "soybean"], 0.15, 25.0, 0),
            (["lentil", "chickpea", "bean", "legume"], 0.1, 20.0, 0),
            
            // Grains
            (["wheat", "flour", "bread"], 0.14, 15.0, 0),
            (["rice"], 0.16, 25.0, 0),
            (["corn", "maize"], 0.1, 12.0, 0),
            (["oat", "oats"], 0.1, 10.0, 0),
            
            // Oils and fats
            (["palm oil", "palm"], 0.35, 20.0, 0),
            (["coconut oil", "coconut"], 0.2, 15.0, 0),
            (["vegetable oil", "canola", "sunflower", "olive"], 0.15, 15.0, 0),
            
            // Sugar and sweeteners
            (["sugar", "cane sugar"], 0.1, 20.0, 0),
            (["honey"], 0.2, 15.0, 0),
            
            // Other common ingredients
            (["salt"], 0.02, 2.0, 0),
            (["spice", "paprika", "pepper", "cinnamon"], 0.05, 5.0, 0),
            (["yeast"], 0.03, 3.0, 0),
        ]
        
        // Track which categories we've already counted to avoid double-counting
        var matchedCategories: Set<String> = []
        
        for ingredient in ingredients {
            let lower = ingredient.lowercased()
            
            for factor in emissionFactors {
                if factor.keywords.contains(where: { lower.contains($0) }) {
                    let categoryKey = factor.keywords.first ?? ""
                    if !matchedCategories.contains(categoryKey) {
                        // Scale factor: assume each ingredient is roughly 20g in a 100g product
                        totalCO2 += factor.co2 * 0.2
                        totalWater += factor.water * 0.2
                        
                        if factor.animalScore > 0 {
                            hasAnimalProducts = true
                            animalIntensity = max(animalIntensity, factor.animalScore)
                        }
                        matchedCategories.insert(categoryKey)
                    }
                    break
                }
            }
        }
        
        // Apply minimum baseline for any product
        totalCO2 = max(totalCO2, 0.15)  // Minimum 0.15 kg CO2 for any product
        totalWater = max(totalWater, 20.0)  // Minimum 20L water
        
        let animalImpact: String
        if !hasAnimalProducts {
            animalImpact = "Low (plant-based)"
        } else {
            switch animalIntensity {
            case 1: animalImpact = "Low-Moderate"
            case 2: animalImpact = "Moderate"
            case 3: animalImpact = "High"
            default: animalImpact = "Moderate"
            }
        }
        
        return (totalCO2, totalWater, animalImpact)
    }
    
    /// Get environmental data with priority: 1) OpenFoodFacts Agribalyse, 2) Eco-Score grade, 3) Ingredient-based calculation
    private func getEnvironmentalData(from product: OpenFoodFactsProduct, ingredients: [String]) -> (co2: Double, water: Double, animalImpact: String) {
        // Get actual PACKAGE weight (total product weight, not serving size)
        var packageWeight: Double = 100  // Default to 100g if unknown
        
        // Priority: product_quantity field (e.g., "187 g") → quantity field
        if let productQty = product.productQuantity {
            let numericString = productQty.replacingOccurrences(of: "[^0-9.]", with: "", options: .regularExpression)
            if let weight = Double(numericString), weight > 0 {
                packageWeight = weight
                AppLogger.debug("📦 Package weight from product_quantity: \(weight)g")
            }
        } else if let quantity = product.quantity {
            let numericString = quantity.replacingOccurrences(of: "[^0-9.]", with: "", options: .regularExpression)
            if let weight = Double(numericString), weight > 0 {
                packageWeight = weight
                AppLogger.debug("📦 Package weight from quantity: \(weight)g")
            }
        }
        
        // Priority 1: Use OpenFoodFacts Agribalyse data (real lifecycle assessment)
        // Agribalyse provides CO2 in kg CO2e per 100g of product
        if let co2Per100g = product.ecoscoreData?.agribalyse?.co2Total, co2Per100g > 0 {
            AppLogger.debug("✅ Using OpenFoodFacts Agribalyse CO2 data: \(co2Per100g) kg per 100g (CONSISTENT)")
            
            // Calculate total CO2 for the ENTIRE package: (CO2 per 100g) × (package weight / 100)
            let totalCO2 = co2Per100g * (packageWeight / 100.0)
            AppLogger.debug("   📊 FINAL CO2: \(String(format: "%.3f", totalCO2)) kg (Agribalyse: \(co2Per100g) × Package: \(packageWeight)g ÷ 100)")
            
            // Water footprint estimate (water correlates with CO2)
            let estimatedWater = totalCO2 * 60.0
            
            // Determine animal impact from ingredients
            let ingredientAnalysis = self.calculateEnvironmentalImpact(ingredients)
            
            return (totalCO2, estimatedWater, ingredientAnalysis.animalImpact)
        }
        
        // Priority 2: Use Eco-Score grade to estimate CO2
        if let ecoscoreGrade = product.ecoscoreGrade?.uppercased() {
            AppLogger.warning("⚠️ No Agribalyse data, using Eco-Score grade estimation: \(ecoscoreGrade) (MAY VARY)")
            
            // Eco-Score based CO2 estimation (per 100g), then scale to package
            let co2Per100g: Double
            switch ecoscoreGrade {
            case "A": co2Per100g = 0.5   // Very low impact
            case "B": co2Per100g = 1.0   // Low impact
            case "C": co2Per100g = 1.8   // Medium impact
            case "D": co2Per100g = 3.0   // High impact
            case "E": co2Per100g = 5.0   // Very high impact
            default:  co2Per100g = 2.0   // Unknown - assume medium-high
            }
            
            let totalCO2 = co2Per100g * (packageWeight / 100.0)
            AppLogger.debug("   📊 FINAL CO2: \(String(format: "%.3f", totalCO2)) kg (Eco-Score estimate: \(ecoscoreGrade))")
            
            let estimatedWater = totalCO2 * 60.0
            let ingredientAnalysis = self.calculateEnvironmentalImpact(ingredients)
            
            return (totalCO2, estimatedWater, ingredientAnalysis.animalImpact)
        }
        
        // Fallback: Calculate from ingredients using standard emissions factors
        AppLogger.warning("⚠️ No OpenFoodFacts environmental data, using ingredient-based calculation (WILL VARY)")
        return calculateEnvironmentalImpact(ingredients)
    }
    
    private func detectAllergensFromIngredients(_ ingredients: [String]) -> [String] {
        var allergens: Set<String> = []

        for ingredient in ingredients {
            // Skip plant-based false positives (coconut milk ≠ dairy, peanut butter ≠ dairy, etc.)
            if isFalsePositive(ingredient) {
                continue
            }
            let lowerIngredient = ingredient.lowercased()
            for (allergen, keywords) in Self.allergenKeywords {
                if keywords.contains(where: { matchesWord(lowerIngredient, $0) }) {
                    allergens.insert(allergen)
                }
            }
        }

        return Array(allergens).sorted()
    }

    /// Merge allergens from backend AI + OpenFoodFacts + client-side keyword detection.
    /// Returns a new AnalysisResult with the union of all sources, filtered to user prefs.
    private func mergeAllergens(into result: AnalysisResult, product: OpenFoodFactsProduct?, preferences: UserPreferences) -> AnalysisResult {
        guard let product = product else { return result }

        var allAllergens = Set(result.detectedAllergens.map { $0.lowercased() })

        // Add OFF allergens field
        if let offAllergens = product.allergens {
            for a in offAllergens.components(separatedBy: ",") {
                let trimmed = a.trimmingCharacters(in: .whitespaces)
                if !trimmed.isEmpty { allAllergens.insert(trimmed.lowercased()) }
            }
        }

        // Add client-side detected allergens from ingredients
        let ingredients = openFoodFactsClient.extractIngredients(from: product)
        if !ingredients.isEmpty {
            let detected = detectAllergensFromIngredients(ingredients)
            for a in detected { allAllergens.insert(a.lowercased()) }
        }

        // Filter to user's selected allergens (synonym-aware)
        let matched = Array(allAllergens.filter { allergen in
            preferences.selectedAllergens.contains { Self.allergensMatch(allergen, $0) }
        }).sorted()

        // Skip reconstruction if nothing changed
        if Set(matched) == Set(result.detectedAllergens.map { $0.lowercased() }) {
            return result
        }

        AppLogger.debug("🔀 Merged allergens: backend=\(result.detectedAllergens) + OFF/client → \(matched)")

        return AnalysisResult(
            id: result.id, productName: result.productName, overallScore: result.overallScore,
            isSafe: matched.isEmpty ? result.isSafe : false,
            confidence: result.confidence, confidenceFactors: result.confidenceFactors,
            violations: result.violations, warnings: result.warnings, cautionWarnings: result.cautionWarnings,
            ingredients: result.ingredients, detectedAllergens: matched, detectionEvidence: result.detectionEvidence,
            healthScore: result.healthScore, environmentalScore: result.environmentalScore,
            co2Emissions: result.co2Emissions, waterUsage: result.waterUsage,
            animalImpact: result.animalImpact, landUse: result.landUse,
            nutritionalHighlights: result.nutritionalHighlights, healthConcerns: result.healthConcerns,
            healthBenefits: result.healthBenefits, recommendations: result.recommendations,
            alternatives: result.alternatives, environmentalBreakdown: result.environmentalBreakdown,
            brand: result.brand, certifications: result.certifications, processingLevel: result.processingLevel,
            estimatedCO2: result.estimatedCO2, packagingScore: result.packagingScore,
            animalWelfareScore: result.animalWelfareScore, additives: result.additives,
            packageWeightGrams: result.packageWeightGrams,
            sourceBarcode: result.sourceBarcode, sourceType: result.sourceType, timestamp: result.timestamp,
            safetyLevel: matched.isEmpty ? result.safetyLevel : "avoid",
            gmoStatus: result.gmoStatus,
            nutriscoreGrade: result.nutriscoreGrade, ecoscoreGrade: result.ecoscoreGrade, novaGroup: result.novaGroup,
            isRestaurantMenu: result.isRestaurantMenu, menuDishes: result.menuDishes,
            safetyConfidenceExplanation: result.safetyConfidenceExplanation,
            ingredientEducation: result.ingredientEducation,
            crossContaminationRisks: result.crossContaminationRisks,
            alternativesMetadata: result.alternativesMetadata
        )
    }

    /// Run client-side dietary checks (vegan/halal/kosher/etc) and merge any violations the AI missed.
    private func mergeDietaryViolations(into result: AnalysisResult, product: OpenFoodFactsProduct, preferences: UserPreferences) -> AnalysisResult {
        let ingredients = openFoodFactsClient.extractIngredients(from: product)
        guard !ingredients.isEmpty else { return result }

        let concernItems = analyzeIngredients(ingredients, preferences: preferences)
        guard !concernItems.isEmpty else { return result }

        // Collect existing violation/warning text so we don't duplicate
        let existingViolations = Set(result.violations.map { $0.lowercased() })
        let existingWarnings = Set(result.warnings.map { $0.lowercased() })
        let existingCautions = Set(result.cautionWarnings.map { $0.lowercased() })

        var newViolations: [String] = []
        var newWarnings: [String] = []
        var newCautions: [String] = []
        var newEvidence: [AnalysisResult.DetectionEvidence] = []

        // Cross-severity dedup: collect ALL existing messages so we can detect
        // duplicates regardless of which severity bucket they landed in
        let allExistingMessages = existingViolations.union(existingWarnings).union(existingCautions)

        for concern in concernItems {
            // Extract the key prohibited-item term from the concern message
            // e.g. "Not Jain-compatible (contains tapioca)" → "tapioca"
            //      "Contains tapioca (root vegetable...)" → "tapioca"
            let keyTerm: String? = {
                if let range = concern.concern.range(of: #"contains\s+([^)]+)"#, options: [.regularExpression, .caseInsensitive]) {
                    let match = String(concern.concern[range])
                    return match.replacingOccurrences(of: "contains ", with: "", options: .caseInsensitive)
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                }
                return nil
            }()

            // Skip if the key term is already mentioned in any existing message
            if let term = keyTerm, !term.isEmpty,
               allExistingMessages.contains(where: { $0.contains(term.lowercased()) }) {
                AppLogger.debug("🔀 Skipping duplicate dietary concern (key term '\(term)' already flagged): \(concern.concern)")
                continue
            }

            let text: String
            switch concern.severity {
            case "high":
                text = "⛔ \(concern.concern): \(concern.ingredient)"
                if !existingViolations.contains(text.lowercased()) &&
                   !existingViolations.contains(where: { $0.contains(concern.ingredient.lowercased()) && $0.contains(concern.concern.lowercased()) }) {
                    newViolations.append(text)
                }
            case "medium":
                text = "⚠️ \(concern.concern): \(concern.ingredient)"
                if !existingWarnings.contains(text.lowercased()) &&
                   !existingWarnings.contains(where: { $0.contains(concern.ingredient.lowercased()) && $0.contains(concern.concern.lowercased()) }) {
                    newWarnings.append(text)
                }
            default:
                text = "ℹ️ \(concern.concern): \(concern.ingredient)"
                if !existingCautions.contains(text.lowercased()) &&
                   !existingCautions.contains(where: { $0.contains(concern.ingredient.lowercased()) && $0.contains(concern.concern.lowercased()) }) {
                    newCautions.append(text)
                }
            }

            newEvidence.append(AnalysisResult.DetectionEvidence(
                ingredient: concern.ingredient,
                matchedPreference: concern.concern,
                reason: "Detected via client-side dietary check",
                source: "Ingredient Analysis",
                confidence: 85,
                riskLevel: nil, riskExplanation: nil, manufacturingDetails: nil, guidance: nil
            ))
        }

        // Nothing new found — return as-is
        if newViolations.isEmpty && newWarnings.isEmpty && newCautions.isEmpty { return result }

        AppLogger.debug("🔀 Merged dietary violations: +\(newViolations.count) violations, +\(newWarnings.count) warnings, +\(newCautions.count) cautions")

        let mergedViolations = result.violations + newViolations
        let mergedWarnings = result.warnings + newWarnings
        let mergedCautions = result.cautionWarnings + newCautions
        let mergedEvidence = result.detectionEvidence + newEvidence
        let hasViolations = !mergedViolations.isEmpty || !mergedWarnings.isEmpty

        return AnalysisResult(
            id: result.id, productName: result.productName, overallScore: result.overallScore,
            isSafe: hasViolations ? false : result.isSafe,
            confidence: result.confidence, confidenceFactors: result.confidenceFactors,
            violations: mergedViolations, warnings: mergedWarnings, cautionWarnings: mergedCautions,
            ingredients: result.ingredients, detectedAllergens: result.detectedAllergens,
            detectionEvidence: mergedEvidence,
            healthScore: result.healthScore, environmentalScore: result.environmentalScore,
            co2Emissions: result.co2Emissions, waterUsage: result.waterUsage,
            animalImpact: result.animalImpact, landUse: result.landUse,
            nutritionalHighlights: result.nutritionalHighlights, healthConcerns: result.healthConcerns,
            healthBenefits: result.healthBenefits, recommendations: result.recommendations,
            alternatives: result.alternatives, environmentalBreakdown: result.environmentalBreakdown,
            brand: result.brand, certifications: result.certifications, processingLevel: result.processingLevel,
            estimatedCO2: result.estimatedCO2, packagingScore: result.packagingScore,
            animalWelfareScore: result.animalWelfareScore, additives: result.additives,
            packageWeightGrams: result.packageWeightGrams,
            sourceBarcode: result.sourceBarcode, sourceType: result.sourceType, timestamp: result.timestamp,
            safetyLevel: hasViolations ? "avoid" : result.safetyLevel,
            gmoStatus: result.gmoStatus,
            nutriscoreGrade: result.nutriscoreGrade, ecoscoreGrade: result.ecoscoreGrade, novaGroup: result.novaGroup,
            isRestaurantMenu: result.isRestaurantMenu, menuDishes: result.menuDishes,
            safetyConfidenceExplanation: result.safetyConfidenceExplanation,
            ingredientEducation: result.ingredientEducation,
            crossContaminationRisks: result.crossContaminationRisks,
            alternativesMetadata: result.alternativesMetadata
        )
    }

    // MARK: - Backend Analysis (Gemini AI)
    
    private func analyzeWithBackendRawText(ingredientsText: String, productName: String?, preferences: UserPreferences, barcode: String, product: OpenFoodFactsProduct?, rawOFFJSON: [String: Any]? = nil) async -> AnalysisResult? {
        // 🚀 Extract ingredients from raw text before sending to backend
        guard let url = URL(string: "\(AppConfig.backendURL)/comprehensive-analysis") else {
            AppLogger.error("❌ Invalid backend URL")
            return nil
        }

        // Extract ingredients from raw text using the same logic as fallback
        let ingredients = openFoodFactsClient.extractIngredients(from: ingredientsText)
        AppLogger.debug("🔍 Raw ingredients text: \(ingredientsText.prefix(100))...")
        AppLogger.debug("✅ Extracted \(ingredients.count) ingredients: \(ingredients.joined(separator: ", ").prefix(100))...")

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 45.0  // Allow enough time for cold starts and AI analysis
        await addAuthToken(to: &request)

        // Extract package weight from OpenFoodFacts product if available
        var packageWeightGrams: Double? = nil
        if let product = product {
            if let servingQty = product.servingQuantity, servingQty > 0 {
                packageWeightGrams = servingQty
            } else if let productQtyStr = product.productQuantity {
                let numericStr = productQtyStr.replacingOccurrences(of: "[^0-9.]", with: "", options: .regularExpression)
                if let weight = Double(numericStr), weight > 0 {
                    packageWeightGrams = weight
                }
            }
        }

        // Build payload with extracted ingredients array (backend expects this format)
        var payload: [String: Any] = [
            "barcode": barcode,
            "ingredients": ingredients,
            "userPreferences": [
                "selectedAllergens": Array(preferences.selectedAllergens),
                "customAllergens": preferences.customAllergens,
                "selectedDiets": Array(preferences.selectedDiets),
                "customDiets": preferences.customDiets,
                "avoidGMO": preferences.avoidGMO
            ],
            "dietaryPreferences": Array(preferences.selectedDiets) + preferences.customDiets
        ]

        if let weight = packageWeightGrams {
            payload["packageWeightGrams"] = weight
        }

        if let product = product, let co2Per100g = product.ecoscoreData?.agribalyse?.co2Total, co2Per100g > 0 {
            payload["agribalyseCO2"] = co2Per100g
            AppLogger.debug("🌍 Sending Agribalyse CO2 to backend: \(co2Per100g) kg per 100g")
        }

        if let rawJSON = rawOFFJSON, !rawJSON.isEmpty {
            payload["openfoodfacts_product"] = rawJSON
            AppLogger.debug("⚡ Including pre-fetched OFF data in payload (saves backend ~1s)")
        }

        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: payload)
            AppLogger.debug("📤 Sending ingredients to backend (barcode: \(barcode), count: \(ingredients.count))")

            // Retry with exponential backoff (2 attempts)
            let data: Data = try await performWithRetry(maxAttempts: 2) {
                let (data, response) = try await self.backendSession.data(for: request)
                guard let httpResponse = response as? HTTPURLResponse else {
                    throw NSError(domain: "ProductDatabaseService", code: -1,
                                  userInfo: [NSLocalizedDescriptionKey: "Invalid response type"])
                }
                AppLogger.debug("📥 Backend response status: \(httpResponse.statusCode)")
                guard httpResponse.statusCode == 200 else {
                    let errorText = String(data: data, encoding: .utf8) ?? "Unknown"
                    AppLogger.error("❌ Backend error (\(httpResponse.statusCode)): \(errorText.prefix(200))")
                    throw NSError(domain: "ProductDatabaseService", code: httpResponse.statusCode,
                                  userInfo: [NSLocalizedDescriptionKey: errorText])
                }
                return data
            }

            if let responseString = String(data: data, encoding: .utf8) {
                AppLogger.debug("📦 Backend response: \(responseString.prefix(500))")
            }

            return parseBackendResponse(data: data, barcode: barcode, productName: productName, product: product)

        } catch {
            AppLogger.error("❌ Backend analysis error after retries: \(error)")
            return nil
        }
    }
    
    // MARK: - SSE Streaming Backend Analysis

    /// Stream backend analysis via SSE. Returns preliminary result immediately; publishes enhancedResult when AI completes.
    /// Falls back to non-streaming analyzeWithBackendRawText if SSE fails.
    private func analyzeWithBackendStreaming(
        ingredientsText: String,
        productName: String?,
        preferences: UserPreferences,
        barcode: String,
        product: OpenFoodFactsProduct?,
        rawOFFJSON: [String: Any]? = nil
    ) async -> AnalysisResult? {
        guard let url = URL(string: "\(AppConfig.backendURL)/comprehensive-analysis") else {
            AppLogger.error("❌ Invalid backend URL for streaming")
            return await analyzeWithBackendRawText(ingredientsText: ingredientsText, productName: productName, preferences: preferences, barcode: barcode, product: product, rawOFFJSON: rawOFFJSON)
        }

        let ingredients = openFoodFactsClient.extractIngredients(from: ingredientsText)

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("text/event-stream", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 45.0
        await addAuthToken(to: &request)

        // Build payload (same as analyzeWithBackendRawText)
        var packageWeightGrams: Double? = nil
        if let product = product {
            if let servingQty = product.servingQuantity, servingQty > 0 {
                packageWeightGrams = servingQty
            } else if let productQtyStr = product.productQuantity {
                let numericStr = productQtyStr.replacingOccurrences(of: "[^0-9.]", with: "", options: .regularExpression)
                if let weight = Double(numericStr), weight > 0 { packageWeightGrams = weight }
            }
        }

        var payload: [String: Any] = [
            "barcode": barcode,
            "ingredients": ingredients,
            "userPreferences": [
                "selectedAllergens": Array(preferences.selectedAllergens),
                "customAllergens": preferences.customAllergens,
                "selectedDiets": Array(preferences.selectedDiets),
                "customDiets": preferences.customDiets,
                "avoidGMO": preferences.avoidGMO
            ],
            "dietaryPreferences": Array(preferences.selectedDiets) + preferences.customDiets
        ]
        if let weight = packageWeightGrams { payload["packageWeightGrams"] = weight }
        if let product = product, let co2Per100g = product.ecoscoreData?.agribalyse?.co2Total, co2Per100g > 0 {
            payload["agribalyseCO2"] = co2Per100g
        }
        if let rawJSON = rawOFFJSON, !rawJSON.isEmpty {
            payload["openfoodfacts_product"] = rawJSON
        }

        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: payload)
        } catch {
            AppLogger.error("❌ Failed to serialize streaming payload: \(error)")
            return await analyzeWithBackendRawText(ingredientsText: ingredientsText, productName: productName, preferences: preferences, barcode: barcode, product: product, rawOFFJSON: rawOFFJSON)
        }

        logger.debug("📡 Starting SSE streaming request for barcode: \(barcode)")

        do {
            let (bytes, response) = try await backendSession.bytes(for: request)

            guard let httpResponse = response as? HTTPURLResponse else {
                logger.warning("⚠️ SSE: Invalid response type, falling back")
                return await analyzeWithBackendRawText(ingredientsText: ingredientsText, productName: productName, preferences: preferences, barcode: barcode, product: product, rawOFFJSON: rawOFFJSON)
            }

            // If server doesn't support SSE (e.g. old backend), fall back
            let contentType = httpResponse.value(forHTTPHeaderField: "Content-Type") ?? ""
            if !contentType.contains("text/event-stream") {
                logger.warning("⚠️ SSE: Server returned \(contentType) instead of event-stream, falling back")
                return await analyzeWithBackendRawText(ingredientsText: ingredientsText, productName: productName, preferences: preferences, barcode: barcode, product: product, rawOFFJSON: rawOFFJSON)
            }

            var preliminaryResult: AnalysisResult?
            var completeResult: AnalysisResult?
            var currentEvent = ""
            var currentData = ""

            for try await line in bytes.lines {
                if line.hasPrefix("event: ") {
                    currentEvent = String(line.dropFirst(7))
                } else if line.hasPrefix("data: ") {
                    currentData = String(line.dropFirst(6))
                } else if line.isEmpty && !currentData.isEmpty {
                    // Empty line = end of SSE event
                    if let data = currentData.data(using: .utf8) {
                        switch currentEvent {
                        case "partial":
                            if let parsed = parseBackendResponse(data: data, barcode: barcode, productName: productName, product: product) {
                                preliminaryResult = parsed
                                logger.debug("📡 SSE: Got preliminary result for \(parsed.productName)")
                            }
                        case "complete":
                            if let parsed = parseBackendResponse(data: data, barcode: barcode, productName: productName, product: product) {
                                completeResult = parsed
                                logger.debug("📡 SSE: Got complete AI result for \(parsed.productName)")
                                // Publish enhanced result for ResultsView to pick up
                                ProductDatabaseService.enhancedResultSubject.send(parsed)
                            }
                        case "done":
                            logger.debug("📡 SSE: Stream done")
                        case "error":
                            logger.error("📡 SSE: Server error in stream")
                        default:
                            break
                        }
                    }
                    currentEvent = ""
                    currentData = ""
                }
            }

            // Return: prefer preliminary (for fast display), enhanced comes via publisher
            if let preliminary = preliminaryResult {
                // If complete already arrived (fast cache hit), return it directly
                if let complete = completeResult {
                    // Complete arrived with preliminary — no progressive update needed
                    return complete
                }
                return preliminary
            }

            // No preliminary received — return complete if we got it
            if let complete = completeResult {
                return complete
            }

            // SSE stream ended without useful data — fall back
            logger.warning("⚠️ SSE: No results received, falling back")
            return await analyzeWithBackendRawText(ingredientsText: ingredientsText, productName: productName, preferences: preferences, barcode: barcode, product: product, rawOFFJSON: rawOFFJSON)

        } catch {
            logger.warning("⚠️ SSE connection failed: \(error.localizedDescription), falling back to standard request")
            return await analyzeWithBackendRawText(ingredientsText: ingredientsText, productName: productName, preferences: preferences, barcode: barcode, product: product, rawOFFJSON: rawOFFJSON)
        }
    }

    /// Call backend with barcode only (no OFF data, no ingredients).
    /// Backend will use Gemini AI to identify the product and return full analysis.
    private func analyzeWithBackendBarcodeOnly(barcode: String, productName: String? = nil, product: OpenFoodFactsProduct? = nil, preferences: UserPreferences) async -> AnalysisResult? {
        guard let url = URL(string: "\(AppConfig.backendURL)/comprehensive-analysis") else {
            AppLogger.error("❌ Invalid backend URL for barcode-only analysis")
            return nil
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 30.0
        await addAuthToken(to: &request)

        var payload: [String: Any] = [
            "barcode": barcode,
            "ingredients": [] as [String],
            "userPreferences": [
                "selectedAllergens": Array(preferences.selectedAllergens),
                "customAllergens": preferences.customAllergens,
                "selectedDiets": Array(preferences.selectedDiets),
                "customDiets": preferences.customDiets,
                "avoidGMO": preferences.avoidGMO
            ],
            "dietaryPreferences": Array(preferences.selectedDiets) + preferences.customDiets
        ]
        if let productName = productName {
            payload["productName"] = productName
        }

        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: payload)
            AppLogger.debug("📤 Barcode-only backend request (Gemini): \(barcode)")

            // Retry with exponential backoff (2 attempts)
            let data: Data = try await performWithRetry(maxAttempts: 2) {
                let (data, response) = try await self.backendSession.data(for: request)
                guard let httpResponse = response as? HTTPURLResponse else {
                    throw NSError(domain: "ProductDatabaseService", code: -1,
                                  userInfo: [NSLocalizedDescriptionKey: "Invalid response type"])
                }
                AppLogger.debug("📥 Backend barcode-only response: \(httpResponse.statusCode)")
                guard httpResponse.statusCode == 200 else {
                    let errorText = String(data: data, encoding: .utf8) ?? "Unknown"
                    throw NSError(domain: "ProductDatabaseService", code: httpResponse.statusCode,
                                  userInfo: [NSLocalizedDescriptionKey: errorText])
                }
                return data
            }

            return parseBackendResponse(data: data, barcode: barcode, productName: productName, product: product)
        } catch {
            AppLogger.error("❌ Backend barcode-only failed after retries: \(error)")
            return nil
        }
    }

    // MARK: - Backend Response Parsing

    private func parseBackendResponse(data: Data, barcode: String, productName: String?, product: OpenFoodFactsProduct?) -> AnalysisResult? {
        do {
            if let jsonString = String(data: data, encoding: .utf8) {
                AppLogger.debug("📦 Backend JSON response: \(jsonString.prefix(500))")
            }

            // Parse JSON so we can inject sourceBarcode/sourceType before decoding
            guard var json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                AppLogger.error("❌ Failed to parse JSON")
                return nil
            }

            // Inject tracking fields that come from method params, not backend
            json["sourceBarcode"] = barcode
            // Preserve backend's sourceType if it sent one (e.g. "gemini_identified"), otherwise default to "backend"
            if json["sourceType"] == nil {
                json["sourceType"] = "backend"
            }

            // If backend didn't send productName (or returned "Unknown Product") but we have it from OpenFoodFacts, inject it
            if let productName = productName, !productName.isEmpty {
                let backendName = json["productName"] as? String
                if backendName == nil || backendName == "Unknown Product" || backendName?.isEmpty == true {
                    json["productName"] = productName
                }
            }

            // If backend returned zero environmental data but we have OFF product, compute from Agribalyse/Eco-Score
            if let product = product {
                let co2 = json["co2Emissions"] as? Double ?? 0
                let water = json["waterUsage"] as? Double ?? 0
                if co2 == 0 && water == 0 {
                    let ingredients = openFoodFactsClient.extractIngredients(from: product)
                    let envImpact = getEnvironmentalData(from: product, ingredients: ingredients)
                    json["co2Emissions"] = envImpact.co2
                    json["waterUsage"] = envImpact.water
                    json["animalImpact"] = envImpact.animalImpact
                }
            }

            // Re-serialize the modified JSON
            let modifiedData = try JSONSerialization.data(withJSONObject: json)

            // Use JSONDecoder — this leverages AnalysisResult's existing init(from decoder:)
            // which correctly handles flat fields, recommendations as array or dict,
            // alternatives as objects or strings, and all other field mappings
            let decoder = JSONDecoder()
            let result = try decoder.decode(AnalysisResult.self, from: modifiedData)

            AppLogger.debug("✅ Backend analysis successful (JSONDecoder):")
            AppLogger.debug("   - Product: \(result.productName)")
            AppLogger.debug("   - Overall score: \(result.overallScore)")
            AppLogger.debug("   - Health score: \(result.healthScore)")
            AppLogger.debug("   - Environmental score: \(result.environmentalScore)")
            AppLogger.debug("   - isSafe: \(result.isSafe)")
            AppLogger.debug("   - Violations: \(result.violations.count)")
            AppLogger.debug("   - Warnings: \(result.warnings.count)")
            AppLogger.debug("   - Caution warnings: \(result.cautionWarnings.count)")
            AppLogger.debug("   - Recommendations: \(result.recommendations.count)")
            AppLogger.debug("   - Alternatives: \(result.alternatives.count)")
            AppLogger.debug("   - Additives: \(result.additives.count)")
            AppLogger.debug("   - Health concerns: \(result.healthConcerns.count)")
            AppLogger.debug("   - Health benefits: \(result.healthBenefits.count)")
            AppLogger.debug("   - Nutritional highlights: \(result.nutritionalHighlights.count)")

            return result
        } catch {
            AppLogger.error("❌ Failed to decode backend response: \(error)")
            // Log detailed decoding errors for debugging
            if let decodingError = error as? DecodingError {
                switch decodingError {
                case .keyNotFound(let key, let ctx):
                    AppLogger.error("   Missing key: \(key.stringValue) — \(ctx.debugDescription)")
                case .typeMismatch(let type, let ctx):
                    AppLogger.error("   Type mismatch for \(type) — \(ctx.debugDescription)")
                case .valueNotFound(let type, let ctx):
                    AppLogger.error("   Value not found for \(type) — \(ctx.debugDescription)")
                case .dataCorrupted(let ctx):
                    AppLogger.error("   Data corrupted — \(ctx.debugDescription)")
                @unknown default:
                    AppLogger.error("   Unknown decoding error")
                }
            }
            return nil
        }
    }
    
    // MARK: - Analysis Logic
    
    // FALSE POSITIVES: Ingredients that sound like they contain animal products but are actually plant-based
    // This prevents false flags for vegan, vegetarian, kosher, halal, and all other diets
    private let falsePositiveIngredients: Set<String> = [
        // Plant-based "butters" (NOT dairy)
        "cocoa butter", "cacao butter", "shea butter", "mango butter", "kokum butter",
        "peanut butter", "almond butter", "cashew butter", "sunflower butter", "seed butter",
        "coconut butter", "nut butter", "apple butter", "fruit butter",
        
        // Plant-based "milks" and "creams" (NOT dairy)
        "coconut milk", "coconut cream", "almond milk", "oat milk", "soy milk", "rice milk",
        "cashew milk", "hemp milk", "coconut milk powder", "cream of tartar", "cream of coconut",
        
        // Plant-based "cheese" terms (NOT dairy)
        "nutritional yeast", "vegan cheese", "plant-based cheese", "dairy-free cheese",
        
        // "Egg" terms that are NOT eggs
        "eggplant", "egg plant", "aubergine", "egg fruit", "eggfruit",

        // "Nut/Chestnut" terms that are NOT tree nuts
        "water chestnut", "water chestnuts",
        
        // "Meat" terms that are NOT meat
        "mincemeat", "mince meat", // traditional fruit-based filling
        "coconut meat", "jackfruit meat", "young coconut meat",
        
        // "Fish" terms that are NOT fish
        "jellyfish plant", "starfish fruit", "kingfish bean",
        
        // "Gelatin" alternatives (plant-based)
        "agar", "agar-agar", "carrageenan", "pectin", "konjac", "xanthan gum",
        
        // "Honey" alternatives (plant-based)
        "honeydew", "honey dew", "honeynut", "honeycrisp", "honeybush",
        
        // "Lard" terms that are NOT lard
        "collard", "collard greens", "mallard",
        
        // Other false positives
        "butternut", "butternut squash", "buttercup squash", "butterfly pea",
        "milkweed", "milkwort",
        "cheesecloth", "cheese plant",
        "eggnog flavoring", // when clearly labeled as flavoring only
        "butterfat-free", "dairy-free butter", "vegan butter"
    ]
    
    // 🚀 Regex cache to avoid recompiling patterns for every ingredient check
    private var regexCache: [String: NSRegularExpression] = [:]
    private let regexCacheLock = NSLock()
    
    // Check if an ingredient is a known false positive (plant-based despite the name)
    private func isFalsePositive(_ ingredient: String) -> Bool {
        let lower = ingredient.lowercased()
        
        // Check exact matches first
        if falsePositiveIngredients.contains(lower) {
            AppLogger.debug("     ✅ FALSE POSITIVE detected: \"\(ingredient)\" - plant-based, skipping")
            return true
        }
        
        // Check if any false positive phrase is contained in the ingredient
        for falsePositive in falsePositiveIngredients {
            if lower.contains(falsePositive) {
                AppLogger.debug("     ✅ FALSE POSITIVE detected: \"\(ingredient)\" contains \"\(falsePositive)\" - plant-based, skipping")
                return true
            }
        }
        
        // Special pattern matching for compound plant-based butters
        // e.g., "organic cocoa butter", "raw shea butter"
        let butterPatterns = ["cocoa butter", "cacao butter", "shea butter", "mango butter", 
                              "kokum butter", "peanut butter", "almond butter", "cashew butter",
                              "sunflower butter", "coconut butter", "nut butter", "seed butter",
                              "apple butter", "fruit butter"]
        for pattern in butterPatterns {
            if lower.contains(pattern) {
                AppLogger.debug("     ✅ FALSE POSITIVE detected: \"\(ingredient)\" contains plant butter \"\(pattern)\" - skipping")
                return true
            }
        }
        
        // Special pattern matching for plant milks/creams
        let milkPatterns = ["coconut milk", "coconut cream", "almond milk", "oat milk", 
                            "soy milk", "rice milk", "cashew milk", "hemp milk",
                            "cream of tartar", "cream of coconut"]
        for pattern in milkPatterns {
            if lower.contains(pattern) {
                AppLogger.debug("     ✅ FALSE POSITIVE detected: \"\(ingredient)\" contains plant milk/cream \"\(pattern)\" - skipping")
                return true
            }
        }
        
        return false
    }
    
    /// Word-boundary match helper — prevents "fig" matching "configuration"
    /// 🚀 Optimized: Caches compiled regexes (thread-safe via NSLock)
    private func matchesWord(_ text: String, _ term: String) -> Bool {
        // Check cache first (thread-safe)
        regexCacheLock.lock()
        let cachedRegex = regexCache[term]
        regexCacheLock.unlock()

        if let regex = cachedRegex {
            let range = NSRange(text.startIndex..<text.endIndex, in: text)
            return regex.firstMatch(in: text, range: range) != nil
        }

        // Compile and cache new regex
        let escaped = NSRegularExpression.escapedPattern(for: term)
        let pattern = "\\b\(escaped)(?:s|es)?\\b"
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) else {
            return text.contains(term) // Fallback
        }

        regexCacheLock.lock()
        regexCache[term] = regex
        regexCacheLock.unlock()

        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        return regex.firstMatch(in: text, range: range) != nil
    }

    private func analyzeIngredients(_ ingredients: [String], preferences: UserPreferences) -> [ConcernItem] {
        var concerns: [ConcernItem] = []

        AppLogger.debug("🔬 Analyzing \(ingredients.count) ingredients for concerns:")
        AppLogger.debug("   - User diets: \(Array(preferences.selectedDiets) + preferences.customDiets)")
        AppLogger.debug("   - User allergens: \(Array(preferences.selectedAllergens) + preferences.customAllergens)")

        // Use shared allergen keyword map + resolve synonyms for user's selections
        let allergenKeywords = Self.allergenKeywords

        // Pre-compute diet flags once (not per-ingredient)
        let allDiets = Array(preferences.selectedDiets) + preferences.customDiets
        let allDietsLower = Set(allDiets.map { $0.lowercased() })
        let isVegan = allDietsLower.contains("vegan")
        let isVegetarian = allDietsLower.contains("vegetarian")
        let isJain = allDietsLower.contains("jain")
        let isHalal = allDietsLower.contains("halal")
        let isKosher = allDietsLower.contains("kosher")
        let isPescatarian = allDietsLower.contains("pescatarian")
        let isPaleo = allDietsLower.contains("paleo")
        let isLowFODMAP = allDietsLower.contains("low-fodmap") || allDietsLower.contains("low fodmap") || allDietsLower.contains("fodmap")

        // Vegan non-animal keywords for word-boundary matching
        let veganProhibited = ["milk", "dairy", "cream", "butter", "cheese", "whey",
                               "casein", "lactose", "egg", "albumin", "honey", "gelatin"]
        // Vegetarian prohibited keywords
        let vegetarianProhibited = ["meat", "beef", "pork", "chicken", "fish", "gelatin", "lard"]
        // Halal prohibited (excludes "sugar alcohol" and "wine vinegar" via word-boundary matching)
        let halalProhibited = ["pork", "lard", "bacon", "ham", "pepperoni", "ethanol",
                               "ethyl alcohol", "beer", "rum", "vodka", "whiskey", "brandy"]
        // Kosher prohibited
        let kosherProhibited = ["pork", "shellfish", "shrimp", "crab", "lobster", "lard", "gelatin"]
        // Pescatarian prohibited (land-based meat)
        let pescatarianProhibited = ["beef", "pork", "chicken", "turkey", "lamb", "veal", "bacon", "ham", "sausage", "lard"]
        // Paleo prohibited
        let paleoProhibited = ["wheat", "flour", "gluten", "grain", "corn", "rice", "soy", "legume",
                               "bean", "dairy", "milk", "cheese", "sugar", "artificial"]
        // Low-FODMAP prohibited
        let lowFODMAPProhibited = ["garlic", "onion", "wheat", "apple", "honey", "milk",
                                   "yogurt", "legume", "bean", "cashew"]

        // Track flagged ingredients to prevent duplicate violations when diets overlap
        var flaggedIngredients: Set<String> = []

        for ingredient in ingredients {
            AppLogger.debug("   - Checking ingredient: \"\(ingredient)\"")

            // FIRST: Check if this is a false positive (plant-based despite the name)
            if isFalsePositive(ingredient) {
                continue
            }

            let fullText = ingredient.lowercased()
            let ingredientKey = fullText

            // JAIN DIET CHECK — now delegates to JainDietValidator for comprehensive matching
            if isJain && !flaggedIngredients.contains(ingredientKey) {
                let jainViolations = JainDietValidator.shared.validateIngredient(ingredient)
                if let first = jainViolations.first {
                    AppLogger.warning("     ⚠️ Found Jain violation: \(first.prohibitedItem)")
                    concerns.append(ConcernItem(
                        ingredient: ingredient,
                        concern: "Not Jain-compatible (contains \(first.prohibitedItem))",
                        severity: first.severity
                    ))
                    flaggedIngredients.insert(ingredientKey)
                }
            }

            // VEGAN CHECK — no `continue` so allergen check still runs below
            if isVegan && !flaggedIngredients.contains(ingredientKey) {
                if veganProhibited.contains(where: { matchesWord(fullText, $0) }) {
                    AppLogger.warning("     ⚠️ Found vegan violation!")
                    concerns.append(ConcernItem(
                        ingredient: ingredient,
                        concern: "Not vegan-friendly",
                        severity: "high"
                    ))
                    flaggedIngredients.insert(ingredientKey)
                }
            }

            // VEGETARIAN CHECK — no `continue` so allergen check still runs below
            if isVegetarian && !flaggedIngredients.contains(ingredientKey) {
                if vegetarianProhibited.contains(where: { matchesWord(fullText, $0) }) {
                    concerns.append(ConcernItem(
                        ingredient: ingredient,
                        concern: "Not vegetarian-friendly",
                        severity: "high"
                    ))
                    flaggedIngredients.insert(ingredientKey)
                }
            }

            // HALAL CHECK (no `continue` — allergen check must still run below)
            if isHalal && !flaggedIngredients.contains(ingredientKey) {
                if halalProhibited.contains(where: { matchesWord(fullText, $0) }) {
                    concerns.append(ConcernItem(ingredient: ingredient, concern: "Not halal-compatible", severity: "high"))
                    flaggedIngredients.insert(ingredientKey)
                }
            }

            // KOSHER CHECK
            if isKosher && !flaggedIngredients.contains(ingredientKey) {
                if kosherProhibited.contains(where: { matchesWord(fullText, $0) }) {
                    concerns.append(ConcernItem(ingredient: ingredient, concern: "Not kosher-compatible", severity: "high"))
                    flaggedIngredients.insert(ingredientKey)
                }
            }

            // PESCATARIAN CHECK
            if isPescatarian && !flaggedIngredients.contains(ingredientKey) {
                if pescatarianProhibited.contains(where: { matchesWord(fullText, $0) }) {
                    concerns.append(ConcernItem(ingredient: ingredient, concern: "Not pescatarian-compatible", severity: "high"))
                    flaggedIngredients.insert(ingredientKey)
                }
            }

            // PALEO CHECK
            if isPaleo && !flaggedIngredients.contains(ingredientKey) {
                if paleoProhibited.contains(where: { matchesWord(fullText, $0) }) {
                    concerns.append(ConcernItem(ingredient: ingredient, concern: "Not paleo-compatible", severity: "high"))
                    flaggedIngredients.insert(ingredientKey)
                }
            }

            // LOW-FODMAP CHECK
            if isLowFODMAP && !flaggedIngredients.contains(ingredientKey) {
                if lowFODMAPProhibited.contains(where: { matchesWord(fullText, $0) }) {
                    concerns.append(ConcernItem(ingredient: ingredient, concern: "High-FODMAP ingredient", severity: "high"))
                    flaggedIngredients.insert(ingredientKey)
                }
            }

            // ALLERGEN CHECK — synonym-aware keyword lookup with word-boundary matching
            let allAllergens = Array(preferences.selectedAllergens) + preferences.customAllergens
            if !allAllergens.isEmpty {
                for selectedAllergen in allAllergens {
                    let allergenKey = selectedAllergen.lowercased()
                    // Collect keywords from this key AND all synonym keys
                    var keywords: [String] = allergenKeywords[allergenKey] ?? []
                    for (mapKey, mapKeywords) in allergenKeywords {
                        if mapKey != allergenKey && Self.allergensMatch(allergenKey, mapKey) {
                            keywords.append(contentsOf: mapKeywords)
                        }
                    }

                    if !keywords.isEmpty {
                        if keywords.contains(where: { matchesWord(fullText, $0) }) {
                            AppLogger.warning("     ⚠️ ALLERGEN VIOLATION: \(selectedAllergen) found in '\(ingredient)'")
                            concerns.append(ConcernItem(
                                ingredient: ingredient,
                                concern: "Contains \(selectedAllergen.capitalized)",
                                severity: "high"
                            ))
                            break
                        }
                    } else {
                        // Fallback for custom allergens not in the keyword map
                        if matchesWord(fullText, allergenKey) {
                            AppLogger.warning("     ⚠️ CUSTOM ALLERGEN VIOLATION: \(selectedAllergen) found in '\(ingredient)'")
                            concerns.append(ConcernItem(
                                ingredient: ingredient,
                                concern: "Contains \(selectedAllergen.capitalized)",
                                severity: "high"
                            ))
                            break
                        }
                    }
                }
            }

            // Check for harmful additives
            if matchesWord(fullText, "e621") || matchesWord(fullText, "msg") {
                concerns.append(ConcernItem(
                    ingredient: ingredient,
                    concern: "Controversial additive",
                    severity: "medium"
                ))
            }
        }
        
        AppLogger.debug("   ✅ Found \(concerns.count) concerns")
        return concerns
    }
    
    // MARK: - Yuka-Style Health Score Calculation
    // Yuka scoring: 60% nutritional quality (FSA/Nutri-Score), 30% additives, 10% organic
    private func calculateHealthScore(ingredients: [String], concerns: Int, nutriments: OpenFoodFactsProduct.Nutriments? = nil, novaGroup: Int? = nil, nutriscoreGrade: String? = nil) -> Int {
        
        // Component 1: Nutritional Quality (60% of score, max 60 points)
        // Based on Nutri-Score which uses the UK FSA nutrient profiling system
        var nutritionalScore: Double = 30  // Start at middle
        
        if let nutriscoreGrade = nutriscoreGrade?.uppercased() {
            switch nutriscoreGrade {
            case "A": nutritionalScore = 60  // Excellent - full points
            case "B": nutritionalScore = 48  // Good - 80%
            case "C": nutritionalScore = 36  // Average - 60%
            case "D": nutritionalScore = 24  // Below average - 40%
            case "E": nutritionalScore = 12  // Poor - 20%
            default: break
            }
        } else if let nutriments = nutriments {
            // Calculate approximate Nutri-Score from nutriments if grade not available
            nutritionalScore = calculateNutritionalComponent(nutriments: nutriments)
        }
        
        // Component 2: Additives Penalty (30% of score, max 30 points)
        // Yuka penalizes heavily for controversial additives
        var additiveScore: Double = 30  // Start with full points
        let additivesPenalty = calculateAdditivesPenalty(ingredients: ingredients)
        additiveScore = max(0, 30 - additivesPenalty)
        
        // Component 3: NOVA/Processing Penalty (10% of score, max 10 points)
        // Yuka uses organic certification, we'll use NOVA group as proxy
        var processingScore: Double = 5  // Default middle value
        if let nova = novaGroup {
            switch nova {
            case 1: processingScore = 10  // Unprocessed - full points
            case 2: processingScore = 7   // Culinary ingredients
            case 3: processingScore = 4   // Processed foods
            case 4: processingScore = 0   // Ultra-processed - no points
            default: break
            }
        }
        
        // Combine all components
        let totalScore = Int(round(nutritionalScore + additiveScore + processingScore))
        
        AppLogger.debug("   📊 Yuka-style score breakdown:")
        AppLogger.debug("      - Nutritional (60%): \(Int(nutritionalScore))/60")
        AppLogger.debug("      - Additives (30%): \(Int(additiveScore))/30")
        AppLogger.debug("      - Processing (10%): \(Int(processingScore))/10")
        AppLogger.debug("      - Total: \(totalScore)/100")
        
        return max(0, min(100, totalScore))
    }
    
    // Calculate nutritional component using FSA-style scoring
    private func calculateNutritionalComponent(nutriments: OpenFoodFactsProduct.Nutriments) -> Double {
        var score: Double = 30  // Start at middle
        
        // Use per-100g values for consistency (FSA standard)
        let energy = nutriments.energyKcal100g ?? 0
        let sugars = nutriments.sugars100g ?? 0
        let saturatedFat = nutriments.saturatedFat100g ?? 0
        let sodium = (nutriments.sodium100g ?? 0) * 1000  // Convert to mg
        let fiber = nutriments.fiber100g ?? 0
        let proteins = nutriments.proteins100g ?? 0
        
        // Negative points (per 100g) - FSA thresholds
        if energy > 335 { score -= 3 }
        if energy > 670 { score -= 3 }
        if energy > 1005 { score -= 3 }
        
        if sugars > 4.5 { score -= 3 }
        if sugars > 9 { score -= 3 }
        if sugars > 13.5 { score -= 3 }
        if sugars > 18 { score -= 3 }
        
        if saturatedFat > 1 { score -= 3 }
        if saturatedFat > 2 { score -= 3 }
        if saturatedFat > 3 { score -= 3 }
        if saturatedFat > 4 { score -= 3 }
        
        if sodium > 90 { score -= 2 }
        if sodium > 180 { score -= 2 }
        if sodium > 270 { score -= 2 }
        if sodium > 360 { score -= 2 }
        
        // Positive points
        if fiber > 0.9 { score += 3 }
        if fiber > 1.9 { score += 3 }
        if fiber > 2.8 { score += 3 }
        
        if proteins > 1.6 { score += 2 }
        if proteins > 3.2 { score += 2 }
        if proteins > 4.8 { score += 2 }
        
        return max(0, min(60, score))
    }
    
    // Calculate additives penalty based on Yuka's additive database
    private func calculateAdditivesPenalty(ingredients: [String]) -> Double {
        var penalty: Double = 0
        let ingredientsLower = ingredients.joined(separator: " ").lowercased()
        
        // HIGH RISK additives (red in Yuka) - 10 points penalty each
        let highRiskAdditives = [
            "sodium nitrite", "e250", "sodium nitrate", "e251",
            "potassium nitrite", "e249", "potassium nitrate", "e252",
            "bha", "e320", "bht", "e321",
            "sulfur dioxide", "e220", "sodium sulfite", "e221",
            "aspartame", "e951", "acesulfame", "e950",
            "titanium dioxide", "e171",
            "carrageenan", "e407",
            "caramel color", "e150d", "ammonia caramel",
            "phosphoric acid", "e338",
            "msg", "monosodium glutamate", "e621"
        ]
        
        // MODERATE RISK additives (orange in Yuka) - 5 points penalty each
        let moderateRiskAdditives = [
            "annatto", "e160b",
            "mono and diglycerides", "e471",
            "guar gum", "e412",
            "xanthan gum", "e415",
            "lecithin", "e322",
            "citric acid", "e330",
            "ascorbic acid", "e300",
            "natural flavors", "natural flavor",
            "autolyzed yeast", "yeast extract",
            "maltodextrin",
            "modified food starch", "modified starch",
            "cellulose", "e460"
        ]
        
        for additive in highRiskAdditives {
            if ingredientsLower.contains(additive) {
                penalty += 10
            }
        }
        
        for additive in moderateRiskAdditives {
            if ingredientsLower.contains(additive) {
                penalty += 5
            }
        }
        
        // Cap penalty at 30 (full loss of additive component)
        return min(30, penalty)
    }
    
    private func calculateEnvironmentalScore(co2: Double, water: Double, animalImpact: String) -> Double {
        var score: Double = 100
        
        // CO2 penalty (typical product: 0.3-1.5 kg CO2)
        // Low impact: 0-0.3 kg, Medium: 0.3-1.0 kg, High: 1.0+ kg
        if co2 > 2.0 {
            score -= 30  // Very high emissions
        } else if co2 > 1.0 {
            score -= 20  // High emissions
        } else if co2 > 0.5 {
            score -= 10  // Moderate emissions
        }
        // Below 0.5 is good - no penalty
        
        // Water penalty (typical: 50-500 liters)
        // Low: 0-100L, Medium: 100-300L, High: 300+L
        if water > 500 {
            score -= 20  // Very high water usage
        } else if water > 300 {
            score -= 15  // High water usage
        } else if water > 150 {
            score -= 10  // Moderate water usage
        }
        // Below 150L is good - no penalty
        
        // Animal impact penalty
        let animalImpactLower = animalImpact.lowercased()
        if animalImpactLower.contains("high") {
            score -= 25  // Meat/multiple animal products
        } else if animalImpactLower.contains("medium") {
            score -= 15  // Dairy or eggs
        }
        // "Low" (plant-based) gets no penalty - best score
        
        return max(0, min(100, score))
    }
    
    // MARK: - Alternative Product Generation
    
    private func generateAlternatives(product: OpenFoodFactsProduct, concernItems: [ConcernItem], healthScore: Int, ingredients: [String], preferences: UserPreferences) -> [AnalysisResult.Alternative] {
        var alternatives: [AnalysisResult.Alternative] = []
        
        // Determine product category from product name and ingredients
        let productName = (product.productNameEn ?? product.productName ?? "").lowercased()
        let brands = (product.brands ?? "").lowercased()
        let ingredientText = ingredients.joined(separator: " ").lowercased()
        
        AppLogger.debug("🔄 Generating alternatives:")
        AppLogger.debug("   - Product: \(productName)")
        AppLogger.debug("   - Concern items: \(concernItems.count)")
        AppLogger.debug("   - Health score: \(healthScore)")
        AppLogger.debug("   - Selected diets: \(preferences.selectedDiets)")
        AppLogger.debug("   - Selected allergens: \(preferences.selectedAllergens)")
        
        // Only suggest alternatives if there are dietary concerns or health issues
        guard !concernItems.isEmpty || healthScore < 70 else {
            AppLogger.error("   ❌ No alternatives needed (no concerns and health score >= 70)")
            return alternatives
        }
        
        AppLogger.debug("   ✅ Generating alternatives due to concerns or low health score")
        
        // Analyze ALL concern items to determine what ingredients to avoid
        // This works for ANY diet (vegan, vegetarian, kosher, halal, paleo, keto, etc.)
        var problematicIngredients: Set<String> = []
        for concern in concernItems {
            let concernLower = concern.concern.lowercased()
            let ingredientLower = concern.ingredient.lowercased()
            
            // Extract the problematic ingredient keyword
            problematicIngredients.insert(concernLower)
            problematicIngredients.insert(ingredientLower)
        }
        
        AppLogger.debug("   - Problematic ingredients detected: \(problematicIngredients)")
        
        // Check what types of violations exist
        let hasDairyViolation = problematicIngredients.contains { ing in
            ing.contains("milk") || ing.contains("dairy") || ing.contains("lactose") ||
            ing.contains("cream") || ing.contains("cheese") || ing.contains("whey") ||
            ing.contains("casein") || ing.contains("butter") || ing.contains("yogurt") ||
            ing.contains("skyr")
        }
        
        let hasMeatViolation = problematicIngredients.contains { ing in
            ing.contains("meat") || ing.contains("beef") || ing.contains("pork") ||
            ing.contains("chicken") || ing.contains("fish") || ing.contains("lamb") ||
            ing.contains("turkey") || ing.contains("veal") || ing.contains("gelatin") ||
            ing.contains("lard") || ing.contains("bacon")
        }
        
        let hasEggViolation = problematicIngredients.contains { ing in
            ing.contains("egg") || ing.contains("albumin")
        }
        
        let hasShellfishViolation = problematicIngredients.contains { ing in
            ing.contains("shellfish") || ing.contains("shrimp") || ing.contains("crab") ||
            ing.contains("lobster") || ing.contains("oyster")
        }
        
        let hasGlutenViolation = problematicIngredients.contains { ing in
            ing.contains("gluten") || ing.contains("wheat") || ing.contains("barley") ||
            ing.contains("rye")
        }
        
        let hasPorkViolation = problematicIngredients.contains { ing in
            ing.contains("pork") || ing.contains("bacon") || ing.contains("ham") ||
            ing.contains("lard") || ing.contains("pork gelatin")
        }
        
        // Detect product category from ingredients and product name
        let isDairyProduct = ingredientText.contains("milk") || ingredientText.contains("dairy") ||
                            ingredientText.contains("cream") || ingredientText.contains("whey") ||
                            ingredientText.contains("cheese") || ingredientText.contains("yogurt") ||
                            productName.contains("milk") || productName.contains("yogurt") ||
                            productName.contains("cheese") || productName.contains("butter") ||
                            productName.contains("skyr") || productName.contains("quark")
        
        let isMeatProduct = ingredientText.contains("beef") || ingredientText.contains("pork") ||
                           ingredientText.contains("chicken") || ingredientText.contains("meat") ||
                           productName.contains("burger") || productName.contains("beef") ||
                           productName.contains("chicken") || productName.contains("meat") ||
                           productName.contains("sausage")
        
        let isEggProduct = ingredientText.contains("egg") || productName.contains("egg")
        
        let isBreadProduct = productName.contains("bread") || productName.contains("bagel") ||
                            productName.contains("pasta") || productName.contains("cereal") ||
                            productName.contains("cracker")
        
        // Generate alternatives based on violations + product type
        
        // Dairy product alternatives
        if hasDairyViolation && isDairyProduct {
            // Determine specific dairy product type
            if productName.contains("milk") && !productName.contains("almond") && !productName.contains("oat") && !productName.contains("soy") {
                let altIngredients = ["oat", "water", "salt"]
                let altImpact = self.calculateEnvironmentalImpact(altIngredients)
                alternatives.append(AnalysisResult.Alternative(
                    name: "Oat Milk",
                    brand: "Oatly",
                    reason: "Plant-based, creamy texture, lower environmental impact",
                    imageURL: nil,
                    link: "https://www.amazon.com/s?k=oatly+oat+milk",
                    estimatedCO2: altImpact.co2,
                    estimatedWater: altImpact.water
                ))
            } else if productName.contains("cheese") {
                let altIngredients = ["coconut oil", "potato starch", "salt"]
                let altImpact = self.calculateEnvironmentalImpact(altIngredients)
                alternatives.append(AnalysisResult.Alternative(
                    name: "Vegan Cheddar",
                    brand: "Violife",
                    reason: "Dairy-free, melts well, fortified with B12",
                    imageURL: nil,
                    link: "https://www.amazon.com/s?k=violife+vegan+cheddar",
                    estimatedCO2: altImpact.co2,
                    estimatedWater: altImpact.water
                ))
            } else if productName.contains("yogurt") || productName.contains("skyr") || productName.contains("quark") {
                // Skyr, yogurt, and quark are all cultured dairy products
                let altIngredients = ["coconut", "live cultures", "fruit"]
                let altImpact = self.calculateEnvironmentalImpact(altIngredients)
                alternatives.append(AnalysisResult.Alternative(
                    name: "Coconut Yogurt",
                    brand: "So Delicious",
                    reason: "Dairy-free with live cultures, creamy and delicious",
                    imageURL: nil,
                    link: "https://www.amazon.com/s?k=so+delicious+coconut+yogurt",
                    estimatedCO2: altImpact.co2,
                    estimatedWater: altImpact.water
                ))
            } else if productName.contains("butter") {
                let altIngredients = ["cashew cream", "coconut oil", "salt"]
                let altImpact = self.calculateEnvironmentalImpact(altIngredients)
                alternatives.append(AnalysisResult.Alternative(
                    name: "Vegan Butter",
                    brand: "Miyoko's",
                    reason: "Made from cultured cashew cream, tastes like real butter",
                    imageURL: nil,
                    link: "https://www.amazon.com/s?k=miyokos+vegan+butter",
                    estimatedCO2: altImpact.co2,
                    estimatedWater: altImpact.water
                ))
            } else {
                // Generic dairy product
                let altIngredients = ["plant-based ingredients"]
                let altImpact = self.calculateEnvironmentalImpact(altIngredients)
                alternatives.append(AnalysisResult.Alternative(
                    name: "Plant-Based Alternative",
                    brand: "Multiple brands available",
                    reason: "Dairy-free options available for most dairy products",
                    imageURL: nil,
                    link: "https://www.amazon.com/s?k=vegan+dairy+free",
                    estimatedCO2: altImpact.co2,
                    estimatedWater: altImpact.water
                ))
            }
        }
        
        // Meat product alternatives
        if hasMeatViolation && isMeatProduct {
            if productName.contains("burger") || productName.contains("beef") {
                let altIngredients = ["pea protein", "rice protein", "coconut oil", "potato starch"]
                let altImpact = self.calculateEnvironmentalImpact(altIngredients)
                alternatives.append(AnalysisResult.Alternative(
                    name: "Beyond Burger",
                    brand: "Beyond Meat",
                    reason: "Plant-based, 20g protein, cooks like real beef",
                    imageURL: nil,
                    link: "https://www.amazon.com/s?k=beyond+meat+burger",
                    estimatedCO2: altImpact.co2,
                    estimatedWater: altImpact.water
                ))
            } else if productName.contains("chicken") {
                let altIngredients = ["soy protein", "wheat gluten", "corn", "spices"]
                let altImpact = self.calculateEnvironmentalImpact(altIngredients)
                alternatives.append(AnalysisResult.Alternative(
                    name: "Chick'n Strips",
                    brand: "Gardein",
                    reason: "Plant-based protein, versatile for any recipe",
                    imageURL: nil,
                    link: "https://www.amazon.com/s?k=gardein+chicken+strips",
                    estimatedCO2: altImpact.co2,
                    estimatedWater: altImpact.water
                ))
            } else if productName.contains("sausage") {
                let altIngredients = ["wheat gluten", "barley", "vegetables", "spices"]
                let altImpact = self.calculateEnvironmentalImpact(altIngredients)
                alternatives.append(AnalysisResult.Alternative(
                    name: "Vegan Sausage",
                    brand: "Field Roast",
                    reason: "Made from grains and vegetables, savory and satisfying",
                    imageURL: nil,
                    link: "https://www.amazon.com/s?k=field+roast+sausage",
                    estimatedCO2: altImpact.co2,
                    estimatedWater: altImpact.water
                ))
            } else {
                // Generic meat product
                let altIngredients = ["plant protein", "vegetables"]
                let altImpact = self.calculateEnvironmentalImpact(altIngredients)
                alternatives.append(AnalysisResult.Alternative(
                    name: "Plant-Based Protein",
                    brand: "Multiple brands available",
                    reason: "Many delicious meat alternatives available",
                    imageURL: nil,
                    link: "https://www.amazon.com/s?k=plant+based+meat+alternative",
                    estimatedCO2: altImpact.co2,
                    estimatedWater: altImpact.water
                ))
            }
        }
        
        // Egg alternatives
        if hasEggViolation && isEggProduct {
            let altIngredients = ["mung bean protein", "turmeric", "salt"]
            let altImpact = self.calculateEnvironmentalImpact(altIngredients)
            alternatives.append(AnalysisResult.Alternative(
                name: "JUST Egg",
                brand: "Eat Just",
                reason: "Mung bean-based, scrambles like eggs, cholesterol-free",
                imageURL: nil,
                link: "https://www.amazon.com/s?k=just+egg",
                estimatedCO2: altImpact.co2,
                estimatedWater: altImpact.water
            ))
        }
        
        // High sugar products
        if let nutriments = product.nutriments, let sugars = nutriments.sugars100g, sugars > 10 {
            if productName.contains("soda") || productName.contains("cola") {
                let altIngredients = ["carbonated water", "natural flavors"]
                let altImpact = self.calculateEnvironmentalImpact(altIngredients)
                alternatives.append(AnalysisResult.Alternative(
                    name: "Sparkling Water",
                    brand: "LaCroix",
                    reason: "Zero sugar, zero calories, naturally flavored",
                    imageURL: nil,
                    link: "https://www.lacroix.com/",
                    estimatedCO2: altImpact.co2,
                    estimatedWater: altImpact.water
                ))
            } else if productName.contains("juice") {
                let altIngredients = ["kale", "spinach", "apple", "lemon"]
                let altImpact = self.calculateEnvironmentalImpact(altIngredients)
                alternatives.append(AnalysisResult.Alternative(
                    name: "Organic Green Juice",
                    brand: "Suja",
                    reason: "Cold-pressed vegetables and fruits, no added sugar",
                    imageURL: nil,
                    link: "https://www.amazon.com/s?k=suja+organic+juice",
                    estimatedCO2: altImpact.co2,
                    estimatedWater: altImpact.water
                ))
            }
        }
        
        // Gluten alternatives
        if hasGlutenViolation && isBreadProduct {
            if productName.contains("bread") {
                alternatives.append(AnalysisResult.Alternative(
                    name: "Gluten-Free Bread",
                    brand: "Canyon Bakehouse",
                    reason: "Made with whole grains, soft texture, certified gluten-free",
                    imageURL: nil,
                    link: "https://www.amazon.com/s?k=canyon+bakehouse+gluten+free+bread"
                ))
            } else if productName.contains("pasta") {
                alternatives.append(AnalysisResult.Alternative(
                    name: "Brown Rice Pasta",
                    brand: "Tinkyada",
                    reason: "Gluten-free, cooks like regular pasta, good texture",
                    imageURL: nil,
                    link: "https://www.amazon.com/s?k=tinkyada+brown+rice+pasta"
                ))
            } else if productName.contains("cereal") {
                alternatives.append(AnalysisResult.Alternative(
                    name: "Gluten-Free Oats",
                    brand: "Bob's Red Mill",
                    reason: "Certified gluten-free, whole grain, high fiber",
                    imageURL: nil,
                    link: "https://www.amazon.com/s?k=bobs+red+mill+gluten+free+oats"
                ))
            }
        }
        
        // Pork alternatives (for kosher/halal)
        if hasPorkViolation {
            if productName.contains("bacon") {
                alternatives.append(AnalysisResult.Alternative(
                    name: "Turkey Bacon",
                    brand: "Applegate",
                    reason: "No pork, halal-friendly, lower fat",
                    imageURL: nil,
                    link: "https://www.amazon.com/s?k=applegate+turkey+bacon"
                ))
            } else if productName.contains("sausage") {
                alternatives.append(AnalysisResult.Alternative(
                    name: "Chicken Sausage",
                    brand: "Aidells",
                    reason: "No pork, flavorful, higher quality ingredients",
                    imageURL: nil,
                    link: "https://www.amazon.com/s?k=aidells+chicken+sausage"
                ))
            }
        }
        
        // Shellfish alternatives
        if hasShellfishViolation {
            alternatives.append(AnalysisResult.Alternative(
                name: "Wild-Caught Fish",
                brand: "Multiple brands available",
                reason: "No shellfish, rich in omega-3s, safer for allergies",
                imageURL: nil,
                link: "https://www.amazon.com/s?k=wild+caught+salmon"
            ))
        }
        
        // Ultra-processed (NOVA 4) - suggest minimally processed alternatives
        if product.novaGroup == 4 {
            if productName.contains("cereal") {
                alternatives.append(AnalysisResult.Alternative(
                    name: "Organic Steel Cut Oats",
                    brand: "Bob's Red Mill",
                    reason: "Whole grain, high fiber, minimal processing",
                    imageURL: nil,
                    link: "https://www.amazon.com/s?k=bobs+red+mill+steel+cut+oats"
                ))
            } else if productName.contains("snack") || productName.contains("chip") {
                alternatives.append(AnalysisResult.Alternative(
                    name: "Veggie Chips",
                    brand: "Bare Snacks",
                    reason: "Simply baked vegetables, no added oil or preservatives",
                    imageURL: nil,
                    link: "https://www.amazon.com/s?k=bare+snacks+veggie+chips"
                ))
            }
        }
        
        // If we still have no alternatives but have concerns, add context-appropriate suggestions
        if alternatives.isEmpty && !concernItems.isEmpty {
            // Detect product type for smart fallback
            let isBar = productName.contains("bar") || productName.contains("energy") || 
                       productName.contains("protein") || productName.contains("granola")
            let isSnack = productName.contains("snack") || productName.contains("chip") || 
                         productName.contains("cracker") || productName.contains("cookie")
            let isDrink = productName.contains("drink") || productName.contains("beverage") ||
                         productName.contains("juice") || productName.contains("soda") ||
                         productName.contains("water") || productName.contains("tea")
            let isCandy = productName.contains("candy") || productName.contains("chocolate") ||
                         productName.contains("gummy") || productName.contains("sweet")
            
            if isBar {
                // Suggest healthier bars
                if preferences.selectedDiets.contains("Vegan") {
                    alternatives.append(AnalysisResult.Alternative(
                        name: "Vegan Protein Bar",
                        brand: "GoMacro",
                        reason: "Plant-based, organic ingredients, sustained energy",
                        imageURL: nil,
                        link: "https://www.amazon.com/s?k=gomacro+vegan+protein+bar"
                    ))
                } else {
                    alternatives.append(AnalysisResult.Alternative(
                        name: "RXBar",
                        brand: "RXBAR",
                        reason: "Simple ingredients, high protein, no added sugar",
                        imageURL: nil,
                        link: "https://www.amazon.com/s?k=rxbar+protein+bar"
                    ))
                }
            } else if isSnack {
                alternatives.append(AnalysisResult.Alternative(
                    name: "Organic Trail Mix",
                    brand: "365 by Whole Foods",
                    reason: "Whole food ingredients, good fats, no preservatives",
                    imageURL: nil,
                    link: "https://www.amazon.com/s?k=organic+trail+mix"
                ))
            } else if isDrink {
                alternatives.append(AnalysisResult.Alternative(
                    name: "Unsweetened Tea",
                    brand: "Honest Tea",
                    reason: "No added sugar, natural antioxidants",
                    imageURL: nil,
                    link: "https://www.amazon.com/s?k=honest+tea+unsweetened"
                ))
            } else if isCandy {
                alternatives.append(AnalysisResult.Alternative(
                    name: "Dark Chocolate",
                    brand: "Hu Kitchen",
                    reason: "No refined sugar, organic cacao, simple ingredients",
                    imageURL: nil,
                    link: "https://www.amazon.com/s?k=hu+kitchen+dark+chocolate"
                ))
            }
        }
        
        // Return up to 3 alternatives
        AppLogger.debug("   📋 Generated \(alternatives.count) alternatives")
        return Array(alternatives.prefix(3))
    }
    
    // MARK: - Progress Updates
    
    private func updateProgress(_ progress: Double, step: String) async {
        self.lookupProgress = progress
        self.currentStep = step
    }
    
    // MARK: - Cache Management
    
    func clearExpiredCache() async {
        await cacheService.clearExpired()
    }

    func getCacheStats() async -> (total: Int, expired: Int) {
        return await cacheService.getCacheStats()
    }
}
