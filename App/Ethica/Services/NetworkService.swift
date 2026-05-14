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
        // Fetch fresh token from Firebase (automatically refreshes if expired)
        await AuthenticationService.shared.fetchAuthToken()

        if let token = AuthenticationService.shared.authToken {
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
        guard let url = URL(string: "\(AppConfig.backendURL)/quick-allergen-check") else {
            AppLogger.error("❌ Invalid URL for quick-allergen-check")
            return nil
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 12.0  // Allow 10s Gemini + network overhead
        await addAuthToken(to: &request)

        var payload: [String: Any] = [
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
        if let barcode = barcode { payload["barcode"] = barcode }
        if let name = productName { payload["productName"] = name }
        if let offData = openfoodfactsData { payload["openfoodfactsData"] = offData }

        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: payload)
            AppLogger.debug("🚀 Sending quick-allergen-check for \(ingredients.count) ingredients")

            let (data, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
                AppLogger.warning("⚠️ quick-allergen-check returned non-200")
                return nil
            }

            let result = try JSONDecoder().decode(QuickSafetyResult.self, from: data)
            AppLogger.debug("✅ quick-allergen-check: isSafe=\(result.isSafe), violations=\(result.violations.count)")
            return result
        } catch {
            AppLogger.warning("⚠️ quick-allergen-check failed: \(error.localizedDescription)")
            return nil
        }
    }

    // MARK: - Quick Safety Check from Ingredient Photo

    /// OCR ingredient photo on backend (Gemini Flash) then run safety checks. Returns in ~3-5s.
    func quickSafetyCheckFromPhoto(
        image: UIImage,
        preferences: UserPreferences
    ) async -> QuickSafetyResult? {
        guard isConnected else {
            AppLogger.debug("⚡ Skipping quick-safety-check: offline")
            return nil
        }
        guard let url = URL(string: "\(AppConfig.backendURL)/quick-safety-check") else {
            AppLogger.error("❌ Invalid URL for quick-safety-check")
            return nil
        }

        // Resize and compress
        let resized = resizeImage(image, maxSize: 2048)
        guard let imageData = resized.jpegData(compressionQuality: 0.7) else {
            AppLogger.error("❌ Failed to compress ingredient photo")
            return nil
        }
        let base64Image = imageData.base64EncodedString()

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 15.0  // Gemini OCR ~3s + safety checks + network
        await addAuthToken(to: &request)

        let payload: [String: Any] = [
            "imageBase64": base64Image,
            "userPreferences": [
                "selectedAllergens": Array(preferences.selectedAllergens),
                "customAllergens": preferences.customAllergens,
                "selectedDiets": Array(preferences.selectedDiets),
                "customDiets": preferences.customDiets,
                "avoidGMO": preferences.avoidGMO,
                "mayContainSafe": preferences.mayContainSafe
            ]
        ]

        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: payload)
            AppLogger.debug("🚀 Sending quick-safety-check with ingredient photo (\(imageData.count / 1024)KB)")

            let (data, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
                let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0
                AppLogger.warning("⚠️ quick-safety-check returned \(statusCode)")
                return nil
            }

            let result = try JSONDecoder().decode(QuickSafetyResult.self, from: data)
            AppLogger.debug("✅ quick-safety-check: isSafe=\(result.isSafe), violations=\(result.violations.count)")
            return result
        } catch {
            AppLogger.warning("⚠️ quick-safety-check failed: \(error.localizedDescription)")
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

        let base64Image = imageData.base64EncodedString()

        guard let url = URL(string: "\(AppConfig.backendURL)/identify-product") else {
            AppLogger.debug("Invalid URL")
            return nil
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        await addAuthToken(to: &request)
        request.timeoutInterval = 15  // Identification-only is fast (3-5s)

        let payload: [String: Any] = [
            "imageBase64": base64Image,
            "userPreferences": [
                "selectedAllergens": Array(preferences.selectedAllergens),
                "customAllergens": preferences.customAllergens,
                "selectedDiets": Array(preferences.selectedDiets),
                "customDiets": preferences.customDiets,
                "avoidGMO": preferences.avoidGMO
            ]
        ]

        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: payload)

            AppLogger.debug("🔍 Identifying product from visual image...")
            await MainActor.run {
                self.analysisProgress = 0.3
            }

            let (data, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse else {
                throw NSError(domain: "Invalid response", code: -1)
            }

            AppLogger.debug("📡 Visual identification response status: \(httpResponse.statusCode)")

            if httpResponse.statusCode == 200 {
                // Parse identification-only response (snake_case from backend)
                guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let productName = json["product_name"] as? String else {
                    throw NSError(domain: "Invalid identification response", code: -1)
                }

                let identification = VisualIdentification(
                    productName: productName,
                    confidence: json["confidence"] as? Double ?? 0,
                    estimatedIngredients: json["ingredients"] as? [String] ?? [],
                    ingredientConfidence: json["ingredient_confidence"] as? Double ?? 0,
                    ingredientSource: json["ingredient_source"] as? String ?? "unknown",
                    productCategory: json["product_category"] as? String ?? ""
                )

                AppLogger.debug("✅ Visual identification: \(identification.productName) (\(identification.confidence)%)")

                await MainActor.run {
                    self.analysisProgress = 0.5
                }

                return identification
            } else {
                // Parse backend error
                var backendMessage: String?
                if let errorJSON = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let msg = errorJSON["error"] as? String {
                    backendMessage = msg
                }

                await MainActor.run {
                    self.isAnalyzing = false
                    self.analysisProgress = 0.0
                    if let msg = backendMessage, msg.contains("Could not identify") || msg.contains("AI says") {
                        self.errorMessage = msg
                    } else if httpResponse.statusCode == 429 {
                        self.errorMessage = "Too many scans. Please wait a moment and try again."
                    } else if httpResponse.statusCode >= 500 {
                        self.errorMessage = "Server temporarily unavailable. Please try again in a moment."
                    } else {
                        self.errorMessage = "Could not identify product. Try:\n• Getting closer to product\n• Ensuring brand name is visible\n• Better lighting\n• Clearer focus"
                    }
                }
                return nil
            }
        } catch {
            AppLogger.error("❌ Network error identifying product: \(error)")
            await MainActor.run {
                self.isAnalyzing = false
                self.analysisProgress = 0.0
                self.errorMessage = "Failed to identify product: \(error.localizedDescription)"
            }
            return nil
        }
    }
    
    private func analyzeRestaurantMenu(base64Image: String, preferences: UserPreferences) async -> AnalysisResult? {
        guard let url = URL(string: "\(AppConfig.backendURL)/extract-menu-items") else {
            AppLogger.debug("Invalid URL")
            return nil
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        await addAuthToken(to: &request)
        request.timeoutInterval = 30
        
        let payload: [String: Any] = [
            "imageBase64": base64Image,
            "isRestaurantMenu": true,
            "user_preferences": [
                "avoidIngredients": Array(preferences.selectedAllergens) + preferences.customAllergens,
                "dietaryGoal": Array(preferences.selectedDiets).joined(separator: ", "),
                "avoidGMO": preferences.avoidGMO
            ]
        ]
        
        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: payload)
            
            AppLogger.debug("🔄 Analyzing restaurant menu...")
            await MainActor.run {
                self.analysisProgress = 0.60 // 60% - Processing menu
            }

            // Use retry logic for reliability
            let (data, httpResponse) = try await performWithRetry(maxAttempts: 3) {
                let (data, response) = try await URLSession.shared.data(for: request)
                await MainActor.run {
                    self.analysisProgress = 0.80 // 80% - Menu analyzed
                }
                guard let httpResponse = response as? HTTPURLResponse else {
                    throw NSError(domain: "Invalid response", code: -1)
                }
                return (data, httpResponse)
            }
            
            AppLogger.debug("📡 Restaurant menu response status: \(httpResponse.statusCode)")
            
            if httpResponse.statusCode == 200 {
                // Parse the menu analysis response
                let menuResponse = try JSONDecoder().decode(MenuAnalysisResponse.self, from: data)
                
                guard let menuAnalysis = menuResponse.menuAnalysis, !menuAnalysis.isEmpty else {
                    await MainActor.run {
                        self.isAnalyzing = false
                        self.analysisProgress = 0.0
                        self.errorMessage = "No dishes found in menu. Please:\n• Use a clear photo of the menu\n• Ensure good lighting\n• Include dish names and descriptions"
                    }
                    return nil
                }
                
                AppLogger.debug("✅ Found \(menuAnalysis.count) dishes in menu")
                
                // Convert to MenuDish format
                let dishes = menuAnalysis.map { dish in
                    AnalysisResult.MenuDish(
                        dish: dish.dish ?? "Unknown Dish",
                        ingredients: dish.ingredients ?? [],
                        safe: dish.safe ?? false,
                        warnings: dish.warnings ?? [],
                        estimatedCO2: dish.estimatedCO2
                    )
                }
                
                // Count safe vs unsafe dishes
                let safeDishes = dishes.filter { $0.safe }.count
                let unsafeDishes = dishes.count - safeDishes
                
                // Create a summary result
                let result = AnalysisResult(
                    productName: "Restaurant Menu Analysis",
                    overallScore: Double(safeDishes) / Double(dishes.count) * 10.0,
                    isSafe: safeDishes > 0,
                    confidence: 0.7, // Lower confidence for inferred ingredients
                    confidenceFactors: ["Menu analysis based on typical ingredients"],
                    violations: unsafeDishes > 0 ? ["\(unsafeDishes) dishes may contain restricted ingredients"] : [],
                    warnings: ["⚠️ Always verify ingredients with restaurant staff"],
                    cautionWarnings: ["Ingredient analysis is based on typical recipes"],
                    ingredients: menuResponse.ingredients ?? [],
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
                    isRestaurantMenu: true,
                    menuDishes: dishes
                )
                
                await MainActor.run {
                    self.isAnalyzing = false
                    self.analysisProgress = 1.0
                }
                
                return result
            } else {
                let errorText = String(data: data, encoding: .utf8) ?? "Unknown error"
                AppLogger.error("❌ Restaurant menu analysis error: \(errorText)")
                throw NSError(domain: errorText, code: httpResponse.statusCode)
            }
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
    
    private func extractIngredientsOrMatchProduct(base64Image: String, preferences: UserPreferences, isRestaurantMenu: Bool = false) async -> ExtractResult {
        guard isConnected else {
            AppLogger.debug("⚡ Skipping \(isRestaurantMenu ? "menu" : "ingredient") extraction: offline")
            return .error
        }
        let endpoint = isRestaurantMenu ? "/extract-menu-items" : "/extract-ingredients"
        guard let url = URL(string: "\(AppConfig.backendURL)\(endpoint)") else {
            AppLogger.debug("Invalid URL")
            return .error
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        await addAuthToken(to: &request)
        request.timeoutInterval = 30
        
        // Build payload - include user preferences for restaurant mode
        var payload: [String: Any] = [
            "imageBase64": base64Image,
            "isRestaurantMenu": isRestaurantMenu
        ]
        
        // Add user preferences for restaurant menu analysis
        if isRestaurantMenu {
            payload["user_preferences"] = [
                "avoidIngredients": Array(preferences.selectedAllergens) + preferences.customAllergens,
                "dietaryGoal": Array(preferences.selectedDiets).joined(separator: ", "),
                "avoidGMO": preferences.avoidGMO
            ]
        }
        
        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: payload)
            
            AppLogger.debug("🔄 Extracting ingredients from image...")
            await MainActor.run {
                self.analysisProgress = 0.55 // 55% - Sending to Vision API
            }

            // Use retry logic for reliability
            let (data, httpResponse): (Data, HTTPURLResponse)
            do {
                (data, httpResponse) = try await performWithRetry(maxAttempts: 3) {
                    let (data, response) = try await URLSession.shared.data(for: request)
                    await MainActor.run {
                        self.analysisProgress = 0.65 // 65% - Processing OCR response
                    }
                    guard let httpResponse = response as? HTTPURLResponse else {
                        throw NSError(domain: "Invalid response", code: -1)
                    }
                    return (data, httpResponse)
                }
            } catch {
                return .error
            }
            
            AppLogger.debug("📡 Extract response status: \(httpResponse.statusCode)")
            
            if httpResponse.statusCode == 200 {
                let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
                let ingredients = json?["ingredients"] as? [String] ?? []
                let dataSource = json?["dataSource"] as? String ?? "ocr_only"
                let extractedProductName = json?["productName"] as? String
                let extractedOcrText = json?["ocrText"] as? String
                let allergenContains = json?["allergenContains"] as? [String] ?? []
                let allergenMayContain = json?["allergenMayContain"] as? [String] ?? []
                let ocrConfidenceWarning = json?["ocrConfidenceWarning"] as? String
                let gmoDeclaration = json?["gmoDeclaration"] as? String
                
                // NEW: Check if we found a matching product in OpenFoodFacts
                if let matchedProduct = json?["matchedProduct"] as? [String: Any],
                   dataSource == "openfoodfacts" {
                    AppLogger.debug("✅ OCR scan matched to OpenFoodFacts product!")
                    
                    // Use ProductDatabaseService to handle the matched product
                    // This gives us the same accuracy as barcode scans
                    let productName = matchedProduct["product_name"] as? String ?? "Unknown Product"
                    let barcode = matchedProduct["code"] as? String ?? ""
                    let matchConfidence = matchedProduct["match_confidence"] as? Double ?? 0.0
                    
                    AppLogger.debug("   Product: \(productName)")
                    AppLogger.debug("   Barcode: \(barcode)")
                    AppLogger.debug("   Match confidence: \(matchConfidence)%")
                    
                    // Look up the product using its barcode for full accuracy
                    if !barcode.isEmpty {
                        AppLogger.debug("🔄 Looking up matched product by barcode for full data...")
                        if let fullProduct = await productDatabaseService.lookupBarcode(barcode, preferences: preferences) {
                            AppLogger.debug("✅ Retrieved full product data from OpenFoodFacts")
                            
                            // Save to history
                            let scanHistory = ScanHistory(from: fullProduct)
                            AppLogger.debug("💾 Saving OCR->OpenFoodFacts matched scan to history")
                            HistoryService.shared.saveScan(scanHistory)
                            
                            await MainActor.run {
                                self.isAnalyzing = false
                                self.analysisProgress = 1.0
                            }
                            
                            return .matchedProduct(fullProduct)
                        }
                    }
                }
                
                if ingredients.isEmpty {
                    await MainActor.run {
                        self.isAnalyzing = false
                    self.analysisProgress = 0.0
                        self.errorMessage = "No text found in image. Please:\n• Use a clear photo of the ingredient label\n• Ensure good lighting\n• Hold camera steady\n• Try a different angle"
                    }
                    return .error
                }
                
                return .ingredients(ingredients, productName: extractedProductName, ocrText: extractedOcrText, allergenContains: allergenContains, allergenMayContain: allergenMayContain, ocrConfidenceWarning: ocrConfidenceWarning, gmoDeclaration: gmoDeclaration)
            } else {
                let errorText = String(data: data, encoding: .utf8) ?? "Unknown error"
                AppLogger.error("❌ Extract error: \(errorText)")
                throw NSError(domain: errorText, code: httpResponse.statusCode)
            }
        } catch {
            AppLogger.error("❌ Network error extracting ingredients: \(error)")
            
            // Provide helpful error messages
            var userMessage = "Failed to extract ingredients"
            if let urlError = error as? URLError {
                switch urlError.code {
                case .notConnectedToInternet:
                    userMessage = "No internet connection. Please check your network."
                case .cannotFindHost, .cannotConnectToHost:
                    userMessage = "Cannot reach backend server (\(AppConfig.backendURL)). Please try again later."
                case .timedOut:
                    userMessage = "Request timed out. Please check your connection and try again."
                case .badServerResponse:
                    userMessage = "Server error. Please try again."
                default:
                    userMessage = "Network error: \(error.localizedDescription)"
                }
            } else {
                userMessage = error.localizedDescription
            }
            
            await MainActor.run {
                self.isAnalyzing = false
                self.errorMessage = userMessage
            }
            return .error
        }
    }
    
    private func analyzeIngredients(_ ingredients: [String], preferences: UserPreferences, ingredientsList: [String], productName: String? = nil, ingredientsText: String? = nil, allergenContains: [String] = [], allergenMayContain: [String] = [], gmoDeclaration: String? = nil) async -> AnalysisResult? {
        guard let url = URL(string: "\(AppConfig.backendURL)/comprehensive-analysis") else {
            AppLogger.debug("Invalid URL")
            return nil
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        await addAuthToken(to: &request)
        request.timeoutInterval = 60 // Increased for complex AI analysis with many ingredients
        
        // Get dietary preferences
        let allDiets = Array(preferences.selectedDiets)
        
        var payload: [String: Any] = [
            "ingredients": ingredients,
            "userPreferences": preferences.toJSON(),
            "dietaryPreferences": allDiets.isEmpty ? ["none"] : allDiets
        ]
        // Forward OCR context so backend can try OpenFoodFacts enrichment
        if let name = productName {
            payload["productName"] = name
        }
        if let text = ingredientsText {
            payload["ingredientsText"] = text
        }
        // Forward label allergen declarations from OCR extraction
        if !allergenContains.isEmpty {
            payload["allergenContains"] = allergenContains
        }
        if !allergenMayContain.isEmpty {
            payload["allergenMayContain"] = allergenMayContain
        }
        // Forward GMO label declaration from OCR extraction
        if let gmo = gmoDeclaration {
            payload["gmoDeclaration"] = gmo
        }
        
        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: payload)
            AppLogger.debug("🔄 Sending request to: \(AppConfig.backendURL)/comprehensive-analysis")
            await MainActor.run {
                self.analysisProgress = 0.8 // 80% - Sending AI analysis request
            }

            // Use retry logic for reliability (most critical endpoint)
            let (data, httpResponse) = try await performWithRetry(maxAttempts: 3) {
                let (data, response) = try await URLSession.shared.data(for: request)
                await MainActor.run {
                    self.analysisProgress = 0.9 // 90% - Processing AI analysis
                }
                guard let httpResponse = response as? HTTPURLResponse else {
                    throw NSError(domain: "Invalid response", code: -1)
                }
                return (data, httpResponse)
            }
            AppLogger.debug("📡 Response status: \(httpResponse.statusCode)")
            if let jsonString = String(data: data, encoding: .utf8) {
                AppLogger.debug("📦 Raw JSON response:")
                AppLogger.debug(jsonString)
            }
            if httpResponse.statusCode == 200 {
                do {
                    let backendResponse = try JSONDecoder().decode(BackendResponse.self, from: data)
                    AppLogger.debug("✅ Successfully decoded response")
                    var result = await convertToAnalysisResult(backendResponse, ingredients: ingredientsList, preferences: preferences)
                    // Client-side Jain validation on OCR path results
                    if let validated = applyJainValidation(result, preferences: preferences) {
                        result = validated
                    }
                    await MainActor.run {
                        self.isAnalyzing = false
                        self.analysisProgress = 1.0
                    }
                    return result
                } catch let decodingError {
                    AppLogger.error("❌ Decoding error: \(decodingError)")
                    if let decodingError = decodingError as? DecodingError {
                        switch decodingError {
                        case .keyNotFound(let key, let context):
                            AppLogger.error("❌ Missing key: \(key.stringValue)")
                            AppLogger.error("❌ Context: \(context.debugDescription)")
                        case .typeMismatch(let type, let context):
                            AppLogger.error("❌ Type mismatch for type: \(type)")
                            AppLogger.error("❌ Context: \(context.debugDescription)")
                        case .valueNotFound(let type, let context):
                            AppLogger.error("❌ Value not found for type: \(type)")
                            AppLogger.error("❌ Context: \(context.debugDescription)")
                        case .dataCorrupted(let context):
                            AppLogger.error("❌ Data corrupted: \(context.debugDescription)")
                        @unknown default:
                            AppLogger.error("❌ Unknown decoding error")
                        }
                    }
                    // Show decoding error in UI for easier debugging
                    await MainActor.run {
                        self.errorMessage = "Decoding error: \(decodingError.localizedDescription)\nCheck Xcode console for details."
                        self.isAnalyzing = false
                    self.analysisProgress = 0.0
                    }
                    return nil
                }
            } else {
                let errorText = String(data: data, encoding: .utf8) ?? "Unknown error"
                AppLogger.error("❌ Server error: \(errorText)")
                var userMessage = "Server error"
                if errorText.contains("No ingredients") {
                    userMessage = "No text found in image. Please:\n• Use a clear photo of the ingredient label\n• Ensure good lighting\n• Hold camera steady\n• Try a different angle"
                } else {
                    userMessage = errorText
                }
                await MainActor.run {
                    self.errorMessage = userMessage
                    self.isAnalyzing = false
                    self.analysisProgress = 0.0
                }
                return nil
            }
        } catch {
            AppLogger.error("❌ Network error: \(error)")
            await MainActor.run {
                self.isAnalyzing = false
                self.errorMessage = "Error: \(error.localizedDescription)"
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
        guard let url = URL(string: "\(AppConfig.backendURL)/fetch-alternatives") else {
            AppLogger.debug("Invalid URL for fetch-alternatives")
            return []
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        await addAuthToken(to: &request)
        request.timeoutInterval = 25

        let payload: [String: Any] = [
            "productName": metadata.productName,
            "category": metadata.category,
            "categoriesTags": metadata.categoriesTags,
            "sourceBarcode": metadata.sourceBarcode ?? "",
            "sourceBrand": metadata.sourceBrand ?? "",
            "diets": Array(preferences.selectedDiets) + preferences.customDiets,
            "allergens": Array(preferences.selectedAllergens) + preferences.customAllergens,
            "userPreferences": preferences.toJSON()
        ]

        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: payload)
            let (data, response) = try await URLSession.shared.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse,
                  httpResponse.statusCode == 200 else {
                AppLogger.warning("⚠️ fetch-alternatives returned non-200")
                return []
            }

            struct AlternativesResponse: Codable {
                let alternatives: [AnalysisResult.Alternative]
            }

            let result = try JSONDecoder().decode(AlternativesResponse.self, from: data)
            AppLogger.debug("✅ Lazy-loaded \(result.alternatives.count) alternatives")
            return result.alternatives
        } catch {
            AppLogger.error("❌ Error fetching alternatives: \(error.localizedDescription)")
            return []
        }
    }

    func analyzeAlternative(_ alternative: AnalysisResult.Alternative) async throws -> (co2: Double, water: Double) {
        AppLogger.debug("🔬 Analyzing alternative: \(alternative.name)")

        guard let url = URL(string: "\(AppConfig.backendURL)/analyze-alternative") else {
            throw NSError(domain: "NetworkService", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid URL"])
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        await addAuthToken(to: &request)
        request.timeoutInterval = 15
        
        let body: [String: Any] = [
            "name": alternative.name,
            "brand": alternative.brand ?? ""
        ]
        
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw NSError(domain: "NetworkService", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid response"])
        }
        
        struct AlternativeAnalysis: Codable {
            let estimatedCO2: Double
            let estimatedWater: Double
            let confidence: Int?
            let reasoning: String?
        }
        
        let result = try JSONDecoder().decode(AlternativeAnalysis.self, from: data)
        AppLogger.debug("✅ Backend analysis: CO2=\(result.estimatedCO2)kg, Water=\(result.estimatedWater)L, Confidence=\(result.confidence ?? 0)%")

        return (result.estimatedCO2, result.estimatedWater)
    }

    /// Enrich alternatives with OpenFoodFacts data (health, environment, ethics scores)
    /// Returns enriched alternatives array with real data where available
    func enrichAlternatives(_ alternatives: [AnalysisResult.Alternative]) async -> [AnalysisResult.Alternative] {
        guard !alternatives.isEmpty else { return [] }

        AppLogger.debug("🔍 Enriching \(alternatives.count) alternatives with OpenFoodFacts data...")

        guard let url = URL(string: "\(AppConfig.backendURL)/enrich-alternatives") else {
            AppLogger.debug("Invalid URL")
            return alternatives
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        await addAuthToken(to: &request)
        request.timeoutInterval = 5  // Short timeout for comparison view

        // Convert alternatives to JSON
        let alternativesArray = alternatives.map { alt -> [String: Any] in
            var dict: [String: Any] = [
                "name": alt.name,
                "brand": alt.brand ?? "",
                "reason": alt.reason ?? ""
            ]
            if let co2 = alt.estimatedCO2 {
                dict["estimatedCO2"] = co2
            }
            if let water = alt.estimatedWater {
                dict["estimatedWater"] = water
            }
            return dict
        }

        let body: [String: Any] = ["alternatives": alternativesArray]

        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: body)

            let (data, response) = try await URLSession.shared.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse,
                  httpResponse.statusCode == 200 else {
                AppLogger.warning("⚠️ Enrichment failed - using AI estimates")
                return alternatives  // Return original if enrichment fails
            }

            struct EnrichmentResponse: Codable {
                let enriched: [EnrichedAlternative]
            }

            struct EnrichedAlternative: Codable {
                let name: String
                let brand: String?
                let reason: String?
                let estimatedCO2: Double?
                let estimatedWater: Double?
                let healthScore: Double?
                let environmentalScore: Double?
                let ethicsScore: Double?
                let barcode: String?
                let isEnriched: Bool?
                let dataSource: String?
            }

            let enrichmentResult = try JSONDecoder().decode(EnrichmentResponse.self, from: data)

            // Convert enriched data back to Alternative objects
            let enrichedAlternatives = enrichmentResult.enriched.map { enriched -> AnalysisResult.Alternative in
                AnalysisResult.Alternative(
                    name: enriched.name,
                    brand: enriched.brand,
                    reason: enriched.reason,
                    imageURL: nil,
                    link: nil,
                    estimatedCO2: enriched.estimatedCO2,
                    estimatedWater: enriched.estimatedWater,
                    healthScore: enriched.healthScore,
                    environmentalScore: enriched.environmentalScore,
                    ethicsScore: enriched.ethicsScore,
                    barcode: enriched.barcode,
                    isEnriched: enriched.isEnriched ?? false,
                    dataSource: enriched.dataSource
                )
            }

            let enrichedCount = enrichedAlternatives.filter { $0.isEnriched }.count
            AppLogger.debug("✅ Enriched \(enrichedCount)/\(alternatives.count) alternatives with real data")

            return enrichedAlternatives

        } catch {
            AppLogger.error("❌ Enrichment error: \(error.localizedDescription)")
            return alternatives  // Return original on error
        }
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
    
    // DEPRECATED: Use submitPurchaseDecision() instead
    // This function is not called anywhere in the codebase
    /*
    func savePurchaseDecision(
        userId: String,
        scanId: String,
        productName: String,
        decision: String,
        productCO2: Double,
        productWater: Double,
        alternativeName: String? = nil,
        alternativeCO2: Double? = nil,
        alternativeWater: Double? = nil
    ) async throws {
        guard let url = URL(string: "\(AppConfig.backendURL)/save-purchase-decision") else {
            throw NSError(domain: "NetworkService", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid URL"])
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        await addAuthToken(to: &request)
        request.timeoutInterval = 15

        var body: [String: Any] = [
            "userId": userId,
            "scanId": scanId,
            "productName": productName,
            "decision": decision,
            "productCO2": productCO2,
            "productWater": productWater,
            "timestamp": Date().timeIntervalSince1970
        ]

        if let altName = alternativeName {
            body["alternativeName"] = altName
        }
        if let altCO2 = alternativeCO2 {
            body["alternativeCO2"] = altCO2
        }
        if let altWater = alternativeWater {
            body["alternativeWater"] = altWater
        }

        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw NSError(domain: "NetworkService", code: -1, userInfo: [NSLocalizedDescriptionKey: "Failed to save purchase decision"])
        }

        let result = try JSONDecoder().decode([String: AnyCodable].self, from: data)
        AppLogger.debug("✅ Purchase decision saved: \(result)")
    }
    */

    // REMOVED: logAlternativeInteraction - Now handled exclusively by HistoryService.swift (local SQLite)
    // Alternative interactions are tracked locally for better offline support and data consistency
    // If backend analytics are needed, they should query the local database during sync operations

    func getUserImpact(userId: String) async throws -> UserImpactData {
        guard let url = URL(string: "\(AppConfig.backendURL)/get-user-impact") else {
            throw NSError(domain: "NetworkService", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid URL"])
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        await addAuthToken(to: &request)
        request.timeoutInterval = 15
        
        let body: [String: Any] = ["userId": userId]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        
        AppLogger.debug("🌐 Fetching user impact from: \(url)")
        AppLogger.debug("📤 Request body: \(body)")
        
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            
            guard let httpResponse = response as? HTTPURLResponse else {
                throw NSError(domain: "NetworkService", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid response"])
            }
            
            AppLogger.debug("📥 Response status: \(httpResponse.statusCode)")
            
            if httpResponse.statusCode != 200 {
                let errorBody = String(data: data, encoding: .utf8) ?? "No error body"
                AppLogger.error("❌ Backend error: \(errorBody)")
                throw NSError(domain: "NetworkService", code: httpResponse.statusCode, userInfo: [NSLocalizedDescriptionKey: "Backend returned \(httpResponse.statusCode): \(errorBody)"])
            }
            
            let responseBody = String(data: data, encoding: .utf8) ?? "Unable to decode"
            AppLogger.debug("📦 Response body: \(responseBody)")
            
            let result = try JSONDecoder().decode(UserImpactData.self, from: data)
            AppLogger.debug("✅ Successfully decoded user impact: \(result.totalScans) scans")
            return result
        } catch let error as NSError {
            AppLogger.error("❌ Network error: \(error.localizedDescription)")
            throw error
        }
    }
    
    func analyzePlate(image: UIImage, preferences: UserPreferences, restaurantName: String, dishName: String, cuisineType: String) async -> [String: Any]? {
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
        
        // Resize image for faster upload
        // Perform on background thread to avoid blocking UI
        let imageData: Data? = await Task.detached(priority: .userInitiated) {
            let resized = self.resizeImage(image, maxSize: 800)
            return resized.jpegData(compressionQuality: 0.8)
        }.value

        guard let imageData = imageData else {
            await MainActor.run {
                self.isAnalyzing = false
                self.analysisProgress = 0.0
                self.errorMessage = "Could not process image"
            }
            return nil
        }
        
        let base64Image = imageData.base64EncodedString()
        guard let url = URL(string: "\(AppConfig.backendURL)/analyze-plate") else {
            AppLogger.debug("Invalid URL")
            return nil
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        await addAuthToken(to: &request)
        request.timeoutInterval = 60
        
        let payload: [String: Any] = [
            "imageBase64": base64Image,
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
                "mayContainSafe": preferences.mayContainSafe,
                "avoidGMO": preferences.avoidGMO
            ],
            "restaurantName": restaurantName,
            "dishName": dishName,
            "cuisineType": cuisineType
        ]
        
        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: payload)
            
            AppLogger.debug("🍽️ Analyzing plate photo...")
            await MainActor.run {
                self.analysisProgress = 0.3
            }
            
            let (data, response) = try await URLSession.shared.data(for: request)
            
            guard let httpResponse = response as? HTTPURLResponse else {
                throw NSError(domain: "Invalid response", code: -1)
            }
            
            AppLogger.debug("📡 Plate analysis response status: \(httpResponse.statusCode)")
            
            if httpResponse.statusCode == 200 {
                await MainActor.run {
                    self.analysisProgress = 0.9
                }
                
                if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                    AppLogger.debug("✅ Plate analysis complete")
                    await MainActor.run {
                        self.isAnalyzing = false
                        self.analysisProgress = 1.0
                    }
                    return json
                } else {
                    throw NSError(domain: "Invalid JSON", code: -1)
                }
            } else {
                let errorText = String(data: data, encoding: .utf8) ?? "Unknown error"
                AppLogger.error("❌ Plate analysis error: \(errorText)")
                
                await MainActor.run {
                    self.isAnalyzing = false
                    self.analysisProgress = 0.0
                    self.errorMessage = "Could not analyze plate. Try:\n• Better lighting\n• Clearer photo\n• Include full dish"
                }
                
                return nil
            }
        } catch {
            AppLogger.error("❌ Network error analyzing plate: \(error)")
            
            await MainActor.run {
                self.isAnalyzing = false
                self.analysisProgress = 0.0
                self.errorMessage = "Failed to analyze plate: \(error.localizedDescription)"
            }
            
            return nil
        }
    }

    // MARK: - Plate Analysis (SSE Streaming — Two Phase)

    /// Streams plate analysis via SSE. Returns Phase 1 (safety verdict) immediately.
    /// Phase 2 detail is published to `NetworkService.plateDetailSubject`.
    /// Falls back to non-SSE `analyzePlate()` on error.
    /// Convenience overload: resizes UIImage then delegates to the Data overload.
    func analyzePlateStreaming(image: UIImage, preferences: UserPreferences, restaurantName: String, dishName: String, cuisineType: String) async -> [String: Any]? {
        // Resize image on background thread
        let imageData: Data? = await Task.detached(priority: .userInitiated) {
            let resized = self.resizeImage(image, maxSize: 800)
            return resized.jpegData(compressionQuality: 0.8)
        }.value

        guard let imageData = imageData else {
            await MainActor.run {
                self.isAnalyzing = false
                self.analysisProgress = 0.0
                self.errorMessage = "Could not process image"
            }
            return nil
        }

        return await analyzePlateStreaming(imageData: imageData, preferences: preferences, restaurantName: restaurantName, dishName: dishName, cuisineType: cuisineType)
    }

    /// Core overload accepting pre-encoded JPEG data (skips resize when data is already prepared).
    func analyzePlateStreaming(imageData: Data, preferences: UserPreferences, restaurantName: String, dishName: String, cuisineType: String) async -> [String: Any]? {
        guard await checkNetworkConnection() else {
            await MainActor.run {
                self.isAnalyzing = false
                self.analysisProgress = 0.0
            }
            return nil
        }

        // Bump generation to invalidate any in-flight Phase 2 from a previous scan
        plateStreamGeneration += 1
        let myGeneration = plateStreamGeneration

        // Reset detail subject for new scan
        NetworkService.plateDetailSubject.send(nil)

        await MainActor.run {
            self.isAnalyzing = true
            self.errorMessage = nil
            self.analysisProgress = 0.0
        }

        let base64Image = imageData.base64EncodedString()
        guard let url = URL(string: "\(AppConfig.backendURL)/analyze-plate") else {
            AppLogger.debug("Invalid URL")
            return nil
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("text/event-stream", forHTTPHeaderField: "Accept")
        await addAuthToken(to: &request)
        request.timeoutInterval = 60

        let payload: [String: Any] = [
            "imageBase64": base64Image,
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
                "mayContainSafe": preferences.mayContainSafe,
                "avoidGMO": preferences.avoidGMO
            ],
            "restaurantName": restaurantName,
            "dishName": dishName,
            "cuisineType": cuisineType
        ]

        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: payload)
        } catch {
            AppLogger.error("❌ Failed to serialize plate request: \(error)")
            return nil
        }

        AppLogger.debug("🍽️ Plate streaming: sending SSE request...")
        await MainActor.run { self.analysisProgress = 0.2 }

        do {
            let (bytes, response) = try await URLSession.shared.bytes(for: request)

            guard let httpResponse = response as? HTTPURLResponse else {
                throw NSError(domain: "NetworkService", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid response"])
            }

            // If server doesn't support SSE, fall back to standard JSON
            let contentType = httpResponse.allHeaderFields["Content-Type"] as? String ?? ""
            if httpResponse.statusCode != 200 || !contentType.contains("text/event-stream") {
                AppLogger.debug("🍽️ SSE not available, falling back to standard analyzePlate")
                guard let fallbackImage = UIImage(data: imageData) else { return nil }
                let fallbackResult = await analyzePlate(image: fallbackImage, preferences: preferences, restaurantName: restaurantName, dishName: dishName, cuisineType: cuisineType)
                // Publish complete detail so UI doesn't show loading spinner
                if let r = fallbackResult, myGeneration == self.plateStreamGeneration {
                    var detail = PlateAnalysis(from: r)
                    detail.detailLoaded = true
                    NetworkService.plateDetailSubject.send(detail)
                }
                return fallbackResult
            }

            await MainActor.run { self.analysisProgress = 0.4 }

            // Use continuation to return Phase 1 fast while continuing to read Phase 2
            let phase1: [String: Any]? = await withCheckedContinuation { continuation in
                Task {
                    var hasResumed = false
                    var currentEvent = ""
                    var dataLines: [String] = []
                    var receivedComplete = false

                    do {
                        for try await line in bytes.lines {
                            let trimmed = line.trimmingCharacters(in: .whitespaces)

                            // Blank line = SSE event dispatch boundary
                            if trimmed.isEmpty {
                                let dataBuffer = dataLines.joined(separator: "\n")
                                dataLines = []

                                guard !dataBuffer.isEmpty, dataBuffer != "{}" else {
                                    currentEvent = ""
                                    continue
                                }

                                guard let jsonData = dataBuffer.data(using: .utf8),
                                      let json = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any] else {
                                    currentEvent = ""
                                    continue
                                }

                                switch currentEvent {
                                case "partial":
                                    AppLogger.debug("✅ Plate SSE Phase 1 received: \(json["dishName"] as? String ?? "?")")
                                    await MainActor.run { self.analysisProgress = 0.7 }
                                    if !hasResumed {
                                        hasResumed = true
                                        continuation.resume(returning: json)
                                    }

                                case "complete":
                                    receivedComplete = true
                                    guard myGeneration == self.plateStreamGeneration else {
                                        AppLogger.debug("🍽️ Ignoring stale Phase 2 (generation mismatch)")
                                        break
                                    }
                                    var detailModel = PlateAnalysis(from: json)
                                    detailModel.detailLoaded = true
                                    NetworkService.plateDetailSubject.send(detailModel)
                                    AppLogger.debug("✅ Plate SSE Phase 2 received (complete)")
                                    await MainActor.run {
                                        self.analysisProgress = 1.0
                                        self.isAnalyzing = false
                                    }
                                    // If we never got a partial event, return complete as phase1
                                    if !hasResumed {
                                        hasResumed = true
                                        continuation.resume(returning: json)
                                    }

                                case "error":
                                    let errMsg = json["error"] as? String ?? "Unknown error"
                                    AppLogger.error("❌ Plate SSE error event: \(errMsg)")
                                    if !hasResumed {
                                        hasResumed = true
                                        continuation.resume(returning: nil)
                                    }

                                default:
                                    break
                                }

                                currentEvent = ""
                                continue
                            }

                            if trimmed.hasPrefix("event:") {
                                currentEvent = String(trimmed.dropFirst(6)).trimmingCharacters(in: .whitespaces)
                            } else if trimmed.hasPrefix("data:") {
                                dataLines.append(String(trimmed.dropFirst(5)).trimmingCharacters(in: .whitespaces))
                            }
                        }
                    } catch {
                        AppLogger.error("❌ Plate SSE stream read error: \(error)")
                    }

                    // Stream ended — clean up if Phase 2 never arrived
                    if !receivedComplete {
                        await MainActor.run {
                            self.isAnalyzing = false
                            self.analysisProgress = 1.0
                        }
                        // Unblock Actions tab shimmer
                        if myGeneration == self.plateStreamGeneration {
                            var endMarker = PlateAnalysis(from: [:])
                            endMarker.detailLoaded = true
                            NetworkService.plateDetailSubject.send(endMarker)
                        }
                    }

                    // Stream ended without resuming — return nil
                    if !hasResumed {
                        continuation.resume(returning: nil)
                    }
                }
            }

            if let result = phase1 {
                await MainActor.run {
                    // Don't set isAnalyzing=false yet — Phase 2 may still be streaming
                    self.analysisProgress = 0.8
                }
                return result
            }

            // No data received
            throw NSError(domain: "NetworkService", code: -1, userInfo: [NSLocalizedDescriptionKey: "No plate analysis data received"])

        } catch {
            AppLogger.error("❌ Plate streaming error: \(error)")
            await MainActor.run {
                self.isAnalyzing = false
                self.analysisProgress = 0.0
                self.errorMessage = "Failed to analyze plate: \(error.localizedDescription)"
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
        guard let url = URL(string: "\(AppConfig.backendURL)/submit-purchase-decision") else {
            AppLogger.debug("Invalid URL")
            return
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        await addAuthToken(to: &request)
        request.timeoutInterval = 15

        let body: [String: Any] = [
            "product_id": productId,
            "product_name": productName,
            "decision": decision,
            "co2_impact": co2Impact,
            "water_impact": waterImpact,
            "timestamp": ISO8601DateFormatter().string(from: Date())
        ]

        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
            let (_, response) = try await URLSession.shared.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse,
                  httpResponse.statusCode == 200 else {
                AppLogger.warning("⚠️ Failed to submit purchase decision to backend")
                return
            }

            AppLogger.debug("✅ Purchase decision submitted to backend: \(decision) for \(productName)")
        } catch {
            AppLogger.error("❌ Error submitting purchase decision: \(error)")
        }
    }

    
    // MARK: - GDPR Data Deletion
    
    func deleteUserData(userId: String) async throws {
        guard let url = URL(string: "\(AppConfig.backendURL)/delete-user-data") else {
            throw NSError(domain: "NetworkService", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid URL"])
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        await addAuthToken(to: &request)
        request.timeoutInterval = 15
        
        let body: [String: Any] = [
            "userId": userId,
            "confirmDeletion": true
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            let errorText = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw NSError(domain: "NetworkService", code: -1, userInfo: [NSLocalizedDescriptionKey: "Failed to delete data: \(errorText)"])
        }
    }

    // MARK: - Log Alternative Interaction
    
    func logAlternativeInteraction(alternativeName: String, alternativeBrand: String?, originalProduct: String, action: String) async {
        guard let url = URL(string: "\(AppConfig.backendURL)/log-alternative-interaction") else { return }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 10

        let body: [String: Any] = [
            "alternative_name": alternativeName,
            "alternative_brand": alternativeBrand ?? "",
            "original_product": originalProduct,
            "action": action
        ]

        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
            let (_, _) = try await URLSession.shared.data(for: request)
        } catch {
            AppLogger.debug("Failed to log alternative interaction: \(error)")
        }
    }

    // MARK: - Cloud Sync

    /// Push user preferences to backend (Firestore)
    func syncPreferencesToBackend(_ prefs: UserPreferences) async {
        guard isConnected else { return }
        guard let url = URL(string: "\(AppConfig.backendURL)/user/preferences") else { return }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 15
        await addAuthToken(to: &request)

        let payload: [String: Any] = ["preferences": prefs.toJSON()]
        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: payload)
            let (_, response) = try await URLSession.shared.data(for: request)
            if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 {
                AppLogger.debug("✅ Preferences synced to backend")
            }
        } catch {
            AppLogger.debug("⚠️ Preferences sync failed (will retry on next save): \(error.localizedDescription)")
        }
    }

    /// Pull user preferences from backend (for reinstall recovery)
    func pullPreferencesFromBackend() async -> UserPreferences? {
        guard let url = URL(string: "\(AppConfig.backendURL)/user/preferences") else { return nil }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 15
        await addAuthToken(to: &request)

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else { return nil }

            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let prefsDict = json["preferences"] as? [String: Any] else { return nil }

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

            AppLogger.debug("✅ Pulled preferences from backend")
            return prefs
        } catch {
            AppLogger.debug("⚠️ Failed to pull preferences from backend: \(error.localizedDescription)")
            return nil
        }
    }

    /// Pull scan history from backend (for reinstall recovery)
    func pullHistoryFromBackend(limit: Int = 100) async -> [[String: Any]]? {
        guard let url = URL(string: "\(AppConfig.backendURL)/user/history?limit=\(limit)") else { return nil }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 30
        await addAuthToken(to: &request)

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else { return nil }

            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let history = json["history"] as? [[String: Any]] else { return nil }

            AppLogger.debug("✅ Pulled \(history.count) history entries from backend")
            return history
        } catch {
            AppLogger.debug("⚠️ Failed to pull history from backend: \(error.localizedDescription)")
            return nil
        }
    }

    /// Pull user stats from backend
    func pullStatsFromBackend() async -> (co2Saved: Double, waterSaved: Double, totalScans: Int)? {
        guard let url = URL(string: "\(AppConfig.backendURL)/user/stats") else { return nil }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 15
        await addAuthToken(to: &request)

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else { return nil }

            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let stats = json["stats"] as? [String: Any] else { return nil }

            let co2 = stats["total_co2_saved"] as? Double ?? 0
            let water = stats["total_water_saved"] as? Double ?? 0
            let scans = stats["total_scans"] as? Int ?? 0

            AppLogger.debug("✅ Pulled stats from backend: \(scans) scans, \(co2)kg CO₂ saved")
            return (co2, water, scans)
        } catch {
            AppLogger.debug("⚠️ Failed to pull stats from backend: \(error.localizedDescription)")
            return nil
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

