//
//  ExpandableSection.swift
//  Ethica
//
//  Collapsible section with smooth animations
//  Used for ingredient lists, details, etc.
//

import SwiftUI

/// Expandable/collapsible section with header and content
struct ExpandableSection<Content: View>: View {

    // MARK: - Properties

    let title: String
    let icon: String?
    let badge: String?
    let variant: SectionVariant
    let defaultExpanded: Bool
    let content: Content

    @State private var isExpanded: Bool

    // MARK: - Initializers

    init(
        _ title: String,
        icon: String? = nil,
        badge: String? = nil,
        variant: SectionVariant = .neutral,
        defaultExpanded: Bool = false,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.icon = icon
        self.badge = badge
        self.variant = variant
        self.defaultExpanded = defaultExpanded
        self.content = content()
        _isExpanded = State(initialValue: defaultExpanded)
    }

    // MARK: - Body

    var body: some View {
        VStack(spacing: 0) {
            // Header (always visible)
            Button(action: {
                withAnimation(AnimationSystem.springSmooth) {
                    isExpanded.toggle()
                }
            }) {
                HStack(spacing: Spacing.md) {
                    // Icon
                    if let icon = icon {
                        Image(systemName: icon)
                            .font(.system(size: 18, weight: .medium))
                            .foregroundColor(variant.iconColor)
                            .frame(width: 24, height: 24)
                    }

                    // Title
                    Text(title)
                        .textStyleH3(color: Theme.textPrimary)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    // Badge
                    if let badge = badge {
                        Text(badge)
                            .textStyleCaption(color: Theme.textMuted)
                            .padding(.horizontal, Spacing.sm)
                            .padding(.vertical, 4)
                            .background(
                                Capsule()
                                    .fill(Color.white.opacity(0.1))
                            )
                    }

                    // Chevron
                    Image(systemName: "chevron.right")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(Theme.textMuted)
                        .rotationEffect(.degrees(isExpanded ? 90 : 0))
                        .animation(AnimationSystem.springSmooth, value: isExpanded)
                }
                .padding(Spacing.md)
                .background(
                    RoundedRectangle(cornerRadius: Spacing.radiusMD)
                        .fill(variant.headerBackground)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: Spacing.radiusMD)
                        .strokeBorder(variant.borderColor, lineWidth: 1)
                )
            }
            .buttonStyle(PlainButtonStyle())

            // Content (expandable)
            if isExpanded {
                content
                    .padding(Spacing.md)
                    .transition(.asymmetric(
                        insertion: .move(edge: .top).combined(with: .opacity),
                        removal: .move(edge: .top).combined(with: .opacity)
                    ))
            }
        }
    }
}

// MARK: - Section Variants

extension ExpandableSection {
    enum SectionVariant {
        case neutral
        case success
        case warning
        case error
        case primary

        var headerBackground: Color {
            switch self {
            case .neutral:
                return Color.white.opacity(0.05)
            case .success:
                return Theme.success.opacity(0.1)
            case .warning:
                return Theme.warning.opacity(0.1)
            case .error:
                return Theme.error.opacity(0.1)
            case .primary:
                return Theme.primary.opacity(0.1)
            }
        }

        var borderColor: Color {
            switch self {
            case .neutral:
                return Color.white.opacity(0.1)
            case .success:
                return Theme.success.opacity(0.3)
            case .warning:
                return Theme.warning.opacity(0.3)
            case .error:
                return Theme.error.opacity(0.3)
            case .primary:
                return Theme.primary.opacity(0.3)
            }
        }

        var iconColor: Color {
            switch self {
            case .neutral:
                return Theme.textSecondary
            case .success:
                return Theme.success
            case .warning:
                return Theme.warning
            case .error:
                return Theme.error
            case .primary:
                return Theme.primary
            }
        }
    }
}

// MARK: - Convenience Initializers

extension ExpandableSection {
    /// Create expandable section with success styling
    static func success(
        _ title: String,
        icon: String? = "checkmark.circle.fill",
        badge: String? = nil,
        defaultExpanded: Bool = false,
        @ViewBuilder content: @escaping () -> Content
    ) -> ExpandableSection {
        ExpandableSection(title, icon: icon, badge: badge, variant: .success, defaultExpanded: defaultExpanded, content: content)
    }

    /// Create expandable section with warning styling
    static func warning(
        _ title: String,
        icon: String? = "exclamationmark.triangle.fill",
        badge: String? = nil,
        defaultExpanded: Bool = true,
        @ViewBuilder content: @escaping () -> Content
    ) -> ExpandableSection {
        ExpandableSection(title, icon: icon, badge: badge, variant: .warning, defaultExpanded: defaultExpanded, content: content)
    }

    /// Create expandable section with error styling
    static func error(
        _ title: String,
        icon: String? = "xmark.circle.fill",
        badge: String? = nil,
        defaultExpanded: Bool = true,
        @ViewBuilder content: @escaping () -> Content
    ) -> ExpandableSection {
        ExpandableSection(title, icon: icon, badge: badge, variant: .error, defaultExpanded: defaultExpanded, content: content)
    }
}

// MARK: - Preview

#if swift(>=5.9)
@available(iOS 17.0, *)
#Preview("Section Variants") {
    ScrollView {
        VStack(spacing: Spacing.md) {
            // Neutral section
            ExpandableSection(
                "Ingredients",
                icon: "list.bullet",
                badge: "15 items"
            ) {
                VStack(alignment: .leading, spacing: Spacing.sm) {
                    Text("• Organic almonds")
                    Text("• Filtered water")
                    Text("• Sea salt")
                    Text("• Natural vanilla extract")
                }
                .textStyleBody()
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            // Success section
            ExpandableSection.success(
                "Compatible Diets",
                badge: "3 matched"
            ) {
                VStack(spacing: Spacing.sm) {
                    StatusBadge.vegan()
                    StatusBadge.glutenFree()
                    StatusBadge("Organic", icon: "leaf.fill", variant: .success)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            // Warning section
            ExpandableSection.warning(
                "Caution Items",
                badge: "2 found"
            ) {
                VStack(alignment: .leading, spacing: Spacing.sm) {
                    HStack {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundColor(Theme.warning)
                        Text("May contain traces of ambiguous ingredients")
                            .textStyleBody()
                    }
                    Text("• Natural flavors (source unclear)")
                        .textStyleBodySmall()
                        .padding(.leading, Spacing.lg)
                }
            }

            // Error section
            ExpandableSection.error(
                "Dietary Violations",
                badge: "1 found"
            ) {
                VStack(alignment: .leading, spacing: Spacing.sm) {
                    HStack {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(Theme.error)
                        Text("Contains ingredients not compatible with your diet")
                            .textStyleBody()
                    }
                    Text("• Gelatin (animal-derived)")
                        .textStyleBodySmall()
                        .padding(.leading, Spacing.lg)
                }
            }

            // Primary section
            ExpandableSection(
                "Environmental Impact",
                icon: "leaf.fill",
                variant: .primary,
                defaultExpanded: true
            ) {
                VStack(spacing: Spacing.md) {
                    StatisticCard(
                        title: "CO2 Emissions",
                        numericValue: 2.4,
                        unit: "kg",
                        icon: "cloud.fill",
                        variant: .primary,
                        size: .compact
                    )

                    StatisticCard(
                        title: "Water Usage",
                        numericValue: 120,
                        unit: "L",
                        icon: "drop.fill",
                        variant: .accent,
                        size: .compact
                    )
                }
            }
        }
        .padding(Spacing.screenHorizontal)
    }
    .background(Theme.backgroundPrimary)
    .preferredColorScheme(.dark)
}

#Preview("In Glass Card") {
    ScrollView {
        VStack(spacing: Spacing.lg) {
            GlassCard.primary {
                VStack(spacing: Spacing.md) {
                    Text("Product Details")
                        .textStyleH2()
                        .frame(maxWidth: .infinity, alignment: .leading)

                    ExpandableSection(
                        "Full Ingredient List",
                        icon: "list.bullet",
                        badge: "12 items",
                        defaultExpanded: true
                    ) {
                        VStack(alignment: .leading, spacing: Spacing.xs) {
                            ForEach(0..<12, id: \.self) { index in
                                Text("• Ingredient \(index + 1)")
                                    .textStyleBody()
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }

                    ExpandableSection(
                        "Nutritional Information",
                        icon: "chart.bar.fill"
                    ) {
                        VStack(spacing: Spacing.sm) {
                            HStack {
                                Text("Calories")
                                    .textStyleBody()
                                Spacer()
                                Text("250 kcal")
                                    .textStyleBody(color: Theme.textPrimary)
                            }
                            HStack {
                                Text("Protein")
                                    .textStyleBody()
                                Spacer()
                                Text("8g")
                                    .textStyleBody(color: Theme.textPrimary)
                            }
                            HStack {
                                Text("Carbs")
                                    .textStyleBody()
                                Spacer()
                                Text("30g")
                                    .textStyleBody(color: Theme.textPrimary)
                            }
                        }
                    }

                    ExpandableSection(
                        "Certifications",
                        icon: "checkmark.seal.fill",
                        variant: .success
                    ) {
                        if #available(iOS 16.0, *) {
                            FlowLayout(spacing: Spacing.sm) {
                                StatusBadge("USDA Organic", icon: "leaf.fill", variant: .success)
                                StatusBadge("Non-GMO", variant: .primary)
                                StatusBadge("Fair Trade", variant: .info)
                            }
                        } else {
                            VStack(alignment: .leading, spacing: 4) {
                                StatusBadge("USDA Organic", icon: "leaf.fill", variant: .success)
                                StatusBadge("Non-GMO", variant: .primary)
                                StatusBadge("Fair Trade", variant: .info)
                            }
                        }
                    }
                }
            }
        }
        .padding(Spacing.screenHorizontal)
    }
    .background(Theme.backgroundPrimary)
    .preferredColorScheme(.dark)
}

#Preview("Interactive Test") {
    struct InteractivePreview: View {
        @State private var expandCount = 0

        var body: some View {
            ScrollView {
                VStack(spacing: Spacing.lg) {
                    Text("Tap sections to expand/collapse")
                        .textStyleH3()

                    Text("Expanded \(expandCount) times")
                        .textStyleBody()

                    ExpandableSection(
                        "Test Section",
                        icon: "star.fill"
                    ) {
                        Text("This content appears when expanded")
                            .textStyleBody()
                            .padding()
                            .onAppear {
                                expandCount += 1
                            }
                    }
                }
                .padding(Spacing.screenHorizontal)
            }
            .background(Theme.backgroundPrimary)
            .preferredColorScheme(.dark)
        }
    }

    return InteractivePreview()
}

#endif
