//
//  NetworkService.swift
//  Ethica
//
//  Created on 11/11/2025
//

import Foundation
import UIKit
import Combine
import Network

/// Fast safety verdict from /quick-allergen-check and /quick-safety-check endpoints
struct QuickSafetyResult: Codable {
    let isSafe: Bool
    let safetyLevel: String?
    let confidence: Double
    let violations: [String]
    let warnings: [String]
    let cautionWarnings: [String]
    let detectedAllergens: [String]
    let detectionEvidence: [AnalysisResult.DetectionEvidence]?
    let crossContaminationRisks: [String]?
    let gmoStatus: String?
    let sourceType: String?
    // Extra fields from /quick-safety-check (ingredient photo OCR)
    let extractedIngredients: [String]?
    let ingredientsText: String?
    let productName: String?
}

/// Identification-only result from /identify-product (no analysis)
struct VisualIdentification {
    let productName: String
    let confidence: Double
    let estimatedIngredients: [String]
    let ingredientConfidence: Double
    let ingredientSource: String
    let productCategory: String
}

@MainActor
class NetworkService: ObservableObject {
    static let shared = NetworkService()
    @Published var isAnalyzing = false
    @Published var errorMessage: String?
    @Published var analysisProgress: Double = 0.0 // 0.0 to 1.0

    /// Phase 2 detail enrichment for plate analysis — late subscribers get the last value.
    static let plateDetailSubject = CurrentValueSubject<PlateAnalysis?, Never>(nil)

    /// Monotonic counter to discard stale Phase 2 events from previous scans.
    private var plateStreamGeneration: Int = 0

    private let productDatabaseService = ProductDatabaseService.shared
    nonisolated let networkMonitor = NWPathMonitor()
    @Published var isConnected = true

    /// Apply client-side Jain diet validation if user has Jain selected
    private func applyJainValidation(_ result: AnalysisResult?, preferences: UserPreferences) -> AnalysisResult? {
        guard let result = result else { return nil }
        let allDiets = Array(preferences.selectedDiets) + preferences.customDiets
        let isJain = allDiets.contains { $0.lowercased() == "jain" }
        guard isJain else { return result }
        return JainDietValidator.shared.validateResult(result)
    }
    
    // Result type for ingredient extraction
    private enum ExtractResult {
        case ingredients([String], productName: String?, ocrText: String?, allergenContains: [String], allergenMayContain: [String], ocrConfidenceWarning: String?, gmoDeclaration: String?)
        case matchedProduct(AnalysisResult)
        case error
    }
    
    // Helper to add auth token and compression headers to requests
    private func addAuthToken(to request: inout URLRequest) async {
        if let token = AuthenticationService.shared.authToken, !token.isEmpty {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        } else {
            AppLogger.warning("No auth token available — request will be unauthenticated")
        }
        // Enable gzip compression for 75% bandwidth reduction
        request.setValue("gzip, deflate", forHTTPHeaderField: "Accept-Encoding")
    }
    
    // MARK: - Quick Allergen Check (Fast Safety Verdict)

    /// Fast allergen/dietary/GMO safety check (2-4s). Returns nil on failure (caller falls back to client-side).
    func quickAllergenCheck(
        ingredients: [String],
        preferences: UserPreferences,
        barcode: String?,
        productName: String?,
        openfoodfactsData: [String: Any]?
    ) async -> QuickSafetyResult? {
        guard isConnected else {
            AppLogger.debug("⚡ Skipping quick-allergen-check: offline")
            return nil
        }
        _ = barcode
        _ = openfoodfactsData

        do {
            guard GeminiConfig.isConfigured else { return nil }

            let text = ingredients.joined(separator: ", ")
            let json = try await GeminiService.shared.analyzeIngredientsTextToAnalysisResultJSON(
                ingredientsText: text,
                productName: productName,
                preferences: preferences
            )

            let isSafe = (json["isSafe"] as? Bool) ?? true
            let safetyLevel = json["safetyLevel"] as? String
            let confidence = (json["confidence"] as? Double) ?? 0.6
            let violations = json["violations"] as? [String] ?? []
            let warnings = json["warnings"] as? [String] ?? []
            let cautionWarnings = json["cautionWarnings"] as? [String] ?? []
            let detectedAllergens = json["detectedAllergens"] as? [String] ?? []

            return QuickSafetyResult(
                isSafe: isSafe,
                safetyLevel: safetyLevel,
                confidence: confidence,
                violations: violations,
                warnings: warnings,
                cautionWarnings: cautionWarnings,
                detectedAllergens: detectedAllergens,
                detectionEvidence: nil,
                crossContaminationRisks: nil,
                gmoStatus: json["gmoStatus"] as? String,
                sourceType: "gemini_text",
                extractedIngredients: ingredients,
                ingredientsText: text,
                productName: (json["productName"] as? String) ?? productName
            )
        } catch {
            AppLogger.warning("⚠️ quick-allergen-check failed: \(error.localizedDescription)")
            return nil
        }
    }

    // MARK: - Quick Safety Check from Ingredient Photo

    /// Ingredient label photo — direct Gemini API (no backend).
    func quickSafetyCheckFromPhoto(
        image: UIImage,
        preferences: UserPreferences
    ) async -> QuickSafetyResult? {
        guard isConnected else {
            AppLogger.debug("⚡ Skipping quick-safety-check: offline")
            return nil
        }
        guard GeminiConfig.isConfigured else {
            AppLogger.warning("⚠️ Gemini API key missing for label quick check")
            return nil
        }

        let resized = resizeImage(image, maxSize: 1200)
        guard let imageData = resized.jpegData(compressionQuality: 0.75) else {
            AppLogger.error("❌ Failed to compress ingredient photo")
            return nil
        }

        do {
            let result = try await GeminiService.shared.quickSafetyFromLabel(
                imageData: imageData,
                preferences: preferences
            )
            AppLogger.debug("✅ Gemini quick-safety: isSafe=\(result.isSafe), violations=\(result.violations.count)")
            return result
        } catch {
            AppLogger.warning("⚠️ Gemini quick-safety failed: \(error.localizedDescription)")
            return nil
        }
    }

    // MARK: - Full Analysis from Extracted Ingredients

    /// Run full comprehensive analysis using pre-extracted ingredients (from QuickSafetyResultView).
    func analyzeIngredientsDirectly(
        ingredients: [String],
        productName: String,
        preferences: UserPreferences
    ) async -> AnalysisResult? {
        return await analyzeIngredients(
            ingredients,
            preferences: preferences,
            ingredientsList: ingredients,
            productName: productName,
            ingredientsText: ingredients.joined(separator: ", ")
        )
    }

    init() {
        // Monitor network connectivity
        networkMonitor.pathUpdateHandler = { [weak self] path in
            let connected = path.status == .satisfied
            Task { @MainActor in
                self?.isConnected = connected
            }
            if connected {
                AppLogger.debug("✅ Network connected")
            } else {
                AppLogger.error("❌ Network disconnected")
            }
        }
        let queue = DispatchQueue(label: "NetworkMonitor")
        networkMonitor.start(queue: queue)
    }
    
    deinit {
        networkMonitor.cancel()
    }
    
    private func checkNetworkConnection() async -> Bool {
        if !isConnected {
            let cachedCount = OfflineCacheService.shared.cachedCount
            await MainActor.run {
                if cachedCount > 0 {
                    self.errorMessage = "No internet connection. You can view \(cachedCount) cached results in your History."
                } else {
                    self.errorMessage = "No internet connection. Please check your network and try again."
                }
            }
            return false
        }
        return true
    }

    /// Retry wrapper with exponential backoff for network operations
    /// Improves reliability without sacrificing speed on success
    private func performWithRetry<T>(
        maxAttempts: Int = 3,
        operation: @escaping () async throws -> T
    ) async throws -> T {
        var lastError: Error?

        for attempt in 1...maxAttempts {
            do {
                return try await operation()
            } catch {
                lastError = error
                AppLogger.warning("⚠️ Network attempt \(attempt)/\(maxAttempts) failed: \(error.localizedDescription)")

                // Don't retry on last attempt
                if attempt == maxAttempts {
                    break
                }

                // Exponential backoff: 0.5s, 1s, 2s
                let backoffSeconds = 0.5 * pow(2.0, Double(attempt - 1))
                AppLogger.debug("🔄 Retrying in \(backoffSeconds)s...")
                try await Task.sleep(nanoseconds: UInt64(backoffSeconds * 1_000_000_000))
            }
        }

        // All attempts failed
        throw lastError ?? NSError(
            domain: "NetworkService",
            code: -1,
            userInfo: [NSLocalizedDescriptionKey: "All retry attempts failed"]
        )
    }

    func analyzeImage(_ image: UIImage, preferences: UserPreferences, useBarcodeScanning: Bool = false, useRestaurantMode: Bool = false) async -> AnalysisResult? {
        // Check network connectivity first
        guard await checkNetworkConnection() else {
            await MainActor.run {
                self.isAnalyzing = false
                self.analysisProgress = 0.0
            }
            return nil
        }
        
        await MainActor.run {
            self.isAnalyzing = true
            self.errorMessage = nil
            self.analysisProgress = 0.0
        }
        
        // STEP 1: Try barcode lookup if explicitly requested (0.0 → 0.3)
        if useBarcodeScanning {
            AppLogger.debug("🔍 Attempting barcode detection...")
            if let databaseResult = await productDatabaseService.lookupProduct(image: image, preferences: preferences) {
                AppLogger.debug("✅ Found product in database!")
                AppLogger.debug("🏷️ Product name from barcode: \(databaseResult.productName)")
                
                // Cache for offline access
                OfflineCacheService.shared.cacheResult(CachedScanResult(from: databaseResult))
                
                // Save to history
                let scanHistory = ScanHistory(from: databaseResult)
                AppLogger.debug("💾 Saving barcode scan to history with productName: \(scanHistory.productName)")
                HistoryService.shared.saveScan(scanHistory)
                AppLogger.debug("💾 Saved barcode scan to history")
                
                await MainActor.run {
                    self.isAnalyzing = false
                    self.analysisProgress = 1.0
                }
                return databaseResult
            }
            
            // Fallback to OCR if no barcode found
            AppLogger.warning("⚠️ No barcode match, falling back to OCR...")
            await MainActor.run {
                self.analysisProgress = 0.3
            }
        }

        // Take Photo / label OCR: direct Gemini (no Ethica backend)
        if !useRestaurantMode {
            return await analyzeIngredientPhotoWithGemini(image: image, preferences: preferences)
        }
        
        // Resize image for faster upload + processing (800px is enough for AI)
        // Perform image processing on background thread to avoid blocking UI
        let imageData: Data? = await Task.detached(priority: .userInitiated) {
            let resized = self.resizeImage(image, maxSize: 800)
            return resized.jpegData(compressionQuality: 0.7)
        }.value

        guard let imageData = imageData else {
            await MainActor.run {
                self.isAnalyzing = false
                self.errorMessage = "Failed to process image"
                self.analysisProgress = 0.0
            }
            return nil
        }
        
        AppLogger.debug("📸 Image size: \(imageData.count / 1024)KB")
        
        await MainActor.run {
            self.analysisProgress = 0.4 // 40% - Image processed (OCR fallback)
        }
        
        // Step 1: Extract ingredients from image using Google Vision
        let base64Image = imageData.base64EncodedString()
        
        await MainActor.run {
            self.analysisProgress = 0.5 // 50% - Starting OCR extraction
        }
        
        // Branch based on restaurant mode
        if useRestaurantMode {
            // Restaurant menu: extract and analyze directly
            return await analyzeRestaurantMenu(base64Image: base64Image, preferences: preferences)
        }
        
        // NEW: Extract ingredients (may return matched OpenFoodFacts product directly)
        let extractResult = await extractIngredientsOrMatchProduct(base64Image: base64Image, preferences: preferences)
        
        // If we got a direct product match from OpenFoodFacts, return it
        if case .matchedProduct(let product) = extractResult {
            AppLogger.debug("✅ OCR scan matched to OpenFoodFacts product, returning directly")
            return product
        }
        
        // Otherwise, extract the ingredients list (with optional OCR context for enrichment)
        guard case .ingredients(let ingredients, let extractedProductName, let extractedOcrText, let allergenContains, let allergenMayContain, let ocrConfidenceWarning, let gmoDeclaration) = extractResult else {
            await MainActor.run {
                self.analysisProgress = 0.0
            }
            return nil
        }

        AppLogger.debug("✅ Extracted \(ingredients.count) ingredients")
        if let name = extractedProductName {
            AppLogger.debug("📝 Extracted product name: \(name)")
        }
        if !allergenContains.isEmpty {
            AppLogger.debug("⚠️ Label allergen declaration: \(allergenContains.joined(separator: ", "))")
        }
        if !allergenMayContain.isEmpty {
            AppLogger.debug("⚠️ Label cross-contamination: \(allergenMayContain.joined(separator: ", "))")
        }

        // Surface OCR quality warning to user
        if let warning = ocrConfidenceWarning {
            AppLogger.warning("📸 OCR quality warning: \(warning)")
            await MainActor.run {
                self.errorMessage = warning
            }
        }

        await MainActor.run {
            self.analysisProgress = 0.7 // 70% - OCR ingredients extracted
        }

        // Step 2: Analyze the ingredients (forward OCR context and allergen declarations)
        await MainActor.run {
            self.analysisProgress = 0.75 // 75% - Starting AI analysis
        }

        let result = await analyzeIngredients(ingredients, preferences: preferences, ingredientsList: ingredients, productName: extractedProductName, ingredientsText: extractedOcrText, allergenContains: allergenContains, allergenMayContain: allergenMayContain, gmoDeclaration: gmoDeclaration)
        
        // Save OCR scan to history if successful
        if let result = result {
            AppLogger.debug("🏷️ OCR result productName: \(result.productName)")
            let scanHistory = ScanHistory(from: result)
            AppLogger.debug("💾 Saving OCR scan to history with productName: \(scanHistory.productName)")
            HistoryService.shared.saveScan(scanHistory)
            AppLogger.debug("💾 Saved OCR scan to history")
        }
        
        await MainActor.run {
            self.analysisProgress = result != nil ? 1.0 : 0.0 // 100% - Complete
        }
        
        return result
    }
    
    func identifyVisualProduct(_ image: UIImage, preferences: UserPreferences) async -> VisualIdentification? {
        // Check network connectivity first
        guard await checkNetworkConnection() else {
            await MainActor.run {
                self.isAnalyzing = false
                self.analysisProgress = 0.0
            }
            return nil
        }

        await MainActor.run {
            self.isAnalyzing = true
            self.errorMessage = nil
            self.analysisProgress = 0.1
        }

        // Resize to 768px at 0.7 quality — sufficient for brand/text recognition, faster upload
        let imageData: Data? = await Task.detached(priority: .userInitiated) {
            let resized = self.resizeImage(image, maxSize: 768)
            return resized.jpegData(compressionQuality: 0.7)
        }.value

        guard let imageData = imageData else {
            await MainActor.run {
                self.isAnalyzing = false
                self.errorMessage = "Failed to process image"
                self.analysisProgress = 0.0
            }
            return nil
        }

        AppLogger.debug("📸 Image size: \(imageData.count / 1024)KB")

        do {
            AppLogger.debug("🔍 Identifying product from visual image...")
            await MainActor.run {
                self.analysisProgress = 0.3
            }
            let json = try await GeminiService.shared.identifyProductFromImage(imageData: imageData)
            let productName = (json["product_name"] as? String) ?? "Unknown Product"

            let identification = VisualIdentification(
                productName: productName,
                confidence: json["confidence"] as? Double ?? 0,
                estimatedIngredients: json["ingredients"] as? [String] ?? [],
                ingredientConfidence: json["ingredient_confidence"] as? Double ?? 0,
                ingredientSource: json["ingredient_source"] as? String ?? "image_estimate",
                productCategory: json["product_category"] as? String ?? ""
            )

            AppLogger.debug("✅ Visual identification (Gemini): \(identification.productName) (\(identification.confidence)%)")

            await MainActor.run {
                self.analysisProgress = 0.5
            }

            return identification
        } catch {
            AppLogger.error("❌ Visual identification failed: \(error)")
            await MainActor.run {
                self.isAnalyzing = false
                self.analysisProgress = 0.0
                self.errorMessage = "Failed to identify product: \(error.localizedDescription)"
            }
            return nil
        }
    }
    
    private func analyzeRestaurantMenu(base64Image: String, preferences: UserPreferences) async -> AnalysisResult? {
        do {
            AppLogger.debug("🔄 Analyzing restaurant menu...")
            await MainActor.run {
                self.analysisProgress = 0.60 // 60% - Processing menu
            }

            guard let imageData = Data(base64Encoded: base64Image) else { return nil }
            let json = try await GeminiService.shared.extractMenuDishesFromImage(imageData: imageData, preferences: preferences)
            let items = (json["menuAnalysis"] as? [[String: Any]]) ?? []

            guard !items.isEmpty else {
                await MainActor.run {
                    self.isAnalyzing = false
                    self.analysisProgress = 0.0
                    self.errorMessage = "No dishes found in menu. Please:\n• Use a clear photo of the menu\n• Ensure good lighting\n• Include dish names and descriptions"
                }
                return nil
            }

            let dishes: [AnalysisResult.MenuDish] = items.map { dish in
                AnalysisResult.MenuDish(
                    dish: dish["dish"] as? String ?? "Unknown Dish",
                    ingredients: dish["ingredients"] as? [String] ?? [],
                    safe: dish["safe"] as? Bool ?? false,
                    warnings: dish["warnings"] as? [String] ?? [],
                    estimatedCO2: dish["estimatedCO2"] as? Double
                )
            }

            let safeDishes = dishes.filter { $0.safe }.count
            let unsafeDishes = dishes.count - safeDishes

            let result = AnalysisResult(
                productName: "Restaurant Menu Analysis",
                overallScore: dishes.isEmpty ? 0 : (Double(safeDishes) / Double(dishes.count) * 10.0),
                isSafe: safeDishes > 0,
                confidence: 0.7,
                confidenceFactors: ["Menu analysis based on typical ingredients"],
                violations: unsafeDishes > 0 ? ["\(unsafeDishes) dishes may contain restricted ingredients"] : [],
                warnings: ["⚠️ Always verify ingredients with restaurant staff"],
                cautionWarnings: ["Ingredient analysis is based on typical recipes"],
                ingredients: [],
                detectedAllergens: [],
                detectionEvidence: [],
                healthScore: 5.0,
                environmentalScore: 5.0,
                co2Emissions: 0,
                waterUsage: 0,
                animalImpact: "Unknown",
                landUse: "Unknown",
                nutritionalHighlights: [],
                healthConcerns: [],
                healthBenefits: [],
                recommendations: ["\(safeDishes) dishes appear safe for your preferences"],
                alternatives: [],
                environmentalBreakdown: [],
                sourceBarcode: nil,
                sourceType: "restaurant_menu",
                timestamp: Date(),
                isRestaurantMenu: true,
                menuDishes: dishes
            )

            await MainActor.run {
                self.isAnalyzing = false
                self.analysisProgress = 1.0
            }

            return result
        } catch {
            AppLogger.error("❌ Error analyzing restaurant menu: \(error)")
            await MainActor.run {
                self.isAnalyzing = false
                self.errorMessage = "Failed to analyze menu: \(error.localizedDescription)"
                self.analysisProgress = 0.0
            }
            return nil
        }
    }
    
    // MARK: - Ingredient label photo (Gemini, on-device API key)

    private func analyzeIngredientPhotoWithGemini(
        image: UIImage,
        preferences: UserPreferences
    ) async -> AnalysisResult? {
        guard GeminiConfig.isConfigured else {
            await MainActor.run {
                self.isAnalyzing = false
                self.analysisProgress = 0.0
                self.errorMessage = GeminiConfig.missingKeyMessage
            }
            return nil
        }

        let imageData: Data? = await Task.detached(priority: .userInitiated) {
            let resized = self.resizeImage(image, maxSize: 1200)
            return resized.jpegData(compressionQuality: 0.75)
        }.value

        guard let imageData = imageData else {
            await MainActor.run {
                self.isAnalyzing = false
                self.errorMessage = "Failed to process image"
            }
            return nil
        }

        await MainActor.run { self.analysisProgress = 0.35 }

        do {
            AppLogger.debug("🤖 Take Photo: Gemini label analysis (\(imageData.count / 1024)KB)")
            let backendResponse = try await GeminiService.shared.analyzeIngredientLabel(
                imageData: imageData,
                preferences: preferences
            )
            let ingredients = backendResponse.ingredients ?? []

            if ingredients.isEmpty {
                let violations = backendResponse.violations ?? []
                if violations.contains(where: { $0.lowercased().contains("no readable") || $0.lowercased().contains("no text") }) {
                    await MainActor.run {
                        self.isAnalyzing = false
                        self.analysisProgress = 0.0
                        self.errorMessage = "No text found in image. Please:\n• Use a clear photo of the ingredient label\n• Ensure good lighting\n• Hold camera steady"
                    }
                    return nil
                }
            }

            await MainActor.run { self.analysisProgress = 0.75 }

            var result = await convertToAnalysisResult(backendResponse, ingredients: ingredients, preferences: preferences)
            if let validated = applyJainValidation(result, preferences: preferences) {
                result = validated
            }

            AppLogger.debug("🏷️ Gemini label result: \(result.productName)")
            let scanHistory = ScanHistory(from: result)
            HistoryService.shared.saveScan(scanHistory)
            OfflineCacheService.shared.cacheResult(CachedScanResult(from: result))

            await MainActor.run {
                self.isAnalyzing = false
                self.analysisProgress = 1.0
            }
            return result
        } catch {
            AppLogger.error("❌ Gemini label analysis: \(error.localizedDescription)")
            await MainActor.run {
                self.isAnalyzing = false
                self.analysisProgress = 0.0
                self.errorMessage = error.localizedDescription
            }
            return nil
        }
    }

    private func extractIngredientsOrMatchProduct(base64Image: String, preferences: UserPreferences, isRestaurantMenu: Bool = false) async -> ExtractResult {
        _ = base64Image
        _ = preferences
        _ = isRestaurantMenu
        // Backend-less build: ingredient/menu extraction is handled by Gemini directly in
        // `analyzeIngredientPhotoWithGemini` and `analyzeRestaurantMenu`.
        return .error
    }
    
    private func analyzeIngredients(_ ingredients: [String], preferences: UserPreferences, ingredientsList: [String], productName: String? = nil, ingredientsText: String? = nil, allergenContains: [String] = [], allergenMayContain: [String] = [], gmoDeclaration: String? = nil) async -> AnalysisResult? {
        do {
            _ = ingredientsList
            _ = allergenContains
            _ = allergenMayContain
            _ = gmoDeclaration

            let text = ingredientsText ?? ingredients.joined(separator: ", ")
            let json = try await GeminiService.shared.analyzeIngredientsTextToAnalysisResultJSON(
                ingredientsText: text,
                productName: productName,
                preferences: preferences
            )
            let data = try JSONSerialization.data(withJSONObject: json)

            await MainActor.run {
                self.analysisProgress = 0.8 // 80% - Sending AI analysis request
            }
            await MainActor.run { self.analysisProgress = 0.9 }

            var result = try JSONDecoder().decode(AnalysisResult.self, from: data)
            if let validated = applyJainValidation(result, preferences: preferences) {
                result = validated
            }

            await MainActor.run {
                self.isAnalyzing = false
                self.analysisProgress = 1.0
            }

            return result
        } catch {
            AppLogger.error("❌ Gemini analysis error: \(error)")
            await MainActor.run {
                self.isAnalyzing = false
                self.errorMessage = "Error: \(error.localizedDescription)"
                self.analysisProgress = 0.0
            }
            return nil
        }
    }
    
    private func convertToAnalysisResult(_ response: BackendResponse, ingredients: [String], preferences: UserPreferences) async -> AnalysisResult {
        let productName = response.productName ?? ingredients.prefix(3).joined(separator: ", ")

        // Defensive extraction — prefer flat keys from backend, fall back to nested structs
        let definiteViolationStrings = response.detectedAllergens ?? response.allergens?.definiteViolations?.compactMap { $0.allergen } ?? []
        let cautionWarningStrings = response.cautionWarnings ?? response.allergens?.cautionWarnings?.compactMap { $0.warning } ?? []
        let dietaryViolations = response.dietaryViolations ?? response.dietary?.violations ?? []
        let allViolations = response.violations ?? (definiteViolationStrings + dietaryViolations)
        let allWarnings = (response.warnings ?? []) + cautionWarningStrings

        // Check for custom allergen violations (client-side for reliability)
        let (customAllergenViolations, detectionEvidence) = await Task.detached(priority: .userInitiated) {
            let violations = self.checkCustomAllergens(ingredients: ingredients, preferences: preferences)
            let allViolationsWithCustom = allViolations + violations
            let evidence = self.createDetectionEvidence(
                violations: allViolationsWithCustom,
                ingredients: ingredients,
                preferences: preferences
            )
            return (violations, evidence)
        }.value

        let allViolationsWithCustom = allViolations + customAllergenViolations

        // Environmental score calculation
        let co2 = response.co2Emissions ?? response.environmental?.totalCO2 ?? 0.5
        let water = response.waterUsage ?? response.environmental?.waterUsage ?? 200
        let animalImpactStr = (response.animalImpact ?? response.environmental?.animalImpact ?? "medium").lowercased()

        let co2Score: Double
        if co2 <= 0.5 { co2Score = 10 + (co2 / 0.5) * 10 }
        else if co2 <= 1.5 { co2Score = 30 + ((co2 - 0.5) / 1.0) * 20 }
        else if co2 <= 3.0 { co2Score = 60 + ((co2 - 1.5) / 1.5) * 10 }
        else { co2Score = min(80 + ((co2 - 3.0) / 2.0) * 20, 100) }

        let waterScore: Double
        if water <= 200 { waterScore = 10 + (water / 200.0) * 10 }
        else if water <= 400 { waterScore = 30 + ((water - 200) / 200.0) * 20 }
        else if water <= 600 { waterScore = 60 + ((water - 400) / 200.0) * 10 }
        else { waterScore = min(80 + ((water - 600) / 400.0) * 20, 100) }

        let animalScore: Double = animalImpactStr.contains("low") ? 10 : animalImpactStr.contains("high") ? 90 : 50

        let localEnvScore = (co2Score + waterScore + animalScore) / 3.0
        let envScore: Double = {
            if let score = response.environmentalScore, score > 0 { return score }
            return localEnvScore
        }()

        let healthScore = response.healthScore ?? response.health?.score ?? 0
        let overallScore: Double = {
            if let score = response.overallScore, score > 0 { return score }
            return (healthScore + envScore) / 2.0
        }()

        // Build typed alternatives directly (no JSON round-trip)
        let hp = preferences.healthPriority
        let ep = preferences.environmentPriority
        let ethp = preferences.ethicsPriority

        let typedAlternatives: [AnalysisResult.Alternative] = (response.alternatives ?? []).compactMap { alt in
            guard let name = alt.name, !name.isEmpty else { return nil }
            return AnalysisResult.Alternative(
                name: name,
                brand: alt.brand,
                reason: alt.reason,
                imageURL: alt.imageURL,
                link: alt.link,
                estimatedCO2: alt.estimatedCO2,
                estimatedWater: alt.estimatedWater,
                healthScore: alt.healthScore,
                environmentalScore: alt.environmentalScore,
                ethicsScore: alt.ethicsScore,
                barcode: nil,
                isEnriched: alt.dataSource == "openfoodfacts",
                dataSource: alt.dataSource,
                price: alt.price,
                priceSource: alt.priceSource,
                nutrition: alt.nutrition.map { n in
                    AnalysisResult.NutritionFacts(
                        calories: n.calories, protein: n.protein, carbs: n.carbs,
                        sugar: n.sugar, fat: n.fat, fiber: n.fiber, sodium: n.sodium
                    )
                }
            )
        }.sorted { a, b in
            func ws(_ alt: AnalysisResult.Alternative) -> Double {
                let h = alt.healthScore ?? 50.0
                let e = alt.environmentalScore ?? 50.0
                let et = alt.ethicsScore ?? 50.0
                return (h * hp + e * ep + et * ethp) / 100.0
            }
            return ws(a) > ws(b)
        }

        // Build typed additives directly
        let typedAdditives: [AnalysisResult.AdditiveInfo] = (response.additives ?? []).compactMap { additive in
            guard let code = additive.code, !code.isEmpty else { return nil }
            return AnalysisResult.AdditiveInfo(
                code: code,
                name: additive.name ?? code,
                category: additive.category ?? "Additive",
                riskLevel: additive.riskLevel ?? "low",
                description: additive.description ?? "",
                source: additive.source ?? "EFSA"
            )
        }

        // Build typed environmental breakdown directly
        let typedBreakdown: [AnalysisResult.EnvironmentalBreakdown] = (response.environmentalBreakdown ?? response.environmental?.breakdown ?? []).compactMap { item in
            AnalysisResult.EnvironmentalBreakdown(
                ingredient: item.ingredient ?? "",
                co2: item.co2 ?? 0,
                percentage: item.percentage ?? 0
            )
        }

        // Build safety confidence explanation
        let safetyConf: AnalysisResult.SafetyConfidenceExplanation? = {
            guard let sc = response.safetyConfidenceExplanation else { return nil }
            return AnalysisResult.SafetyConfidenceExplanation(
                overallConfidence: sc.overallConfidence ?? 0,
                confidenceLevel: sc.confidenceLevel ?? "Medium",
                detailedReasons: sc.detailedReasons ?? [],
                whatThisMeans: sc.whatThisMeans ?? "",
                recommendedAction: sc.recommendedAction ?? ""
            )
        }()

        // Build cross-contamination risks
        let typedCrossContam: [AnalysisResult.CrossContaminationRisk]? = response.crossContaminationRisks?.compactMap { risk in
            guard let allergen = risk.allergen else { return nil }
            return AnalysisResult.CrossContaminationRisk(
                allergen: allergen,
                riskLevel: risk.riskLevel ?? "Low",
                riskExplanation: risk.riskExplanation ?? "",
                manufacturingDetails: risk.manufacturingDetails ?? "",
                guidance: risk.guidance ?? ""
            )
        }

        // Build ingredient education
        let typedIngredientEdu: [AnalysisResult.IngredientEducation]? = response.ingredientEducation?.compactMap { edu in
            guard let ingredient = edu.ingredient else { return nil }
            return AnalysisResult.IngredientEducation(
                ingredient: ingredient,
                whatItIs: edu.whatItIs ?? "",
                hiddenSources: edu.hiddenSources ?? [],
                whyItMatters: edu.whyItMatters ?? "",
                isSafe: edu.isSafe,
                confidence: edu.confidence ?? 0
            )
        }

        var isSafe = customAllergenViolations.isEmpty
            ? (response.isSafe ?? ((response.allergens?.safe ?? true) && dietaryViolations.isEmpty))
            : false

        // Enforce mayContainSafe=false (strict mode):
        // Elevate caution warnings matching user allergens to violations
        var mayContainViolations: [String] = []
        var filteredCautionWarnings = cautionWarningStrings
        if !preferences.mayContainSafe && !cautionWarningStrings.isEmpty {
            let userAllergens = (Array(preferences.selectedAllergens) + preferences.customAllergens).map { $0.lowercased() }
            if !userAllergens.isEmpty {
                for caution in cautionWarningStrings {
                    let cautionLower = caution.lowercased()
                    if userAllergens.contains(where: { cautionLower.contains($0) }) {
                        mayContainViolations.append(caution)
                        isSafe = false
                    }
                }
                if !mayContainViolations.isEmpty {
                    // Remove elevated cautions from caution list
                    filteredCautionWarnings = cautionWarningStrings.filter { !mayContainViolations.contains($0) }
                    AppLogger.warning("mayContainSafe strict mode: elevated \(mayContainViolations.count) caution(s) to violations")
                }
            }
        }
        // Enforce avoidGMO preference (defense-in-depth) — Jain decoupled, avoidGMO is sole control
        let gmoStatus = response.gmoStatus ?? "no_risk"
        if gmoStatus == "confirmed_gmo" && preferences.avoidGMO {
            isSafe = false
        }

        let finalViolations = allViolationsWithCustom + mayContainViolations

        let detectedAllergensList = definiteViolationStrings + customAllergenViolations.map {
            $0.replacingOccurrences(of: "Custom allergen detected: ", with: "")
              .components(separatedBy: " found in").first ?? $0
        }

        // Construct AnalysisResult directly (no JSON serialize→deserialize round-trip)
        return AnalysisResult(
            productName: productName,
            overallScore: overallScore,
            isSafe: isSafe,
            confidence: response.confidence ?? 0,
            confidenceFactors: response.confidenceFactors ?? [],
            violations: finalViolations,
            warnings: allWarnings,
            cautionWarnings: filteredCautionWarnings,
            ingredients: ingredients,
            detectedAllergens: detectedAllergensList,
            detectionEvidence: detectionEvidence,
            healthScore: healthScore,
            environmentalScore: envScore,
            co2Emissions: max(co2, 0.3),
            waterUsage: max(water, 50),
            animalImpact: response.animalImpact ?? response.environmental?.animalImpact ?? "Medium",
            landUse: response.landUse ?? response.environmental?.animalImpact ?? "Unknown",
            nutritionalHighlights: response.nutritionalHighlights ?? response.health?.benefits ?? [],
            healthConcerns: response.healthConcerns ?? response.health?.concerns ?? [],
            healthBenefits: response.healthBenefits ?? response.health?.benefits ?? [],
            recommendations: response.flatRecommendations ?? response.recommendations?.insights ?? [],
            alternatives: typedAlternatives,
            environmentalBreakdown: typedBreakdown,
            brand: response.brand,
            certifications: response.certifications,
            processingLevel: response.processingLevel,
            packagingScore: response.packagingScore ?? 0,
            animalWelfareScore: response.animalWelfareScore ?? 0,
            additives: typedAdditives,
            packageWeightGrams: response.packageWeightGrams,
            sourceBarcode: response.sourceBarcode,
            sourceType: response.sourceType,
            gmoStatus: response.gmoStatus ?? "no_risk",
            safetyConfidenceExplanation: safetyConf,
            ingredientEducation: typedIngredientEdu,
            crossContaminationRisks: typedCrossContam
        )
    }
    
    nonisolated private func checkCustomAllergens(ingredients: [String], preferences: UserPreferences) -> [String] {
        var violations: [String] = []

        // Common allergen derivatives mapping for better detection accuracy
        let allergenDerivatives: [String: [String]] = [
            "milk": ["whey", "casein", "lactose", "ghee", "cream", "butter", "curds", "custard", "lactalbumin", "lactulose"],
            "dairy": ["whey", "casein", "lactose", "ghee", "cream", "butter", "curds", "custard", "lactalbumin", "lactulose"],
            "egg": ["albumin", "lysozyme", "ovalbumin", "ovomucin", "globulin", "lecithin", "mayonnaise"],
            "eggs": ["albumin", "lysozyme", "ovalbumin", "ovomucin", "globulin", "lecithin", "mayonnaise"],
            "peanut": ["arachis oil", "ground nuts", "peanut oil", "peanut butter"],
            "peanuts": ["arachis oil", "ground nuts", "peanut oil", "peanut butter"],
            "soy": ["soybean", "edamame", "tofu", "tempeh", "miso", "soya", "soy lecithin"],
            "soya": ["soybean", "edamame", "tofu", "tempeh", "miso", "soy", "soy lecithin"],
            "wheat": ["gluten", "flour", "bran", "starch", "bulgur", "couscous", "semolina", "seitan"],
            "tree nut": ["almond", "cashew", "walnut", "pecan", "pistachio", "macadamia", "hazelnut", "brazil nut"],
            "fish": ["anchovy", "bass", "catfish", "cod", "salmon", "tuna", "trout", "halibut", "fish sauce"],
            "shellfish": ["crab", "lobster", "shrimp", "prawn", "crayfish", "scallop", "clam", "oyster", "mussel"]
        ]

        func matchesAllergen(ingredient: String, allergen: String) -> Bool {
            let lowerIngredient = ingredient.lowercased()
            let lowerAllergen = allergen.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)

            // First check: Exact allergen match using word-boundary regex
            let escaped = NSRegularExpression.escapedPattern(for: lowerAllergen)
            let pattern = "\\b(?:" + escaped + ")(?:s|es)?\\b"
            if let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) {
                let range = NSRange(lowerIngredient.startIndex..<lowerIngredient.endIndex, in: lowerIngredient)
                if regex.firstMatch(in: lowerIngredient, options: [], range: range) != nil {
                    return true
                }
            }

            // Second check: Check for known derivatives
            if let derivatives = allergenDerivatives[lowerAllergen] {
                for derivative in derivatives {
                    let derivativeEscaped = NSRegularExpression.escapedPattern(for: derivative)
                    let derivativePattern = "\\b(?:" + derivativeEscaped + ")(?:s|es)?\\b"
                    if let derivativeRegex = try? NSRegularExpression(pattern: derivativePattern, options: [.caseInsensitive]) {
                        let range = NSRange(lowerIngredient.startIndex..<lowerIngredient.endIndex, in: lowerIngredient)
                        if derivativeRegex.firstMatch(in: lowerIngredient, options: [], range: range) != nil {
                            return true
                        }
                    }
                }
            }

            // Fallback: match substring when allergen string is long (reduces false positives)
            if lowerAllergen.count >= 4 && lowerIngredient.contains(lowerAllergen) {
                return true
            }

            return false
        }

        for allergen in preferences.customAllergens {
            for ingredient in ingredients {
                if matchesAllergen(ingredient: ingredient, allergen: allergen) {
                    violations.append(allergen)
                    break // Only add each allergen once
                }
            }
        }

        return violations
    }
    
    nonisolated private func createDetectionEvidence(violations: [String], ingredients: [String], preferences: UserPreferences) -> [AnalysisResult.DetectionEvidence] {
        var evidence: [AnalysisResult.DetectionEvidence] = []

        // Same derivatives mapping as checkCustomAllergens
        let allergenDerivatives: [String: [String]] = [
            "milk": ["whey", "casein", "lactose", "ghee", "cream", "butter", "curds", "custard", "lactalbumin", "lactulose"],
            "dairy": ["whey", "casein", "lactose", "ghee", "cream", "butter", "curds", "custard", "lactalbumin", "lactulose"],
            "egg": ["albumin", "lysozyme", "ovalbumin", "ovomucin", "globulin", "lecithin", "mayonnaise"],
            "eggs": ["albumin", "lysozyme", "ovalbumin", "ovomucin", "globulin", "lecithin", "mayonnaise"],
            "peanut": ["arachis oil", "ground nuts", "peanut oil", "peanut butter"],
            "peanuts": ["arachis oil", "ground nuts", "peanut oil", "peanut butter"],
            "soy": ["soybean", "edamame", "tofu", "tempeh", "miso", "soya", "soy lecithin"],
            "soya": ["soybean", "edamame", "tofu", "tempeh", "miso", "soy", "soy lecithin"],
            "wheat": ["gluten", "flour", "bran", "starch", "bulgur", "couscous", "semolina", "seitan"],
            "tree nut": ["almond", "cashew", "walnut", "pecan", "pistachio", "macadamia", "hazelnut", "brazil nut"],
            "fish": ["anchovy", "bass", "catfish", "cod", "salmon", "tuna", "trout", "halibut", "fish sauce"],
            "shellfish": ["crab", "lobster", "shrimp", "prawn", "crayfish", "scallop", "clam", "oyster", "mussel"]
        ]

        func matchesAllergen(ingredient: String, allergen: String) -> (matches: Bool, isDerivative: Bool, derivativeName: String?) {
            let lowerIngredient = ingredient.lowercased()
            let lowerAllergen = allergen.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)

            // Check exact match first
            let escaped = NSRegularExpression.escapedPattern(for: lowerAllergen)
            let pattern = "\\b(?:" + escaped + ")(?:s|es)?\\b"
            if let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) {
                let range = NSRange(lowerIngredient.startIndex..<lowerIngredient.endIndex, in: lowerIngredient)
                if regex.firstMatch(in: lowerIngredient, options: [], range: range) != nil {
                    return (true, false, nil) // Exact match
                }
            }

            // Check derivatives
            if let derivatives = allergenDerivatives[lowerAllergen] {
                for derivative in derivatives {
                    let derivativeEscaped = NSRegularExpression.escapedPattern(for: derivative)
                    let derivativePattern = "\\b(?:" + derivativeEscaped + ")(?:s|es)?\\b"
                    if let derivativeRegex = try? NSRegularExpression(pattern: derivativePattern, options: [.caseInsensitive]) {
                        let range = NSRange(lowerIngredient.startIndex..<lowerIngredient.endIndex, in: lowerIngredient)
                        if derivativeRegex.firstMatch(in: lowerIngredient, options: [], range: range) != nil {
                            return (true, true, derivative) // Derivative match
                        }
                    }
                }
            }

            // Substring fallback
            if lowerAllergen.count >= 4 && lowerIngredient.contains(lowerAllergen) {
                return (true, false, nil)
            }

            return (false, false, nil)
        }

        for violation in violations {
            // Find ingredients that match this violation
            for ingredient in ingredients {
                let match = matchesAllergen(ingredient: ingredient, allergen: violation)
                if match.matches {
                    let reason: String
                    let confidence: Double

                    if match.isDerivative, let derivative = match.derivativeName {
                        reason = "Contains \(derivative) (derived from \(violation))"
                        confidence = 0.95 // High confidence for known derivatives
                    } else {
                        reason = "Contains \(violation) which you have marked as an allergen"
                        confidence = 1.0 // 100% confidence for exact matches
                    }

                    let evidenceItem = AnalysisResult.DetectionEvidence(
                        ingredient: ingredient,
                        matchedPreference: violation,
                        reason: reason,
                        source: "User Preferences",
                        confidence: confidence,
                        riskLevel: nil,
                        riskExplanation: nil,
                        manufacturingDetails: nil,
                        guidance: nil
                    )
                    evidence.append(evidenceItem)
                }
            }
        }

        return evidence
    }
    
    // MARK: - Alternative Analysis

    /// Lazy-load alternatives from backend when they weren't included in the initial response.
    /// Called by ResultsView when alternatives are empty but alternativesMetadata is available.
    func fetchAlternatives(metadata: AnalysisResult.AlternativesMetadata, preferences: UserPreferences) async -> [AnalysisResult.Alternative] {
        do {
            guard GeminiConfig.isConfigured else { return [] }
            let alts = try await GeminiService.shared.suggestAlternatives(
                productName: metadata.productName,
                category: metadata.category,
                brand: metadata.sourceBrand,
                preferences: preferences
            )
            AppLogger.debug("✅ Gemini suggested \(alts.count) alternatives")
            return alts
        } catch {
            AppLogger.error("❌ Error fetching alternatives (Gemini): \(error.localizedDescription)")
            return []
        }
    }

    func analyzeAlternative(_ alternative: AnalysisResult.Alternative) async throws -> (co2: Double, water: Double) {
        let co2 = alternative.estimatedCO2 ?? AnalysisResult.Alternative.estimateCO2(from: alternative.name)
        let water = alternative.estimatedWater ?? AnalysisResult.Alternative.estimateWater(from: alternative.name)
        return (co2, water)
    }

    /// Enrich alternatives with OpenFoodFacts data (health, environment, ethics scores)
    /// Returns enriched alternatives array with real data where available
    func enrichAlternatives(_ alternatives: [AnalysisResult.Alternative]) async -> [AnalysisResult.Alternative] {
        // Backend-less build: keep AI estimates (and any OpenFoodFacts-enriched values already present).
        return alternatives
    }

    /// Public accessor for pre-resizing from ScannerView (runs on background thread).
    nonisolated func resizeImagePublic(_ image: UIImage, maxSize: CGFloat) -> UIImage {
        return resizeImage(image, maxSize: maxSize)
    }

    nonisolated private func resizeImage(_ image: UIImage, maxSize: CGFloat) -> UIImage {
        let size = image.size
        let maxDimension = max(size.width, size.height)

        // If image is already smaller, return as is
        if maxDimension <= maxSize {
            return image
        }

        // Calculate new size maintaining aspect ratio
        let scale = maxSize / maxDimension
        let newSize = CGSize(width: size.width * scale, height: size.height * scale)

        // Resize image using modern renderer
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1.0
        let renderer = UIGraphicsImageRenderer(size: newSize, format: format)
        return renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: newSize))
        }
    }
    
    // MARK: - Purchase Decision Tracking

    // REMOVED: logAlternativeInteraction - Now handled exclusively by HistoryService.swift (local SQLite)
    // Alternative interactions are tracked locally for better offline support and data consistency
    // If backend analytics are needed, they should query the local database during sync operations

    func getUserImpact(userId: String) async throws -> UserImpactData {
        _ = userId
        let stats = ImpactCalculator.shared.calculateImpactStats()
        return UserImpactData(
            totalScans: stats.totalScans,
            totalCO2Impact: stats.yourCO2Footprint,
            totalWaterImpact: stats.yourWaterFootprint,
            co2Saved: stats.totalCO2Saved,
            co2Generated: stats.yourCO2Footprint,
            waterSaved: stats.totalWaterSaved,
            waterGenerated: stats.yourWaterFootprint,
            decisions: UserImpactData.DecisionCounts(
                bought: stats.productsPurchased,
                avoided: stats.productsAvoided,
                bought_alternative: stats.alternativesChosen
            )
        )
    }
    
    // MARK: - Plate Check (Gemini, on-device API key)

    func analyzePlate(image: UIImage, preferences: UserPreferences, restaurantName: String, dishName: String, cuisineType: String) async -> [String: Any]? {
        let imageData: Data? = await Task.detached(priority: .userInitiated) {
            let resized = self.resizeImage(image, maxSize: 800)
            return resized.jpegData(compressionQuality: 0.8)
        }.value
        guard let imageData = imageData else {
            await MainActor.run {
                self.errorMessage = "Could not process image"
            }
            return nil
        }
        return await analyzePlateStreaming(
            imageData: imageData,
            preferences: preferences,
            restaurantName: restaurantName,
            dishName: dishName,
            cuisineType: cuisineType
        )
    }

    func analyzePlateStreaming(image: UIImage, preferences: UserPreferences, restaurantName: String, dishName: String, cuisineType: String) async -> [String: Any]? {
        let imageData: Data? = await Task.detached(priority: .userInitiated) {
            let resized = self.resizeImage(image, maxSize: 800)
            return resized.jpegData(compressionQuality: 0.8)
        }.value
        guard let imageData = imageData else {
            await MainActor.run {
                self.isAnalyzing = false
                self.errorMessage = "Could not process image"
            }
            return nil
        }
        return await analyzePlateStreaming(
            imageData: imageData,
            preferences: preferences,
            restaurantName: restaurantName,
            dishName: dishName,
            cuisineType: cuisineType
        )
    }

    /// Plate Check via Google Gemini API. Publishes full detail to `plateDetailSubject`.
    func analyzePlateStreaming(imageData: Data, preferences: UserPreferences, restaurantName: String, dishName: String, cuisineType: String) async -> [String: Any]? {
        guard await checkNetworkConnection() else {
            await MainActor.run {
                self.isAnalyzing = false
                self.analysisProgress = 0.0
            }
            return nil
        }

        guard GeminiConfig.isConfigured else {
            await MainActor.run {
                self.isAnalyzing = false
                self.analysisProgress = 0.0
                self.errorMessage = GeminiConfig.missingKeyMessage
            }
            return nil
        }

        plateStreamGeneration += 1
        let myGeneration = plateStreamGeneration
        NetworkService.plateDetailSubject.send(nil)

        await MainActor.run {
            self.isAnalyzing = true
            self.errorMessage = nil
            self.analysisProgress = 0.2
        }

        do {
            AppLogger.debug("🤖 Plate Check: Gemini analysis (\(imageData.count / 1024)KB)")
            let json = try await GeminiService.shared.analyzePlate(
                imageData: imageData,
                preferences: preferences,
                restaurantName: restaurantName,
                dishName: dishName,
                cuisineType: cuisineType
            )

            await MainActor.run { self.analysisProgress = 0.85 }

            if myGeneration == self.plateStreamGeneration {
                var detail = PlateAnalysis(from: json)
                detail.detailLoaded = true
                NetworkService.plateDetailSubject.send(detail)
            }

            await MainActor.run {
                self.isAnalyzing = false
                self.analysisProgress = 1.0
            }
            AppLogger.debug("✅ Gemini plate analysis: \(json["dishName"] as? String ?? "?")")
            return json
        } catch {
            AppLogger.error("❌ Gemini plate analysis: \(error.localizedDescription)")
            await MainActor.run {
                self.isAnalyzing = false
                self.analysisProgress = 0.0
                self.errorMessage = error.localizedDescription
            }
            return nil
        }
    }

    // MARK: - Purchase Decision & Impact Tracking

    func submitPurchaseDecision(
        productId: String,
        productName: String,
        decision: String,
        co2Impact: Double,
        waterImpact: Double
    ) async {
        guard let accessToken = AuthenticationService.shared.authToken, !accessToken.isEmpty else { return }
        guard let userId = AuthenticationService.shared.currentUserId, !userId.isEmpty else { return }

        let payload: [String: Any] = [
            "id": productId,
            "user_id": userId,
            "product_name": productName,
            "decision": decision,
            "metadata": [
                "co2_emissions": co2Impact,
                "water_usage": waterImpact
            ],
            "created_at": ISO8601DateFormatter().string(from: Date())
        ]

        do {
            try await SupabaseAPI.shared.upsertRow(accessToken: accessToken, table: "scan_history", payload: payload, onConflict: "id")
        } catch {
            AppLogger.debug("⚠️ Supabase purchase decision sync failed: \(error.localizedDescription)")
        }
    }

    
    // MARK: - GDPR Data Deletion
    
    func deleteUserData(userId: String) async throws {
        // No backend server. Deleting Supabase rows requires privileged service role; the iOS client uses anon key.
        // Local deletion is handled in AuthenticationService.deleteAccount().
        AppLogger.debug("🧹 deleteUserData: no-op (client has no admin rights). userId=\(userId)")
    }

    // MARK: - Log Alternative Interaction
    
    func logAlternativeInteraction(alternativeName: String, alternativeBrand: String?, originalProduct: String, action: String) async {
        guard let accessToken = AuthenticationService.shared.authToken, !accessToken.isEmpty else { return }
        let userId = AuthenticationService.shared.currentUserId
        let payload: [String: Any] = [
            "user_id": userId as Any,
            "alternative_name": alternativeName,
            "alternative_brand": alternativeBrand as Any,
            "original_product": originalProduct,
            "action": action,
            "created_at": ISO8601DateFormatter().string(from: Date())
        ]
        do {
            try await SupabaseAPI.shared.insertRow(accessToken: accessToken, table: "alternative_interactions", payload: payload)
        } catch {
            AppLogger.debug("Failed to log alternative interaction: \(error.localizedDescription)")
        }
    }

    // MARK: - Cloud Sync

    /// Push user preferences to backend
    func syncPreferencesToBackend(_ prefs: UserPreferences) async {
        guard isConnected else { return }
        guard let accessToken = AuthenticationService.shared.authToken, !accessToken.isEmpty else { return }
        guard let userId = AuthenticationService.shared.currentUserId, !userId.isEmpty else { return }

        let payload: [String: Any] = [
            "user_id": userId,
            "preferences": prefs.toJSON(),
            "updated_at": ISO8601DateFormatter().string(from: Date())
        ]
        do {
            try await SupabaseAPI.shared.upsertRow(accessToken: accessToken, table: "user_preferences", payload: payload, onConflict: "user_id")
        } catch {
            AppLogger.debug("⚠️ Preferences sync failed (will retry on next save): \(error.localizedDescription)")
        }
    }

    /// Pull user preferences from backend (for reinstall recovery)
    func pullPreferencesFromBackend() async -> UserPreferences? {
        guard let userId = AuthenticationService.shared.currentUserId, !userId.isEmpty else { return nil }
        let accessToken = AuthenticationService.shared.authToken

        do {
            let rows = try await SupabaseAPI.shared.fetchRows(
                accessToken: accessToken,
                table: "user_preferences",
                queryItems: [
                    URLQueryItem(name: "select", value: "preferences"),
                    URLQueryItem(name: "user_id", value: "eq.\(userId)"),
                    URLQueryItem(name: "limit", value: "1")
                ]
            )
            guard let prefsDict = rows.first?["preferences"] as? [String: Any] else { return nil }

            var prefs = UserPreferences()
            if let diets = prefsDict["selectedDiets"] as? [String] {
                prefs.selectedDiets = Set(diets)
            }
            if let allergens = prefsDict["selectedAllergens"] as? [String] {
                prefs.selectedAllergens = Set(allergens)
            }
            if let customDiets = prefsDict["customDiets"] as? [String] {
                prefs.customDiets = customDiets
            }
            if let customAllergens = prefsDict["customAllergens"] as? [String] {
                prefs.customAllergens = customAllergens
            }
            if let mayContain = prefsDict["mayContainSafe"] as? Bool {
                prefs.mayContainSafe = mayContain
            }
            if let avoidGMO = prefsDict["avoidGMO"] as? Bool {
                prefs.avoidGMO = avoidGMO
            }
            if let health = prefsDict["healthPriority"] as? Double {
                prefs.healthPriority = health
            }
            if let env = prefsDict["environmentPriority"] as? Double {
                prefs.environmentPriority = env
            }
            if let ethics = prefsDict["ethicsPriority"] as? Double {
                prefs.ethicsPriority = ethics
            }

            AppLogger.debug("✅ Pulled preferences from Supabase")
            return prefs
        } catch {
            AppLogger.debug("⚠️ Failed to pull preferences from Supabase: \(error.localizedDescription)")
            return nil
        }
    }

    /// Pull scan history from backend (for reinstall recovery)
    func pullHistoryFromBackend(limit: Int = 100) async -> [[String: Any]]? {
        guard let userId = AuthenticationService.shared.currentUserId, !userId.isEmpty else { return nil }
        let accessToken = AuthenticationService.shared.authToken

        do {
            let rows = try await SupabaseAPI.shared.fetchRows(
                accessToken: accessToken,
                table: "scan_history",
                queryItems: [
                    URLQueryItem(name: "select", value: "id,barcode,product_name,created_at,metadata"),
                    URLQueryItem(name: "user_id", value: "eq.\(userId)"),
                    URLQueryItem(name: "order", value: "created_at.desc"),
                    URLQueryItem(name: "limit", value: "\(limit)")
                ]
            )

            AppLogger.debug("✅ Pulled \(rows.count) history entries from Supabase")
            return rows.map { row in
                var out: [String: Any] = [:]
                out["id"] = row["id"]
                out["barcode"] = row["barcode"]
                out["product_name"] = row["product_name"]

                if let createdAt = row["created_at"] as? String,
                   let date = ISO8601DateFormatter().date(from: createdAt) {
                    out["scanned_at"] = date.timeIntervalSince1970
                }

                let meta = row["metadata"] as? [String: Any] ?? [:]
                out["health_score"] = meta["health_score"]
                out["co2_emissions"] = meta["co2_emissions"]
                out["water_usage"] = meta["water_usage"]
                out["animal_impact"] = meta["animal_impact"]
                out["violations"] = meta["violations"]
                return out
            }
        } catch {
            AppLogger.debug("⚠️ Failed to pull history from Supabase: \(error.localizedDescription)")
            return nil
        }
    }

    /// Pull user stats from backend
    func pullStatsFromBackend() async -> (co2Saved: Double, waterSaved: Double, totalScans: Int)? {
        guard let userId = AuthenticationService.shared.currentUserId, !userId.isEmpty else { return nil }
        let accessToken = AuthenticationService.shared.authToken

        do {
            let rows = try await SupabaseAPI.shared.fetchRows(
                accessToken: accessToken,
                table: "scan_history",
                queryItems: [
                    URLQueryItem(name: "select", value: "metadata,decision"),
                    URLQueryItem(name: "user_id", value: "eq.\(userId)")
                ]
            )

            var co2Saved: Double = 0
            var waterSaved: Double = 0
            var totalScans: Int = 0

            for row in rows {
                totalScans += 1
                let decision = (row["decision"] as? String) ?? ""
                if decision == "avoided" || decision == "alternative" {
                    let meta = row["metadata"] as? [String: Any] ?? [:]
                    co2Saved += (meta["co2_emissions"] as? Double) ?? 0
                    waterSaved += (meta["water_usage"] as? Double) ?? 0
                }
            }

            AppLogger.debug("✅ Pulled stats from Supabase: \(totalScans) scans")
            return (co2Saved, waterSaved, totalScans)
        } catch {
            AppLogger.debug("⚠️ Failed to pull stats from Supabase: \(error.localizedDescription)")
            return nil
        }
    }

    /// Best-effort cloud backup of a full ScanHistory row.
    func syncScanToSupabase(_ scan: ScanHistory) async {
        guard let accessToken = AuthenticationService.shared.authToken, !accessToken.isEmpty else { return }
        guard let userId = AuthenticationService.shared.currentUserId, !userId.isEmpty else { return }

        let meta: [String: Any] = [
            "is_safe": scan.isSafe,
            "violations": scan.violations,
            "health_score": scan.healthScore,
            "co2_emissions": scan.co2Emissions,
            "water_usage": scan.waterUsage,
            "animal_impact": scan.animalImpact,
            "purchase_decision": scan.purchaseDecision.rawValue,
            "alternative_name": scan.alternativeName as Any,
            "alternative_co2": scan.alternativeCO2 as Any,
            "alternative_water": scan.alternativeWater as Any
        ]

        let payload: [String: Any] = [
            "id": scan.id.uuidString,
            "user_id": userId,
            "barcode": scan.barcode as Any,
            "product_name": scan.productName,
            "decision": scan.purchaseDecision.rawValue,
            "source": scan.sourceType,
            "metadata": meta,
            "created_at": ISO8601DateFormatter().string(from: scan.timestamp)
        ]

        do {
            try await SupabaseAPI.shared.upsertRow(accessToken: accessToken, table: "scan_history", payload: payload, onConflict: "id")
        } catch {
            AppLogger.debug("⚠️ Supabase scan sync failed: \(error.localizedDescription)")
        }
    }

}

// MARK: - Helper Types

struct AnyCodable: Codable {
    let value: Any
    
    init(_ value: Any) {
        self.value = value
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let string = try? container.decode(String.self) {
            value = string
        } else if let int = try? container.decode(Int.self) {
            value = int
        } else if let double = try? container.decode(Double.self) {
            value = double
        } else if let bool = try? container.decode(Bool.self) {
            value = bool
        } else {
            value = "unknown"
        }
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        if let string = value as? String {
            try container.encode(string)
        } else if let int = value as? Int {
            try container.encode(int)
        } else if let double = value as? Double {
            try container.encode(double)
        } else if let bool = value as? Bool {
            try container.encode(bool)
        }
    }
}

struct UserImpactData: Codable {
    let totalScans: Int
    let totalCO2Impact: Double
    let totalWaterImpact: Double
    let co2Saved: Double
    let co2Generated: Double
    let waterSaved: Double
    let waterGenerated: Double
    let decisions: DecisionCounts
    
    struct DecisionCounts: Codable {
        let bought: Int
        let avoided: Int
        let bought_alternative: Int
    }
}
