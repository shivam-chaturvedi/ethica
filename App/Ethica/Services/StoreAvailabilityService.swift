//
//  StoreAvailabilityService.swift
//  Ethica
//
//  Service to check product availability at nearby stores
//

import Foundation
import CoreLocation

class StoreAvailabilityService {
    static let shared = StoreAvailabilityService()

    // MARK: - Cache

    private struct CacheEntry {
        let results: [NearbyAvailability]
        let timestamp: Date
        var isExpired: Bool { Date().timeIntervalSince(timestamp) > 300 } // 5 min TTL
    }

    /// In-memory cache keyed by lowercased product name
    private var cache: [String: CacheEntry] = [:]
    private let cacheLock = NSLock()

    private init() {}

    // MARK: - Public API

    /// Check availability for a product at nearby stores.
    /// Results are cached for 5 minutes per product name.
    func checkAvailability(
        productName: String,
        maxStores: Int = 5,
        userPreferences: UserPreferences? = nil
    ) async -> [NearbyAvailability] {
        let cacheKey = productName.lowercased().trimmingCharacters(in: .whitespaces)

        // Return cached result if still valid
        cacheLock.lock()
        if let entry = cache[cacheKey], !entry.isExpired {
            cacheLock.unlock()
            return Array(entry.results.prefix(maxStores))
        }
        cacheLock.unlock()

        // Get nearby stores from LocationService (real stores via OpenStreetMap)
        let nearbyStores = await LocationService.shared.findNearbyStores(maxDistance: 15.0)

        guard !nearbyStores.isEmpty else {
            AppLogger.warning("⚠️ No nearby stores found")
            return []
        }

        // Get user preferences (from PreferencesManager if not provided)
        let preferences = userPreferences ?? PreferencesManager.shared.preferences
        let hasDietaryRestrictions = hasRestrictiveDiet(preferences)

        // Pre-compute distances once (avoid repeated calls during sort)
        let location = LocationService.shared.currentLocation
        var distanceMap: [String: Double] = [:]
        for store in nearbyStores {
            distanceMap[store.id] = location.map { store.distance(from: $0) } ?? 999.0
        }

        // Prioritize and limit stores to check
        let prioritizedStores = prioritizeStores(
            nearbyStores,
            hasDietaryRestrictions: hasDietaryRestrictions,
            distanceMap: distanceMap
        )
        let storesToCheck = Array(prioritizedStores.prefix(min(maxStores + 3, prioritizedStores.count)))

        // Fetch availability concurrently using TaskGroup
        let results: [NearbyAvailability] = await withTaskGroup(of: NearbyAvailability?.self) { group in
            for store in storesToCheck {
                group.addTask {
                    guard let availability = self.fetchAvailability(
                        productName: productName,
                        store: store,
                        userPreferences: preferences
                    ) else { return nil }

                    let distance = distanceMap[store.id] ?? 999.0
                    return NearbyAvailability(
                        store: store,
                        distanceMiles: distance,
                        availability: availability
                    )
                }
            }

            var collected: [NearbyAvailability] = []
            for await result in group {
                if let result = result {
                    collected.append(result)
                }
            }
            return collected
        }

        // Sort results (single pass — no redundant pre-sort)
        let sorted = sortResults(results, hasDietaryRestrictions: hasDietaryRestrictions)

        // Cache the full sorted result set
        cacheLock.lock()
        cache[cacheKey] = CacheEntry(results: sorted, timestamp: Date())
        cacheLock.unlock()

        return Array(sorted.prefix(maxStores))
    }

    /// Invalidate cache for a specific product or all products
    func invalidateCache(for productName: String? = nil) {
        cacheLock.lock()
        if let name = productName {
            cache.removeValue(forKey: name.lowercased().trimmingCharacters(in: .whitespaces))
        } else {
            cache.removeAll()
        }
        cacheLock.unlock()
    }

    // MARK: - Smart Prioritization

    private func hasRestrictiveDiet(_ preferences: UserPreferences) -> Bool {
        return preferences.selectedDiets.contains { diet in
            ["vegan", "vegetarian", "jain", "kosher", "halal"].contains(diet.lowercased())
        } || preferences.selectedAllergens.count >= 3
    }

    /// Single prioritization sort using pre-computed distances
    private func prioritizeStores(
        _ stores: [Store],
        hasDietaryRestrictions: Bool,
        distanceMap: [String: Double]
    ) -> [Store] {
        return stores.sorted { s1, s2 in
            if hasDietaryRestrictions {
                let o1 = s1.chain.isOrganicFocused
                let o2 = s2.chain.isOrganicFocused
                if o1 != o2 { return o1 } // organic-focused first
            }
            // Same category → closer first
            return (distanceMap[s1.id] ?? 999) < (distanceMap[s2.id] ?? 999)
        }
    }

    private func sortResults(_ results: [NearbyAvailability], hasDietaryRestrictions: Bool) -> [NearbyAvailability] {
        return results.sorted { r1, r2 in
            // In-stock always beats out-of-stock
            if r1.availability.inStock != r2.availability.inStock {
                return r1.availability.inStock
            }

            // Among same stock status, organic-focused first for dietary users
            if hasDietaryRestrictions && r1.availability.inStock {
                let o1 = r1.store.chain.isOrganicFocused
                let o2 = r2.store.chain.isOrganicFocused
                if o1 != o2 { return o1 }
            }

            // Same category → closer first
            return r1.distanceMiles < r2.distanceMiles
        }
    }

    // MARK: - Availability Estimation

    /// Synchronous — no async overhead needed for estimation
    private func fetchAvailability(
        productName: String,
        store: Store,
        userPreferences: UserPreferences
    ) -> ProductAvailability? {
        let hasDietaryRestrictions = hasRestrictiveDiet(userPreferences)
        let inStock = estimateInStock(
            productName: productName,
            chain: store.chain,
            storeId: store.id,
            hasDietaryRestrictions: hasDietaryRestrictions
        )
        let price = estimatePrice(productName: productName, chain: store.chain)

        return ProductAvailability(
            productName: productName,
            storeId: store.id,
            inStock: inStock,
            price: price,
            lastUpdated: Date(),
            source: .estimated,
            aisle: inStock ? estimateAisle(productName: productName) : nil
        )
    }

    // MARK: - Deterministic Estimation

    /// Uses a stable hash instead of random — same product + store always yields the same result
    private func estimateInStock(
        productName: String,
        chain: StoreChain,
        storeId: String,
        hasDietaryRestrictions: Bool
    ) -> Bool {
        let productLower = productName.lowercased()

        // Build probability exactly as before
        var probability: Double = 0.5

        if chain.isOrganicFocused {
            if productLower.contains("organic") || productLower.contains("plant") ||
               productLower.contains("beyond") || productLower.contains("impossible") ||
               productLower.contains("almond") || productLower.contains("oat") ||
               productLower.contains("vegan") || productLower.contains("vegetarian") ||
               productLower.contains("dairy-free") || productLower.contains("gluten-free") {
                probability = 0.95
            } else {
                probability = 0.75
            }
            if hasDietaryRestrictions {
                probability = min(0.98, probability + 0.15)
            }
        } else if chain.hasExcellentDietarySelection {
            if chain == .traderJoes && productLower.contains("trader joe") {
                probability = 1.0
            } else if productLower.contains("organic") || productLower.contains("plant") ||
                      productLower.contains("vegan") {
                probability = 0.80
            } else {
                probability = 0.55
            }
            if hasDietaryRestrictions {
                probability = min(0.95, probability + 0.10)
            }
        } else {
            switch chain {
            case .target, .walmart:
                probability = 0.70
            case .kroger, .ralphs, .fredMeyer, .smiths,
                 .safeway, .vons, .albertsons,
                 .publix, .heb, .meijer, .giantFood,
                 .stopAndShop, .harristeeter, .foodLion:
                probability = 0.60
            case .costco, .samsClub:
                probability = 0.30
            case .aldi:
                probability = 0.50
            default:
                probability = 0.50
            }
        }

        // Deterministic decision: hash the product + store combo to a 0-1 value
        let seed = "\(productLower)_\(storeId)"
        let hashValue = abs(seed.hashValue)
        let roll = Double(hashValue % 10000) / 10000.0 // Stable 0..1 value
        return roll < probability
    }

    private func estimatePrice(productName: String, chain: StoreChain) -> Double? {
        let productLower = productName.lowercased()

        var basePrice: Double = 5.99

        if productLower.contains("milk") || productLower.contains("beverage") || productLower.contains("juice") {
            basePrice = 4.49
        } else if productLower.contains("cheese") || productLower.contains("butter") || productLower.contains("yogurt") {
            basePrice = 5.99
        } else if productLower.contains("meat") || productLower.contains("burger") || productLower.contains("chicken") {
            basePrice = 7.99
        } else if productLower.contains("snack") || productLower.contains("chips") || productLower.contains("cookie") {
            basePrice = 3.99
        } else if productLower.contains("bread") || productLower.contains("pasta") {
            basePrice = 4.29
        }

        if productLower.contains("organic") {
            basePrice *= 1.3
        }
        if productLower.contains("beyond") || productLower.contains("impossible") {
            basePrice *= 1.2
        }

        let multiplier: Double = {
            switch chain {
            case .wholeFoods:       return 1.30
            case .naturalGrocers:   return 1.20
            case .freshThyme:       return 1.15
            case .sprouts:          return 1.10
            case .traderJoes:       return 0.85
            case .wegmans:          return 1.05
            case .kroger, .ralphs, .fredMeyer, .smiths:
                                    return 0.95
            case .safeway, .vons, .albertsons:
                                    return 0.98
            case .publix:           return 1.00
            case .heb:              return 0.93
            case .meijer, .giantFood, .stopAndShop:
                                    return 0.95
            case .harristeeter:     return 1.02
            case .foodLion:         return 0.90
            case .target:           return 1.00
            case .walmart:          return 0.88
            case .costco, .samsClub:
                                    return 0.78
            case .aldi:             return 0.82
            case .other:            return 1.00 // Unknown chain — assume market rate
            }
        }()

        return round(basePrice * multiplier * 100) / 100
    }

    private func estimateAisle(productName: String) -> String {
        let productLower = productName.lowercased()

        if productLower.contains("milk") || productLower.contains("cheese") ||
           productLower.contains("yogurt") || productLower.contains("butter") {
            return "Dairy - Aisle 3"
        } else if productLower.contains("meat") || productLower.contains("burger") ||
                  productLower.contains("chicken") || productLower.contains("fish") {
            return "Meat & Seafood - Aisle 7"
        } else if productLower.contains("snack") || productLower.contains("chips") ||
                  productLower.contains("cookie") {
            return "Snacks - Aisle 5"
        } else if productLower.contains("beverage") || productLower.contains("juice") ||
                  productLower.contains("soda") {
            return "Beverages - Aisle 9"
        } else if productLower.contains("organic") || productLower.contains("natural") {
            return "Natural Foods - Aisle 12"
        } else {
            return "Grocery - Aisle 6"
        }
    }

    // MARK: - Future API Integration Points

    // TODO: Integrate with Instacart API
    // https://docs.instacart.com/
    private func fetchFromInstacart(productName: String, store: Store) async -> ProductAvailability? {
        return nil
    }

    // TODO: Integrate with Kroger API
    // https://developer.kroger.com/
    private func fetchFromKroger(productName: String, store: Store) async -> ProductAvailability? {
        return nil
    }

    // TODO: Integrate with Walmart API
    // https://developer.walmart.com/
    private func fetchFromWalmart(productName: String, store: Store) async -> ProductAvailability? {
        return nil
    }
}
