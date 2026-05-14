//
//  DesignSystemShowcase.swift
//  Ethica
//
//  Comprehensive showcase of the design system
//  Used for testing and documentation
//

import SwiftUI

/// Complete showcase of all design system components
@available(iOS 16.0, *)
struct DesignSystemShowcase: View {

    @State private var showLoading = false
    @State private var loadingStep = "Analyzing ingredients..."
    @State private var loadingProgress = 0.3
    @State private var selectedTab = 0

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: Spacing.xxl) {
                    // Hero Section
                    heroSection

                    Divider()
                        .background(Color.white.opacity(0.1))

                    // Components Section
                    componentsSection

                    Divider()
                        .background(Color.white.opacity(0.1))

                    // Cards Section
                    cardsSection

                    Divider()
                        .background(Color.white.opacity(0.1))

                    // Buttons Section
                    buttonsSection

                    Divider()
                        .background(Color.white.opacity(0.1))

                    // Badges Section
                    badgesSection

                    Divider()
                        .background(Color.white.opacity(0.1))

                    // Statistics Section
                    statisticsSection

                    Divider()
                        .background(Color.white.opacity(0.1))

                    // Scores Section
                    scoresSection

                    Divider()
                        .background(Color.white.opacity(0.1))

                    // Expandable Sections
                    expandableSectionsDemo

                    Divider()
                        .background(Color.white.opacity(0.1))

                    // Typography Section
                    typographySection

                    Divider()
                        .background(Color.white.opacity(0.1))

                    // Animation Section
                    animationSection
                }
                .padding(.vertical, Spacing.screenVertical)
            }
            .background(Theme.backgroundPrimary)
            .navigationTitle("Design System")
            .navigationBarTitleDisplayMode(.large)
            .preferredColorScheme(.dark)
            .loadingOverlay(
                isPresented: $showLoading,
                title: "Analyzing Product",
                currentStep: loadingStep,
                progress: loadingProgress,
                productPreview: LoadingProductPreview(
                    name: "Organic Almond Milk",
                    barcode: "012345678901"
                ),
                canCancel: true,
                onCancel: {
                    showLoading = false
                }
            )
        }
    }

    // MARK: - Hero Section

    private var heroSection: some View {
        VStack(spacing: Spacing.lg) {
            Text("Ethica Design System")
                .textStyleDisplay()

            Text("Premium • Sophisticated • Polished")
                .textStyleBody()

            // Hero card
            GlassCard.primary {
                VStack(spacing: Spacing.lg) {
                    HStack {
                        ScoreCircle(
                            score: 92,
                            size: .large,
                            showLabel: false
                        )

                        VStack(alignment: .leading, spacing: Spacing.sm) {
                            Text("Excellent Choice")
                                .textStyleH2()

                            FlowLayout(spacing: Spacing.sm) {
                                StatusBadge.success("Safe")
                                StatusBadge.vegan()
                                StatusBadge("Organic", icon: "leaf.fill", variant: .success)
                            }
                        }
                    }

                    Text("This design system provides consistent, premium components for the entire Ethica app.")
                        .textStyleBody()
                }
            }
        }
        .padding(.horizontal, Spacing.screenHorizontal)
    }

    // MARK: - Components Overview

    private var componentsSection: some View {
        VStack(alignment: .leading, spacing: Spacing.lg) {
            sectionHeader("Component Library", icon: "square.grid.2x2")

            Text("7 core components built with glass morphism and premium animations")
                .textStyleBody()

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: Spacing.md) {
                componentCard("GlassCard", icon: "square.fill", color: Theme.primary)
                componentCard("Buttons", icon: "hand.tap.fill", color: Theme.accent)
                componentCard("Badges", icon: "tag.fill", color: Theme.success)
                componentCard("Loading", icon: "arrow.triangle.2.circlepath", color: Theme.info)
                componentCard("Statistics", icon: "chart.bar.fill", color: Theme.warning)
                componentCard("Scores", icon: "circle.fill", color: Theme.primary)
                componentCard("Sections", icon: "list.bullet.rectangle", color: Theme.accent)
            }
        }
        .padding(.horizontal, Spacing.screenHorizontal)
    }

    private func componentCard(_ title: String, icon: String, color: Color) -> some View {
        GlassCard.secondary {
            VStack(spacing: Spacing.sm) {
                Image(systemName: icon)
                    .font(.system(size: 32, weight: .medium))
                    .foregroundColor(color)

                Text(title)
                    .textStyleBodySmall()
            }
            .frame(maxWidth: .infinity)
            .frame(height: 100)
        }
    }

    // MARK: - Cards Section

    private var cardsSection: some View {
        VStack(alignment: .leading, spacing: Spacing.lg) {
            sectionHeader("Glass Morphism Cards", icon: "square.on.square")

            VStack(spacing: Spacing.md) {
                GlassCard.primary {
                    cardContent("Primary Card", subtitle: "Most elevated surface")
                }

                GlassCard.secondary {
                    cardContent("Secondary Card", subtitle: "Nested content")
                }

                GlassCard.tertiary {
                    cardContent("Tertiary Card", subtitle: "Most subtle")
                }

                GlassCard.accent {
                    cardContent("Accent Card", subtitle: "Special features")
                }
            }
        }
        .padding(.horizontal, Spacing.screenHorizontal)
    }

    private func cardContent(_ title: String, subtitle: String) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: Spacing.xs) {
                Text(title)
                    .textStyleH4()
                Text(subtitle)
                    .textStyleCaption()
            }
            Spacer()
            Image(systemName: "checkmark.circle.fill")
                .foregroundColor(Theme.success)
        }
    }

    // MARK: - Buttons Section

    private var buttonsSection: some View {
        VStack(alignment: .leading, spacing: Spacing.lg) {
            sectionHeader("Buttons", icon: "hand.tap.fill")

            VStack(spacing: Spacing.md) {
                PrimaryButton.primary("Primary Button", icon: "camera.fill") {}
                PrimaryButton.secondary("Secondary Button", icon: "info.circle") {}
                PrimaryButton.tertiary("Tertiary Button") {}
                PrimaryButton("Accent Button", icon: "sparkles", style: .accent) {}
                PrimaryButton("Show Loading Demo", icon: "arrow.triangle.2.circlepath") {
                    showLoading = true
                }
            }
        }
        .padding(.horizontal, Spacing.screenHorizontal)
    }

    // MARK: - Badges Section

    private var badgesSection: some View {
        VStack(alignment: .leading, spacing: Spacing.lg) {
            sectionHeader("Status Badges", icon: "tag.fill")

            VStack(alignment: .leading, spacing: Spacing.md) {
                Text("Status Indicators")
                    .textStyleH4()

                FlowLayout(spacing: Spacing.sm) {
                    StatusBadge.success("Safe")
                    StatusBadge.warning("Caution")
                    StatusBadge.error("Violation")
                    StatusBadge.info("Info")
                    StatusBadge.neutral("Neutral")
                }

                Text("Dietary Tags")
                    .textStyleH4()
                    .padding(.top, Spacing.sm)

                FlowLayout(spacing: Spacing.sm) {
                    StatusBadge.vegan()
                    StatusBadge.jain()
                    StatusBadge.glutenFree()
                    StatusBadge("Halal", icon: "moon.fill", variant: .primary)
                    StatusBadge("Organic", icon: "leaf.fill", variant: .success)
                    StatusBadge("Non-GMO", variant: .primary)
                }
            }
        }
        .padding(.horizontal, Spacing.screenHorizontal)
    }

    // MARK: - Statistics Section

    private var statisticsSection: some View {
        VStack(alignment: .leading, spacing: Spacing.lg) {
            sectionHeader("Statistics Cards", icon: "chart.bar.fill")

            VStack(spacing: Spacing.md) {
                StatisticCard(
                    title: "Health Score",
                    numericValue: 88,
                    unit: "/100",
                    icon: "heart.fill",
                    trend: .up("+5"),
                    variant: .success
                )

                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: Spacing.md) {
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
        .padding(.horizontal, Spacing.screenHorizontal)
    }

    // MARK: - Scores Section

    private var scoresSection: some View {
        VStack(alignment: .leading, spacing: Spacing.lg) {
            sectionHeader("Score Circles", icon: "circle.fill")

            GlassCard.primary {
                VStack(spacing: Spacing.lg) {
                    HStack(spacing: Spacing.xl) {
                        ScoreCircle(
                            score: 92,
                            size: .large,
                            showLabel: true,
                            label: "Excellent"
                        )

                        ScoreCircle(
                            score: 68,
                            size: .large,
                            showLabel: true,
                            label: "Good"
                        )
                    }

                    HStack(spacing: Spacing.lg) {
                        ScoreCircle(score: 85, size: .medium, colorScheme: .success)
                        ScoreCircle(score: 62, size: .medium, colorScheme: .warning)
                        ScoreCircle(score: 38, size: .medium, colorScheme: .error)
                    }
                }
            }
        }
        .padding(.horizontal, Spacing.screenHorizontal)
    }

    // MARK: - Expandable Sections

    private var expandableSectionsDemo: some View {
        VStack(alignment: .leading, spacing: Spacing.lg) {
            sectionHeader("Expandable Sections", icon: "list.bullet.rectangle")

            VStack(spacing: Spacing.md) {
                ExpandableSection(
                    "Ingredients List",
                    icon: "list.bullet",
                    badge: "12 items"
                ) {
                    VStack(alignment: .leading, spacing: Spacing.xs) {
                        ForEach(0..<12, id: \.self) { index in
                            Text("• Ingredient \(index + 1)")
                                .textStyleBody()
                        }
                    }
                }

                ExpandableSection.success(
                    "Compatible Diets",
                    badge: "3 matched"
                ) {
                    FlowLayout(spacing: Spacing.sm) {
                        StatusBadge.vegan()
                        StatusBadge.glutenFree()
                        StatusBadge("Organic", icon: "leaf.fill", variant: .success)
                    }
                }

                ExpandableSection.warning(
                    "Caution Items",
                    badge: "1 found"
                ) {
                    Text("May contain traces of ambiguous ingredients")
                        .textStyleBody()
                }
            }
        }
        .padding(.horizontal, Spacing.screenHorizontal)
    }

    // MARK: - Typography Section

    private var typographySection: some View {
        VStack(alignment: .leading, spacing: Spacing.lg) {
            sectionHeader("Typography", icon: "textformat")

            GlassCard.secondary {
                VStack(alignment: .leading, spacing: Spacing.md) {
                    Text("Display Large")
                        .textStyleDisplayLarge()
                    Text("Display")
                        .textStyleDisplay()
                    Text("Heading 1")
                        .textStyleH1()
                    Text("Heading 2")
                        .textStyleH2()
                    Text("Heading 3")
                        .textStyleH3()
                    Text("Heading 4")
                        .textStyleH4()
                    Text("Body Large - This is larger body text for emphasized content")
                        .textStyleBodyLarge()
                    Text("Body - This is standard body text used throughout the app")
                        .textStyleBody()
                    Text("Body Small - Compact text for secondary information")
                        .textStyleBodySmall()
                    Text("Caption - Supplementary information")
                        .textStyleCaption()
                    Text("OVERLINE - LABELS AND CATEGORIES")
                        .textStyleOverline()
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(.horizontal, Spacing.screenHorizontal)
    }

    // MARK: - Animation Section

    private var animationSection: some View {
        VStack(alignment: .leading, spacing: Spacing.lg) {
            sectionHeader("Animations", icon: "sparkles")

            Text("All components use spring physics and stagger effects for natural, engaging motion")
                .textStyleBody()

            GlassCard.primary {
                VStack(spacing: Spacing.md) {
                    ForEach(0..<5, id: \.self) { index in
                        HStack {
                            Circle()
                                .fill(Theme.gradientHero)
                                .frame(width: 8, height: 8)

                            Text("Stagger animation \(index + 1)")
                                .textStyleBody()

                            Spacer()

                            Image(systemName: "checkmark")
                                .foregroundColor(Theme.success)
                        }
                        .staggerAnimation(index: index)
                    }
                }
            }
        }
        .padding(.horizontal, Spacing.screenHorizontal)
    }

    // MARK: - Helper Views

    private func sectionHeader(_ title: String, icon: String) -> some View {
        HStack(spacing: Spacing.sm) {
            Image(systemName: icon)
                .font(.system(size: 20, weight: .semibold))
                .foregroundColor(Theme.primary)

            Text(title)
                .textStyleH2()
        }
    }
}

// MARK: - Preview

@available(iOS 17.0, *)
#Preview {
    DesignSystemShowcase()
}
