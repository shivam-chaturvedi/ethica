//
//  OfflineCacheService.swift
//  Ethica
//
//  Caches recent scan results for offline viewing
//

import Foundation

/// Service that caches analysis results for offline access
class OfflineCacheService {
    static let shared = OfflineCacheService()
    
    private let cacheKey = "offline_cached_results"
    private let maxCachedResults = 50
    
    private init() {}
    
    // MARK: - Cache Management
    
    /// Cache an analysis result for offline viewing
    func cacheResult(_ result: CachedScanResult) {
        var cached = loadCachedResults()
        
        // Remove duplicate if exists (by barcode or product name)
        cached.removeAll { $0.barcode == result.barcode && result.barcode != nil }
        
        // Add to front
        cached.insert(result, at: 0)
        
        // Trim to max size
        if cached.count > maxCachedResults {
            cached = Array(cached.prefix(maxCachedResults))
        }
        
        saveCachedResults(cached)
    }
    
    /// Get all cached results
    func getCachedResults() -> [CachedScanResult] {
        return loadCachedResults()
    }
    
    /// Look up a cached result by barcode
    func lookupBarcode(_ barcode: String) -> CachedScanResult? {
        let cached = loadCachedResults()
        return cached.first { $0.barcode == barcode }
    }
    
    /// Clear all cached results
    func clearCache() {
        UserDefaults.standard.removeObject(forKey: cacheKey)
    }
    
    /// Check if offline cache is available
    var hasCachedResults: Bool {
        return !loadCachedResults().isEmpty
    }
    
    /// Get the count of cached results
    var cachedCount: Int {
        return loadCachedResults().count
    }
    
    // MARK: - Persistence
    
    private func loadCachedResults() -> [CachedScanResult] {
        guard let data = UserDefaults.standard.data(forKey: cacheKey) else {
            return []
        }
        do {
            return try JSONDecoder().decode([CachedScanResult].self, from: data)
        } catch {
            return []
        }
    }
    
    private func saveCachedResults(_ results: [CachedScanResult]) {
        do {
            let data = try JSONEncoder().encode(results)
            UserDefaults.standard.set(data, forKey: cacheKey)
        } catch {
            // Silently fail - cache is best-effort
        }
    }
}

// MARK: - Cached Result Model

struct CachedScanResult: Codable, Identifiable {
    let id: String
    let productName: String
    let barcode: String?
    let healthScore: Double
    let isSafe: Bool
    let violations: [String]
    let warnings: [String]
    let co2Emissions: Double
    let waterUsage: Double
    let ingredients: [String]
    let timestamp: Date
    
    init(from result: AnalysisResult) {
        self.id = UUID().uuidString
        self.productName = result.productName
        self.barcode = result.sourceBarcode
        self.healthScore = result.healthScore
        self.isSafe = result.isSafe
        self.violations = result.violations
        self.warnings = result.warnings
        self.co2Emissions = result.co2Emissions
        self.waterUsage = result.waterUsage
        self.ingredients = result.ingredients
        self.timestamp = Date()
    }
}
