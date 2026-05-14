//
//  Theme.swift
//  Ethica
//
//  Premium Design System - Colors, Surfaces, Gradients
//  Premium & Sophisticated aesthetic with dark theme
//

import SwiftUI

/// Premium dark theme design system for Ethica
/// Glass morphism design language with sophisticated color palette
struct Theme {

    // MARK: - Primary Colors (Brand Identity)

    /// Main brand teal - used for primary actions, interactive elements
    static let primary = Color(hex: "14B8A6")

    /// Darker teal - pressed states, darker variations
    static let primaryDark = Color(hex: "0D9488")

    /// Lighter teal - highlights, hover states
    static let primaryLight = Color(hex: "5EEAD4")

    // MARK: - Surface Colors (Backgrounds & Cards)

    /// Deepest background color - main app background
    static let backgroundPrimary = Color(hex: "0A0A0A")

    /// Elevated surfaces - standard cards
    static let surfaceBase = Color(hex: "1A1A1A")

    /// Secondary surface - nested cards, panels
    static let surfaceSecondary = Color(hex: "252525")

    // MARK: - Text Colors (Hierarchy)

    /// Primary text - headlines, important content
    static let textPrimary = Color.white

    /// Secondary text - body text, labels (90% white)
    static let textSecondary = Color(hex: "E5E5E5")

    /// Tertiary text - captions, subtle info (70% white)
    static let textTertiary = Color(hex: "B3B3B3")

    /// Muted text - placeholder, disabled (50% white)
    static let textMuted = Color(hex: "808080")

    // MARK: - Semantic Colors (Status & Feedback)

    /// Success - safe products, positive actions
    static let success = Color(hex: "10B981")

    /// Warning - caution, potential issues
    static let warning = Color(hex: "F59E0B")

    /// Error - violations, danger
    static let error = Color(hex: "EF4444")

    /// Info - informational messages
    static let info = Color(hex: "3B82F6")

    /// Purple accent - special features (Plate Check, AR)
    static let accent = Color(hex: "8B5CF6")

    // MARK: - Gradients (Premium Effects)

    /// Hero gradient - primary brand gradient (teal)
    static let gradientHero = LinearGradient(
        colors: [Color(hex: "14B8A6"), Color(hex: "0D9488")],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    /// Accent gradient - purple to blue (special features)
    static let gradientAccent = LinearGradient(
        colors: [Color(hex: "8B5CF6"), Color(hex: "3B82F6")],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    /// Shimmer gradient - loading effects
    static let gradientShimmer = LinearGradient(
        colors: [
            Color.clear,
            Color.white.opacity(0.1),
            Color.clear
        ],
        startPoint: .leading,
        endPoint: .trailing
    )

    /// Success gradient (safe verdict)
    static let gradientSuccess = LinearGradient(
        colors: [Color(hex: "10B981"), Color(hex: "34D399")],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    /// Error gradient (unsafe verdict)
    static let gradientError = LinearGradient(
        colors: [Color(hex: "EF4444"), Color(hex: "DC2626")],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    // MARK: - Shadows (Depth & Elevation)

    /// Subtle shadow for low elevation
    static let shadowSubtle = Shadow(
        color: Color.black.opacity(0.2),
        radius: 10,
        x: 0,
        y: 4
    )

    /// Medium shadow for cards
    static let shadowMedium = Shadow(
        color: Color.black.opacity(0.3),
        radius: 20,
        x: 0,
        y: 10
    )

    /// Strong shadow for modals, floating elements
    static let shadowStrong = Shadow(
        color: Color.black.opacity(0.4),
        radius: 30,
        x: 0,
        y: 15
    )

    // MARK: - Helper Types

    struct Shadow {
        let color: Color
        let radius: CGFloat
        let x: CGFloat
        let y: CGFloat
    }
}

// MARK: - View Modifiers for Glass Effects

extension View {
    /// Apply primary glass morphism effect
    func glassMorphismPrimary(cornerRadius: CGFloat = 20) -> some View {
        self
            .background(
                ZStack {
                    RoundedRectangle(cornerRadius: cornerRadius)
                        .fill(Color.white.opacity(0.05))

                    RoundedRectangle(cornerRadius: cornerRadius)
                        .fill(.ultraThinMaterial)

                    RoundedRectangle(cornerRadius: cornerRadius)
                        .strokeBorder(Color.white.opacity(0.1), lineWidth: 1)
                }
            )
            .shadow(
                color: Theme.shadowMedium.color,
                radius: Theme.shadowMedium.radius,
                x: Theme.shadowMedium.x,
                y: Theme.shadowMedium.y
            )
    }

    /// Apply secondary glass morphism effect
    func glassMorphismSecondary(cornerRadius: CGFloat = 16) -> some View {
        self
            .background(
                ZStack {
                    RoundedRectangle(cornerRadius: cornerRadius)
                        .fill(Color.white.opacity(0.03))

                    RoundedRectangle(cornerRadius: cornerRadius)
                        .fill(.ultraThinMaterial)

                    RoundedRectangle(cornerRadius: cornerRadius)
                        .strokeBorder(Color.white.opacity(0.08), lineWidth: 1)
                }
            )
            .shadow(
                color: Theme.shadowSubtle.color,
                radius: Theme.shadowSubtle.radius,
                x: Theme.shadowSubtle.x,
                y: Theme.shadowSubtle.y
            )
    }

    /// Apply tertiary glass morphism effect (most subtle)
    func glassMorphismTertiary(cornerRadius: CGFloat = 12) -> some View {
        self
            .background(
                ZStack {
                    RoundedRectangle(cornerRadius: cornerRadius)
                        .fill(Color.white.opacity(0.02))

                    RoundedRectangle(cornerRadius: cornerRadius)
                        .fill(.thinMaterial)

                    RoundedRectangle(cornerRadius: cornerRadius)
                        .strokeBorder(Color.white.opacity(0.05), lineWidth: 1)
                }
            )
    }
}

// MARK: - Semantic Color Helpers

extension Theme {
    /// Get color for health score (0-100)
    static func healthScoreColor(_ score: Double) -> Color {
        if score >= 70 {
            return success
        } else if score >= 50 {
            return warning
        } else {
            return error
        }
    }

    /// Get gradient for health score
    static func healthScoreGradient(_ score: Double) -> LinearGradient {
        if score >= 70 {
            return gradientSuccess
        } else if score >= 50 {
            return LinearGradient(
                colors: [warning, Color(hex: "FBBF24")],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        } else {
            return gradientError
        }
    }

    /// Get color for environmental impact (lower is better)
    static func impactColor(_ value: Double, threshold: (low: Double, high: Double)) -> Color {
        if value <= threshold.low {
            return success
        } else if value <= threshold.high {
            return warning
        } else {
            return error
        }
    }
}
