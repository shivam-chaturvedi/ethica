//
//  OnboardingView.swift
//  Ethica
//
//  Multi-page onboarding with diet, allergen, may-contain, and priority setup
//

import SwiftUI

struct OnboardingView: View {
    @ObservedObject var preferencesManager: PreferencesManager
    var onComplete: () -> Void

    @State private var currentPage = 0
    @State private var nameText = ""
    @State private var customDietText = ""

    // Entrance animations
    @State private var logoAppeared = false
    @State private var contentAppeared = false
    @Namespace private var progressNamespace

    private let totalPages = 6

    var body: some View {
        ZStack {
            // Background
            Theme.backgroundPrimary
                .ignoresSafeArea()

            // Parallax floating decorations — shift at 0.3x rate of page transitions
            parallaxDecorations

            VStack(spacing: 0) {
                // Progress indicator + Skip
                HStack {
                    progressBar

                    if currentPage < totalPages - 1 {
                        Button(action: {
                            HapticManager.shared.trigger(.impactLight)
                            withAnimation(AnimationSystem.springResponsive) {
                                currentPage = totalPages - 1
                            }
                        }) {
                            Text("Skip")
                                .font(Typography.bodySmall)
                                .foregroundColor(Theme.textMuted)
                        }
                        .accessibilityLabel("Skip onboarding")
                        .accessibilityHint("Jump to the last onboarding page")
                    }
                }
                    .padding(.top, 12)
                    .padding(.horizontal, Spacing.screenHorizontal)

                // Page content
                TabView(selection: $currentPage) {
                    welcomePage.tag(0)
                    dietPage.tag(1)
                    allergenPage.tag(2)
                    mayContainPage.tag(3)
                    avoidGMOPage.tag(4)
                    prioritiesPage.tag(5)
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
                .animation(.easeInOut(duration: 0.3), value: currentPage)
                .onChange(of: currentPage) { _, _ in
                    HapticManager.shared.trigger(.selectionChanged)
                }

                // Navigation buttons
                navigationButtons
                    .padding(.horizontal, Spacing.screenHorizontal)
                    .padding(.bottom, 40)
            }
        }
    }

    // MARK: - Parallax Decorations

    private var parallaxDecorations: some View {
        let parallaxOffset = CGFloat(currentPage) * -30 // moves at ~0.3x page rate

        return ZStack {
            // Top-right circle
            Circle()
                .fill(Theme.primary.opacity(0.06))
                .frame(width: 200, height: 200)
                .blur(radius: 60)
                .offset(x: 120 + parallaxOffset * 0.3, y: -80)

            // Bottom-left circle
            Circle()
                .fill(Theme.accent.opacity(0.05))
                .frame(width: 160, height: 160)
                .blur(radius: 50)
                .offset(x: -100 + parallaxOffset * 0.2, y: 300)

            // Mid floating leaf — very subtle
            Image(systemName: "leaf.fill")
                .font(.system(size: 60))
                .foregroundColor(Theme.primary.opacity(0.04))
                .rotationEffect(.degrees(Double(currentPage) * -15))
                .offset(x: 140 + parallaxOffset * 0.4, y: 200)
        }
        .allowsHitTesting(false)
        .animation(AnimationSystem.springSmooth, value: currentPage)
    }

    // MARK: - Progress Bar

    private var progressBar: some View {
        HStack(spacing: 6) {
            ForEach(0..<totalPages, id: \.self) { index in
                ZStack {
                    Capsule()
                        .fill(Color(hex: "333333"))
                        .frame(height: 4)

                    if index <= currentPage {
                        Capsule()
                            .fill(Theme.primary)
                            .frame(height: 4)
                            .matchedGeometryEffect(id: "progress_\(index)", in: progressNamespace)
                            .transition(.opacity)
                    }
                }
                .animation(AnimationSystem.springBouncy, value: currentPage)
            }
        }
        .padding(.vertical, Spacing.sm)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Page \(currentPage + 1) of \(totalPages)")
    }

    // MARK: - Navigation Buttons

    private var navigationButtons: some View {
        HStack(spacing: Spacing.md) {
            // Back button
            if currentPage > 0 {
                Button(action: {
                    withAnimation(AnimationSystem.springResponsive) { currentPage -= 1 }
                }) {
                    HStack(spacing: 6) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 14, weight: .semibold))
                        Text("Back")
                            .font(Typography.buttonLarge)
                    }
                    .foregroundColor(Theme.textTertiary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, Spacing.md)
                    .background(
                        RoundedRectangle(cornerRadius: Spacing.radiusMD)
                            .fill(Theme.surfaceSecondary)
                            .overlay(
                                RoundedRectangle(cornerRadius: Spacing.radiusMD)
                                    .stroke(Color.white.opacity(0.06), lineWidth: 1)
                            )
                    )
                }
                .accessibilityLabel("Back")
                .accessibilityHint("Go to the previous onboarding step")
                .buttonPressAnimation()
            }

            // Next / Get Started button
            Button(action: {
                if currentPage < totalPages - 1 {
                    if currentPage == 0 {
                        preferencesManager.preferences.displayName = nameText.trimmingCharacters(in: .whitespacesAndNewlines)
                    }
                    withAnimation(AnimationSystem.springResponsive) { currentPage += 1 }
                } else {
                    onComplete()
                }
            }) {
                HStack(spacing: 8) {
                    Text(currentPage == totalPages - 1 ? "Get Started" : "Continue")
                        .font(Typography.buttonLarge)
                    Image(systemName: currentPage == totalPages - 1 ? "checkmark.circle.fill" : "arrow.right")
                        .font(.system(size: 16, weight: .semibold))
                }
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, Spacing.md)
                .background(
                    RoundedRectangle(cornerRadius: Spacing.radiusMD)
                        .fill(Theme.gradientHero)
                )
                .shadow(color: Theme.primary.opacity(0.3), radius: 12, y: 6)
            }
            .accessibilityLabel(currentPage == totalPages - 1 ? "Get Started" : "Continue")
            .accessibilityHint(currentPage == totalPages - 1 ? "Finish onboarding and start using the app" : "Go to the next onboarding step")
            .buttonPressAnimation()
        }
    }

    // MARK: - Page 0: Welcome

    private var welcomePage: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: Spacing.lg) {
                Spacer().frame(height: Spacing.xl)

                // Logo
                ZStack {
                    // Outer glow
                    Circle()
                        .fill(Theme.primary.opacity(0.12))
                        .frame(width: 140, height: 140)
                        .blur(radius: 30)

                    // Inner glow
                    Circle()
                        .fill(Theme.primary.opacity(0.08))
                        .frame(width: 100, height: 100)

                    Image(systemName: "leaf.fill")
                        .font(.system(size: 52, weight: .semibold))
                        .foregroundStyle(
                            LinearGradient(
                                colors: [Theme.primary, Theme.primaryLight],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .shadow(color: Theme.primary.opacity(0.4), radius: 10, y: 4)
                }
                .accessibilityHidden(true)
                .scaleIn(delay: 0.1)

                VStack(spacing: Spacing.sm) {
                    Text("Welcome to Ethica")
                        .font(Typography.h1)
                        .foregroundColor(Theme.textPrimary)
                        .accessibilityAddTraits(.isHeader)
                        .slideInFromBottom(delay: 0.2)

                    Text("Your personal guide to ethical,\nconscious food choices")
                        .font(Typography.bodyLarge)
                        .foregroundColor(Theme.textMuted)
                        .multilineTextAlignment(.center)
                        .lineSpacing(4)
                        .slideInFromBottom(delay: 0.3)
                }

                // Name input
                VStack(alignment: .leading, spacing: 10) {
                    Text("What should we call you?")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(Theme.textSecondary)

                    TextField("Your name (optional)", text: $nameText)
                        .font(Typography.bodyLarge)
                        .foregroundColor(Theme.textPrimary)
                        .padding(Spacing.md)
                        .background(
                            RoundedRectangle(cornerRadius: Spacing.radiusSM)
                                .fill(Theme.surfaceBase)
                                .overlay(
                                    RoundedRectangle(cornerRadius: Spacing.radiusSM)
                                        .stroke(Color.white.opacity(0.08), lineWidth: 1)
                                )
                        )
                        .tint(Theme.primary)
                        .accessibilityLabel("Your name")
                        .accessibilityHint("Optional. Enter what you'd like to be called")
                }
                .padding(.horizontal, Spacing.screenHorizontal)
                .slideInFromBottom(delay: 0.4)

                // Feature highlights
                VStack(spacing: Spacing.sm) {
                    featureRow(icon: "barcode.viewfinder", color: Theme.primary,
                               title: "Scan Any Product",
                               subtitle: "Instantly check if a product matches your diet")
                        .staggerAnimation(index: 0, delay: 0.12)
                    featureRow(icon: "exclamationmark.triangle.fill", color: Theme.warning,
                               title: "Allergen Alerts",
                               subtitle: "Get warned about allergens & cross-contamination")
                        .staggerAnimation(index: 1, delay: 0.12)
                    featureRow(icon: "leaf.fill", color: Theme.primaryLight,
                               title: "Environmental Impact",
                               subtitle: "See the carbon & water footprint of your food")
                        .staggerAnimation(index: 2, delay: 0.12)
                    featureRow(icon: "arrow.triangle.2.circlepath", color: Theme.info,
                               title: "Better Alternatives",
                               subtitle: "Discover safer, healthier options automatically")
                        .staggerAnimation(index: 3, delay: 0.12)
                }
                .padding(.horizontal, Spacing.screenHorizontal)

                Spacer().frame(height: Spacing.lg)
            }
        }
    }

    private func featureRow(icon: String, color: Color, title: String, subtitle: String) -> some View {
        HStack(spacing: Spacing.md) {
            Image(systemName: icon)
                .font(.system(size: 20, weight: .semibold))
                .foregroundColor(color)
                .frame(width: 44, height: 44)
                .background(
                    RoundedRectangle(cornerRadius: Spacing.radiusSM)
                        .fill(color.opacity(0.12))
                )
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(Theme.textPrimary)
                Text(subtitle)
                    .font(Typography.bodySmall)
                    .foregroundColor(Theme.textMuted)
            }

            Spacer()
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: Spacing.radiusMD)
                .fill(Theme.surfaceBase)
                .overlay(
                    RoundedRectangle(cornerRadius: Spacing.radiusMD)
                        .stroke(Color.white.opacity(0.06), lineWidth: 1)
                )
        )
        .accessibilityElement(children: .combine)
    }

    // MARK: - Page 1: Dietary Preferences

    private let dietChoices: [(id: String, emoji: String, name: String, desc: String)] = [
        ("vegan", "\u{1F331}", "Vegan", "No animal products"),
        ("vegetarian", "\u{1F95A}", "Vegetarian", "No meat or fish"),
        ("jain", "\u{1F549}\u{FE0F}", "Jain", "Strict non-violence diet"),
        ("halal", "\u{262A}\u{FE0F}", "Halal", "Islamic dietary law"),
        ("kosher", "\u{2721}\u{FE0F}", "Kosher", "Jewish dietary law"),
        ("pescatarian", "\u{1F41F}", "Pescatarian", "Fish but no meat"),
    ]

    private var dietPage: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: Spacing.lg) {
                Spacer().frame(height: Spacing.sm)

                onboardingHeader(
                    emoji: "\u{1F957}",
                    title: "Dietary Preferences",
                    subtitle: "Select all diets you follow.\nWe\u{2019}ll flag anything that doesn\u{2019}t match."
                )

                // Diet grid
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
                    ForEach(Array(dietChoices.enumerated()), id: \.element.id) { index, option in
                        let isSelected = preferencesManager.preferences.selectedDiets.contains(option.id)
                        Button(action: {
                            withAnimation(AnimationSystem.springResponsive) {
                                preferencesManager.toggleDiet(option.id)
                            }
                        }) {
                            VStack(spacing: 8) {
                                Text(option.emoji)
                                    .font(.system(size: 32))
                                Text(option.name)
                                    .font(.system(size: 15, weight: .semibold))
                                    .foregroundColor(isSelected ? Theme.textPrimary : Theme.textTertiary)
                                Text(option.desc)
                                    .font(Typography.overline)
                                    .foregroundColor(isSelected ? Theme.textSecondary : Theme.textMuted)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 18)
                            .background(
                                RoundedRectangle(cornerRadius: Spacing.radiusMD)
                                    .fill(isSelected ? Theme.primary.opacity(0.15) : Theme.surfaceBase)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: Spacing.radiusMD)
                                            .stroke(isSelected ? Theme.primary : Color.white.opacity(0.06), lineWidth: isSelected ? 2 : 1)
                                    )
                            )
                            .scaleEffect(isSelected ? 1.02 : 1.0)
                        }
                        .accessibilityLabel("\(option.name), \(option.desc)")
                        .accessibilityHint(isSelected ? "Double tap to deselect" : "Double tap to select")
                        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
                        .buttonPressAnimation()
                        .staggerAnimation(index: index, delay: 0.06)
                    }
                }
                .padding(.horizontal, Spacing.screenHorizontal)

                // Custom diet input
                VStack(alignment: .leading, spacing: 10) {
                    Text("Don\u{2019}t see your diet?")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(Theme.textSecondary)

                    HStack(spacing: 10) {
                        TextField("e.g., Keto, Paleo, Low-FODMAP", text: $customDietText)
                            .font(.system(size: 15, weight: .medium))
                            .foregroundColor(Theme.textPrimary)
                            .padding(Spacing.md)
                            .background(
                                RoundedRectangle(cornerRadius: Spacing.radiusSM)
                                    .fill(Theme.surfaceBase)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: Spacing.radiusSM)
                                            .stroke(Color.white.opacity(0.08), lineWidth: 1)
                                    )
                            )
                            .tint(Theme.primary)
                            .submitLabel(.done)
                            .onSubmit {
                                addCustomDiet()
                            }
                            .accessibilityLabel("Custom diet name")
                            .accessibilityHint("Enter a custom diet, for example Keto, Paleo, or Low-FODMAP")

                        Button(action: { addCustomDiet() }) {
                            Image(systemName: "plus.circle.fill")
                                .font(.system(size: 28, weight: .semibold))
                                .foregroundStyle(
                                    LinearGradient(
                                        colors: [Theme.primary, Theme.primaryLight],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                )
                        }
                        .accessibilityLabel("Add custom diet")
                        .accessibilityHint("Adds the entered custom diet to your selections")
                        .buttonPressAnimation()
                    }
                }
                .padding(.horizontal, Spacing.screenHorizontal)
                .slideInFromBottom(delay: 0.4)

                infoNote(text: "No diet selected? That\u{2019}s fine \u{2014} we\u{2019}ll still check for allergens and nutrition.")

                if !preferencesManager.preferences.selectedDiets.isEmpty {
                    selectedSummary(
                        items: Array(preferencesManager.preferences.selectedDiets).sorted().map { $0.capitalized },
                        color: Theme.primary
                    )
                }

                Spacer().frame(height: Spacing.lg)
            }
        }
    }

    // MARK: - Page 2: Allergens

    private let allergenChoices: [(id: String, emoji: String, name: String)] = [
        ("gluten", "\u{1F33E}", "Gluten"),
        ("dairy", "\u{1F95B}", "Dairy"),
        ("nuts", "\u{1F95C}", "Nuts"),
        ("soy", "\u{1FAD8}", "Soy"),
        ("eggs", "\u{1F95A}", "Eggs"),
        ("shellfish", "\u{1F990}", "Shellfish"),
        ("peanuts", "\u{1F95C}", "Peanuts"),
        ("treenuts", "\u{1F330}", "Tree Nuts"),
        ("fish", "\u{1F41F}", "Fish"),
        ("sesame", "\u{1FAD3}", "Sesame"),
    ]

    private var allergenPage: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: Spacing.lg) {
                Spacer().frame(height: Spacing.sm)

                onboardingHeader(
                    emoji: "\u{26A0}\u{FE0F}",
                    title: "Allergens",
                    subtitle: "Select any allergens you need to avoid.\nWe\u{2019}ll alert you if a product contains them."
                )

                // Allergen grid
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
                    ForEach(Array(allergenChoices.enumerated()), id: \.element.id) { index, option in
                        let isSelected = preferencesManager.preferences.selectedAllergens.contains(option.id.lowercased())
                        Button(action: {
                            withAnimation(AnimationSystem.springResponsive) {
                                preferencesManager.toggleAllergen(option.id)
                            }
                        }) {
                            VStack(spacing: 6) {
                                Text(option.emoji)
                                    .font(.system(size: 28))
                                Text(option.name)
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundColor(isSelected ? Theme.textPrimary : Theme.textTertiary)
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.8)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, Spacing.md)
                            .background(
                                RoundedRectangle(cornerRadius: Spacing.radiusMD)
                                    .fill(isSelected ? Theme.warning.opacity(0.15) : Theme.surfaceBase)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: Spacing.radiusMD)
                                            .stroke(isSelected ? Theme.warning : Color.white.opacity(0.06), lineWidth: isSelected ? 2 : 1)
                                    )
                            )
                            .scaleEffect(isSelected ? 1.03 : 1.0)
                        }
                        .accessibilityLabel(option.name)
                        .accessibilityHint(isSelected ? "Double tap to deselect this allergen" : "Double tap to select this allergen")
                        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
                        .buttonPressAnimation()
                        .staggerAnimation(index: index, delay: 0.05)
                    }
                }
                .padding(.horizontal, Spacing.screenHorizontal)

                infoNote(text: "No allergies? Skip ahead \u{2014} you can always add them later in Settings.")

                if !preferencesManager.preferences.selectedAllergens.isEmpty {
                    selectedSummary(
                        items: Array(preferencesManager.preferences.selectedAllergens).sorted().map { $0.capitalized },
                        color: Theme.warning
                    )
                }

                Spacer().frame(height: Spacing.lg)
            }
        }
    }

    // MARK: - Page 3: May-Contain Strictness

    private var mayContainPage: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: Spacing.lg) {
                Spacer().frame(height: Spacing.sm)

                onboardingHeader(
                    emoji: "\u{1F3ED}",
                    title: "\"May Contain\" Warnings",
                    subtitle: "Products are sometimes made in facilities that also process allergens. How should we handle this?"
                )

                // Explanation card
                VStack(alignment: .leading, spacing: 14) {
                    HStack(spacing: 10) {
                        Image(systemName: "info.circle.fill")
                            .font(.system(size: 18))
                            .foregroundColor(Theme.info)
                            .accessibilityHidden(true)
                        Text("What does this mean?")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundColor(Theme.textPrimary)
                    }

                    Text("Labels like \"may contain traces of nuts\" or \"made in a facility that processes milk\" indicate possible cross-contamination \u{2014} not guaranteed ingredients.")
                        .font(Typography.body)
                        .foregroundColor(Theme.textMuted)
                        .lineSpacing(4)

                    HStack(spacing: 8) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 12))
                            .foregroundColor(Theme.warning)
                            .accessibilityHidden(true)
                        Text("For severe allergies (e.g. anaphylaxis), treating these as unsafe is strongly recommended.")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(Theme.warning.opacity(0.9))
                            .lineSpacing(3)
                    }
                }
                .padding(18)
                .background(
                    RoundedRectangle(cornerRadius: Spacing.radiusMD)
                        .fill(Theme.surfaceBase)
                        .overlay(
                            RoundedRectangle(cornerRadius: Spacing.radiusMD)
                                .stroke(Color.white.opacity(0.06), lineWidth: 1)
                        )
                )
                .padding(.horizontal, Spacing.screenHorizontal)
                .accessibilityElement(children: .combine)
                .slideInFromBottom(delay: 0.1)

                // Two option cards
                VStack(spacing: 14) {
                    mayContainOption(
                        isSelected: !preferencesManager.preferences.mayContainSafe,
                        icon: "exclamationmark.shield.fill",
                        iconColor: Theme.error,
                        title: "Strict \u{2014} Treat as Unsafe",
                        description: "Products with \"may contain\" warnings for your allergens will be flagged as unsafe. Best for severe allergies.",
                        action: { preferencesManager.preferences.mayContainSafe = false }
                    )
                    .staggerAnimation(index: 0, delay: 0.1)

                    mayContainOption(
                        isSelected: preferencesManager.preferences.mayContainSafe,
                        icon: "info.circle.fill",
                        iconColor: Theme.info,
                        title: "Relaxed \u{2014} Show as Warning",
                        description: "\"May contain\" items appear as caution notes but won\u{2019}t mark the product unsafe. Good for mild sensitivities.",
                        action: { preferencesManager.preferences.mayContainSafe = true }
                    )
                    .staggerAnimation(index: 1, delay: 0.1)
                }
                .padding(.horizontal, Spacing.screenHorizontal)

                // Current selection indicator pill
                HStack(spacing: 8) {
                    Image(systemName: preferencesManager.preferences.mayContainSafe ? "info.circle.fill" : "exclamationmark.shield.fill")
                        .foregroundColor(preferencesManager.preferences.mayContainSafe ? Theme.info : Theme.error)
                        .accessibilityHidden(true)

                    Text(preferencesManager.preferences.mayContainSafe
                         ? "\"May contain\" = informational warning"
                         : "\"May contain\" = treated as unsafe")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(Theme.textTertiary)
                }
                .padding(.vertical, 12)
                .padding(.horizontal, 20)
                .background(
                    Capsule()
                        .fill(Theme.surfaceBase)
                        .overlay(Capsule().stroke(Color.white.opacity(0.06), lineWidth: 1))
                )
                .accessibilityElement(children: .combine)
                .accessibilityLabel(preferencesManager.preferences.mayContainSafe
                    ? "Current setting: May contain labels shown as informational warning"
                    : "Current setting: May contain labels treated as unsafe")
                .animation(AnimationSystem.springResponsive, value: preferencesManager.preferences.mayContainSafe)

                infoNote(text: "You can change this anytime in Settings.")

                Spacer().frame(height: Spacing.lg)
            }
        }
    }

    private func mayContainOption(isSelected: Bool, icon: String, iconColor: Color, title: String, description: String, action: @escaping () -> Void) -> some View {
        Button(action: { withAnimation(AnimationSystem.springResponsive) { action() } }) {
            HStack(alignment: .top, spacing: 14) {
                // Radio circle
                ZStack {
                    Circle()
                        .stroke(isSelected ? Theme.primary : Color(hex: "444444"), lineWidth: 2)
                        .frame(width: 24, height: 24)
                    if isSelected {
                        Circle()
                            .fill(Theme.primary)
                            .frame(width: 14, height: 14)
                            .transition(.scale.combined(with: .opacity))
                    }
                }
                .padding(.top, 2)
                .animation(AnimationSystem.springBouncy, value: isSelected)
                .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 8) {
                        Image(systemName: icon)
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(iconColor)
                            .accessibilityHidden(true)
                        Text(title)
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundColor(Theme.textPrimary)
                    }

                    Text(description)
                        .font(Typography.bodySmall)
                        .foregroundColor(Theme.textMuted)
                        .lineSpacing(3)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer()
            }
            .padding(Spacing.md)
            .background(
                RoundedRectangle(cornerRadius: Spacing.radiusMD)
                    .fill(isSelected ? Theme.primary.opacity(0.08) : Theme.surfaceBase)
                    .overlay(
                        RoundedRectangle(cornerRadius: Spacing.radiusMD)
                            .stroke(isSelected ? Theme.primary.opacity(0.5) : Color.white.opacity(0.06), lineWidth: isSelected ? 2 : 1)
                    )
            )
        }
        .accessibilityLabel("\(title). \(description)")
        .accessibilityHint(isSelected ? "Currently selected" : "Double tap to select")
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
        .buttonStyle(.plain)
    }

    // MARK: - Page 4: GMO Preference

    private var avoidGMOPage: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: Spacing.lg) {
                Spacer().frame(height: Spacing.sm)

                onboardingHeader(
                    emoji: "\u{1F9EC}",
                    title: "GMO Preferences",
                    subtitle: "Some products contain genetically modified organisms. How should we handle GMO ingredients?"
                )

                // Explanation card
                VStack(alignment: .leading, spacing: 14) {
                    HStack(spacing: 10) {
                        Image(systemName: "info.circle.fill")
                            .font(.system(size: 18))
                            .foregroundColor(Theme.info)
                            .accessibilityHidden(true)
                        Text("What are GMOs?")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundColor(Theme.textPrimary)
                    }

                    Text("Genetically modified organisms (GMOs) are common in products containing corn, soy, canola, and sugar beets. Some users prefer to avoid them for personal, dietary, or religious reasons.")
                        .font(Typography.body)
                        .foregroundColor(Theme.textMuted)
                        .lineSpacing(4)
                }
                .padding(18)
                .background(
                    RoundedRectangle(cornerRadius: Spacing.radiusMD)
                        .fill(Theme.surfaceBase)
                        .overlay(
                            RoundedRectangle(cornerRadius: Spacing.radiusMD)
                                .stroke(Color.white.opacity(0.06), lineWidth: 1)
                        )
                )
                .padding(.horizontal, Spacing.screenHorizontal)
                .accessibilityElement(children: .combine)
                .slideInFromBottom(delay: 0.1)

                // Two option cards
                VStack(spacing: 14) {
                    mayContainOption(
                        isSelected: !preferencesManager.preferences.avoidGMO,
                        icon: "info.circle.fill",
                        iconColor: Theme.info,
                        title: "No Preference",
                        description: "GMO information is shown for reference only. Products won\u{2019}t be marked unsafe for containing GMOs.",
                        action: { preferencesManager.preferences.avoidGMO = false }
                    )
                    .staggerAnimation(index: 0, delay: 0.1)

                    mayContainOption(
                        isSelected: preferencesManager.preferences.avoidGMO,
                        icon: "exclamationmark.triangle.fill",
                        iconColor: Theme.warning,
                        title: "Avoid GMO",
                        description: "Products with confirmed GMO ingredients will be flagged as unsafe.",
                        action: { preferencesManager.preferences.avoidGMO = true }
                    )
                    .staggerAnimation(index: 1, delay: 0.1)
                }
                .padding(.horizontal, Spacing.screenHorizontal)

                // Current selection indicator pill
                HStack(spacing: 8) {
                    Image(systemName: preferencesManager.preferences.avoidGMO ? "exclamationmark.triangle.fill" : "info.circle.fill")
                        .foregroundColor(preferencesManager.preferences.avoidGMO ? Theme.warning : Theme.info)
                        .accessibilityHidden(true)

                    Text(preferencesManager.preferences.avoidGMO
                         ? "GMO products = flagged as unsafe"
                         : "GMO info = shown for reference only")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(Theme.textTertiary)
                }
                .padding(.vertical, 12)
                .padding(.horizontal, 20)
                .background(
                    Capsule()
                        .fill(Theme.surfaceBase)
                        .overlay(Capsule().stroke(Color.white.opacity(0.06), lineWidth: 1))
                )
                .accessibilityElement(children: .combine)
                .accessibilityLabel(preferencesManager.preferences.avoidGMO
                    ? "Current setting: GMO products flagged as unsafe"
                    : "Current setting: GMO information shown for reference only")
                .animation(AnimationSystem.springResponsive, value: preferencesManager.preferences.avoidGMO)

                infoNote(text: "You can change this anytime in Settings.")

                Spacer().frame(height: Spacing.lg)
            }
        }
    }

    // MARK: - Page 5: Priorities

    private var prioritiesPage: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: Spacing.lg) {
                Spacer().frame(height: Spacing.sm)

                onboardingHeader(
                    emoji: "\u{2696}\u{FE0F}",
                    title: "What Matters Most?",
                    subtitle: "When we suggest alternatives, how should we rank them? Adjust the sliders."
                )

                VStack(spacing: Spacing.md) {
                    prioritySlider(
                        icon: "heart.fill",
                        color: Color(hex: "E57373"),
                        name: "Health",
                        subtitle: "Nutrition, additives, processing",
                        value: Binding(
                            get: { preferencesManager.preferences.healthPriority },
                            set: {
                                preferencesManager.preferences.adjustPriority(changed: "health", newValue: $0)
                            }
                        ),
                        percentage: Int(preferencesManager.preferences.healthPriority)
                    )
                    .staggerAnimation(index: 0, delay: 0.1)

                    prioritySlider(
                        icon: "leaf.fill",
                        color: Color(hex: "66BB6A"),
                        name: "Environment",
                        subtitle: "Carbon footprint, water usage, packaging",
                        value: Binding(
                            get: { preferencesManager.preferences.environmentPriority },
                            set: {
                                preferencesManager.preferences.adjustPriority(changed: "environment", newValue: $0)
                            }
                        ),
                        percentage: Int(preferencesManager.preferences.environmentPriority)
                    )
                    .staggerAnimation(index: 1, delay: 0.1)

                    prioritySlider(
                        icon: "checkmark.seal.fill",
                        color: Color(hex: "42A5F5"),
                        name: "Ethics & Certifications",
                        subtitle: "Fair trade, cruelty-free, organic",
                        value: Binding(
                            get: { preferencesManager.preferences.ethicsPriority },
                            set: {
                                preferencesManager.preferences.adjustPriority(changed: "ethics", newValue: $0)
                            }
                        ),
                        percentage: Int(preferencesManager.preferences.ethicsPriority)
                    )
                    .staggerAnimation(index: 2, delay: 0.1)
                }
                .padding(.horizontal, Spacing.screenHorizontal)

                // All-set celebration
                let greeting = nameText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    ? "You\u{2019}re all set!"
                    : "\(nameText.trimmingCharacters(in: .whitespacesAndNewlines)), you\u{2019}re all set!"

                VStack(spacing: 10) {
                    Text("\u{1F389}")
                        .font(.system(size: 44))
                        .accessibilityHidden(true)
                        .scaleIn(delay: 0.4)

                    Text(greeting)
                        .font(Typography.h3)
                        .foregroundColor(Theme.textPrimary)
                        .accessibilityAddTraits(.isHeader)
                        .slideInFromBottom(delay: 0.5)

                    Text("Tap \"Get Started\" to begin scanning.")
                        .font(Typography.body)
                        .foregroundColor(Theme.textMuted)
                        .slideInFromBottom(delay: 0.6)
                }
                .padding(.top, Spacing.sm)

                Spacer().frame(height: Spacing.lg)
            }
        }
    }

    private func prioritySlider(icon: String, color: Color, name: String, subtitle: String, value: Binding<Double>, percentage: Int) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: icon)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(color)
                    .frame(width: 32, height: 32)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(color.opacity(0.12))
                    )
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 2) {
                    Text(name)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(Theme.textPrimary)
                    Text(subtitle)
                        .font(Typography.caption)
                        .foregroundColor(Theme.textMuted)
                }

                Spacer()

                Text("\(percentage)%")
                    .font(Typography.numberSmall)
                    .foregroundColor(color)
                    .accessibilityHidden(true)
            }

            Slider(value: value, in: 0...100, step: 5)
                .accentColor(color)
                .accessibilityLabel("\(name) priority")
                .accessibilityValue("\(percentage) percent")
                .accessibilityHint("Adjusts the \(name.lowercased()) priority. \(subtitle)")
        }
        .padding(Spacing.md)
        .background(
            RoundedRectangle(cornerRadius: Spacing.radiusMD)
                .fill(Theme.surfaceBase)
                .overlay(
                    RoundedRectangle(cornerRadius: Spacing.radiusMD)
                        .stroke(Color.white.opacity(0.06), lineWidth: 1)
                )
        )
    }

    // MARK: - Shared Components

    private func addCustomDiet() {
        let trimmed = customDietText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        withAnimation(AnimationSystem.springResponsive) {
            preferencesManager.toggleDiet(trimmed)
        }
        customDietText = ""
    }

    private func onboardingHeader(emoji: String, title: String, subtitle: String) -> some View {
        VStack(spacing: 10) {
            Text(emoji)
                .font(.system(size: 44))
                .accessibilityHidden(true)
                .scaleIn(delay: 0.05)

            Text(title)
                .font(Typography.h1)
                .foregroundColor(Theme.textPrimary)
                .accessibilityAddTraits(.isHeader)
                .slideInFromBottom(delay: 0.1)

            Text(subtitle)
                .font(Typography.body)
                .foregroundColor(Theme.textMuted)
                .multilineTextAlignment(.center)
                .lineSpacing(4)
                .slideInFromBottom(delay: 0.15)
        }
        .padding(.horizontal, Spacing.screenHorizontal)
    }

    private func infoNote(text: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "lightbulb.fill")
                .font(.system(size: 13))
                .foregroundColor(Theme.warning)
                .accessibilityHidden(true)
            Text(text)
                .font(Typography.bodySmall)
                .foregroundColor(Theme.textMuted)
        }
        .padding(.horizontal, Spacing.screenHorizontal + 8)
        .accessibilityElement(children: .combine)
    }

    private func selectedSummary(items: [String], color: Color) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Selected:")
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(Theme.textMuted)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(items, id: \.self) { item in
                        Text(item)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(color)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(
                                Capsule()
                                    .fill(color.opacity(0.12))
                                    .overlay(
                                        Capsule()
                                            .stroke(color.opacity(0.3), lineWidth: 1)
                                    )
                            )
                    }
                }
            }
        }
        .padding(.horizontal, Spacing.screenHorizontal)
        .transition(.opacity.combined(with: .move(edge: .bottom)))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Selected: \(items.joined(separator: ", "))")
    }
}

struct OnboardingView_Previews: PreviewProvider {
    static var previews: some View {
        OnboardingView(
            preferencesManager: PreferencesManager.shared,
            onComplete: {}
        )
    }
}
