//
//  OpenFoodFactsClient.swift
//  Ethica
//
//  Client for OpenFoodFacts API (2M+ products database)

import Foundation

struct OpenFoodFactsProduct: Codable {
    let code: String?
    let productName: String?
    let brands: String?
    let ingredientsText: String?
    let ingredientsTextEn: String?
    let productNameEn: String?
    let allergens: String?
    let nutriments: Nutriments?
    let novaGroup: Int?
    let nutriscoreGrade: String?
    let ecoscoreGrade: String?
    let ecoscoreData: EcoscoreData?
    let imageUrl: String?
    // Serving and package size info
    let servingSize: String?
    let servingQuantity: Double?  // Serving size in grams
    let productQuantity: String?  // Total package weight (e.g., "187 g")
    let quantity: String?         // Alternative field for package weight (e.g., "187g")
    
    struct EcoscoreData: Codable {
        let agribalyse: Agribalyse?
        
        struct Agribalyse: Codable {
            let co2Total: Double?  // Total CO2 emissions in kg per 100g
            let co2Agriculture: Double?
            let co2Processing: Double?
            let co2Packaging: Double?
            let co2Transportation: Double?
            let co2Distribution: Double?
            
            enum CodingKeys: String, CodingKey {
                case co2Total = "co2_total"
                case co2Agriculture = "co2_agriculture"
                case co2Processing = "co2_processing"
                case co2Packaging = "co2_packaging"
                case co2Transportation = "co2_transportation"
                case co2Distribution = "co2_distribution"
            }
        }
        
        enum CodingKeys: String, CodingKey {
            case agribalyse
        }
    }
    
    struct Nutriments: Codable {
        // Per 100g values
        let energyKcal100g: Double?
        let proteins100g: Double?
        let fat100g: Double?
        let carbohydrates100g: Double?
        let sugars100g: Double?
        let fiber100g: Double?
        let salt100g: Double?
        let saturatedFat100g: Double?
        let sodium100g: Double?
        
        // Per serving values
        let energyKcalServing: Double?
        let proteinsServing: Double?
        let fatServing: Double?
        let carbohydratesServing: Double?
        let sugarsServing: Double?
        let fiberServing: Double?
        let saltServing: Double?
        let saturatedFatServing: Double?
        let sodiumServing: Double?
        
        enum CodingKeys: String, CodingKey {
            case energyKcal100g = "energy-kcal_100g"
            case proteins100g = "proteins_100g"
            case fat100g = "fat_100g"
            case carbohydrates100g = "carbohydrates_100g"
            case sugars100g = "sugars_100g"
            case fiber100g = "fiber_100g"
            case salt100g = "salt_100g"
            case saturatedFat100g = "saturated-fat_100g"
            case sodium100g = "sodium_100g"
            
            case energyKcalServing = "energy-kcal_serving"
            case proteinsServing = "proteins_serving"
            case fatServing = "fat_serving"
            case carbohydratesServing = "carbohydrates_serving"
            case sugarsServing = "sugars_serving"
            case fiberServing = "fiber_serving"
            case saltServing = "salt_serving"
            case saturatedFatServing = "saturated-fat_serving"
            case sodiumServing = "sodium_serving"
        }
        
        // Helper to decode a value that could be Int, Double, or String
        private static func decodeFlexibleDouble(from container: KeyedDecodingContainer<CodingKeys>, forKey key: CodingKeys) -> Double? {
            if let val = try? container.decodeIfPresent(Double.self, forKey: key) {
                return val
            } else if let val = try? container.decodeIfPresent(Int.self, forKey: key) {
                return Double(val)
            } else if let val = try? container.decodeIfPresent(String.self, forKey: key), let d = Double(val) {
                return d
            }
            return nil
        }
        
        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            
            energyKcal100g = Self.decodeFlexibleDouble(from: container, forKey: .energyKcal100g)
            proteins100g = Self.decodeFlexibleDouble(from: container, forKey: .proteins100g)
            fat100g = Self.decodeFlexibleDouble(from: container, forKey: .fat100g)
            carbohydrates100g = Self.decodeFlexibleDouble(from: container, forKey: .carbohydrates100g)
            sugars100g = Self.decodeFlexibleDouble(from: container, forKey: .sugars100g)
            fiber100g = Self.decodeFlexibleDouble(from: container, forKey: .fiber100g)
            salt100g = Self.decodeFlexibleDouble(from: container, forKey: .salt100g)
            saturatedFat100g = Self.decodeFlexibleDouble(from: container, forKey: .saturatedFat100g)
            sodium100g = Self.decodeFlexibleDouble(from: container, forKey: .sodium100g)
            
            energyKcalServing = Self.decodeFlexibleDouble(from: container, forKey: .energyKcalServing)
            proteinsServing = Self.decodeFlexibleDouble(from: container, forKey: .proteinsServing)
            fatServing = Self.decodeFlexibleDouble(from: container, forKey: .fatServing)
            carbohydratesServing = Self.decodeFlexibleDouble(from: container, forKey: .carbohydratesServing)
            sugarsServing = Self.decodeFlexibleDouble(from: container, forKey: .sugarsServing)
            fiberServing = Self.decodeFlexibleDouble(from: container, forKey: .fiberServing)
            saltServing = Self.decodeFlexibleDouble(from: container, forKey: .saltServing)
            saturatedFatServing = Self.decodeFlexibleDouble(from: container, forKey: .saturatedFatServing)
            sodiumServing = Self.decodeFlexibleDouble(from: container, forKey: .sodiumServing)
        }
    }
    
    enum CodingKeys: String, CodingKey {
        case code
        case productName = "product_name"
        case brands
        case ingredientsText = "ingredients_text"
        case ingredientsTextEn = "ingredients_text_en"
        case productNameEn = "product_name_en"
        case allergens
        case nutriments
        case novaGroup = "nova_group"
        case nutriscoreGrade = "nutriscore_grade"
        case ecoscoreGrade = "ecoscore_grade"
        case ecoscoreData = "ecoscore_data"
        case imageUrl = "image_url"
        case servingSize = "serving_size"
        case servingQuantity = "serving_quantity"
        case productQuantity = "product_quantity"
        case quantity
    }
    
    // Custom decoder to handle flexible types from OpenFoodFacts API
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        
        code = try container.decodeIfPresent(String.self, forKey: .code)
        productName = try container.decodeIfPresent(String.self, forKey: .productName)
        brands = try container.decodeIfPresent(String.self, forKey: .brands)
        ingredientsText = try container.decodeIfPresent(String.self, forKey: .ingredientsText)
        ingredientsTextEn = try container.decodeIfPresent(String.self, forKey: .ingredientsTextEn)
        productNameEn = try container.decodeIfPresent(String.self, forKey: .productNameEn)
        allergens = try container.decodeIfPresent(String.self, forKey: .allergens)
        nutriments = try container.decodeIfPresent(Nutriments.self, forKey: .nutriments)
        nutriscoreGrade = try container.decodeIfPresent(String.self, forKey: .nutriscoreGrade)
        ecoscoreGrade = try container.decodeIfPresent(String.self, forKey: .ecoscoreGrade)
        ecoscoreData = try container.decodeIfPresent(EcoscoreData.self, forKey: .ecoscoreData)
        imageUrl = try container.decodeIfPresent(String.self, forKey: .imageUrl)
        servingSize = try container.decodeIfPresent(String.self, forKey: .servingSize)
        
        // productQuantity can be String, Int, or Double
        if let qtyString = try? container.decodeIfPresent(String.self, forKey: .productQuantity) {
            productQuantity = qtyString
        } else if let qtyInt = try? container.decodeIfPresent(Int.self, forKey: .productQuantity) {
            productQuantity = String(qtyInt)
        } else if let qtyDouble = try? container.decodeIfPresent(Double.self, forKey: .productQuantity) {
            productQuantity = String(Int(qtyDouble))
        } else {
            productQuantity = nil
        }
        
        // quantity can be String (alternative field for package weight)
        quantity = try container.decodeIfPresent(String.self, forKey: .quantity)
        
        // novaGroup can be Int or String
        if let novaInt = try? container.decodeIfPresent(Int.self, forKey: .novaGroup) {
            novaGroup = novaInt
        } else if let novaString = try? container.decodeIfPresent(String.self, forKey: .novaGroup),
                  let novaInt = Int(novaString) {
            novaGroup = novaInt
        } else {
            novaGroup = nil
        }
        
        // servingQuantity can be Double, Int, or String
        if let qty = try? container.decodeIfPresent(Double.self, forKey: .servingQuantity) {
            servingQuantity = qty
        } else if let qtyInt = try? container.decodeIfPresent(Int.self, forKey: .servingQuantity) {
            servingQuantity = Double(qtyInt)
        } else if let qtyString = try? container.decodeIfPresent(String.self, forKey: .servingQuantity),
                  let qty = Double(qtyString) {
            servingQuantity = qty
        } else {
            servingQuantity = nil
        }
    }
}

struct OpenFoodFactsResponse: Codable {
    let status: Int
    let product: OpenFoodFactsProduct?
}

struct OpenFoodFactsSearchResponse: Codable {
    let count: Int
    let products: [OpenFoodFactsProduct]
}

class OpenFoodFactsClient {
    private let baseURL = "https://world.openfoodfacts.org/api/v2"
    private let session: URLSession
    private var lastRequestTime: Date?
    private let minRequestInterval: TimeInterval = 1.0 // Rate limiting: 1 request per second

    /// Lock for thread-safe access to responseCache and lastRequestTime
    private let cacheLock = NSLock()

    /// In-memory cache for OFF responses (avoids re-fetching on backend retry)
    private var responseCache: [String: CachedOFFResponse] = [:]
    private let responseCacheDuration: TimeInterval = 5 * 60 // 5 minutes
    private let maxResponseCacheSize = 50

    private struct CachedOFFResponse {
        let product: OpenFoodFactsProduct
        let rawJSON: [String: Any]
        let cachedAt: Date
    }

    init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 5  // 🚀 SPEED: Reduced from 10s
        config.timeoutIntervalForResource = 15  // 🚀 SPEED: Reduced from 30s
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        self.session = URLSession(configuration: config)
    }
    
    /// Fetch product information by barcode
    /// - Parameter barcode: Product barcode (EAN-13, UPC-A, etc.)
    /// - Returns: OpenFoodFactsProduct if found, nil otherwise
    func fetchProduct(barcode: String) async -> (product: OpenFoodFactsProduct, rawJSON: [String: Any])? {
        let candidates = BarcodeScanner.lookupBarcodeCandidates(barcode)
        guard !candidates.isEmpty else { return nil }

        for candidate in candidates {
            if let result = await fetchProductDirect(barcode: candidate) {
                return result
            }
        }
        return nil
    }

    private func fetchProductDirect(barcode: String) async -> (product: OpenFoodFactsProduct, rawJSON: [String: Any])? {
        // Thread-safe cache access
        cacheLock.lock()
        let now = Date()
        responseCache = responseCache.filter { now.timeIntervalSince($0.value.cachedAt) < responseCacheDuration }

        // Check in-memory cache first (avoids re-fetching on backend retry)
        if let cached = responseCache[barcode] {
            cacheLock.unlock()
            AppLogger.debug("⚡ OFF cache hit for barcode: \(barcode)")
            return (product: cached.product, rawJSON: cached.rawJSON)
        }
        cacheLock.unlock()

        guard let url = URL(string: "\(baseURL)/product/\(barcode)") else {
            AppLogger.error("❌ Invalid OpenFoodFacts URL for barcode: \(barcode)")
            return nil
        }
        
        var request = URLRequest(url: url)
        request.setValue("Ethica-iOS/1.0", forHTTPHeaderField: "User-Agent")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        await enforceRateLimit()

        do {
            AppLogger.debug("🌐 Fetching from OpenFoodFacts: \(url.absoluteString)")
            let (data, response) = try await session.data(for: request)
            
            guard let httpResponse = response as? HTTPURLResponse else {
                AppLogger.error("❌ Invalid response from OpenFoodFacts")
                return nil
            }
            
            AppLogger.debug("📡 OpenFoodFacts response status: \(httpResponse.statusCode)")
            
            guard httpResponse.statusCode == 200 else {
                AppLogger.error("❌ OpenFoodFacts API error: HTTP \(httpResponse.statusCode)")
                return nil
            }
            
            // Debug: print raw JSON (first 500 chars)
            if let jsonString = String(data: data, encoding: .utf8) {
                AppLogger.debug("📦 Raw JSON (truncated): \(String(jsonString.prefix(500)))")
            }
            
            // 🚀 SPEED: Extract raw product JSON to pass to backend (avoids redundant OFF fetch)
            var rawProductJSON: [String: Any]? = nil
            if let jsonObj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let productDict = jsonObj["product"] as? [String: Any] {
                rawProductJSON = productDict
            }
            
            let decoder = JSONDecoder()
            do {
                let offResponse = try decoder.decode(OpenFoodFactsResponse.self, from: data)
                
                if offResponse.status == 1, let product = offResponse.product {
                    AppLogger.debug("✅ Found product in OpenFoodFacts: \(product.productName ?? "Unknown")")
                    AppLogger.debug("📦 Product details:")
                    AppLogger.debug("   - Brands: \(product.brands ?? "N/A")")
                    AppLogger.debug("   - Ingredients text: \(product.ingredientsText?.prefix(100) ?? "N/A")")
                    AppLogger.debug("   - Allergens: \(product.allergens ?? "N/A")")
                    AppLogger.debug("   - Nutri-Score: \(product.nutriscoreGrade ?? "N/A")")
                    AppLogger.debug("   - NOVA Group: \(product.novaGroup?.description ?? "N/A")")
                    AppLogger.debug("   - Serving size: \(product.servingSize ?? "N/A")")
                    AppLogger.debug("   - Serving quantity: \(product.servingQuantity?.description ?? "N/A")")
                    // Cache for retry scenarios (thread-safe)
                    let rawJSON = rawProductJSON ?? [:]
                    cacheLock.lock()
                    responseCache[barcode] = CachedOFFResponse(product: product, rawJSON: rawJSON, cachedAt: Date())
                    if responseCache.count > maxResponseCacheSize {
                        let sorted = responseCache.sorted { $0.value.cachedAt < $1.value.cachedAt }
                        for (key, _) in sorted.prefix(10) {
                            responseCache.removeValue(forKey: key)
                        }
                    }
                    cacheLock.unlock()
                    return (product: product, rawJSON: rawJSON)
                } else {
                    AppLogger.warning("⚠️ Product not found in OpenFoodFacts database (status: \(offResponse.status))")
                    return nil
                }
            } catch let decodingError {
                AppLogger.error("❌ DECODING ERROR: \(decodingError)")
                if let decodingError = decodingError as? DecodingError {
                    switch decodingError {
                    case .keyNotFound(let key, let context):
                        AppLogger.debug("   Missing key: \(key.stringValue)")
                        AppLogger.debug("   Context: \(context.debugDescription)")
                        AppLogger.debug("   Coding path: \(context.codingPath.map { $0.stringValue }.joined(separator: " -> "))")
                    case .typeMismatch(let type, let context):
                        AppLogger.debug("   Type mismatch for: \(type)")
                        AppLogger.debug("   Context: \(context.debugDescription)")
                        AppLogger.debug("   Coding path: \(context.codingPath.map { $0.stringValue }.joined(separator: " -> "))")
                    case .valueNotFound(let type, let context):
                        AppLogger.debug("   Value not found for: \(type)")
                        AppLogger.debug("   Context: \(context.debugDescription)")
                        AppLogger.debug("   Coding path: \(context.codingPath.map { $0.stringValue }.joined(separator: " -> "))")
                    case .dataCorrupted(let context):
                        AppLogger.debug("   Data corrupted")
                        AppLogger.debug("   Context: \(context.debugDescription)")
                        AppLogger.debug("   Coding path: \(context.codingPath.map { $0.stringValue }.joined(separator: " -> "))")
                    @unknown default:
                        AppLogger.debug("   Unknown decoding error")
                    }
                }
                return nil
            }
            
        } catch {
            AppLogger.error("❌ OpenFoodFacts fetch error: \(error.localizedDescription)")
            return nil
        }
    }
    
    /// Search for a product by name using the OFF search API
    /// Returns the first product with non-empty ingredients_text
    func searchByName(_ name: String) async -> (product: OpenFoodFactsProduct, rawJSON: [String: Any])? {
        guard let encoded = name.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let url = URL(string: "https://world.openfoodfacts.org/cgi/search.pl?search_terms=\(encoded)&search_simple=1&action=process&json=1&page_size=3") else {
            AppLogger.error("❌ Invalid OpenFoodFacts search URL for: \(name)")
            return nil
        }

        var request = URLRequest(url: url)
        request.setValue("Ethica-iOS/1.0", forHTTPHeaderField: "User-Agent")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        await enforceRateLimit()

        do {
            AppLogger.debug("🔍 Searching OpenFoodFacts for: \(name)")
            let (data, response) = try await session.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
                AppLogger.error("❌ OFF search API error")
                return nil
            }

            // Extract raw JSON for the matched product
            let rawJSON: [String: Any]
            if let jsonObj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let products = jsonObj["products"] as? [[String: Any]] {
                // Find first product with ingredients (prefer English text)
                rawJSON = products.first {
                    ($0["ingredients_text_en"] as? String)?.isEmpty == false ||
                    ($0["ingredients_text"] as? String)?.isEmpty == false
                } ?? products.first ?? [:]
            } else {
                rawJSON = [:]
            }

            let searchResponse = try JSONDecoder().decode(OpenFoodFactsSearchResponse.self, from: data)

            guard searchResponse.count > 0 else {
                AppLogger.warning("⚠️ No products found for: \(name)")
                return nil
            }

            // Prefer product with ingredients (check English text too)
            if let match = searchResponse.products.first(where: {
                ($0.ingredientsTextEn?.isEmpty == false) || ($0.ingredientsText?.isEmpty == false)
            }) {
                AppLogger.debug("✅ OFF search hit: \(match.productName ?? "Unknown") (has ingredients)")

                // Cache result using product code if available
                if let code = match.code {
                    cacheLock.lock()
                    responseCache[code] = CachedOFFResponse(product: match, rawJSON: rawJSON, cachedAt: Date())
                    cacheLock.unlock()
                }

                return (product: match, rawJSON: rawJSON)
            }

            // Fallback: first product even without ingredients
            if let first = searchResponse.products.first {
                AppLogger.debug("⚠️ OFF search hit (no ingredients): \(first.productName ?? "Unknown")")
                return (product: first, rawJSON: rawJSON)
            }

            return nil
        } catch {
            AppLogger.error("❌ OFF search error: \(error.localizedDescription)")
            return nil
        }
    }

    /// Enforce rate limiting (1 request per second) — thread-safe
    private func enforceRateLimit() async {
        cacheLock.lock()
        let lastTime = lastRequestTime
        cacheLock.unlock()

        if let lastTime = lastTime {
            let elapsed = Date().timeIntervalSince(lastTime)
            if elapsed < minRequestInterval {
                let delay = minRequestInterval - elapsed
                try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            }
        }

        cacheLock.lock()
        lastRequestTime = Date()
        cacheLock.unlock()
    }
    
    /// Shared helper: split ingredient text on commas/semicolons respecting parentheses,
    /// then flatten sub-ingredients from parenthesized groups.
    /// e.g. "CHEESE SEASONING (WHEY, SALT, TAPIOCA)" → ["CHEESE SEASONING", "WHEY", "SALT", "TAPIOCA"]
    private func splitAndFlattenIngredients(_ text: String) -> [String] {
        // Step 1: Paren-aware split on commas/semicolons at depth 0
        var topLevel: [String] = []
        var current = ""
        var depth = 0

        for char in text {
            if char == "(" {
                depth += 1
                current.append(char)
            } else if char == ")" {
                depth = max(depth - 1, 0)
                current.append(char)
            } else if (char == "," || char == ";") && depth == 0 {
                let trimmed = current.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty { topLevel.append(trimmed) }
                current = ""
            } else {
                current.append(char)
            }
        }
        let last = current.trimmingCharacters(in: .whitespacesAndNewlines)
        if !last.isEmpty { topLevel.append(last) }

        // Step 2: Flatten — for each item with parentheses, extract the main name
        // plus recursively split the parenthesized content as sub-ingredients.
        var flattened: [String] = []
        var seen = Set<String>() // dedup (case-insensitive), preserving order

        func addUnique(_ item: String) {
            let key = item.lowercased()
            guard !key.isEmpty, key.count > 1, !seen.contains(key) else { return }
            seen.insert(key)
            flattened.append(item)
        }

        for item in topLevel {
            // Find the outermost parenthesized group
            guard let openParen = item.firstIndex(of: "("),
                  let closeParen = item.lastIndex(of: ")"),
                  openParen < closeParen else {
                addUnique(item)
                continue
            }

            // Main name = everything before the first "("
            let mainName = String(item[item.startIndex..<openParen])
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if !mainName.isEmpty {
                addUnique(mainName)
            }

            // Sub-ingredients = content inside the outermost parens
            let innerStart = item.index(after: openParen)
            let innerContent = String(item[innerStart..<closeParen])

            // Recursively split sub-ingredients (handles nested parens)
            let subIngredients = splitAndFlattenIngredients(innerContent)
            for sub in subIngredients {
                addUnique(sub)
            }
        }

        return flattened
    }

    /// Convert OpenFoodFacts product to ingredients list
    func extractIngredients(from product: OpenFoodFactsProduct) -> [String] {
        // Prefer English ingredients text (covers non-English region products like Haldiram Bhujia)
        let rawText = product.ingredientsTextEn ?? product.ingredientsText
        guard let rawText, !rawText.isEmpty else {
            AppLogger.warning("⚠️ No ingredients text available")
            return []
        }
        
        AppLogger.debug("🔍 Raw ingredients text: \(rawText.prefix(200))...")
        
        // Extract actual ingredients section from OCR'd text
        var ingredientsText = rawText
        
        // Look for "INGREDIENTS:" or "NGREDIENTS:" marker (OCR errors common)
        let patterns = ["NGREDIENTS:", "INGREDIENTS:", "Ingredients:", "ingredients:"]
        for pattern in patterns {
            if let range = rawText.range(of: pattern, options: .caseInsensitive) {
                // Extract everything after the marker
                var afterMarker = String(rawText[range.upperBound...])
                
                // Remove OCR line breaks that interrupt ingredients (e.g., "LME AND ACTIVE CULTURES:")
                // These are usually all-caps lines that break the flow
                let ocrNoisePatterns = [
                    "LME AND ACTIVE CULTURES:", "ACTIVE CULTURES:", "STRIBUTED BY:"
                ]
                for noise in ocrNoisePatterns {
                    afterMarker = afterMarker.replacingOccurrences(of: noise, with: "")
                }
                
                // Stop at certain keywords that indicate end of ingredients
                let stopKeywords = [
                    ". Contains", ". CONTAINS", "DISTRIBUTED BY:", "Distributed by:",
                    "ALLERGEN", "Allergen", "MADE IN", "Made in", "Grade A", 
                    "www.", "http", "cording to"
                ]
                
                var cleanedText = afterMarker
                for keyword in stopKeywords {
                    if let stopRange = afterMarker.range(of: keyword, options: .caseInsensitive) {
                        cleanedText = String(afterMarker[..<stopRange.lowerBound])
                        break
                    }
                }
                
                ingredientsText = cleanedText.trimmingCharacters(in: .whitespacesAndNewlines)
                AppLogger.debug("✅ Found ingredients marker '\(pattern)', extracted: \(ingredientsText.prefix(150))...")
                break
            }
        }
        
        // If we didn't find a marker, check if this looks like nutrition facts garbage
        let nutritionKeywords = ["Nutrition Facts", "Amount/Serving", "% DV", "Calories", "Total Fat", "Sat. Fat", "Cholest.", "Sodium", "Total Carb"]
        let hasNutritionGarbage = nutritionKeywords.contains { ingredientsText.contains($0) }
        
        if hasNutritionGarbage {
            AppLogger.warning("⚠️ ingredientsText contains nutrition facts garbage, cannot extract reliable ingredients")
            return []
        }
        
        // Split on commas/semicolons respecting parentheses, then flatten sub-ingredients
        var ingredients = splitAndFlattenIngredients(ingredientsText)

        // Clean up each ingredient
        ingredients = ingredients.map { ingredient in
            var cleaned = ingredient

            // Remove percentage numbers (e.g., "flour 80%" -> "flour")
            if let percentRange = cleaned.range(of: "\\s*\\d+[.,]?\\d*\\s*%", options: .regularExpression) {
                cleaned.removeSubrange(percentRange)
            }

            // Remove numbers at the start (e.g., "1. flour" -> "flour")
            if let numberRange = cleaned.range(of: "^\\d+\\.?\\s*", options: .regularExpression) {
                cleaned.removeSubrange(numberRange)
            }

            return cleaned.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        .filter { !$0.isEmpty && $0.count > 1 } // Filter out single characters

        AppLogger.debug("✅ Extracted \(ingredients.count) ingredients: \(ingredients.prefix(5).joined(separator: ", "))\(ingredients.count > 5 ? "..." : "")")

        return ingredients
    }

    /// Overload: Extract ingredients from raw text string
    func extractIngredients(from rawText: String) -> [String] {
        guard !rawText.isEmpty else {
            AppLogger.warning("⚠️ No ingredients text available")
            return []
        }

        AppLogger.debug("🔍 Raw ingredients text: \(rawText.prefix(200))...")

        // Extract actual ingredients section from OCR'd text
        var ingredientsText = rawText

        // Look for "INGREDIENTS:" or "NGREDIENTS:" marker (OCR errors common)
        let patterns = ["NGREDIENTS:", "INGREDIENTS:", "Ingredients:", "ingredients:"]
        for pattern in patterns {
            if let range = rawText.range(of: pattern, options: .caseInsensitive) {
                // Extract everything after the marker
                var afterMarker = String(rawText[range.upperBound...])

                // Remove OCR line breaks that interrupt ingredients
                let ocrNoisePatterns = [
                    "LME AND ACTIVE CULTURES:", "ACTIVE CULTURES:", "STRIBUTED BY:"
                ]
                for noise in ocrNoisePatterns {
                    afterMarker = afterMarker.replacingOccurrences(of: noise, with: "")
                }

                // Stop at certain keywords that indicate end of ingredients
                let stopKeywords = [
                    ". Contains", ". CONTAINS", "DISTRIBUTED BY:", "Distributed by:",
                    "ALLERGEN", "Allergen", "MADE IN", "Made in", "Grade A",
                    "www.", "http", "cording to"
                ]

                var cleanedText = afterMarker
                for keyword in stopKeywords {
                    if let stopRange = afterMarker.range(of: keyword, options: .caseInsensitive) {
                        cleanedText = String(afterMarker[..<stopRange.lowerBound])
                        break
                    }
                }

                ingredientsText = cleanedText.trimmingCharacters(in: .whitespacesAndNewlines)
                AppLogger.debug("✅ Found ingredients marker '\(pattern)', extracted: \(ingredientsText.prefix(150))...")
                break
            }
        }

        // If we didn't find a marker, check if this looks like nutrition facts garbage
        let nutritionKeywords = ["Nutrition Facts", "Amount/Serving", "% DV", "Calories", "Total Fat", "Sat. Fat", "Cholest.", "Sodium", "Total Carb"]
        let hasNutritionGarbage = nutritionKeywords.contains { ingredientsText.contains($0) }

        if hasNutritionGarbage {
            AppLogger.warning("⚠️ ingredientsText contains nutrition facts garbage, cannot extract reliable ingredients")
            return []
        }

        // Split on commas/semicolons respecting parentheses, then flatten sub-ingredients
        var ingredients = splitAndFlattenIngredients(ingredientsText)

        // Clean up each ingredient
        ingredients = ingredients.map { ingredient in
            var cleaned = ingredient

            // Remove percentage numbers
            if let percentRange = cleaned.range(of: "\\s*\\d+[.,]?\\d*\\s*%", options: .regularExpression) {
                cleaned.removeSubrange(percentRange)
            }

            // Remove numbers at the start
            if let numberRange = cleaned.range(of: "^\\d+\\.?\\s*", options: .regularExpression) {
                cleaned.removeSubrange(numberRange)
            }

            return cleaned.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        .filter { !$0.isEmpty && $0.count > 1 } // Filter out single characters

        AppLogger.debug("✅ Extracted \(ingredients.count) ingredients: \(ingredients.prefix(5).joined(separator: ", "))\(ingredients.count > 5 ? "..." : "")")

        return ingredients
    }

    /// Generate ethical summary from OpenFoodFacts data
    func getEthicalSummary(from product: OpenFoodFactsProduct) -> String {
        var summary: [String] = []
        
        if let nutriscore = product.nutriscoreGrade?.uppercased() {
            summary.append("Nutri-Score: \(nutriscore)")
        }
        
        if let ecoscore = product.ecoscoreGrade?.uppercased() {
            summary.append("Eco-Score: \(ecoscore)")
        }
        
        if let nova = product.novaGroup {
            let novaDescription: String
            switch nova {
            case 1: novaDescription = "Unprocessed or minimally processed"
            case 2: novaDescription = "Processed culinary ingredients"
            case 3: novaDescription = "Processed foods"
            case 4: novaDescription = "Ultra-processed foods"
            default: novaDescription = "Unknown processing level"
            }
            summary.append("NOVA Group \(nova): \(novaDescription)")
        }
        
        return summary.isEmpty ? "Limited ethical data available" : summary.joined(separator: "\n")
    }
}
