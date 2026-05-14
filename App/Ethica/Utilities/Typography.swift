//
//  Typography.swift
//  Ethica
//
//  Premium Typography System
//  Consistent text styles across the app
//

import SwiftUI

/// Typography system with hierarchical text styles
struct Typography {

    // MARK: - Display Styles (Hero Headings)

    /// Extra large display text - hero sections
    static let displayLarge = Font.system(size: 48, weight: .bold, design: .rounded)

    /// Large display text - major headings
    static let display = Font.system(size: 36, weight: .bold, design: .rounded)

    // MARK: - Heading Styles

    /// H1 - Primary section headings
    static let h1 = Font.system(size: 28, weight: .bold, design: .rounded)

    /// H2 - Secondary section headings
    static let h2 = Font.system(size: 24, weight: .semibold, design: .rounded)

    /// H3 - Subsection headings
    static let h3 = Font.system(size: 20, weight: .semibold, design: .default)

    /// H4 - Minor headings
    static let h4 = Font.system(size: 18, weight: .medium, design: .default)

    // MARK: - Body Styles

    /// Large body text - emphasized content
    static let bodyLarge = Font.system(size: 17, weight: .regular, design: .default)

    /// Standard body text - default content
    static let body = Font.system(size: 15, weight: .regular, design: .default)

    /// Small body text - compact content
    static let bodySmall = Font.system(size: 13, weight: .regular, design: .default)

    // MARK: - UI Element Styles

    /// Large button text
    static let buttonLarge = Font.system(size: 16, weight: .semibold, design: .rounded)

    /// Standard button text
    static let button = Font.system(size: 15, weight: .medium, design: .rounded)

    /// Caption text - supplementary info
    static let caption = Font.system(size: 12, weight: .regular, design: .default)

    /// Overline text - labels, categories (uppercase)
    static let overline = Font.system(size: 11, weight: .medium, design: .default)

    // MARK: - Specialized Styles

    /// Number display - large stats, scores
    static let numberLarge = Font.system(size: 48, weight: .bold, design: .rounded).monospacedDigit()

    /// Number medium - cards, metrics
    static let numberMedium = Font.system(size: 32, weight: .bold, design: .rounded).monospacedDigit()

    /// Number small - inline stats
    static let numberSmall = Font.system(size: 20, weight: .semibold, design: .rounded).monospacedDigit()
}

// MARK: - Text Style View Modifiers

extension View {
    /// Apply display large style
    func textStyleDisplayLarge(color: Color = Theme.textPrimary) -> some View {
        self
            .font(Typography.displayLarge)
            .foregroundColor(color)
            .lineSpacing(8)
    }

    /// Apply display style
    func textStyleDisplay(color: Color = Theme.textPrimary) -> some View {
        self
            .font(Typography.display)
            .foregroundColor(color)
            .lineSpacing(6)
    }

    /// Apply H1 style
    func textStyleH1(color: Color = Theme.textPrimary) -> some View {
        self
            .font(Typography.h1)
            .foregroundColor(color)
            .lineSpacing(4)
    }

    /// Apply H2 style
    func textStyleH2(color: Color = Theme.textPrimary) -> some View {
        self
            .font(Typography.h2)
            .foregroundColor(color)
            .lineSpacing(3)
    }

    /// Apply H3 style
    func textStyleH3(color: Color = Theme.textSecondary) -> some View {
        self
            .font(Typography.h3)
            .foregroundColor(color)
            .lineSpacing(2)
    }

    /// Apply H4 style
    func textStyleH4(color: Color = Theme.textSecondary) -> some View {
        self
            .font(Typography.h4)
            .foregroundColor(color)
    }

    /// Apply body large style
    func textStyleBodyLarge(color: Color = Theme.textSecondary) -> some View {
        self
            .font(Typography.bodyLarge)
            .foregroundColor(color)
            .lineSpacing(4)
    }

    /// Apply standard body style
    func textStyleBody(color: Color = Theme.textSecondary) -> some View {
        self
            .font(Typography.body)
            .foregroundColor(color)
            .lineSpacing(3)
    }

    /// Apply small body style
    func textStyleBodySmall(color: Color = Theme.textTertiary) -> some View {
        self
            .font(Typography.bodySmall)
            .foregroundColor(color)
            .lineSpacing(2)
    }

    /// Apply caption style
    func textStyleCaption(color: Color = Theme.textTertiary) -> some View {
        self
            .font(Typography.caption)
            .foregroundColor(color)
    }

    /// Apply overline style (uppercase labels)
    @ViewBuilder
    func textStyleOverline(color: Color = Theme.textMuted) -> some View {
        if #available(iOS 16.0, *) {
            self
                .font(Typography.overline)
                .foregroundColor(color)
                .textCase(.uppercase)
                .tracking(0.5)
        } else {
            self
                .font(Typography.overline)
                .foregroundColor(color)
                .textCase(.uppercase)
        }
    }

    /// Apply large button style
    func textStyleButtonLarge(color: Color = .white) -> some View {
        self
            .font(Typography.buttonLarge)
            .foregroundColor(color)
    }

    /// Apply standard button style
    func textStyleButton(color: Color = .white) -> some View {
        self
            .font(Typography.button)
            .foregroundColor(color)
    }

    /// Apply large number style
    func textStyleNumberLarge(color: Color = Theme.textPrimary) -> some View {
        self
            .font(Typography.numberLarge)
            .foregroundColor(color)
    }

    /// Apply medium number style
    func textStyleNumberMedium(color: Color = Theme.textPrimary) -> some View {
        self
            .font(Typography.numberMedium)
            .foregroundColor(color)
    }

    /// Apply small number style
    func textStyleNumberSmall(color: Color = Theme.textPrimary) -> some View {
        self
            .font(Typography.numberSmall)
            .foregroundColor(color)
    }
}

// MARK: - Line Height Helpers

extension Typography {
    /// Calculate line height multiplier for font
    static func lineHeight(for size: CGFloat) -> CGFloat {
        switch size {
        case 0..<14: return 1.4
        case 14..<18: return 1.5
        case 18..<24: return 1.4
        case 24..<36: return 1.3
        case 36...: return 1.2
        default: return 1.5
        }
    }
}
