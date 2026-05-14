//
//  PlateAnalysisModel.swift
//  Ethica
//
//  Typed Codable model for plate analysis results
//

import Foundation

/// Strongly-typed model for plate analysis responses from the backend
struct PlateAnalysis: Codable {
    var dishName: String?
    var cuisineType: String?
    var visibleIngredients: [String]?
    var likelyContains: [String]?
    var hiddenRisks: [HiddenRisk]?
    var safetyAssessment: SafetyAssessment?
    var questionsToAskStaff: [String]?
    var alternativeOptions: [String]?

    /// Set to true once Phase 2 detail has been merged (even if all detail arrays are empty).
    /// Not part of JSON — excluded from CodingKeys.
    var detailLoaded: Bool = false

    enum CodingKeys: String, CodingKey {
        case dishName, cuisineType, visibleIngredients, likelyContains
        case hiddenRisks, safetyAssessment, questionsToAskStaff, alternativeOptions
    }

    /// True when Phase 2 detail has been received
    var isComplete: Bool { detailLoaded }

    /// Merge Phase 2 detail fields into this model
    func merging(with detail: PlateAnalysis) -> PlateAnalysis {
        var merged = self
        if let lc = detail.likelyContains, !lc.isEmpty {
            merged.likelyContains = lc
        }
        if let q = detail.questionsToAskStaff, !q.isEmpty {
            merged.questionsToAskStaff = q
        }
        if let a = detail.alternativeOptions, !a.isEmpty {
            merged.alternativeOptions = a
        }
        merged.detailLoaded = true
        return merged
    }

    /// Convenience initializer from untyped dictionary (backward compatibility)
    init(from dict: [String: Any]) {
        self.dishName = dict["dishName"] as? String
        self.cuisineType = dict["cuisineType"] as? String
        self.visibleIngredients = dict["visibleIngredients"] as? [String]
        self.likelyContains = dict["likelyContains"] as? [String]
        self.questionsToAskStaff = dict["questionsToAskStaff"] as? [String]
        self.alternativeOptions = dict["alternativeOptions"] as? [String]

        if let risksArray = dict["hiddenRisks"] as? [[String: Any]] {
            self.hiddenRisks = risksArray.enumerated().map { HiddenRisk(from: $1, index: $0) }
        } else {
            self.hiddenRisks = nil
        }

        if let safetyDict = dict["safetyAssessment"] as? [String: Any] {
            self.safetyAssessment = SafetyAssessment(from: safetyDict)
        } else {
            self.safetyAssessment = nil
        }

        // If detail fields are already populated (non-SSE / backward compat path), mark as complete
        let hasLc = !(self.likelyContains ?? []).isEmpty
        let hasQ = !(self.questionsToAskStaff ?? []).isEmpty
        let hasA = !(self.alternativeOptions ?? []).isEmpty
        self.detailLoaded = hasLc || hasQ || hasA
    }

    struct HiddenRisk: Codable, Identifiable {
        let id: String
        let riskType: String
        let ingredient: String?
        let confidence: String?
        let reason: String?
        let questionToAsk: String?

        enum CodingKeys: String, CodingKey {
            case riskType, ingredient, confidence, reason, questionToAsk
        }

        init(from dict: [String: Any], index: Int) {
            self.riskType = dict["riskType"] as? String ?? "Other"
            self.ingredient = dict["ingredient"] as? String
            self.confidence = dict["confidence"] as? String
            self.reason = dict["reason"] as? String
            self.questionToAsk = dict["questionToAsk"] as? String
            self.id = "\(self.riskType)_\(self.ingredient ?? "")_\(index)"
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            self.riskType = try container.decodeIfPresent(String.self, forKey: .riskType) ?? "Other"
            self.ingredient = try container.decodeIfPresent(String.self, forKey: .ingredient)
            self.confidence = try container.decodeIfPresent(String.self, forKey: .confidence)
            self.reason = try container.decodeIfPresent(String.self, forKey: .reason)
            self.questionToAsk = try container.decodeIfPresent(String.self, forKey: .questionToAsk)
            self.id = "\(self.riskType)_\(self.ingredient ?? "")"
        }
    }

    struct SafetyAssessment: Codable {
        let isLikelySafe: Bool?
        let confidence: Double?
        let confidenceLevel: String?
        let recommendation: String?
        let primaryConcerns: [String]?

        init(from dict: [String: Any]) {
            self.isLikelySafe = dict["isLikelySafe"] as? Bool
            // Handle both Int and Double from JSON
            if let dbl = dict["confidence"] as? Double {
                self.confidence = dbl
            } else if let intVal = dict["confidence"] as? Int {
                self.confidence = Double(intVal)
            } else {
                self.confidence = nil
            }
            self.confidenceLevel = dict["confidenceLevel"] as? String
            self.recommendation = dict["recommendation"] as? String
            self.primaryConcerns = dict["primaryConcerns"] as? [String]
        }

        init(isLikelySafe: Bool?, confidence: Double?, confidenceLevel: String?, recommendation: String?, primaryConcerns: [String]?) {
            self.isLikelySafe = isLikelySafe
            self.confidence = confidence
            self.confidenceLevel = confidenceLevel
            self.recommendation = recommendation
            self.primaryConcerns = primaryConcerns
        }
    }
}
