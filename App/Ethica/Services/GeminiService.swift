//
//  GeminiService.swift
//  Ethica
//
//  Direct Google Gemini API — Plate Check and ingredient label (Take Photo).
//

import Foundation
import UIKit

enum GeminiServiceError: LocalizedError {
    case notConfigured
    case invalidResponse
    case apiError(String)
    case emptyContent

    var errorDescription: String? {
        switch self {
        case .notConfigured: return GeminiConfig.missingKeyMessage
        case .invalidResponse: return "Invalid response from Gemini."
        case .apiError(let msg): return msg
        case .emptyContent: return "Gemini returned no analysis. Try a clearer photo."
        }
    }
}

/// On-device Gemini client (no Ethica backend required for plate / label photo flows).
final class GeminiService {
    static let shared = GeminiService()

    private let session: URLSession = {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 90
        config.timeoutIntervalForResource = 120
        return URLSession(configuration: config)
    }()

    private init() {}

    // MARK: - Plate Check

    /// Full plate analysis; returns dictionary for `PlateAnalysis` / `PlateAnalysisResultView`.
    func analyzePlate(
        imageData: Data,
        preferences: UserPreferences,
        restaurantName: String,
        dishName: String,
        cuisineType: String
    ) async throws -> [String: Any] {
        let prefs = preferencesSummary(preferences)
        let context = [
            restaurantName.isEmpty ? nil : "Restaurant: \(restaurantName)",
            dishName.isEmpty ? nil : "Dish: \(dishName)",
            cuisineType.isEmpty ? nil : "Cuisine: \(cuisineType)"
        ].compactMap { $0 }.joined(separator: "\n")

        let prompt = """
        You are a dietary safety expert for the Ethica app. Analyze this photo of food on a plate.

        User preferences:
        \(prefs)

        \(context.isEmpty ? "" : "User-provided context:\n\(context)\n")

        Identify visible ingredients, hidden risks (allergens, cross-contamination, dietary conflicts), and safety for THIS user's allergens and diets.

        Return ONLY valid JSON (no markdown) matching this schema:
        {
          "dishName": "string",
          "cuisineType": "string or empty",
          "visibleIngredients": ["string"],
          "likelyContains": ["string"],
          "hiddenRisks": [
            {
              "riskType": "Allergen|Cross-contamination|Dietary|Other",
              "ingredient": "string or null",
              "confidence": "High|Medium|Low",
              "reason": "string",
              "questionToAsk": "string or null"
            }
          ],
          "safetyAssessment": {
            "isLikelySafe": boolean,
            "confidence": number 0-100,
            "confidenceLevel": "High|Medium|Low",
            "recommendation": "string",
            "primaryConcerns": ["string"]
          },
          "questionsToAskStaff": ["string"],
          "alternativeOptions": ["string"]
        }
        """

        return try await generateJSON(imageData: imageData, prompt: prompt)
    }

    // MARK: - Take Photo (ingredient label)

    /// OCR + safety analysis from a packaged food ingredient label photo.
    func analyzeIngredientLabel(
        imageData: Data,
        preferences: UserPreferences
    ) async throws -> BackendResponse {
        let prefs = preferencesSummary(preferences)

        let prompt = """
        You are analyzing a packaged food INGREDIENT LABEL photo for the Ethica app.

        User preferences:
        \(prefs)

        Read all visible text. Extract every ingredient. Check allergens, diets, and GMO preference against the user's settings.
        mayContainSafe=\(preferences.mayContainSafe) means "may contain" traces are \(preferences.mayContainSafe ? "warnings only" : "treated as unsafe violations").

        Return ONLY valid JSON (no markdown) matching this schema:
        {
          "productName": "string",
          "ingredients": ["string"],
          "ingredientsText": "full label text",
          "allergenContains": ["normalized allergen names found on label"],
          "allergenMayContain": ["may contain / traces"],
          "gmoDeclaration": "string or null",
          "isSafe": boolean,
          "safetyLevel": "safe|caution|avoid",
          "confidence": number 0.0-1.0,
          "violations": ["clear violation messages"],
          "warnings": ["informational warnings"],
          "cautionWarnings": ["may-contain or uncertain items"],
          "detectedAllergens": ["allergens conflicting with user"],
          "dietaryViolations": ["diet rule violations"],
          "healthScore": number 0-100,
          "environmentalScore": number 0-100,
          "overallScore": number 0-100,
          "healthConcerns": ["string"],
          "healthBenefits": ["string"],
          "recommendations": ["string"],
          "co2Emissions": number,
          "waterUsage": number,
          "animalImpact": "low|medium|high",
          "confidenceFactors": ["string"],
          "sourceType": "gemini_label"
        }

        If no readable ingredients text, return {"productName":"Unknown","ingredients":[],"violations":["No readable ingredient text on label"],"isSafe":false,"safetyLevel":"avoid","confidence":0.1,"sourceType":"gemini_label"}.
        """

        let json = try await generateJSON(imageData: imageData, prompt: prompt)
        let data = try JSONSerialization.data(withJSONObject: json)
        let decoder = JSONDecoder()
        return try decoder.decode(BackendResponse.self, from: data)
    }

    // MARK: - Quick safety from label (barcode scanner ingredient photo)

    func quickSafetyFromLabel(imageData: Data, preferences: UserPreferences) async throws -> QuickSafetyResult {
        let backend = try await analyzeIngredientLabel(imageData: imageData, preferences: preferences)
        let ingredients = backend.ingredients ?? []
        return QuickSafetyResult(
            isSafe: backend.isSafe ?? true,
            safetyLevel: backend.safetyLevel,
            confidence: backend.confidence ?? 0.5,
            violations: backend.violations ?? [],
            warnings: backend.warnings ?? [],
            cautionWarnings: backend.cautionWarnings ?? [],
            detectedAllergens: backend.detectedAllergens ?? [],
            detectionEvidence: nil,
            crossContaminationRisks: backend.crossContaminationRisks?.compactMap { $0.allergen ?? $0.riskExplanation },
            gmoStatus: backend.gmoStatus,
            sourceType: "gemini_label",
            extractedIngredients: ingredients,
            ingredientsText: ingredients.joined(separator: ", "),
            productName: backend.productName
        )
    }

    // MARK: - Core API

    private func generateJSON(imageData: Data, prompt: String) async throws -> [String: Any] {
        guard let apiKey = GeminiConfig.apiKey else {
            throw GeminiServiceError.notConfigured
        }

        let base64 = imageData.base64EncodedString()
        let urlString = "https://generativelanguage.googleapis.com/v1beta/models/\(GeminiConfig.model):generateContent?key=\(apiKey)"
        guard let url = URL(string: urlString) else {
            throw GeminiServiceError.invalidResponse
        }

        let body: [String: Any] = [
            "contents": [[
                "parts": [
                    ["text": prompt],
                    [
                        "inline_data": [
                            "mime_type": "image/jpeg",
                            "data": base64
                        ]
                    ]
                ]
            ]],
            "generationConfig": [
                "temperature": 0.2,
                "responseMimeType": "application/json"
            ]
        ]

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        AppLogger.debug("🤖 Gemini request: model=\(GeminiConfig.model), imageKB=\(imageData.count / 1024)")

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw GeminiServiceError.invalidResponse
        }

        if http.statusCode != 200 {
            let text = String(data: data, encoding: .utf8) ?? "HTTP \(http.statusCode)"
            AppLogger.error("❌ Gemini API \(http.statusCode): \(text)")
            if let errJson = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let err = errJson["error"] as? [String: Any],
               let message = err["message"] as? String {
                throw GeminiServiceError.apiError(message)
            }
            throw GeminiServiceError.apiError("Gemini API error (\(http.statusCode))")
        }

        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let candidates = root["candidates"] as? [[String: Any]],
              let first = candidates.first,
              let content = first["content"] as? [String: Any],
              let parts = content["parts"] as? [[String: Any]],
              let text = parts.first?["text"] as? String else {
            throw GeminiServiceError.emptyContent
        }

        guard let json = Self.parseJSONObject(from: text) else {
            AppLogger.error("❌ Gemini JSON parse failed. Raw: \(text.prefix(500))")
            throw GeminiServiceError.invalidResponse
        }

        return json
    }

    static func parseJSONObject(from text: String) -> [String: Any]? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        var jsonString = trimmed
        if jsonString.hasPrefix("```") {
            jsonString = jsonString
                .replacingOccurrences(of: "```json", with: "")
                .replacingOccurrences(of: "```", with: "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }
        guard let data = jsonString.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        return obj
    }

    private func preferencesSummary(_ preferences: UserPreferences) -> String {
        let allergens = Array(preferences.selectedAllergens) + preferences.customAllergens
        let diets = Array(preferences.selectedDiets) + preferences.customDiets
        return """
        Allergens to avoid: \(allergens.isEmpty ? "none specified" : allergens.joined(separator: ", "))
        Diets: \(diets.isEmpty ? "none specified" : diets.joined(separator: ", "))
        Strict may-contain mode: \(!preferences.mayContainSafe)
        Avoid GMO: \(preferences.avoidGMO)
        Health priority: \(Int(preferences.healthPriority))%, Environment: \(Int(preferences.environmentPriority))%, Ethics: \(Int(preferences.ethicsPriority))%
        """
    }

    /// Text-only JSON generation (no image).
    private func generateTextJSON(prompt: String) async throws -> [String: Any] {
        guard let apiKey = GeminiConfig.apiKey else {
            throw GeminiServiceError.notConfigured
        }

        let urlString = "https://generativelanguage.googleapis.com/v1beta/models/\(GeminiConfig.model):generateContent?key=\(apiKey)"
        guard let url = URL(string: urlString) else {
            throw GeminiServiceError.invalidResponse
        }

        let body: [String: Any] = [
            "contents": [[
                "parts": [
                    ["text": prompt]
                ]
            ]],
            "generationConfig": [
                "temperature": 0.2,
                "responseMimeType": "application/json"
            ]
        ]

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        AppLogger.debug("🤖 Gemini request: model=\(GeminiConfig.model) (text-only)")

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw GeminiServiceError.invalidResponse
        }

        if http.statusCode != 200 {
            let text = String(data: data, encoding: .utf8) ?? "HTTP \(http.statusCode)"
            AppLogger.error("❌ Gemini API \(http.statusCode): \(text)")
            if let errJson = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let err = errJson["error"] as? [String: Any],
               let message = err["message"] as? String {
                throw GeminiServiceError.apiError(message)
            }
            throw GeminiServiceError.apiError("Gemini API error (\(http.statusCode))")
        }

        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let candidates = root["candidates"] as? [[String: Any]],
              let first = candidates.first,
              let content = first["content"] as? [String: Any],
              let parts = content["parts"] as? [[String: Any]],
              let text = parts.first?["text"] as? String else {
            throw GeminiServiceError.emptyContent
        }

        guard let json = Self.parseJSONObject(from: text) else {
            AppLogger.error("❌ Gemini JSON parse failed. Raw: \(text.prefix(500))")
            throw GeminiServiceError.invalidResponse
        }

        return json
    }

    // MARK: - Supabase-backend replacement helpers (text/image)

    func identifyProductFromImage(imageData: Data) async throws -> [String: Any] {
        let prompt = """
        Identify the packaged food product in this image. Return ONLY valid JSON (no markdown):
        {
          "product_name": "string",
          "confidence": number 0-100,
          "ingredients": ["string"],
          "ingredient_confidence": number 0-100,
          "ingredient_source": "image_estimate|brand_knowledge|unknown",
          "product_category": "string"
        }
        """
        return try await generateJSON(imageData: imageData, prompt: prompt)
    }

    func extractMenuDishesFromImage(imageData: Data, preferences: UserPreferences) async throws -> [String: Any] {
        let prefs = preferencesSummary(preferences)
        let prompt = """
        You are analyzing a restaurant menu photo for the Ethica app.

        User preferences:
        \(prefs)

        Extract dishes and estimate safety for the user.

        Return ONLY valid JSON (no markdown):
        {
          "menuAnalysis": [
            {
              "dish": "string",
              "ingredients": ["string"],
              "safe": boolean,
              "warnings": ["string"],
              "estimatedCO2": number
            }
          ]
        }
        """
        return try await generateJSON(imageData: imageData, prompt: prompt)
    }

    func analyzeIngredientsTextToAnalysisResultJSON(ingredientsText: String, productName: String?, preferences: UserPreferences) async throws -> [String: Any] {
        let prefs = preferencesSummary(preferences)
        let nameLine = (productName?.isEmpty == false) ? "Product name: \(productName!)" : ""
        let prompt = """
        You are a dietary safety expert for the Ethica app.

        \(nameLine)

        User preferences:
        \(prefs)

        Ingredients text:
        \(ingredientsText)

        Analyze allergens, diets, GMO preference, and provide an Ethica-style result.

        Return ONLY valid JSON (no markdown) compatible with this structure:
        {
          "productName": "string",
          "overallScore": number 0-100,
          "isSafe": boolean,
          "confidence": number 0.0-1.0,
          "confidenceFactors": ["string"],
          "violations": ["string"],
          "warnings": ["string"],
          "cautionWarnings": ["string"],
          "ingredients": ["string"],
          "detectedAllergens": ["string"],
          "healthScore": number 0-100,
          "environmentalScore": number 0-100,
          "co2Emissions": number,
          "waterUsage": number,
          "animalImpact": "Low|Medium|High|Unknown",
          "recommendations": ["string"],
          "alternatives": [{"name":"string","brand":"string or null","reason":"string","estimatedCO2":number,"estimatedWater":number}],
          "sourceType": "gemini_on_device",
          "safetyLevel": "safe|caution|avoid",
          "gmoStatus": "string or null"
        }
        """
        return try await generateTextJSON(prompt: prompt)
    }

    func suggestAlternatives(
        productName: String,
        category: String,
        brand: String?,
        preferences: UserPreferences,
        maxCount: Int = 6
    ) async throws -> [AnalysisResult.Alternative] {
        let prefs = preferencesSummary(preferences)
        let prompt = """
        Suggest up to \(maxCount) safer/healthier alternatives for the Ethica app.

        Product: \(productName)
        Category: \(category)
        Brand: \(brand ?? "")

        User preferences:
        \(prefs)

        Return ONLY valid JSON (no markdown):
        {
          "alternatives": [
            {
              "name": "string",
              "brand": "string or null",
              "reason": "string",
              "estimatedCO2": number,
              "estimatedWater": number
            }
          ]
        }
        """

        let json = try await generateTextJSON(prompt: prompt)
        let items = (json["alternatives"] as? [[String: Any]]) ?? []
        return items.compactMap { item in
            guard let name = item["name"] as? String, !name.isEmpty else { return nil }
            return AnalysisResult.Alternative(
                name: name,
                brand: item["brand"] as? String,
                reason: item["reason"] as? String,
                estimatedCO2: item["estimatedCO2"] as? Double,
                estimatedWater: item["estimatedWater"] as? Double,
                isEnriched: false,
                dataSource: "gemini_suggested"
            )
        }
    }
}
