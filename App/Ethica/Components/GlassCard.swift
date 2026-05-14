//
//  GlassCard.swift
//  Ethica
//
//  Reusable glass morphism card component
//  Provides consistent styling across the app
//

import SwiftUI

/// Glass morphism card with configurable styling
struct GlassCard<Content: View>: View {

    // MARK: - Properties

    let variant: GlassCardVariant
    let cornerRadius: CGFloat
    let padding: CGFloat
    let shadowLevel: ShadowLevel
    let content: Content

    // MARK: - Initializers

    /// Create glass card with default styling
    init(
        variant: GlassCardVariant = .primary,
        cornerRadius: CGFloat? = nil,
        padding: CGFloat = Spacing.cardPadding,
        shadowLevel: ShadowLevel = .medium,
        @ViewBuilder content: () -> Content
    ) {
        self.variant = variant
        self.cornerRadius = cornerRadius ?? variant.defaultRadius
        self.padding = padding
        self.shadowLevel = shadowLevel
        self.content = content()
    }

    // MARK: - Body

    var body: some View {
        content
            .padding(padding)
            .background(
                ZStack {
                    RoundedRectangle(cornerRadius: cornerRadius)
                        .fill(variant.backgroundColor)

                    RoundedRectangle(cornerRadius: cornerRadius)
                        .fill(variant.materialEffect)

                    RoundedRectangle(cornerRadius: cornerRadius)
                        .strokeBorder(variant.borderColor, lineWidth: variant.borderWidth)
                }
            )
            .shadow(
                color: shadowLevel.shadow.color,
                radius: shadowLevel.shadow.radius,
                x: shadowLevel.shadow.x,
                y: shadowLevel.shadow.y
            )
    }
}

// MARK: - Glass Card Variants

enum GlassCardVariant {
    case primary
    case secondary
    case tertiary
    case accent
    case success
    case warning
    case error

    var defaultRadius: CGFloat {
        switch self {
        case .primary: return Spacing.radiusLG
        case .secondary: return Spacing.radiusMD
        case .tertiary: return Spacing.radiusSM
        case .accent, .success, .warning, .error: return Spacing.radiusMD
        }
    }

    var backgroundColor: Color {
        switch self {
        case .primary:
            return Color.white.opacity(0.05)
        case .secondary:
            return Color.white.opacity(0.03)
        case .tertiary:
            return Color.white.opacity(0.02)
        case .accent:
            return Theme.accent.opacity(0.1)
        case .success:
            return Theme.success.opacity(0.1)
        case .warning:
            return Theme.warning.opacity(0.1)
        case .error:
            return Theme.error.opacity(0.1)
        }
    }

    var materialEffect: Material {
        switch self {
        case .primary, .accent, .success, .warning, .error:
            return .ultraThinMaterial
        case .secondary:
            return .ultraThinMaterial
        case .tertiary:
            return .thinMaterial
        }
    }

    var borderColor: Color {
        switch self {
        case .primary:
            return Color.white.opacity(0.1)
        case .secondary:
            return Color.white.opacity(0.08)
        case .tertiary:
            return Color.white.opacity(0.05)
        case .accent:
            return Theme.accent.opacity(0.3)
        case .success:
            return Theme.success.opacity(0.3)
        case .warning:
            return Theme.warning.opacity(0.3)
        case .error:
            return Theme.error.opacity(0.3)
        }
    }

    var borderWidth: CGFloat {
        switch self {
        case .primary, .secondary, .tertiary:
            return 1
        case .accent, .success, .warning, .error:
            return 1.5
        }
    }
}

// MARK: - Shadow Levels

enum ShadowLevel {
    case none
    case subtle
    case medium
    case strong

    var shadow: Theme.Shadow {
        switch self {
        case .none:
            return Theme.Shadow(color: .clear, radius: 0, x: 0, y: 0)
        case .subtle:
            return Theme.shadowSubtle
        case .medium:
            return Theme.shadowMedium
        case .strong:
            return Theme.shadowStrong
        }
    }
}

// MARK: - Convenience Initializers

extension GlassCard {
    /// Create primary glass card (most common)
    static func primary(@ViewBuilder content: @escaping () -> Content) -> GlassCard {
        GlassCard(variant: .primary, content: content)
    }

    /// Create secondary glass card (nested content)
    static func secondary(@ViewBuilder content: @escaping () -> Content) -> GlassCard {
        GlassCard(variant: .secondary, content: content)
    }

    /// Create tertiary glass card (most subtle)
    static func tertiary(@ViewBuilder content: @escaping () -> Content) -> GlassCard {
        GlassCard(variant: .tertiary, content: content)
    }

    /// Create accent card (special features)
    static func accent(@ViewBuilder content: @escaping () -> Content) -> GlassCard {
        GlassCard(variant: .accent, content: content)
    }

    /// Create success card (safe products)
    static func success(@ViewBuilder content: @escaping () -> Content) -> GlassCard {
        GlassCard(variant: .success, content: content)
    }

    /// Create warning card (caution items)
    static func warning(@ViewBuilder content: @escaping () -> Content) -> GlassCard {
        GlassCard(variant: .warning, content: content)
    }

    /// Create error card (violations)
    static func error(@ViewBuilder content: @escaping () -> Content) -> GlassCard {
        GlassCard(variant: .error, content: content)
    }
}

// MARK: - View Extensions

extension View {
    /// Wrap view in primary glass card
    func glassCard(
        variant: GlassCardVariant = .primary,
        cornerRadius: CGFloat? = nil,
        padding: CGFloat = Spacing.cardPadding,
        shadowLevel: ShadowLevel = .medium
    ) -> some View {
        GlassCard(
            variant: variant,
            cornerRadius: cornerRadius,
            padding: padding,
            shadowLevel: shadowLevel
        ) {
            self
        }
    }
}

// MARK: - Preview

#Preview("Glass Card Variants") {
    ScrollView {
        VStack(spacing: Spacing.lg) {
            // Primary Card
            GlassCard.primary {
                VStack(alignment: .leading, spacing: Spacing.sm) {
                    Text("Primary Card")
                        .textStyleH3()
                    Text("Most elevated surface with strong glass effect")
                        .textStyleBody()
                }
            }

            // Secondary Card
            GlassCard.secondary {
                VStack(alignment: .leading, spacing: Spacing.sm) {
                    Text("Secondary Card")
                        .textStyleH3()
                    Text("Nested content with medium glass effect")
                        .textStyleBody()
                }
            }

            // Tertiary Card
            GlassCard.tertiary {
                VStack(alignment: .leading, spacing: Spacing.sm) {
                    Text("Tertiary Card")
                        .textStyleH3()
                    Text("Most subtle effect for backgrounds")
                        .textStyleBody()
                }
            }

            // Accent Card
            GlassCard.accent {
                VStack(alignment: .leading, spacing: Spacing.sm) {
                    Text("Accent Card")
                        .textStyleH3()
                    Text("Special features like Plate Check, AR Scanner")
                        .textStyleBody()
                }
            }

            // Success Card
            GlassCard.success {
                HStack {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(Theme.success)
                    Text("Product is safe for your dietary preferences")
                        .textStyleBody()
                }
            }

            // Warning Card
            GlassCard.warning {
                HStack {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(Theme.warning)
                    Text("Product contains ambiguous ingredients")
                        .textStyleBody()
                }
            }

            // Error Card
            GlassCard.error {
                HStack {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(Theme.error)
                    Text("Product violates your dietary restrictions")
                        .textStyleBody()
                }
            }
        }
        .padding(Spacing.screenHorizontal)
    }
    .background(Theme.backgroundPrimary)
    .preferredColorScheme(.dark)
}

#Preview("Using View Extension") {
    VStack(spacing: Spacing.lg) {
        Text("Content wrapped with .glassCard()")
            .textStyleH3()
            .glassCard()

        HStack {
            Text("Success")
            Image(systemName: "checkmark")
        }
        .glassCard(variant: .success, padding: Spacing.md)
    }
    .padding(Spacing.screenHorizontal)
    .background(Theme.backgroundPrimary)
    .preferredColorScheme(.dark)
}
