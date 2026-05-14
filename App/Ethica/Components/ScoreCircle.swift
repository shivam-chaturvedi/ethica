//
//  ScoreCircle.swift
//  Ethica
//
//  Circular progress indicator for scores and ratings
//  Used for health scores, overall ratings, etc.
//

import SwiftUI

/// Circular progress indicator with animated fill
struct ScoreCircle: View {

    // MARK: - Properties

    let score: Double // 0-100
    let size: CircleSize
    let showPercentage: Bool
    let showLabel: Bool
    let label: String?
    let colorScheme: CircleColorScheme
    let showGlow: Bool
    let revealMode: Bool

    @State private var animatedScore: Double = 0
    @State private var isAnimating = false
    @State private var revealScale: CGFloat = 0.8
    @State private var showGlowBurst = false

    // MARK: - Initializers

    init(
        score: Double,
        size: CircleSize = .medium,
        showPercentage: Bool = true,
        showLabel: Bool = false,
        label: String? = nil,
        colorScheme: CircleColorScheme = .dynamic,
        showGlow: Bool = false,
        revealMode: Bool = false
    ) {
        self.score = min(max(score, 0), 100)
        self.size = size
        self.showPercentage = showPercentage
        self.showLabel = showLabel
        self.label = label
        self.colorScheme = colorScheme
        self.showGlow = showGlow
        self.revealMode = revealMode
    }

    // MARK: - Computed Properties

    private var scoreColor: Color {
        switch colorScheme {
        case .dynamic:
            return Theme.healthScoreColor(score)
        case .success:
            return Theme.success
        case .warning:
            return Theme.warning
        case .error:
            return Theme.error
        case .primary:
            return Theme.primary
        case .accent:
            return Theme.accent
        case .custom(let color):
            return color
        }
    }

    private var animatedScoreColor: Color {
        switch colorScheme {
        case .dynamic:
            return Theme.healthScoreColor(animatedScore)
        default:
            return scoreColor
        }
    }

    private var gradient: LinearGradient {
        switch colorScheme {
        case .dynamic:
            return Theme.healthScoreGradient(score)
        case .success:
            return Theme.gradientSuccess
        case .error:
            return Theme.gradientError
        case .warning:
            return LinearGradient(
                colors: [Theme.warning, Color(hex: "FBBF24")],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        case .primary:
            return Theme.gradientHero
        case .accent:
            return Theme.gradientAccent
        case .custom(let color):
            return LinearGradient(
                colors: [color, color.opacity(0.7)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
    }

    // MARK: - Body

    var body: some View {
        VStack(spacing: size.labelSpacing) {
            ZStack {
                // Background circle
                Circle()
                    .stroke(Color.white.opacity(0.1), lineWidth: size.lineWidth)
                    .frame(width: size.diameter, height: size.diameter)

                // Glow ring (behind progress arc)
                if showGlow || revealMode {
                    Circle()
                        .trim(from: 0, to: animatedScore / 100)
                        .stroke(
                            gradient,
                            style: StrokeStyle(lineWidth: size.lineWidth, lineCap: .round)
                        )
                        .frame(width: size.diameter, height: size.diameter)
                        .rotationEffect(.degrees(-90))
                        .blur(radius: size.lineWidth * 1.5)
                        .opacity(0.4)
                        .animation(AnimationSystem.springSmooth.delay(revealMode ? 0.5 : 0.2), value: animatedScore)
                }

                // Progress circle
                Circle()
                    .trim(from: 0, to: animatedScore / 100)
                    .stroke(
                        gradient,
                        style: StrokeStyle(lineWidth: size.lineWidth, lineCap: .round)
                    )
                    .frame(width: size.diameter, height: size.diameter)
                    .rotationEffect(.degrees(-90))
                    .animation(AnimationSystem.springSmooth.delay(revealMode ? 0.5 : 0.2), value: animatedScore)

                // Score text
                VStack(spacing: 2) {
                    if showPercentage {
                        Text("\(Int(animatedScore))")
                            .font(size.scoreFont)
                            .foregroundColor(animatedScoreColor)
                            .animation(AnimationSystem.springSmooth, value: animatedScore)

                        if size != .small {
                            Text("/100")
                                .font(size.unitFont)
                                .foregroundColor(Theme.textMuted)
                        }
                    }
                }
            }
            .scaleEffect(revealScale)
            .glowBurst(color: scoreColor, trigger: showGlowBurst)

            // Label below circle
            if showLabel, let label = label {
                Text(label)
                    .font(size.labelFont)
                    .foregroundColor(Theme.textSecondary)
                    .multilineTextAlignment(.center)
            }
        }
        .onAppear {
            if revealMode {
                // Delayed reveal with overshoot
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    withAnimation(.spring(response: 0.5, dampingFraction: 0.6)) {
                        revealScale = 1.0
                    }
                    withAnimation(AnimationSystem.springSmooth) {
                        animatedScore = score
                        isAnimating = true
                    }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                        showGlowBurst = true
                        HapticManager.shared.sequence(.scoreReveal)
                    }
                }
            } else {
                revealScale = 1.0
                withAnimation {
                    animatedScore = score
                    isAnimating = true
                }
            }
        }
        .onChange(of: score) { _, newScore in
            withAnimation(AnimationSystem.springSmooth) {
                animatedScore = newScore
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label ?? "Score")
        .accessibilityValue("\(Int(score)) out of 100")
    }
}

// MARK: - Circle Sizes

extension ScoreCircle {
    enum CircleSize {
        case small
        case medium
        case large
        case hero

        var diameter: CGFloat {
            switch self {
            case .small: return 60
            case .medium: return 100
            case .large: return 140
            case .hero: return 200
            }
        }

        var lineWidth: CGFloat {
            switch self {
            case .small: return 6
            case .medium: return 10
            case .large: return 14
            case .hero: return 18
            }
        }

        var scoreFont: Font {
            switch self {
            case .small: return Typography.h4
            case .medium: return Typography.h2
            case .large: return Typography.display
            case .hero: return Typography.displayLarge
            }
        }

        var unitFont: Font {
            switch self {
            case .small: return Typography.caption
            case .medium: return Typography.bodySmall
            case .large: return Typography.body
            case .hero: return Typography.bodyLarge
            }
        }

        var labelFont: Font {
            switch self {
            case .small: return Typography.caption
            case .medium: return Typography.bodySmall
            case .large: return Typography.body
            case .hero: return Typography.bodyLarge
            }
        }

        var labelSpacing: CGFloat {
            switch self {
            case .small: return Spacing.xs
            case .medium: return Spacing.sm
            case .large: return Spacing.md
            case .hero: return Spacing.lg
            }
        }
    }

    enum CircleColorScheme {
        case dynamic       // Changes based on score (green/yellow/red)
        case success
        case warning
        case error
        case primary
        case accent
        case custom(Color)
    }
}

// MARK: - Preview

#Preview("Score Ranges") {
    ScrollView {
        VStack(spacing: Spacing.xl) {
            // Excellent score
            VStack(spacing: Spacing.md) {
                Text("Excellent (90+)")
                    .textStyleH3()
                ScoreCircle(score: 92, size: .large, showLabel: true, label: "Health Score")
            }

            // Good score
            VStack(spacing: Spacing.md) {
                Text("Good (70-89)")
                    .textStyleH3()
                ScoreCircle(score: 78, size: .large, showLabel: true, label: "Health Score")
            }

            // Fair score
            VStack(spacing: Spacing.md) {
                Text("Fair (50-69)")
                    .textStyleH3()
                ScoreCircle(score: 58, size: .large, showLabel: true, label: "Health Score")
            }

            // Poor score
            VStack(spacing: Spacing.md) {
                Text("Poor (<50)")
                    .textStyleH3()
                ScoreCircle(score: 32, size: .large, showLabel: true, label: "Health Score")
            }
        }
        .padding(Spacing.screenHorizontal)
    }
    .background(Theme.backgroundPrimary)
    .preferredColorScheme(.dark)
}

#Preview("Sizes") {
    ScrollView {
        VStack(spacing: Spacing.xxl) {
            // Hero size
            VStack(spacing: Spacing.md) {
                Text("Hero Size")
                    .textStyleH3()
                ScoreCircle(score: 85, size: .hero, showLabel: true, label: "Overall Health")
            }

            // Large size
            VStack(spacing: Spacing.md) {
                Text("Large Size")
                    .textStyleH3()
                ScoreCircle(score: 85, size: .large, showLabel: true, label: "Health Score")
            }

            // Medium size
            VStack(spacing: Spacing.md) {
                Text("Medium Size")
                    .textStyleH3()
                ScoreCircle(score: 85, size: .medium, showLabel: true, label: "Health Score")
            }

            // Small size
            VStack(spacing: Spacing.md) {
                Text("Small Size")
                    .textStyleH3()
                ScoreCircle(score: 85, size: .small)
            }
        }
        .padding(Spacing.screenHorizontal)
    }
    .background(Theme.backgroundPrimary)
    .preferredColorScheme(.dark)
}

#Preview("Color Schemes") {
    ScrollView {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: Spacing.lg) {
            VStack {
                ScoreCircle(score: 85, colorScheme: .dynamic)
                Text("Dynamic")
                    .textStyleCaption()
            }

            VStack {
                ScoreCircle(score: 85, colorScheme: .success)
                Text("Success")
                    .textStyleCaption()
            }

            VStack {
                ScoreCircle(score: 85, colorScheme: .warning)
                Text("Warning")
                    .textStyleCaption()
            }

            VStack {
                ScoreCircle(score: 85, colorScheme: .error)
                Text("Error")
                    .textStyleCaption()
            }

            VStack {
                ScoreCircle(score: 85, colorScheme: .primary)
                Text("Primary")
                    .textStyleCaption()
            }

            VStack {
                ScoreCircle(score: 85, colorScheme: .accent)
                Text("Accent")
                    .textStyleCaption()
            }
        }
        .padding(Spacing.screenHorizontal)
    }
    .background(Theme.backgroundPrimary)
    .preferredColorScheme(.dark)
}

#Preview("In Card") {
    ScrollView {
        VStack(spacing: Spacing.lg) {
            GlassCard.primary {
                VStack(spacing: Spacing.lg) {
                    Text("Product Analysis")
                        .textStyleH2()
                        .frame(maxWidth: .infinity, alignment: .leading)

                    HStack(spacing: Spacing.xl) {
                        ScoreCircle(
                            score: 88,
                            size: .large,
                            showLabel: true,
                            label: "Health Score"
                        )

                        VStack(alignment: .leading, spacing: Spacing.sm) {
                            StatusBadge.success("Safe to Consume")
                            StatusBadge.vegan()
                            StatusBadge("Organic", icon: "leaf.fill", variant: .success)
                        }
                    }
                }
            }

            // Multiple scores
            GlassCard.primary {
                VStack(spacing: Spacing.lg) {
                    Text("Environmental Impact")
                        .textStyleH2()
                        .frame(maxWidth: .infinity, alignment: .leading)

                    HStack(spacing: Spacing.lg) {
                        ScoreCircle(
                            score: 75,
                            size: .medium,
                            showLabel: true,
                            label: "CO2 Impact",
                            colorScheme: .primary
                        )

                        ScoreCircle(
                            score: 60,
                            size: .medium,
                            showLabel: true,
                            label: "Water Usage",
                            colorScheme: .accent
                        )
                    }
                }
            }
        }
        .padding(Spacing.screenHorizontal)
    }
    .background(Theme.backgroundPrimary)
    .preferredColorScheme(.dark)
}

#Preview("Interactive Animation") {
    struct AnimationPreview: View {
        @State private var score: Double = 0

        var body: some View {
            VStack(spacing: Spacing.xxl) {
                ScoreCircle(score: score, size: .hero, showLabel: true, label: "Health Score")

                VStack(spacing: Spacing.md) {
                    Text("Score: \(Int(score))")
                        .textStyleH3()

                    Slider(value: $score, in: 0...100, step: 1)
                        .tint(Theme.primary)

                    HStack(spacing: Spacing.sm) {
                        PrimaryButton.secondary("Poor (30)") {
                            score = 30
                        }
                        PrimaryButton.secondary("Good (75)") {
                            score = 75
                        }
                        PrimaryButton.secondary("Excellent (95)") {
                            score = 95
                        }
                    }
                }
                .padding(Spacing.lg)
            }
            .padding(Spacing.screenHorizontal)
            .frame(maxHeight: .infinity)
            .background(Theme.backgroundPrimary)
            .preferredColorScheme(.dark)
        }
    }

    return AnimationPreview()
}
