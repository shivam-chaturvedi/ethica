//
//  ColorPalette.swift
//  Ethica
//
//  Colors consolidated into Theme.swift
//  Kept for backward compatibility - references Theme definitions
//

import SwiftUI

// Text color extensions are defined here for backward compatibility.
// Primary color definitions live in Theme.swift.
// These match the Theme.textSecondary / textTertiary / textMuted values.
extension Color {
    static let textSecondary = Theme.textSecondary
    static let textTertiary = Theme.textTertiary
    static let textMuted = Theme.textMuted
}
