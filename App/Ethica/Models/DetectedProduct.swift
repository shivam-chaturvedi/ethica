//
//  DetectedProduct.swift
//  Ethica
//
//  AR-detected product model for shelf recognition
//

import Foundation
import Vision
import CoreGraphics

struct DetectedProduct: Identifiable, Equatable {
    let id = UUID()
    let name: String
    let brand: String?
    let boundingBox: CGRect  // Normalized coordinates (0-1)
    let confidence: Float
    let barcode: String?
    
    // Safety assessment
    var safetyStatus: SafetyStatus = .unknown
    var allergenWarnings: [String] = []
    var isSafeForUser: Bool = false
    
    // Environmental data
    var co2: Double?
    var waterUsage: Double?
    var healthScore: Double?
    
    // Analysis result (if available)
    var analysisResult: AnalysisResult?
    
    // Visual state
    var isSelected: Bool = false
    var showingDetails: Bool = false
    
    // Equatable conformance
    static func == (lhs: DetectedProduct, rhs: DetectedProduct) -> Bool {
        lhs.id == rhs.id
    }
    
    enum SafetyStatus: Equatable {
        case safe
        case caution
        case danger
        case unknown
        
        var color: String {
            switch self {
            case .safe: return "10B981"      // Green
            case .caution: return "F59E0B"   // Yellow
            case .danger: return "EF4444"    // Red
            case .unknown: return "9CA3AF"   // Gray
            }
        }
        
        var glowColor: String {
            switch self {
            case .safe: return "34D399"      // Lighter green
            case .caution: return "FBBF24"   // Lighter yellow
            case .danger: return "F87171"    // Lighter red
            case .unknown: return "D1D5DB"   // Lighter gray
            }
        }
    }
}

// Product recognition result from Vision
struct VisionDetection {
    let text: String
    let boundingBox: CGRect
    let confidence: Float
    
    var isPotentialProductName: Bool {
        // Filter out common non-product text
        let lowerText = text.lowercased()
        let ignoreWords = ["ingredients", "nutrition", "facts", "allergen", "warning", "made in", "best by", "exp", "upc", "calories", "serving", "net wt", "fl oz", "contains", "distributed by"]
        
        // Must be at least 3 characters
        guard text.count >= 3 else { return false }
        
        // Ignore if contains only numbers
        if text.allSatisfy({ $0.isNumber || $0.isWhitespace }) { return false }
        
        // Ignore if it's a common excluded phrase
        if ignoreWords.contains(where: { lowerText.contains($0) }) { return false }
        
        return true
    }
    
    var isPotentialBrand: Bool {
        // Brand names are typically capitalized, shorter, and at top of package
        // They're often single words or short phrases
        guard text.count >= 2 && text.count <= 25 else { return false }
        
        // Check if first letter is uppercase (common for brands)
        guard text.first?.isUppercase == true else { return false }
        
        // Ignore if contains numbers (likely nutritional info)
        if text.contains(where: { $0.isNumber }) { return false }
        
        return true
    }
}

// Shelf section for grouped analysis
struct ShelfSection {
    let boundingBox: CGRect
    let detectedProducts: [DetectedProduct]
    
    var safeProductCount: Int {
        detectedProducts.filter { $0.safetyStatus == .safe }.count
    }
    
    var unsafeProductCount: Int {
        detectedProducts.filter { $0.safetyStatus == .danger }.count
    }
    
    var cautionProductCount: Int {
        detectedProducts.filter { $0.safetyStatus == .caution }.count
    }
    
    var totalCount: Int {
        detectedProducts.count
    }
    
    var safeCoverage: Double {
        guard totalCount > 0 else { return 0 }
        return Double(safeProductCount) / Double(totalCount)
    }
}
