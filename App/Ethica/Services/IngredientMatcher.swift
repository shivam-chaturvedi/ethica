//
//  IngredientMatcher.swift
//  Ethica
//
//  Lightweight, deterministic ingredient -> preference matcher.
//  Implements normalization, tokenization, simple singularization and
//  word-boundary matching so that "pineapple" does not match "apple".
//
import Foundation

struct MatchedIngredient: Codable {
    let ingredient: String
    let matchedPreference: String
    let reason: String
    let source: String // e.g. "client"
    let confidence: Double
}

enum IngredientMatcher {
    // Small synonym map for common variants; expand as needed.
    private static let synonyms: [String: String] = [
        "egg whites": "egg",
        "egg white": "egg",
        "peanut oil": "peanut",
        "soy protein": "soy",
        "wheat flour": "wheat",
        "milk powder": "milk",
        "almond oil": "almond",
        "coconut oil": "coconut"
    ]

    private static func normalize(_ s: String) -> String {
        var s = s.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        // Remove punctuation except spaces
        s = s.components(separatedBy: CharacterSet.punctuationCharacters).joined(separator: " ")
        // Collapse multiple spaces
        while s.contains("  ") { s = s.replacingOccurrences(of: "  ", with: " ") }
        return s
    }

    private static func canonicalToken(_ token: String) -> String {
        let t = token.trimmingCharacters(in: .whitespacesAndNewlines)
        if let mapped = synonyms[t] { return mapped }
        // rudimentary singularization: drop trailing 's' for tokens > 3 chars
        if t.count > 3 && t.hasSuffix("s") {
            let end = t.index(before: t.endIndex)
            return String(t[..<end])
        }
        return t
    }

    private static func tokens(from s: String) -> [String] {
        let normalized = normalize(s)
        return normalized.split(separator: " ").map { canonicalToken(String($0)) }
    }

    // Returns a list of MatchedIngredient with ingredient=original ingredient string
    // matchedPreference=the user preference that matched (normalized), reason=human-readable explanation
    static func match(ingredients: [String], preferences: [String]) -> [MatchedIngredient] {
        var results: [MatchedIngredient] = []
        // Normalize preferences up front
        let prefTokensList: [(orig: String, tokens: [String])] = preferences.compactMap { pref in
            let n = normalize(pref)
            guard !n.isEmpty else { return nil }
            return (orig: pref, tokens: tokens(from: n))
        }

        for ingredient in ingredients {
            let ingNorm = normalize(ingredient)
            let ingTokens = tokens(from: ingNorm)
            // build a lookup set for quick exact token checks
            let ingSet = Set(ingTokens)

            for pref in prefTokensList {
                if pref.tokens.isEmpty { continue }

                // If preference is multi-token (e.g., "egg white"), check that all tokens are present
                if pref.tokens.count > 1 {
                    let allPresent = pref.tokens.allSatisfy { ingSet.contains($0) }
                    if allPresent {
                        let reason = "matched tokens: \(pref.tokens.joined(separator: ", "))"
                        results.append(MatchedIngredient(ingredient: ingredient, matchedPreference: pref.orig, reason: reason, source: "client", confidence: 0.9))
                        continue
                    }
                    // Also attempt phrase match using word-boundary regex to catch exact phrase
                    if let _ = ingNorm.range(of: "\\b\(NSRegularExpression.escapedPattern(for: pref.orig))\\b", options: .regularExpression) {
                        let reason = "matched phrase: \(pref.orig)"
                        results.append(MatchedIngredient(ingredient: ingredient, matchedPreference: pref.orig, reason: reason, source: "client", confidence: 0.95))
                        continue
                    }
                } else {
                    // single token preference: check word boundary equality to avoid substrings
                    let token = pref.tokens[0]
                    if ingSet.contains(token) {
                        let reason = "matched token: \(token)"
                        results.append(MatchedIngredient(ingredient: ingredient, matchedPreference: pref.orig, reason: reason, source: "client", confidence: 0.9))
                        continue
                    }
                    // Also check whole-ingredient word-boundary regex for safety
                    let pattern = "\\b\(NSRegularExpression.escapedPattern(for: token))\\b"
                    if let _ = ingNorm.range(of: pattern, options: .regularExpression) {
                        let reason = "matched regex token: \(token)"
                        results.append(MatchedIngredient(ingredient: ingredient, matchedPreference: pref.orig, reason: reason, source: "client", confidence: 0.8))
                        continue
                    }
                }
            }
        }

        // Deduplicate by ingredient+preference
        var seen = Set<String>()
        let unique = results.filter { m in
            let key = "\(m.ingredient.lowercased())|\(m.matchedPreference.lowercased())"
            if seen.contains(key) { return false }
            seen.insert(key)
            return true
        }

        return unique
    }
}
