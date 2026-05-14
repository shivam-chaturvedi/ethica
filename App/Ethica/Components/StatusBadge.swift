//
//  StatusBadge.swift
//  Ethica
//
//  Pill-shaped badge for status indicators, tags, and labels
//  Used for dietary tags, allergens, certifications, etc.
//

import SwiftUI

/// Pill-shaped status badge with icon and color variants
struct StatusBadge: View {

    // MARK: - Properties

    let text: String
    let icon: String?
    let variant: BadgeVariant
    let size: BadgeSize

    // MARK: - Initializers

    init(
        _ text: String,
        icon: String? = nil,
        variant: BadgeVariant = .neutral,
        size: BadgeSize = .medium
    ) {
        self.text = text
        self.icon = icon
        self.variant = variant
        self.size = size
    }

    // MARK: - Body

    var body: some View {
        HStack(spacing: size.spacing) {
            if let icon = icon {
                Image(systemName: icon)
                    .font(size.iconFont)
                    .foregroundColor(variant.foregroundColor)
            }

            Text(text)
                .font(size.font)
                .foregroundColor(variant.foregroundColor)
        }
        .padding(.horizontal, size.horizontalPadding)
        .padding(.vertical, size.verticalPadding)
        .background(
            Capsule()
                .fill(variant.backgroundColor)
        )
        .overlay(
            Capsule()
                .strokeBorder(variant.borderColor, lineWidth: variant.borderWidth)
        )
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(text)
    }
}

// MARK: - Badge Variants

extension StatusBadge {
    enum BadgeVariant {
        case success
        case warning
        case error
        case info
        case neutral
        case primary
        case accent
        case vegan
        case jain
        case glutenFree
        case gmo
        case custom(backgroundColor: Color, foregroundColor: Color, borderColor: Color?)

        var backgroundColor: Color {
            switch self {
            case .success:
                return Theme.success.opacity(0.2)
            case .warning:
                return Theme.warning.opacity(0.2)
            case .error:
                return Theme.error.opacity(0.2)
            case .info:
                return Theme.info.opacity(0.2)
            case .neutral:
                return Color.white.opacity(0.1)
            case .primary:
                return Theme.primary.opacity(0.2)
            case .accent:
                return Theme.accent.opacity(0.2)
            case .vegan:
                return Theme.success.opacity(0.2)
            case .jain:
                return Theme.warning.opacity(0.2)
            case .glutenFree:
                return Theme.info.opacity(0.2)
            case .gmo:
                return Theme.error.opacity(0.2)
            case .custom(let bg, _, _):
                return bg
            }
        }

        var foregroundColor: Color {
            switch self {
            case .success:
                return Theme.success
            case .warning:
                return Theme.warning
            case .error:
                return Theme.error
            case .info:
                return Theme.info
            case .neutral:
                return Theme.textSecondary
            case .primary:
                return Theme.primary
            case .accent:
                return Theme.accent
            case .vegan:
                return Theme.success
            case .jain:
                return Theme.warning
            case .glutenFree:
                return Theme.info
            case .gmo:
                return Theme.error
            case .custom(_, let fg, _):
                return fg
            }
        }

        var borderColor: Color {
            switch self {
            case .success:
                return Theme.success.opacity(0.4)
            case .warning:
                return Theme.warning.opacity(0.4)
            case .error:
                return Theme.error.opacity(0.4)
            case .info:
                return Theme.info.opacity(0.4)
            case .neutral:
                return Color.white.opacity(0.2)
            case .primary:
                return Theme.primary.opacity(0.4)
            case .accent:
                return Theme.accent.opacity(0.4)
            case .vegan:
                return Theme.success.opacity(0.4)
            case .jain:
                return Theme.warning.opacity(0.4)
            case .glutenFree:
                return Theme.info.opacity(0.4)
            case .gmo:
                return Theme.error.opacity(0.4)
            case .custom(_, _, let border):
                return border ?? .clear
            }
        }

        var borderWidth: CGFloat {
            switch self {
            case .custom(_, _, let border):
                return border == nil ? 0 : 1
            default:
                return 1
            }
        }
    }

    enum BadgeSize {
        case small
        case medium
        case large

        var font: Font {
            switch self {
            case .small:
                return Typography.caption
            case .medium:
                return Typography.bodySmall
            case .large:
                return Typography.body
            }
        }

        var iconFont: Font {
            switch self {
            case .small:
                return .system(size: 10, weight: .medium)
            case .medium:
                return .system(size: 12, weight: .medium)
            case .large:
                return .system(size: 14, weight: .medium)
            }
        }

        var horizontalPadding: CGFloat {
            switch self {
            case .small:
                return 8
            case .medium:
                return 12
            case .large:
                return 16
            }
        }

        var verticalPadding: CGFloat {
            switch self {
            case .small:
                return 4
            case .medium:
                return 6
            case .large:
                return 8
            }
        }

        var spacing: CGFloat {
            switch self {
            case .small:
                return 4
            case .medium:
                return 6
            case .large:
                return 8
            }
        }
    }
}

// MARK: - Convenience Initializers

extension StatusBadge {
    /// Success badge (green)
    static func success(_ text: String, icon: String? = "checkmark.circle.fill") -> StatusBadge {
        StatusBadge(text, icon: icon, variant: .success)
    }

    /// Warning badge (orange)
    static func warning(_ text: String, icon: String? = "exclamationmark.triangle.fill") -> StatusBadge {
        StatusBadge(text, icon: icon, variant: .warning)
    }

    /// Error badge (red)
    static func error(_ text: String, icon: String? = "xmark.circle.fill") -> StatusBadge {
        StatusBadge(text, icon: icon, variant: .error)
    }

    /// Info badge (blue)
    static func info(_ text: String, icon: String? = "info.circle.fill") -> StatusBadge {
        StatusBadge(text, icon: icon, variant: .info)
    }

    /// Neutral badge (gray)
    static func neutral(_ text: String, icon: String? = nil) -> StatusBadge {
        StatusBadge(text, icon: icon, variant: .neutral)
    }

    /// Vegan badge
    static func vegan(icon: String? = "leaf.fill") -> StatusBadge {
        StatusBadge("Vegan", icon: icon, variant: .vegan)
    }

    /// Jain badge
    static func jain(icon: String? = "aqi.medium") -> StatusBadge {
        StatusBadge("Jain", icon: icon, variant: .jain)
    }

    /// Gluten-Free badge
    static func glutenFree(icon: String? = "g.circle.fill") -> StatusBadge {
        StatusBadge("Gluten-Free", icon: icon, variant: .glutenFree)
    }

    /// GMO badge
    static func gmo(icon: String? = "exclamationmark.shield.fill") -> StatusBadge {
        StatusBadge("Contains GMO", icon: icon, variant: .gmo)
    }
}

// MARK: - Preview

#if swift(>=5.9)
@available(iOS 17.0, *)
#Preview("Badge Variants") {
    ScrollView {
        VStack(alignment: .leading, spacing: Spacing.lg) {
            // Status badges
            VStack(alignment: .leading, spacing: Spacing.md) {
                Text("Status Badges")
                    .textStyleH3()

                FlowLayout(spacing: Spacing.sm) {
                    StatusBadge.success("Safe")
                    StatusBadge.warning("Caution")
                    StatusBadge.error("Violation")
                    StatusBadge.info("Info")
                    StatusBadge.neutral("Neutral")
                }
            }

            Divider()

            // Dietary badges
            VStack(alignment: .leading, spacing: Spacing.md) {
                Text("Dietary Badges")
                    .textStyleH3()

                FlowLayout(spacing: Spacing.sm) {
                    StatusBadge.vegan()
                    StatusBadge.jain()
                    StatusBadge.glutenFree()
                    StatusBadge("Halal", icon: "moon.fill", variant: .primary)
                    StatusBadge("Kosher", icon: "star.fill", variant: .info)
                    StatusBadge("Organic", icon: "leaf.fill", variant: .success)
                }
            }

            Divider()

            // Warning badges
            VStack(alignment: .leading, spacing: Spacing.md) {
                Text("Warning Badges")
                    .textStyleH3()

                FlowLayout(spacing: Spacing.sm) {
                    StatusBadge.gmo()
                    StatusBadge("Contains Allergens", icon: "exclamationmark.triangle.fill", variant: .error)
                    StatusBadge("High Sugar", icon: "cube.fill", variant: .warning)
                    StatusBadge("Processed", icon: "gearshape.fill", variant: .neutral)
                }
            }

            Divider()

            // Badge sizes
            VStack(alignment: .leading, spacing: Spacing.md) {
                Text("Badge Sizes")
                    .textStyleH3()

                VStack(alignment: .leading, spacing: Spacing.sm) {
                    StatusBadge("Large Badge", icon: "star.fill", variant: .primary, size: .large)
                    StatusBadge("Medium Badge", icon: "star.fill", variant: .primary, size: .medium)
                    StatusBadge("Small Badge", icon: "star.fill", variant: .primary, size: .small)
                }
            }

            Divider()

            // Without icons
            VStack(alignment: .leading, spacing: Spacing.md) {
                Text("Text Only")
                    .textStyleH3()

                FlowLayout(spacing: Spacing.sm) {
                    StatusBadge("Vegan", variant: .vegan)
                    StatusBadge("Jain", variant: .jain)
                    StatusBadge("Organic", variant: .success)
                    StatusBadge("Non-GMO", variant: .primary)
                }
            }

            Divider()

            // On glass card
            VStack(alignment: .leading, spacing: Spacing.md) {
                Text("On Glass Card")
                    .textStyleH3()

                GlassCard.primary {
                    VStack(alignment: .leading, spacing: Spacing.md) {
                        Text("Product Name")
                            .textStyleH2()

                        FlowLayout(spacing: Spacing.sm) {
                            StatusBadge.success("Safe")
                            StatusBadge.vegan()
                            StatusBadge("Organic", icon: "leaf.fill", variant: .success)
                            StatusBadge("Non-GMO", variant: .primary)
                        }

                        Text("This product meets all your dietary preferences")
                            .textStyleBody()
                    }
                }
            }
        }
        .padding(Spacing.screenHorizontal)
    }
    .background(Theme.backgroundPrimary)
    .preferredColorScheme(.dark)
}

#endif

// MARK: - Flow Layout Helper

/// Simple flow layout for wrapping badges
@available(iOS 16.0, *)
struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let result = FlowResult(
            in: proposal.replacingUnspecifiedDimensions().width,
            subviews: subviews,
            spacing: spacing
        )
        return result.size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = FlowResult(
            in: bounds.width,
            subviews: subviews,
            spacing: spacing
        )
        for (index, subview) in subviews.enumerated() {
            subview.place(at: CGPoint(x: bounds.minX + result.positions[index].x, y: bounds.minY + result.positions[index].y), proposal: .unspecified)
        }
    }

    struct FlowResult {
        var size: CGSize = .zero
        var positions: [CGPoint] = []

        init(in maxWidth: CGFloat, subviews: Subviews, spacing: CGFloat) {
            var x: CGFloat = 0
            var y: CGFloat = 0
            var lineHeight: CGFloat = 0

            for subview in subviews {
                let size = subview.sizeThatFits(.unspecified)

                if x + size.width > maxWidth && x > 0 {
                    x = 0
                    y += lineHeight + spacing
                    lineHeight = 0
                }

                positions.append(CGPoint(x: x, y: y))
                lineHeight = max(lineHeight, size.height)
                x += size.width + spacing
            }

            self.size = CGSize(width: maxWidth, height: y + lineHeight)
        }
    }
}
