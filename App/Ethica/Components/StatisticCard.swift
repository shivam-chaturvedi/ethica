//
//  StatisticCard.swift
//  Ethica
//
//  Card for displaying statistics and metrics
//  Used for health scores, environmental impact, etc.
//

import SwiftUI

/// Card displaying a statistic with animated counter
struct StatisticCard: View {

    // MARK: - Properties

    let title: String
    let value: String
    let icon: String?
    let trend: TrendIndicator?
    let variant: StatisticVariant
    let size: StatisticSize
    let animateValue: Bool

    @State private var displayValue: Double = 0
    @State private var isAnimating = false

    // MARK: - Initializers

    init(
        title: String,
        value: String,
        icon: String? = nil,
        trend: TrendIndicator? = nil,
        variant: StatisticVariant = .neutral,
        size: StatisticSize = .standard,
        animateValue: Bool = false
    ) {
        self.title = title
        self.value = value
        self.icon = icon
        self.trend = trend
        self.variant = variant
        self.size = size
        self.animateValue = animateValue
    }

    /// Create statistic card with numeric value and animation
    init(
        title: String,
        numericValue: Double,
        unit: String = "",
        formatter: NumberFormatter? = nil,
        icon: String? = nil,
        trend: TrendIndicator? = nil,
        variant: StatisticVariant = .neutral,
        size: StatisticSize = .standard
    ) {
        self.title = title

        let defaultFormatter = NumberFormatter()
        defaultFormatter.numberStyle = .decimal
        defaultFormatter.maximumFractionDigits = 1

        let formattedValue = (formatter ?? defaultFormatter).string(from: NSNumber(value: numericValue)) ?? "\(Int(numericValue))"
        self.value = "\(formattedValue)\(unit)"

        self.icon = icon
        self.trend = trend
        self.variant = variant
        self.size = size
        self.animateValue = true

        _displayValue = State(initialValue: numericValue)
    }

    // MARK: - Body

    var body: some View {
        GlassCard(variant: variant.cardVariant, padding: size.padding) {
            VStack(spacing: size.spacing) {
                // Header (icon + title)
                HStack {
                    if let icon = icon {
                        Image(systemName: icon)
                            .font(size.iconFont)
                            .foregroundColor(variant.accentColor)
                    }

                    Text(title)
                        .font(size.titleFont)
                        .foregroundColor(Theme.textSecondary)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    if let trend = trend {
                        trendView(trend)
                    }
                }

                // Value
                Text(value)
                    .font(size.valueFont)
                    .foregroundColor(variant.valueColor)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .opacity(isAnimating ? 1 : 0)
                    .offset(y: isAnimating ? 0 : 10)
            }
        }
        .onAppear {
            withAnimation(AnimationSystem.springSmooth.delay(0.1)) {
                isAnimating = true
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(title): \(value)")
    }

    // MARK: - Trend View

    @ViewBuilder
    private func trendView(_ trend: TrendIndicator) -> some View {
        HStack(spacing: 4) {
            Image(systemName: trend.icon)
                .font(.system(size: 12, weight: .semibold))
            Text(trend.text)
                .font(.system(size: 12, weight: .medium))
        }
        .foregroundColor(trend.color)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(
            Capsule()
                .fill(trend.color.opacity(0.2))
        )
    }
}

// MARK: - Statistic Variants

extension StatisticCard {
    enum StatisticVariant {
        case neutral
        case success
        case warning
        case error
        case primary
        case accent

        var cardVariant: GlassCardVariant {
            switch self {
            case .neutral: return .secondary
            case .success: return .success
            case .warning: return .warning
            case .error: return .error
            case .primary: return .primary
            case .accent: return .accent
            }
        }

        var accentColor: Color {
            switch self {
            case .neutral: return Theme.textSecondary
            case .success: return Theme.success
            case .warning: return Theme.warning
            case .error: return Theme.error
            case .primary: return Theme.primary
            case .accent: return Theme.accent
            }
        }

        var valueColor: Color {
            switch self {
            case .neutral: return Theme.textPrimary
            case .success: return Theme.success
            case .warning: return Theme.warning
            case .error: return Theme.error
            case .primary: return Theme.primary
            case .accent: return Theme.accent
            }
        }
    }

    enum StatisticSize {
        case compact
        case standard
        case large

        var padding: CGFloat {
            switch self {
            case .compact: return Spacing.sm
            case .standard: return Spacing.md
            case .large: return Spacing.lg
            }
        }

        var spacing: CGFloat {
            switch self {
            case .compact: return Spacing.xs
            case .standard: return Spacing.sm
            case .large: return Spacing.md
            }
        }

        var titleFont: Font {
            switch self {
            case .compact: return Typography.caption
            case .standard: return Typography.bodySmall
            case .large: return Typography.body
            }
        }

        var valueFont: Font {
            switch self {
            case .compact: return Typography.h4
            case .standard: return Typography.h3
            case .large: return Typography.h1
            }
        }

        var iconFont: Font {
            switch self {
            case .compact: return .system(size: 14, weight: .medium)
            case .standard: return .system(size: 16, weight: .medium)
            case .large: return .system(size: 20, weight: .semibold)
            }
        }
    }

    struct TrendIndicator {
        let text: String
        let direction: TrendDirection

        var icon: String {
            switch direction {
            case .up: return "arrow.up.right"
            case .down: return "arrow.down.right"
            case .neutral: return "arrow.right"
            }
        }

        var color: Color {
            switch direction {
            case .up: return Theme.success
            case .down: return Theme.error
            case .neutral: return Theme.textMuted
            }
        }

        enum TrendDirection {
            case up
            case down
            case neutral
        }

        static func up(_ text: String) -> TrendIndicator {
            TrendIndicator(text: text, direction: .up)
        }

        static func down(_ text: String) -> TrendIndicator {
            TrendIndicator(text: text, direction: .down)
        }

        static func neutral(_ text: String) -> TrendIndicator {
            TrendIndicator(text: text, direction: .neutral)
        }
    }
}

// MARK: - Preview

#Preview("Statistic Variants") {
    ScrollView {
        VStack(spacing: Spacing.md) {
            // Health Score
            StatisticCard(
                title: "Health Score",
                numericValue: 85,
                unit: "/100",
                icon: "heart.fill",
                trend: .up("+5"),
                variant: .success
            )

            // CO2 Emissions
            StatisticCard(
                title: "CO2 Emissions",
                numericValue: 2.4,
                unit: "kg",
                icon: "cloud.fill",
                trend: .down("-0.5kg"),
                variant: .primary
            )

            // Water Usage
            StatisticCard(
                title: "Water Usage",
                numericValue: 120,
                unit: "L",
                icon: "drop.fill",
                variant: .accent
            )

            // Calories
            StatisticCard(
                title: "Calories",
                value: "250 kcal",
                icon: "flame.fill",
                variant: .neutral
            )

            // Violations
            StatisticCard(
                title: "Dietary Violations",
                value: "2 found",
                icon: "exclamationmark.triangle.fill",
                variant: .error
            )

            // Warning
            StatisticCard(
                title: "Caution Items",
                value: "3 items",
                icon: "exclamationmark.shield.fill",
                variant: .warning
            )
        }
        .padding(Spacing.screenHorizontal)
    }
    .background(Theme.backgroundPrimary)
    .preferredColorScheme(.dark)
}

#Preview("Sizes") {
    ScrollView {
        VStack(spacing: Spacing.lg) {
            Text("Large Size")
                .textStyleH3()
                .frame(maxWidth: .infinity, alignment: .leading)

            StatisticCard(
                title: "Health Score",
                numericValue: 92,
                unit: "/100",
                icon: "heart.fill",
                variant: .success,
                size: .large
            )

            Divider()

            Text("Standard Size")
                .textStyleH3()
                .frame(maxWidth: .infinity, alignment: .leading)

            StatisticCard(
                title: "Health Score",
                numericValue: 92,
                unit: "/100",
                icon: "heart.fill",
                variant: .success,
                size: .standard
            )

            Divider()

            Text("Compact Size")
                .textStyleH3()
                .frame(maxWidth: .infinity, alignment: .leading)

            StatisticCard(
                title: "Health Score",
                numericValue: 92,
                unit: "/100",
                icon: "heart.fill",
                variant: .success,
                size: .compact
            )
        }
        .padding(Spacing.screenHorizontal)
    }
    .background(Theme.backgroundPrimary)
    .preferredColorScheme(.dark)
}

#Preview("Grid Layout") {
    ScrollView {
        VStack(spacing: Spacing.lg) {
            Text("Scan Statistics")
                .textStyleH2()
                .frame(maxWidth: .infinity, alignment: .leading)

            // 2-column grid
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: Spacing.md) {
                StatisticCard(
                    title: "Health Score",
                    numericValue: 85,
                    unit: "/100",
                    icon: "heart.fill",
                    variant: .success,
                    size: .compact
                )

                StatisticCard(
                    title: "CO2",
                    numericValue: 2.4,
                    unit: "kg",
                    icon: "cloud.fill",
                    variant: .primary,
                    size: .compact
                )

                StatisticCard(
                    title: "Water",
                    numericValue: 120,
                    unit: "L",
                    icon: "drop.fill",
                    variant: .accent,
                    size: .compact
                )

                StatisticCard(
                    title: "Calories",
                    value: "250",
                    icon: "flame.fill",
                    variant: .neutral,
                    size: .compact
                )
            }
        }
        .padding(Spacing.screenHorizontal)
    }
    .background(Theme.backgroundPrimary)
    .preferredColorScheme(.dark)
}
