//
//  Spacing.swift
//  Ethica
//
//  8pt Spacing System
//  Consistent spacing and layout across the app
//

import SwiftUI

/// 8pt-based spacing system for consistent layouts
struct Spacing {

    // MARK: - Base Spacing Values (8pt System)

    /// Extra small: 4pt - tight spacing
    static let xs: CGFloat = 4

    /// Small: 8pt - compact spacing
    static let sm: CGFloat = 8

    /// Medium: 16pt - standard spacing (DEFAULT)
    static let md: CGFloat = 16

    /// Large: 24pt - comfortable spacing
    static let lg: CGFloat = 24

    /// Extra large: 32pt - generous spacing
    static let xl: CGFloat = 32

    /// 2XL: 48pt - major section spacing
    static let xxl: CGFloat = 48

    /// 3XL: 64pt - hero section spacing
    static let xxxl: CGFloat = 64

    // MARK: - Semantic Spacing

    /// Card padding - internal padding for cards
    static let cardPadding: CGFloat = md // 16pt

    /// Card spacing - gap between cards
    static let cardSpacing: CGFloat = lg // 24pt

    /// Screen horizontal padding - side margins
    static let screenHorizontal: CGFloat = 20

    /// Screen vertical padding - top/bottom margins
    static let screenVertical: CGFloat = lg // 24pt

    /// Button padding - internal button padding
    static let buttonPadding = EdgeInsets(top: 12, leading: lg, bottom: 12, trailing: lg)

    /// Small button padding
    static let buttonPaddingSmall = EdgeInsets(top: 8, leading: md, bottom: 8, trailing: md)

    /// Large button padding
    static let buttonPaddingLarge = EdgeInsets(top: md, leading: xl, bottom: md, trailing: xl)

    // MARK: - Corner Radius

    /// Extra small radius - 8pt
    static let radiusXS: CGFloat = 8

    /// Small radius - 12pt
    static let radiusSM: CGFloat = 12

    /// Medium radius - 16pt (DEFAULT for cards)
    static let radiusMD: CGFloat = 16

    /// Large radius - 20pt (glass morphism cards)
    static let radiusLG: CGFloat = 20

    /// Extra large radius - 24pt
    static let radiusXL: CGFloat = 24

    /// Pill radius - fully rounded
    static let radiusPill: CGFloat = 999

    /// Circle radius - fully circular
    static let radiusCircle: CGFloat = .infinity
}

// MARK: - Padding View Modifiers

extension View {
    /// Apply standard card padding (16pt all sides)
    func cardPadding() -> some View {
        self.padding(Spacing.cardPadding)
    }

    /// Apply screen horizontal padding (20pt sides)
    func screenHorizontalPadding() -> some View {
        self.padding(.horizontal, Spacing.screenHorizontal)
    }

    /// Apply screen vertical padding (24pt top/bottom)
    func screenVerticalPadding() -> some View {
        self.padding(.vertical, Spacing.screenVertical)
    }

    /// Apply full screen padding (20pt horizontal, 24pt vertical)
    func screenPadding() -> some View {
        self
            .padding(.horizontal, Spacing.screenHorizontal)
            .padding(.vertical, Spacing.screenVertical)
    }

    /// Apply spacing based on size
    func spacing(_ size: SpacingSize) -> some View {
        self.padding(size.value)
    }
}

// MARK: - Spacing Size Enum

enum SpacingSize {
    case xs
    case sm
    case md
    case lg
    case xl
    case xxl
    case xxxl

    var value: CGFloat {
        switch self {
        case .xs: return Spacing.xs
        case .sm: return Spacing.sm
        case .md: return Spacing.md
        case .lg: return Spacing.lg
        case .xl: return Spacing.xl
        case .xxl: return Spacing.xxl
        case .xxxl: return Spacing.xxxl
        }
    }
}

// MARK: - Layout Helpers

extension Spacing {
    /// Safe area insets for different screen sections
    struct SafeArea {
        static let top: CGFloat = 0
        static let bottom: CGFloat = 0
        static let horizontal: CGFloat = 0
    }

    /// Standard heights for UI elements
    struct Height {
        /// Minimum touch target height
        static let touchTarget: CGFloat = 44

        /// Standard button height
        static let button: CGFloat = 48

        /// Large button height
        static let buttonLarge: CGFloat = 56

        /// Small button height
        static let buttonSmall: CGFloat = 36

        /// Standard input field height
        static let input: CGFloat = 48

        /// Tab bar height
        static let tabBar: CGFloat = 56

        /// Navigation bar height
        static let navigationBar: CGFloat = 44

        /// Card minimum height
        static let cardMinimum: CGFloat = 80
    }

    /// Standard widths for UI elements
    struct Width {
        /// Maximum content width for readability
        static let maxContent: CGFloat = 760

        /// Maximum card width
        static let maxCard: CGFloat = 500

        /// Minimum button width
        static let buttonMinimum: CGFloat = 120
    }
}

// MARK: - Size Helper View Modifiers

extension View {
    /// Set fixed button height
    func buttonHeight(_ size: ButtonSize = .standard) -> some View {
        self.frame(height: size.height)
    }

    /// Set minimum touch target size
    func touchTarget() -> some View {
        self.frame(minWidth: Spacing.Height.touchTarget, minHeight: Spacing.Height.touchTarget)
    }

    /// Set maximum content width for readability
    func maxContentWidth() -> some View {
        self.frame(maxWidth: Spacing.Width.maxContent)
    }
}

// MARK: - Button Size Enum

enum ButtonSize {
    case small
    case standard
    case large

    var height: CGFloat {
        switch self {
        case .small: return Spacing.Height.buttonSmall
        case .standard: return Spacing.Height.button
        case .large: return Spacing.Height.buttonLarge
        }
    }

    var padding: EdgeInsets {
        switch self {
        case .small: return Spacing.buttonPaddingSmall
        case .standard: return Spacing.buttonPadding
        case .large: return Spacing.buttonPaddingLarge
        }
    }

    var font: Font {
        switch self {
        case .small: return Typography.bodySmall
        case .standard: return Typography.body
        case .large: return Typography.bodyLarge
        }
    }

    var iconFont: Font {
        switch self {
        case .small: return .system(size: 14, weight: .medium)
        case .standard: return .system(size: 16, weight: .medium)
        case .large: return .system(size: 18, weight: .medium)
        }
    }

    var cornerRadius: CGFloat {
        switch self {
        case .small: return Spacing.radiusSM
        case .standard: return Spacing.radiusMD
        case .large: return Spacing.radiusLG
        }
    }
}
