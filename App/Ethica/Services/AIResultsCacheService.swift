//
//  AIResultsCacheService.swift
//  Ethica
//
//  Thread-safe in-memory cache for AI analysis results (instant repeated scans)

import Foundation
import UIKit
import OSLog

actor AIResultsCacheService {
    static let shared = AIResultsCacheService()

    private var cache: [String: CachedAIResult] = [:]
    private let cacheDuration: TimeInterval = 24 * 60 * 60 // 24 hours
    private let maxCacheSize = 50 // Keep last 50 results (memory-safe)
    private let logger = Logger(subsystem: "com.ethica.app", category: "AICache")

    init() {
        // Evict cache on memory pressure to prevent OOM kills
        NotificationCenter.default.addObserver(
            forName: UIApplication.didReceiveMemoryWarningNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            guard let self else { return }
            Task { await self.clearAll() }
        }
    }

    // CACHE VERSION: Increment this to invalidate all old cached results
    // Version 3: Thread-safe actor + Jain validation improvements
    private let CACHE_VERSION = 3

    struct CachedAIResult {
        let result: AnalysisResult
        let cachedAt: Date
        let expiresAt: Date
        let version: Int

        var isExpired: Bool {
            return Date() > expiresAt
        }
    }

    /// Generate cache key from barcode and user preferences
    /// 🚀 Optimized: Use Hasher for efficient key generation
    private func cacheKey(barcode: String, preferences: UserPreferences) -> String {
        var hasher = Hasher()
        hasher.combine(barcode)

        // Sort once for consistent hashing
        preferences.selectedAllergens.sorted().forEach { hasher.combine($0) }
        preferences.customAllergens.sorted().forEach { hasher.combine($0) }
        preferences.selectedDiets.sorted().forEach { hasher.combine($0) }
        preferences.customDiets.sorted().forEach { hasher.combine($0) }

        // Include avoidGMO — different GMO preference = different cache entry
        hasher.combine(preferences.avoidGMO)

        return "\(barcode)_\(abs(hasher.finalize()))"
    }

    /// Save AI result to cache
    func save(barcode: String, preferences: UserPreferences, result: AnalysisResult) {
        clearExpired()

        let key = cacheKey(barcode: barcode, preferences: preferences)
        let now = Date()
        let expiresAt = now.addingTimeInterval(cacheDuration)

        cache[key] = CachedAIResult(
            result: result,
            cachedAt: now,
            expiresAt: expiresAt,
            version: CACHE_VERSION
        )

        logger.debug("✅ Cached AI result for \(barcode) (version: \(self.CACHE_VERSION))")

        if cache.count > maxCacheSize {
            evictOldest()
        }
    }

    /// Fetch AI result from cache
    func fetch(barcode: String, preferences: UserPreferences) -> AnalysisResult? {
        let key = cacheKey(barcode: barcode, preferences: preferences)

        guard let cached = cache[key] else {
            return nil
        }

        if cached.version != CACHE_VERSION {
            logger.warning("⚠️ Cached result version mismatch — invalidating")
            cache.removeValue(forKey: key)
            return nil
        }

        if cached.isExpired {
            cache.removeValue(forKey: key)
            return nil
        }

        logger.debug("⚡ AI cache hit for \(barcode) (age: \(Int(Date().timeIntervalSince(cached.cachedAt)))s)")
        return cached.result
    }

    /// Clear expired entries
    func clearExpired() {
        let expiredKeys = cache.filter { $0.value.isExpired }.map { $0.key }
        for key in expiredKeys {
            cache.removeValue(forKey: key)
        }
        if !expiredKeys.isEmpty {
            logger.debug("✅ Cleared \(expiredKeys.count) expired AI cache entries")
        }
    }

    /// Clear all cache
    func clearAll() {
        let count = cache.count
        cache.removeAll()
        logger.debug("✅ Cleared all \(count) AI cache entries")
    }

    /// Evict single oldest entry (LRU) when cache is full
    private func evictOldest() {
        guard cache.count >= maxCacheSize else { return }
        if let oldestKey = cache.min(by: { $0.value.cachedAt < $1.value.cachedAt })?.key {
            cache.removeValue(forKey: oldestKey)
            logger.debug("✅ Evicted oldest AI cache entry")
        }
    }

    /// Get cache stats
    func getCacheStats() -> (total: Int, expired: Int) {
        let total = cache.count
        let expired = cache.filter { $0.value.isExpired }.count
        return (total, expired)
    }
}
