//
//  PlateAnalysisResultView.swift
//  Ethica
//
//  Premium plate analysis results — glass morphism, staggered animations
//

import SwiftUI
import Combine

struct PlateAnalysisResultView: View {
    let analysis: [String: Any]
    let onDismiss: () -> Void

    /// Mutable model — starts from Phase 1 data, enriched when Phase 2 arrives
    @State private var model: PlateAnalysis

    init(analysis: [String: Any], onDismiss: @escaping () -> Void) {
        self.analysis = analysis
        self.onDismiss = onDismiss
        self._model = State(initialValue: PlateAnalysis(from: analysis))
    }

    @State private var selectedSection: PlateSection = .overview
    @State private var tabDirection: Edge = .trailing
    @Namespace private var tabNamespace

    enum PlateSection: String, CaseIterable {
        case overview = "Overview"
        case risks = "Risks"
        case actions = "Actions"

        var icon: String {
            switch self {
            case .overview: return "fork.knife"
            case .risks: return "exclamationmark.triangle.fill"
            case .actions: return "checkmark.circle.fill"
            }
        }
    }

    // MARK: - Share

    private var shareSummary: String {
        "\(dishName) — \(plateSafety.title)\nConfidence: \(confidence)%\nRisks: \(hiddenRisks.count)\nRecommendation: \(recommendation)\n\nAnalyzed with Ethica"
    }

    // MARK: - Derived properties

    private var dishName: String { model.dishName ?? "Unknown Dish" }
    private var cuisineType: String { model.cuisineType ?? "" }
    private var visibleIngredients: [String] { model.visibleIngredients ?? [] }
    private var likelyContains: [String] { model.likelyContains ?? [] }
    private var hiddenRisks: [PlateAnalysis.HiddenRisk] { model.hiddenRisks ?? [] }
    private var questionsToAskStaff: [String] { model.questionsToAskStaff ?? [] }
    private var alternativeOptions: [String] { model.alternativeOptions ?? [] }
    private var isLikelySafe: Bool { model.safetyAssessment?.isLikelySafe ?? false }
    private var confidence: Int { Int(model.safetyAssessment?.confidence ?? 0) }
    private var confidenceLevel: String { model.safetyAssessment?.confidenceLevel ?? "Unknown" }
    private var recommendation: String { model.safetyAssessment?.recommendation ?? "Cannot determine" }
    private var primaryConcerns: [String] { model.safetyAssessment?.primaryConcerns ?? [] }

    private var plateSafety: PlateSafetyState {
        if recommendation.lowercased().contains("avoid") || (!isLikelySafe && confidence >= 70) {
            return .avoid
        } else if !isLikelySafe || !primaryConcerns.isEmpty || !hiddenRisks.isEmpty {
            return .caution
        } else {
            return .safe
        }
    }

    // MARK: - Body

    var body: some View {
        ZStack {
            Theme.backgroundPrimary.ignoresSafeArea()

            VStack(spacing: 0) {
                // Header
                headerSection
                    .slideInFromTop(delay: 0.05)

                // Tab bar
                tabBar
                    .slideInFromBottom(delay: 0.1)

                // Scrollable content
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(spacing: Spacing.md) {
                        sectionContent
                    }
                    .padding(.horizontal, Spacing.screenHorizontal)
                    .padding(.vertical, Spacing.lg)
                }

                // Bottom action
                bottomAction
                    .slideInFromBottom(delay: 0.15)
            }
        }
        .onAppear {
            if plateSafety == .avoid {
                HapticManager.shared.trigger(.warning)
            }
        }
        .onReceive(NetworkService.plateDetailSubject.compactMap { $0 }) { detail in
            withAnimation(.easeInOut(duration: 0.3)) {
                model = model.merging(with: detail)
            }
        }
    }

    // MARK: - Header

    private var headerSection: some View {
        VStack(spacing: Spacing.md) {
            // Top bar: dismiss + confidence badge
            HStack {
                Button(action: onDismiss) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 28))
                        .foregroundColor(Theme.textMuted)
                }
                .accessibilityLabel("Dismiss")

                Spacer()

                // Share button
                ShareLink(item: shareSummary) {
                    Image(systemName: "square.and.arrow.up.circle.fill")
                        .font(.system(size: 28))
                        .foregroundColor(Theme.textMuted)
                }

                // Confidence pill
                HStack(spacing: 6) {
                    Circle()
                        .fill(plateSafety.color)
                        .frame(width: 8, height: 8)
                    Text("\(confidence)% confidence")
                        .font(.system(size: 12, weight: .bold, design: .rounded))
                        .foregroundColor(plateSafety.color)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .background(plateSafety.color.opacity(0.12))
                .cornerRadius(Spacing.radiusPill)
                .overlay(
                    RoundedRectangle(cornerRadius: Spacing.radiusPill)
                        .stroke(plateSafety.color.opacity(0.2), lineWidth: 1)
                )
            }

            // Hero verdict card
            heroVerdictCard
                .scaleIn(delay: 0.15)
        }
        .padding(.horizontal, Spacing.screenHorizontal)
        .padding(.top, Spacing.md)
        .padding(.bottom, Spacing.sm)
    }

    @ViewBuilder
    private var heroVerdictCard: some View {
        let state = plateSafety

        GlassCard(variant: state.variant) {
            VStack(spacing: Spacing.md) {
                // Accent capsule
                Capsule()
                    .fill(state.color)
                    .frame(width: 60, height: 3)

                // Glowing icon
                ZStack {
                    Circle()
                        .fill(state.color.opacity(0.15))
                        .frame(width: 72, height: 72)
                        .blur(radius: 8)

                    Image(systemName: state.icon)
                        .font(.system(size: 48))
                        .foregroundColor(state.color)
                }
                .glowPulse(color: state.color, intensity: 0.5, speed: 2.0)

                // Dish name
                Text(dishName)
                    .font(Typography.h2)
                    .foregroundColor(Theme.textPrimary)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)

                // Cuisine type
                if !cuisineType.isEmpty {
                    Text(cuisineType)
                        .textStyleCaption(color: Theme.textMuted)
                }

                // Safety title
                Text(state.title)
                    .font(Typography.body)
                    .foregroundColor(state.color)

                // Recommendation pill
                HStack(spacing: 8) {
                    Image(systemName: state.icon)
                        .font(.system(size: 13, weight: .semibold))
                    Text(recommendation)
                        .font(.system(size: 14, weight: .semibold))
                }
                .foregroundColor(state.color)
                .padding(.horizontal, Spacing.md)
                .padding(.vertical, 10)
                .frame(maxWidth: .infinity)
                .background(state.color.opacity(0.1))
                .cornerRadius(Spacing.radiusSM)
                .overlay(
                    RoundedRectangle(cornerRadius: Spacing.radiusSM)
                        .stroke(state.color.opacity(0.2), lineWidth: 1)
                )
            }
            .frame(maxWidth: .infinity)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(dishName). Safety: \(recommendation). Confidence \(confidence) percent.")
    }

    // MARK: - Tab Bar

    private var tabBar: some View {
        HStack(spacing: 6) {
            ForEach(PlateSection.allCases, id: \.self) { section in
                Button(action: {
                    let allCases = PlateSection.allCases
                    let oldIndex = allCases.firstIndex(of: selectedSection) ?? 0
                    let newIndex = allCases.firstIndex(of: section) ?? 0
                    tabDirection = newIndex > oldIndex ? .trailing : .leading
                    withAnimation(AnimationSystem.springResponsive) {
                        selectedSection = section
                    }
                    HapticManager.shared.trigger(.impactLight)
                }) {
                    HStack(spacing: 6) {
                        Image(systemName: section.icon)
                            .font(.system(size: 12, weight: .semibold))
                        Text(section.rawValue)
                            .font(.system(size: 13, weight: .bold))
                    }
                    .foregroundColor(selectedSection == section ? .white : Theme.textMuted)
                    .padding(.vertical, 10)
                    .padding(.horizontal, 18)
                    .background(
                        ZStack {
                            if selectedSection == section {
                                RoundedRectangle(cornerRadius: Spacing.radiusSM)
                                    .fill(plateSafety.color.opacity(0.85))
                                    .matchedGeometryEffect(id: "activeTab", in: tabNamespace)
                            } else {
                                RoundedRectangle(cornerRadius: Spacing.radiusSM)
                                    .fill(Theme.surfaceSecondary)
                            }
                        }
                    )
                    .cornerRadius(Spacing.radiusSM)
                    .overlay(
                        RoundedRectangle(cornerRadius: Spacing.radiusSM)
                            .stroke(
                                selectedSection == section
                                    ? plateSafety.color.opacity(0.4)
                                    : Color.white.opacity(0.05),
                                lineWidth: 1
                            )
                    )
                }
                .buttonPressAnimation()
            }
        }
        .padding(.horizontal, Spacing.screenHorizontal)
        .padding(.vertical, Spacing.sm)
    }

    // MARK: - Section Content

    @ViewBuilder
    private var sectionContent: some View {
        let opposite: Edge = tabDirection == .trailing ? .leading : .trailing
        Group {
            switch selectedSection {
            case .overview: overviewContent
            case .risks: risksContent
            case .actions: actionsContent
            }
        }
        .id(selectedSection)
        .transition(.asymmetric(
            insertion: .move(edge: tabDirection).combined(with: .opacity),
            removal: .move(edge: opposite).combined(with: .opacity)
        ))
    }

    // MARK: - Overview

    private var overviewContent: some View {
        VStack(spacing: Spacing.md) {
            // Quick stats row
            if confidence > 0 || !hiddenRisks.isEmpty {
                quickStatsRow
                    .slideInFromBottom(delay: 0.05)
            }

            // Visible Ingredients
            if !visibleIngredients.isEmpty {
                plateGlassCard(
                    title: "Visible Ingredients",
                    icon: "eye.fill",
                    color: Theme.success
                ) {
                    ingredientChips(visibleIngredients, color: Theme.success)
                }
                .slideInFromBottom(delay: 0.1)
            }

            // Likely Contains
            if !likelyContains.isEmpty {
                plateGlassCard(
                    title: "Likely Contains",
                    icon: "questionmark.circle.fill",
                    color: Theme.warning
                ) {
                    ingredientChips(likelyContains, color: Theme.warning)
                }
                .slideInFromBottom(delay: 0.15)
            }

            // Primary Concerns
            if !primaryConcerns.isEmpty {
                plateGlassCard(
                    title: "Key Concerns",
                    icon: "exclamationmark.circle.fill",
                    color: Theme.error
                ) {
                    VStack(alignment: .leading, spacing: 10) {
                        ForEach(primaryConcerns, id: \.self) { concern in
                            HStack(alignment: .top, spacing: 10) {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .font(.system(size: 12))
                                    .foregroundColor(Theme.error)
                                    .offset(y: 2)

                                Text(concern)
                                    .textStyleBody(color: Theme.textTertiary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }
                }
                .slideInFromBottom(delay: 0.2)
            }

            // All clear state
            if primaryConcerns.isEmpty && hiddenRisks.isEmpty && isLikelySafe {
                GlassCard(variant: .success) {
                    HStack(spacing: Spacing.md) {
                        Image(systemName: "checkmark.seal.fill")
                            .font(.system(size: 28))
                            .foregroundColor(Theme.success)

                        VStack(alignment: .leading, spacing: 4) {
                            Text("Looks Good!")
                                .font(Typography.h3)
                                .foregroundColor(Theme.textPrimary)

                            Text("No major dietary concerns detected. Always verify with staff for hidden ingredients.")
                                .textStyleBodySmall(color: Theme.textTertiary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
                .slideInFromBottom(delay: 0.1)
            }
        }
    }

    private var quickStatsRow: some View {
        HStack(spacing: Spacing.sm) {
            ScoreCircle(
                score: Double(confidence),
                size: .small,
                showLabel: true,
                label: "Confidence",
                colorScheme: .custom(plateSafety.color),
                showGlow: true
            )
            .scaleIn(delay: 0.1)

            statPill(
                title: "Risks",
                value: "\(hiddenRisks.count)",
                icon: "exclamationmark.triangle.fill",
                color: hiddenRisks.isEmpty ? Theme.success : Theme.warning
            )
            .scaleIn(delay: 0.15)

            statPill(
                title: "Ingredients",
                value: "\(visibleIngredients.count)",
                icon: "leaf.fill",
                color: Theme.primary
            )
            .scaleIn(delay: 0.2)
        }
    }

    private func statPill(title: String, value: String, icon: String, color: Color) -> some View {
        VStack(spacing: 4) {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 11))
                Text(value)
                    .font(Typography.numberSmall)
            }
            .foregroundColor(color)

            Text(title)
                .font(Typography.overline)
                .foregroundColor(Theme.textMuted)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 14)
        .background(Theme.surfaceSecondary)
        .cornerRadius(Spacing.radiusSM)
        .overlay(
            RoundedRectangle(cornerRadius: Spacing.radiusSM)
                .stroke(Color.white.opacity(0.05), lineWidth: 1)
        )
    }

    @ViewBuilder
    private func ingredientChips(_ items: [String], color: Color) -> some View {
        if #available(iOS 16.0, *) {
            FlowLayout(spacing: 8) {
                ForEach(Array(items.enumerated()), id: \.element) { index, item in
                    chipView(item, color: color)
                        .scaleIn(delay: 0.05 * Double(index))
                }
            }
        } else {
            WrappingHStack(items: items, color: color)
        }
    }

    private func chipView(_ text: String, color: Color) -> some View {
        Text(text)
            .font(.system(size: 13, weight: .medium))
            .foregroundColor(color)
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(color.opacity(0.1))
            .cornerRadius(Spacing.radiusXS)
            .overlay(
                RoundedRectangle(cornerRadius: Spacing.radiusXS)
                    .stroke(color.opacity(0.2), lineWidth: 1)
            )
    }

    // MARK: - Risks

    private var risksContent: some View {
        VStack(spacing: Spacing.md) {
            if hiddenRisks.isEmpty {
                GlassCard(variant: .success) {
                    HStack(spacing: Spacing.md) {
                        Image(systemName: "checkmark.shield.fill")
                            .font(.system(size: 28))
                            .foregroundColor(Theme.success)

                        VStack(alignment: .leading, spacing: 4) {
                            Text("No Hidden Risks")
                                .font(Typography.h3)
                                .foregroundColor(Theme.textPrimary)

                            Text("No major hidden risks identified for your dietary preferences.")
                                .textStyleBodySmall(color: Theme.textTertiary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
                .slideInFromBottom(delay: 0.05)
            } else {
                ForEach(Array(hiddenRisks.enumerated()), id: \.element.id) { index, risk in
                    HiddenRiskCard(risk: risk)
                        .slideInFromBottom(delay: 0.05 + Double(index) * 0.07)
                }
            }

            // Disclaimer banner
            disclaimerBanner
                .slideInFromBottom(delay: 0.15 + Double(hiddenRisks.count) * 0.07)
        }
    }

    private var disclaimerBanner: some View {
        GlassCard(variant: .warning, padding: Spacing.sm + 4) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "info.circle.fill")
                    .font(.system(size: 15))
                    .foregroundColor(Theme.warning)
                    .offset(y: 1)

                Text("Visual analysis has limitations. Cross-contamination and hidden ingredients cannot be detected from photos alone. Always confirm with restaurant staff.")
                    .textStyleCaption(color: Theme.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    // MARK: - Actions

    private var actionsContent: some View {
        VStack(spacing: Spacing.md) {
            if !model.isComplete {
                // Phase 2 still loading — show shimmer placeholders
                actionsLoadingPlaceholder
                    .slideInFromBottom(delay: 0.05)
            } else {
                // Questions to ask staff
                if !questionsToAskStaff.isEmpty {
                    plateGlassCard(
                        title: "Ask the Staff",
                        icon: "bubble.left.and.bubble.right.fill",
                        color: Theme.accent
                    ) {
                        VStack(spacing: Spacing.sm) {
                            ForEach(Array(questionsToAskStaff.enumerated()), id: \.offset) { index, question in
                                HStack(alignment: .top, spacing: 12) {
                                    Text("\(index + 1)")
                                        .font(.system(size: 12, weight: .bold, design: .rounded))
                                        .foregroundColor(Theme.accent)
                                        .frame(width: 26, height: 26)
                                        .background(Theme.accent.opacity(0.15))
                                        .cornerRadius(13)

                                    Text(question)
                                        .textStyleBody(color: Theme.textTertiary)
                                        .fixedSize(horizontal: false, vertical: true)

                                    Spacer(minLength: 0)
                                }
                            }
                        }
                    }
                    .slideInFromBottom(delay: 0.05)
                }

                // Alternative options
                if !alternativeOptions.isEmpty {
                    plateGlassCard(
                        title: "Safer Alternatives",
                        icon: "lightbulb.fill",
                        color: Theme.success
                    ) {
                        VStack(spacing: Spacing.sm) {
                            ForEach(alternativeOptions, id: \.self) { option in
                                HStack(spacing: 10) {
                                    Image(systemName: "arrow.right.circle.fill")
                                        .font(.system(size: 14))
                                        .foregroundColor(Theme.success)

                                    Text(option)
                                        .textStyleBody(color: Theme.textTertiary)
                                        .fixedSize(horizontal: false, vertical: true)

                                    Spacer(minLength: 0)
                                }
                                .padding(Spacing.sm + 4)
                                .background(Theme.success.opacity(0.06))
                                .cornerRadius(Spacing.radiusSM)
                                .overlay(
                                    RoundedRectangle(cornerRadius: Spacing.radiusSM)
                                        .stroke(Theme.success.opacity(0.1), lineWidth: 1)
                                )
                            }
                        }
                    }
                    .slideInFromBottom(delay: 0.1)
                }

                // Empty state — only show after detail loaded and still empty
                if questionsToAskStaff.isEmpty && alternativeOptions.isEmpty {
                    GlassCard(variant: .success) {
                        HStack(spacing: Spacing.md) {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 28))
                                .foregroundColor(Theme.success)

                            VStack(alignment: .leading, spacing: 4) {
                                Text("No Actions Needed")
                                    .font(Typography.h3)
                                    .foregroundColor(Theme.textPrimary)

                                Text("This dish appears compatible with your dietary preferences. Enjoy your meal!")
                                    .textStyleBodySmall(color: Theme.textTertiary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }
                    .slideInFromBottom(delay: 0.05)
                }
            }
        }
    }

    // MARK: - Actions Loading Placeholder

    private var actionsLoadingPlaceholder: some View {
        VStack(spacing: Spacing.md) {
            GlassCard(variant: .secondary) {
                VStack(spacing: Spacing.md) {
                    HStack(spacing: Spacing.md) {
                        ProgressView()
                            .tint(Theme.accent)
                        Text("Loading suggestions...")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(Theme.textMuted)
                        Spacer()
                    }

                    // Shimmer bars
                    ForEach(0..<3, id: \.self) { _ in
                        shimmerBar
                    }
                }
            }
        }
    }

    private var shimmerBar: some View {
        RoundedRectangle(cornerRadius: Spacing.radiusXS)
            .fill(Theme.surfaceSecondary)
            .frame(height: 14)
            .shimmer()
    }

    // MARK: - Bottom Action

    private var bottomAction: some View {
        Button(action: onDismiss) {
            Text("Done")
                .font(Typography.buttonLarge)
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .background(
                    LinearGradient(
                        colors: [plateSafety.color, plateSafety.color.opacity(0.8)],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .cornerRadius(Spacing.radiusMD)
                .shadow(color: plateSafety.color.opacity(0.3), radius: 12, y: 4)
        }
        .buttonPressAnimation()
        .accessibilityLabel("Done")
        .padding(.horizontal, Spacing.screenHorizontal)
        .padding(.vertical, Spacing.sm + 4)
        .background(
            Theme.backgroundPrimary
                .shadow(color: Color.black.opacity(0.3), radius: 10, y: -5)
        )
    }

    // MARK: - Reusable Plate Glass Card

    private func plateGlassCard<Content: View>(
        title: String,
        icon: String,
        color: Color,
        @ViewBuilder content: () -> Content
    ) -> some View {
        GlassCard(variant: .secondary) {
            VStack(alignment: .leading, spacing: Spacing.sm + 4) {
                HStack(spacing: 10) {
                    Image(systemName: icon)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(color)
                        .frame(width: 32, height: 32)
                        .background(color.opacity(0.12))
                        .cornerRadius(Spacing.radiusXS)

                    Text(title)
                        .font(.system(size: 16, weight: .bold))
                        .foregroundColor(Theme.textPrimary)

                    Spacer()
                }

                content()
            }
        }
    }
}

// MARK: - Plate Safety State

private enum PlateSafetyState {
    case safe, caution, avoid

    var title: String {
        switch self {
        case .safe: return "Safe to Eat"
        case .caution: return "Eat with Caution"
        case .avoid: return "Avoid This Dish"
        }
    }

    var icon: String {
        switch self {
        case .safe: return "checkmark.shield.fill"
        case .caution: return "exclamationmark.triangle.fill"
        case .avoid: return "xmark.shield.fill"
        }
    }

    var color: Color {
        switch self {
        case .safe: return Theme.success
        case .caution: return Theme.warning
        case .avoid: return Theme.error
        }
    }

    var variant: GlassCardVariant {
        switch self {
        case .safe: return .success
        case .caution: return .warning
        case .avoid: return .error
        }
    }
}

// MARK: - Hidden Risk Card (Premium)

struct HiddenRiskCard: View {
    let risk: PlateAnalysis.HiddenRisk

    private var riskColor: Color {
        switch risk.riskType.lowercased() {
        case "dairy": return Theme.info
        case "egg": return Theme.warning
        case "meat", "dietary": return Theme.error
        case "gluten": return Theme.accent
        case "nuts", "shellfish": return Color(hex: "F97316")
        case "soy": return Color(hex: "A855F7")
        case "crosscontamination": return Color(hex: "EC4899")
        default: return Theme.textMuted
        }
    }

    private var riskIcon: String {
        switch risk.riskType.lowercased() {
        case "dairy": return "drop.fill"
        case "egg": return "oval.fill"
        case "meat": return "flame.fill"
        case "dietary": return "exclamationmark.triangle.fill"
        case "gluten": return "leaf.fill"
        case "nuts": return "circle.hexagongrid.fill"
        case "crosscontamination": return "arrow.triangle.swap"
        default: return "exclamationmark.triangle.fill"
        }
    }

    private var confidenceColor: Color {
        switch (risk.confidence ?? "Medium").lowercased() {
        case "high": return Theme.error
        case "medium": return Theme.warning
        case "low": return Theme.info
        default: return Theme.textMuted
        }
    }

    var body: some View {
        GlassCard(variant: .secondary) {
            VStack(alignment: .leading, spacing: Spacing.sm + 4) {
                // Header: risk type + confidence badge
                HStack {
                    HStack(spacing: 10) {
                        Image(systemName: riskIcon)
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(riskColor)
                            .frame(width: 30, height: 30)
                            .background(riskColor.opacity(0.12))
                            .cornerRadius(Spacing.radiusXS)

                        Text(risk.riskType)
                            .font(.system(size: 15, weight: .bold))
                            .foregroundColor(Theme.textPrimary)
                    }

                    Spacer()

                    // Confidence badge
                    Text(risk.confidence ?? "Medium")
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .foregroundColor(confidenceColor)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(confidenceColor.opacity(0.12))
                        .cornerRadius(Spacing.radiusPill)
                        .overlay(
                            RoundedRectangle(cornerRadius: Spacing.radiusPill)
                                .stroke(confidenceColor.opacity(0.2), lineWidth: 1)
                        )
                }

                // Ingredient name
                if let ingredient = risk.ingredient, !ingredient.isEmpty {
                    Text(ingredient)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(Theme.textSecondary)
                }

                // Reason description
                if let reason = risk.reason, !reason.isEmpty {
                    Text(reason)
                        .textStyleBodySmall(color: Theme.textTertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                // Question to ask
                if let question = risk.questionToAsk, !question.isEmpty {
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: "questionmark.circle.fill")
                            .font(.system(size: 13))
                            .foregroundColor(Theme.accent)
                            .offset(y: 1)

                        Text(question)
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(Theme.accent)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(Spacing.sm + 4)
                    .background(Theme.accent.opacity(0.08))
                    .cornerRadius(Spacing.radiusSM)
                    .overlay(
                        RoundedRectangle(cornerRadius: Spacing.radiusSM)
                            .stroke(Theme.accent.opacity(0.15), lineWidth: 1)
                    )
                }
            }
        }
        .overlay(
            RoundedRectangle(cornerRadius: Spacing.radiusMD)
                .stroke(riskColor.opacity(0.15), lineWidth: 1)
        )
        .overlay(alignment: .leading) {
            UnevenRoundedRectangle(
                topLeadingRadius: Spacing.radiusMD,
                bottomLeadingRadius: Spacing.radiusMD,
                bottomTrailingRadius: 0,
                topTrailingRadius: 0
            )
            .fill(riskColor)
            .frame(width: 4)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(risk.riskType) risk: \(risk.ingredient ?? ""), confidence \(risk.confidence ?? "unknown")")
    }
}

// MARK: - iOS 15 Fallback for FlowLayout

struct WrappingHStack: View {
    let items: [String]
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(items, id: \.self) { item in
                Text(item)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(color)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                    .background(color.opacity(0.1))
                    .cornerRadius(Spacing.radiusXS)
                    .overlay(
                        RoundedRectangle(cornerRadius: Spacing.radiusXS)
                            .stroke(color.opacity(0.2), lineWidth: 1)
                    )
            }
        }
    }
}
