//
//  StoreAvailability.swift
//  Ethica
//
//  Store availability tracking for alternative products
//

import Foundation
import CoreLocation

// MARK: - Store

struct Store: Identifiable, Codable, Equatable {
    let id: String
    let name: String
    let chain: StoreChain
    let address: String
    let city: String
    let state: String
    let zipCode: String
    let latitude: Double
    let longitude: Double
    let phone: String?

    // Computed property for distance
    func distance(from location: CLLocation) -> Double {
        let storeLocation = CLLocation(latitude: latitude, longitude: longitude)
        return location.distance(from: storeLocation) / 1609.34 // Convert meters to miles
    }
}

// MARK: - Store Chains

enum StoreChain: String, Codable, CaseIterable {
    // Premium Organic & Natural
    case wholeFoods = "Whole Foods Market"
    case sprouts = "Sprouts Farmers Market"
    case naturalGrocers = "Natural Grocers"
    case freshThyme = "Fresh Thyme Market"

    // Specialty
    case traderJoes = "Trader Joe's"

    // Major Chains
    case kroger = "Kroger"
    case safeway = "Safeway"
    case albertsons = "Albertsons"
    case publix = "Publix"
    case heb = "H-E-B"
    case wegmans = "Wegmans"
    case meijer = "Meijer"
    case giantFood = "Giant Food"
    case stopAndShop = "Stop & Shop"
    case harristeeter = "Harris Teeter"
    case foodLion = "Food Lion"

    // Regional Kroger Family
    case ralphs = "Ralphs"
    case fredMeyer = "Fred Meyer"
    case vons = "Vons"
    case smiths = "Smith's"

    // Big Box
    case target = "Target"
    case walmart = "Walmart"
    case costco = "Costco"
    case samsClub = "Sam's Club"

    // Discount
    case aldi = "Aldi"

    // Unknown / independent store (not in our chain list)
    case other = "Local Store"

    /// Initialize from the backend's chain identifier string (e.g. "wholeFoods", "traderJoes")
    static func fromIdentifier(_ id: String?) -> StoreChain {
        guard let id = id else { return .other }
        // Map backend identifiers to enum cases
        switch id {
        case "wholeFoods":     return .wholeFoods
        case "sprouts":        return .sprouts
        case "naturalGrocers": return .naturalGrocers
        case "freshThyme":     return .freshThyme
        case "traderJoes":     return .traderJoes
        case "kroger":         return .kroger
        case "safeway":        return .safeway
        case "albertsons":     return .albertsons
        case "publix":         return .publix
        case "heb":            return .heb
        case "wegmans":        return .wegmans
        case "meijer":         return .meijer
        case "giantFood":      return .giantFood
        case "stopAndShop":    return .stopAndShop
        case "harristeeter":   return .harristeeter
        case "foodLion":       return .foodLion
        case "ralphs":         return .ralphs
        case "fredMeyer":      return .fredMeyer
        case "vons":           return .vons
        case "smiths":         return .smiths
        case "target":         return .target
        case "walmart":        return .walmart
        case "costco":         return .costco
        case "samsClub":       return .samsClub
        case "aldi":           return .aldi
        default:               return .other
        }
    }

    var icon: String {
        switch self {
        case .wholeFoods:
            return "leaf.circle.fill"
        case .sprouts, .naturalGrocers, .freshThyme:
            return "carrot.fill"
        case .traderJoes:
            return "cart.fill"
        case .target:
            return "target"
        case .walmart:
            return "cart.badge.plus"
        case .costco, .samsClub:
            return "building.2.fill"
        case .aldi:
            return "cart.circle.fill"
        default:
            return "building.columns"
        }
    }

    var color: String {
        switch self {
        case .wholeFoods:
            return "10B981" // Whole Foods Green
        case .sprouts, .naturalGrocers, .freshThyme:
            return "22C55E" // Bright Green
        case .traderJoes:
            return "EF4444" // Red
        case .target:
            return "CC0000" // Target Red
        case .walmart:
            return "0071CE" // Walmart Blue
        case .kroger, .ralphs, .fredMeyer, .smiths:
            return "0047AB" // Kroger Blue
        case .safeway, .vons, .albertsons:
            return "E31837" // Red
        case .publix:
            return "00834C" // Green
        case .heb:
            return "DD0031" // H-E-B Red
        case .wegmans:
            return "F58220" // Orange
        case .meijer:
            return "FF0000" // Red
        case .giantFood:
            return "C8102E" // Red
        case .stopAndShop:
            return "E21836" // Red
        case .harristeeter:
            return "00539F" // Blue
        case .foodLion:
            return "C41230" // Red
        case .costco:
            return "0066B2" // Blue
        case .samsClub:
            return "0057A0" // Blue
        case .aldi:
            return "FF6600" // Orange
        case .other:
            return "9CA3AF" // Gray
        }
    }

    /// Returns true if this chain specializes in organic/natural products
    /// Perfect for vegan, vegetarian, Jain, and other dietary restrictions
    var isOrganicFocused: Bool {
        switch self {
        case .wholeFoods, .sprouts, .naturalGrocers, .freshThyme:
            return true
        default:
            return false
        }
    }

    /// Returns true if this chain has excellent selection for dietary restrictions
    var hasExcellentDietarySelection: Bool {
        switch self {
        case .wholeFoods, .sprouts, .naturalGrocers, .freshThyme, .traderJoes, .wegmans:
            return true
        default:
            return false
        }
    }
}

// MARK: - Product Availability

struct ProductAvailability: Codable, Equatable {
    let productName: String
    let storeId: String
    let inStock: Bool
    let price: Double?
    let lastUpdated: Date
    let source: AvailabilitySource
    let aisle: String? // e.g., "Dairy - Aisle 3"

    enum AvailabilitySource: String, Codable {
        case instacartAPI = "instacart"
        case krogerAPI = "kroger"
        case walmartAPI = "walmart"
        case userReported = "user_reported"
        case estimated = "estimated"
    }
}

// MARK: - Nearby Availability Summary

struct NearbyAvailability: Identifiable, Equatable {
    /// Stable identity derived from store + product — safe for SwiftUI ForEach diffing
    var id: String { "\(store.id)_\(availability.productName)" }
    let store: Store
    let distanceMiles: Double
    let availability: ProductAvailability

    var formattedDistance: String {
        if distanceMiles < 0.1 {
            return "< 0.1 mi"
        } else if distanceMiles < 1.0 {
            return String(format: "%.1f mi", distanceMiles)
        } else {
            return String(format: "%.0f mi", distanceMiles)
        }
    }

    var formattedPrice: String? {
        guard let price = availability.price else { return nil }
        return String(format: "$%.2f", price)
    }
}

// MARK: - JSON Parsing (from backend OpenStreetMap response)

extension Store {
    /// Parse a Store from the backend's /nearby-stores JSON response
    static func fromJSON(_ json: [String: Any]) -> Store? {
        guard let id = json["id"] as? String,
              let name = json["name"] as? String,
              let latitude = json["latitude"] as? Double,
              let longitude = json["longitude"] as? Double else {
            return nil
        }

        let chain = StoreChain.fromIdentifier(json["chain"] as? String)

        return Store(
            id: id,
            name: name,
            chain: chain,
            address: json["address"] as? String ?? name,
            city: json["city"] as? String ?? "",
            state: json["state"] as? String ?? "",
            zipCode: json["zipCode"] as? String ?? "",
            latitude: latitude,
            longitude: longitude,
            phone: json["phone"] as? String
        )
    }
}
