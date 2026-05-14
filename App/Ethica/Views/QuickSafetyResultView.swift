//
//  QuickSafetyResultView.swift
//  Ethica
//
//  Safety-first results view for quick ingredient photo checks

import SwiftUI

struct QuickSafetyResultView: View {
    let result: QuickSafetyResult
    let onDismiss: () -> Void
    let onRunFullAnalysis: (([String], String?) -> Void)?

    @State private var showIngredients = false

    var body: some View {
        ZStack {
            Theme.backgroundPrimary
                .ignoresSafeArea()

            ScrollView {
                VStack(spacing: Spacing.lg) {

                    // MARK: - Header
                    headerBar

                    // MARK: - Safety Badge
                    safetyBadge
                        .padding(.top, Spacing.sm)

                    // MARK: - Violations
                    if !result.violations.isEmpty {
                        issueSection(
                            title: "Violations",
                            icon: "xmark.octagon.fill",
                            color: Theme.error,
                            items: result.violations,
                            variant: .error
                        )
                    }

                    // MARK: - Caution Warnings
                    if !result.cautionWarnings.isEmpty {
                        issueSection(
                            title: "Caution",
                            icon: "exclamationmark.triangle.fill",
                            color: Theme.warning,
                            items: result.cautionWarnings,
                            variant: .warning
                        )
                    }

                    // MARK: - Detected Allergens
                    if !result.detectedAllergens.isEmpty {
                        GlassCard(variant: .primary) {
                            VStack(alignment: .leading, spacing: Spacing.sm) {
                                Label("Detected Allergens", systemImage: "allergens")
                                    .font(.system(size: 15, weight: .semibold))
                                    .foregroundColor(Theme.error)

                                FlowLayout(spacing: 8) {
                                    ForEach(result.detectedAllergens, id: \.self) { allergen in
                                        Text(allergen.capitalized)
                                            .font(.system(size: 13, weight: .medium))
                                            .foregroundColor(.white)
                                            .padding(.horizontal, 12)
                                            .padding(.vertical, 6)
                                            .background(Theme.error.opacity(0.3))
                                            .cornerRadius(Spacing.radiusXS)
                                    }
                                }
                            }
                        }
                    }

                    // MARK: - GMO Status
                    if let gmo = result.gmoStatus, gmo != "no_risk" {
                        GlassCard(variant: gmo == "confirmed_gmo" ? .error : .warning) {
                            HStack(spacing: Spacing.sm) {
                                Image(systemName: gmo == "confirmed_gmo" ? "leaf.fill" : "questionmark.circle.fill")
                                    .foregroundColor(gmo == "confirmed_gmo" ? Theme.error : Theme.warning)
                                    .font(.system(size: 20))

                                VStack(alignment: .leading, spacing: 2) {
                                    Text(gmo == "confirmed_gmo" ? "Contains GMO Ingredients" : "Potential GMO Ingredients")
                                        .font(.system(size: 14, weight: .semibold))
                                        .foregroundColor(Theme.textPrimary)

                                    Text(gmo == "confirmed_gmo"
                                         ? "Product contains bioengineered food ingredients"
                                         : "Contains high-risk GMO crops without non-GMO certification")
                                        .font(.system(size: 12))
                                        .foregroundColor(Theme.textTertiary)
                                }

                                Spacer()
                            }
                        }
                    }

                    // MARK: - Cross-Contamination Risks
                    if let risks = result.crossContaminationRisks, !risks.isEmpty {
                        GlassCard(variant: .warning) {
                            VStack(alignment: .leading, spacing: Spacing.sm) {
                                Label("Cross-Contamination Risks", systemImage: "building.2.fill")
                                    .font(.system(size: 15, weight: .semibold))
                                    .foregroundColor(Theme.warning)

                                ForEach(risks, id: \.self) { risk in
                                    HStack(spacing: 8) {
                                        Circle()
                                            .fill(Theme.warning)
                                            .frame(width: 6, height: 6)
                                        Text(risk.capitalized)
                                            .font(.system(size: 13))
                                            .foregroundColor(Theme.textSecondary)
                                        Spacer()
                                    }
                                }
                            }
                        }
                    }

                    // MARK: - Ingredients (collapsible)
                    if let ingredients = result.extractedIngredients, !ingredients.isEmpty {
                        GlassCard(variant: .secondary) {
                            VStack(alignment: .leading, spacing: Spacing.sm) {
                                Button {
                                    withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                                        showIngredients.toggle()
                                    }
                                } label: {
                                    HStack {
                                        Label("Ingredients (\(ingredients.count))", systemImage: "list.bullet")
                                            .font(.system(size: 15, weight: .semibold))
                                            .foregroundColor(Theme.textPrimary)
                                        Spacer()
                                        Image(systemName: showIngredients ? "chevron.up" : "chevron.down")
                                            .font(.system(size: 12, weight: .semibold))
                                            .foregroundColor(Theme.textTertiary)
                                    }
                                }

                                if showIngredients {
                                    Text(ingredients.joined(separator: ", "))
                                        .font(.system(size: 13))
                                        .foregroundColor(Theme.textTertiary)
                                        .transition(.opacity.combined(with: .move(edge: .top)))
                                }
                            }
                        }
                    }

                    // MARK: - Product Name
                    if let name = result.productName, !name.isEmpty {
                        HStack {
                            Text("Product: \(name)")
                                .font(.system(size: 13))
                                .foregroundColor(Theme.textMuted)
                            Spacer()
                        }
                        .padding(.horizontal, Spacing.xs)
                    }

                    // MARK: - Actions
                    VStack(spacing: Spacing.sm) {
                        if let onFullAnalysis = onRunFullAnalysis,
                           let ingredients = result.extractedIngredients, !ingredients.isEmpty {
                            Button {
                                onFullAnalysis(ingredients, result.productName)
                            } label: {
                                HStack(spacing: 8) {
                                    Image(systemName: "chart.bar.doc.horizontal.fill")
                                    Text("Run Full Analysis")
                                }
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundColor(.white)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 14)
                                .background(Theme.primary)
                                .cornerRadius(Spacing.radiusMD)
                            }
                        }

                        Button {
                            onDismiss()
                        } label: {
                            HStack(spacing: 8) {
                                Image(systemName: "barcode.viewfinder")
                                Text("Scan Another Product")
                            }
                            .font(.system(size: 16, weight: .medium))
                            .foregroundColor(Theme.textSecondary)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(Color.white.opacity(0.08))
                            .cornerRadius(Spacing.radiusMD)
                        }
                    }
                    .padding(.top, Spacing.sm)

                    // Source info
                    HStack {
                        Spacer()
                        Text("Quick safety check \(result.sourceType == "ingredient_photo" ? "from photo" : "") • Confidence: \(Int(result.confidence))%")
                            .font(.system(size: 11))
                            .foregroundColor(Theme.textMuted)
                        Spacer()
                    }
                    .padding(.bottom, Spacing.xl)
                }
                .padding(.horizontal, Spacing.screenHorizontal)
            }
        }
        .preferredColorScheme(.dark)
    }

    // MARK: - Header Bar

    private var headerBar: some View {
        HStack {
            Button {
                onDismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(Theme.textSecondary)
                    .frame(width: 36, height: 36)
                    .background(Color.white.opacity(0.1))
                    .clipShape(Circle())
            }

            Spacer()

            Text("Safety Check")
                .font(.system(size: 17, weight: .bold))
                .foregroundColor(Theme.textPrimary)

            Spacer()

            // Balance the X button
            Color.clear
                .frame(width: 36, height: 36)
        }
        .padding(.top, Spacing.sm)
    }

    // MARK: - Safety Badge

    private var safetyBadge: some View {
        let level = result.safetyLevel ?? "caution"
        let config = safetyConfig(for: level)

        return GlassCard(variant: config.variant) {
            VStack(spacing: Spacing.md) {
                ZStack {
                    Circle()
                        .fill(config.color.opacity(0.2))
                        .frame(width: 80, height: 80)

                    Image(systemName: config.icon)
                        .font(.system(size: 36, weight: .bold))
                        .foregroundColor(config.color)
                }

                Text(config.title)
                    .font(.system(size: 22, weight: .bold))
                    .foregroundColor(config.color)

                Text(config.subtitle)
                    .font(.system(size: 14))
                    .foregroundColor(Theme.textTertiary)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, Spacing.sm)
        }
    }

    // MARK: - Issue Section

    private func issueSection(
        title: String,
        icon: String,
        color: Color,
        items: [String],
        variant: GlassCardVariant
    ) -> some View {
        GlassCard(variant: variant) {
            VStack(alignment: .leading, spacing: Spacing.sm) {
                Label(title, systemImage: icon)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(color)

                ForEach(items, id: \.self) { item in
                    HStack(alignment: .top, spacing: 8) {
                        Circle()
                            .fill(color)
                            .frame(width: 6, height: 6)
                            .padding(.top, 6)

                        Text(item)
                            .font(.system(size: 13))
                            .foregroundColor(Theme.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)

                        Spacer()
                    }
                }
            }
        }
    }

    // MARK: - Safety Config

    private struct SafetyConfig {
        let icon: String
        let title: String
        let subtitle: String
        let color: Color
        let variant: GlassCardVariant
    }

    private func safetyConfig(for level: String) -> SafetyConfig {
        switch level {
        case "safe":
            return SafetyConfig(
                icon: "checkmark.circle.fill",
                title: "Safe",
                subtitle: "No violations found for your dietary preferences",
                color: Theme.success,
                variant: .success
            )
        case "caution":
            return SafetyConfig(
                icon: "exclamationmark.triangle.fill",
                title: "Caution",
                subtitle: "Some warnings detected — review details below",
                color: Theme.warning,
                variant: .warning
            )
        default: // "avoid"
            return SafetyConfig(
                icon: "xmark.circle.fill",
                title: "Avoid",
                subtitle: "Violations found for your dietary preferences",
                color: Theme.error,
                variant: .error
            )
        }
    }
}
