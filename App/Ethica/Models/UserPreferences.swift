//
//  UserPreferences.swift
//  Ethica
//
//  Created on 11/11/2025
//

import Foundation

struct UserBrandPreferences: Codable {
    let preferredBrands: [String: Int]
    let dismissedBrands: [String: Int]
    let preferredProductTypes: [String: Int]
}

struct UserPreferences: Codable {
    var selectedDiets: Set<String> = []
    var selectedAllergens: Set<String> = []
    var customDiets: [String] = []
    var customAllergens: [String] = []

    /// When true (default/relaxed), "may contain" warnings are informational only.
    /// When false (strict), cross-contamination traces are treated as UNSAFE violations.
    var mayContainSafe: Bool = true

    /// When true, GMO products are flagged as unsafe. Default false (informational only).
    /// Jain diet implicitly enables this.
    var avoidGMO: Bool = false

    /// User's display name (collected during onboarding)
    var displayName: String = ""

    // Alternative ranking priorities (0-100, sum to 100)
    var healthPriority: Double = 40.0
    var environmentPriority: Double = 40.0
    var ethicsPriority: Double = 20.0

    /// Adjust one priority slider. Only the LARGER of the two remaining sliders
    /// absorbs the change first. If it bottoms out at 0, the smaller one absorbs the rest.
    /// This means dragging one slider only visually moves one other slider (usually).
    mutating func adjustPriority(changed: String, newValue: Double) {
        let clamped = min(max(round(newValue / 5.0) * 5.0, 0), 100)

        // Work with local copies to avoid overlapping exclusive access to self
        var h = healthPriority
        var e = environmentPriority
        var t = ethicsPriority

        switch changed {
        case "health":
            let delta = clamped - h
            h = clamped
            Self.redistributeDelta(delta, &e, &t)
        case "environment":
            let delta = clamped - e
            e = clamped
            Self.redistributeDelta(delta, &h, &t)
        case "ethics":
            let delta = clamped - t
            t = clamped
            Self.redistributeDelta(delta, &h, &e)
        default:
            break
        }

        healthPriority = h
        environmentPriority = e
        ethicsPriority = t
    }

    /// Subtract delta from the larger of a/b first. If it can't absorb it all, the other takes the rest.
    private static func redistributeDelta(_ delta: Double, _ a: inout Double, _ b: inout Double) {
        guard abs(delta) > 0.01 else { return }

        // Determine which absorbs first (the larger one)
        if a >= b {
            // a absorbs first
            let newA = max(a - delta, 0)
            let absorbed = a - newA
            a = newA
            let remaining = delta - absorbed
            if remaining > 0.01 {
                b = max(b - remaining, 0)
            }
        } else {
            // b absorbs first
            let newB = max(b - delta, 0)
            let absorbed = b - newB
            b = newB
            let remaining = delta - absorbed
            if remaining > 0.01 {
                a = max(a - remaining, 0)
            }
        }

        // Snap to 5% increments
        a = round(a / 5.0) * 5.0
        b = round(b / 5.0) * 5.0
    }

    func toJSON() -> [String: Any] {
        return [
            "selectedDiets": Array(selectedDiets),
            "selectedAllergens": Array(selectedAllergens),
            "customDiets": customDiets,
            "customAllergens": customAllergens,
            "mayContainSafe": mayContainSafe,
            "avoidGMO": avoidGMO,
            "healthPriority": healthPriority,
            "environmentPriority": environmentPriority,
            "ethicsPriority": ethicsPriority
        ]
    }
}
