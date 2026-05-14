//
//  MenuAnalysisView.swift
//  Ethica
//
//  Restaurant Menu Analysis Results View
//

import SwiftUI

struct MenuAnalysisView: View {
    let result: AnalysisResult
    @Environment(\.presentationMode) var presentationMode
    @State private var selectedDishes: Set<String> = []
    @State private var showingPurchaseConfirmation = false

    var body: some View {
        ZStack {
            Theme.backgroundPrimary
                .ignoresSafeArea()

            ScrollView {
                VStack(spacing: 24) {
                    // Header
                    VStack(spacing: 12) {
                        ZStack {
                            Circle()
                                .fill(Theme.primary)
                                .frame(width: 80, height: 80)
                                .shadow(color: Theme.primary.opacity(0.3), radius: 10, x: 0, y: 4)

                            Image(systemName: "fork.knife")
                                .font(Typography.display)
                                .foregroundColor(.white)
                        }
                        .scaleIn(delay: 0.1)

                        Text("Menu Analysis")
                            .font(Typography.h1)
                            .foregroundColor(Theme.textPrimary)

                        Text("Select dishes you ordered to track impact")
                            .font(Typography.body)
                            .foregroundColor(Theme.textTertiary)

                        // Disclaimer Banner
                        DisclaimerBanner()
                    }
                    .padding(.top, 20)
                    .slideInFromBottom(delay: 0.1)

                    // Summary Card
                    if let dishes = result.menuDishes {
                        SummaryCard(dishes: dishes)
                            .slideInFromBottom(delay: 0.2)
                    }

                    // Dishes List
                    if let dishes = result.menuDishes {
                        VStack(spacing: 12) {
                            Text("Menu Items")
                                .font(Typography.h3)
                                .foregroundColor(Theme.textPrimary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal, 20)

                            ForEach(Array(dishes.enumerated()), id: \.element.id) { index, dish in
                                DishCard(
                                    dish: dish,
                                    isSelected: selectedDishes.contains(dish.id),
                                    onToggleSelection: {
                                        if selectedDishes.contains(dish.id) {
                                            selectedDishes.remove(dish.id)
                                        } else {
                                            selectedDishes.insert(dish.id)
                                        }
                                        HapticManager.shared.trigger(.selectionChanged)
                                    }
                                )
                                .staggerAnimation(index: index, delay: 0.1)
                            }
                        }
                        .padding(.horizontal, 16)
                    }

                    // Action buttons
                    VStack(spacing: 12) {
                        if !selectedDishes.isEmpty {
                            Button(action: {
                                savePurchasedDishes()
                            }) {
                                HStack(spacing: 10) {
                                    Image(systemName: "checkmark.circle.fill")
                                        .font(Typography.h3)
                                    Text("Save \(selectedDishes.count) Dish\(selectedDishes.count == 1 ? "" : "es") to History")
                                        .font(Typography.buttonLarge)
                                }
                                .foregroundColor(.white)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 16)
                                .background(Theme.gradientHero)
                                .clipShape(RoundedRectangle(cornerRadius: Spacing.radiusSM))
                                .shadow(color: Theme.primary.opacity(0.4), radius: 8, x: 0, y: 4)
                            }
                        }

                        Button(action: {
                            presentationMode.wrappedValue.dismiss()
                        }) {
                            Text(selectedDishes.isEmpty ? "Done" : "Done Without Saving")
                                .font(Typography.buttonLarge)
                                .foregroundColor(selectedDishes.isEmpty ? .white : Theme.primary)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 16)
                                .background(selectedDishes.isEmpty ? Theme.primary : Theme.surfaceBase)
                                .clipShape(RoundedRectangle(cornerRadius: Spacing.radiusSM))
                                .overlay(
                                    RoundedRectangle(cornerRadius: Spacing.radiusSM)
                                        .stroke(Theme.primary, lineWidth: selectedDishes.isEmpty ? 0 : 2)
                                )
                                .shadow(color: .black.opacity(0.1), radius: 4, x: 0, y: 2)
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 30)
                    .slideInFromBottom(delay: 0.4)
                }
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .alert("Saved to History", isPresented: $showingPurchaseConfirmation) {
            Button("OK") {
                presentationMode.wrappedValue.dismiss()
            }
        } message: {
            Text("\(selectedDishes.count) dish\(selectedDishes.count == 1 ? "" : "es") saved to your impact history.")
        }
    }

    private func savePurchasedDishes() {
        guard let dishes = result.menuDishes else { return }

        for dish in dishes where selectedDishes.contains(dish.id) {
            // Skip dishes with invalid data
            let dishName = dish.dish
            guard !dishName.isEmpty else {
                continue
            }

            let isSafe = dish.safe ?? false
            let ingredients = dish.ingredients ?? []
            let warnings = dish.warnings ?? []

            // Create an AnalysisResult for each purchased dish
            let dishResult = AnalysisResult(
                productName: dishName,
                overallScore: isSafe ? 80.0 : 40.0,
                isSafe: isSafe,
                confidence: 0.7,
                confidenceFactors: ["Restaurant menu analysis"],
                violations: warnings,
                warnings: isSafe ? [] : ["Contains restricted ingredients"],
                cautionWarnings: ["Based on typical ingredients"],
                ingredients: ingredients,
                detectedAllergens: warnings,
                detectionEvidence: [],
                healthScore: 50.0,  // Neutral default — health is nutrition-based, not allergen-based
                environmentalScore: 50.0,  // Use 0-100 scale
                co2Emissions: (dish.estimatedCO2 ?? 0.0) / 1000.0,  // Convert grams to kilograms
                waterUsage: 0.0,
                animalImpact: "Unknown",
                landUse: "Unknown",
                nutritionalHighlights: [],
                healthConcerns: isSafe ? [] : warnings,
                healthBenefits: [],
                recommendations: [],
                alternatives: [],
                environmentalBreakdown: [],
                sourceType: "restaurant_menu",
                timestamp: Date()
            )

            // Create scan history and mark as PURCHASED (user selected it)
            var scanHistory = ScanHistory(from: dishResult)
            scanHistory = ScanHistory(
                id: scanHistory.id,
                timestamp: scanHistory.timestamp,
                productName: scanHistory.productName,
                barcode: scanHistory.barcode,
                sourceType: "restaurant_menu",
                isSafe: scanHistory.isSafe,
                violationsCount: scanHistory.violationsCount,
                violations: scanHistory.violations,
                co2Emissions: scanHistory.co2Emissions,
                waterUsage: scanHistory.waterUsage,
                animalImpact: scanHistory.animalImpact,
                healthScore: scanHistory.healthScore,
                concernsCount: scanHistory.concernsCount,
                purchaseDecision: .purchased,  // Mark as purchased!
                alternativeName: nil,
                alternativeCO2: nil,
                alternativeWater: nil,
                selectedAlternativeIndex: nil,
                priceComparison: nil,
                decisionTimestamp: Date(),
                needsReview: false  // No review needed - user explicitly selected
            )

            HistoryService.shared.saveScan(scanHistory)
        }

        showingPurchaseConfirmation = true
    }
}

struct DisclaimerBanner: View {
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(Typography.h2)
                .foregroundColor(Theme.warning)

            VStack(alignment: .leading, spacing: 6) {
                Text("Important Notice")
                    .font(Typography.body)
                    .fontWeight(.bold)
                    .foregroundColor(Theme.textPrimary)

                Text("Menu analysis based on typical ingredients. Always verify with restaurant staff for allergy safety.")
                    .font(Typography.bodySmall)
                    .foregroundColor(Theme.textSecondary)
                    .lineSpacing(2)
            }

            Spacer()
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: Spacing.radiusSM)
                .fill(Theme.surfaceBase)
                .shadow(color: Theme.warning.opacity(0.15), radius: 12, x: 0, y: 4)
        )
        .overlay(
            RoundedRectangle(cornerRadius: Spacing.radiusSM)
                .strokeBorder(
                    LinearGradient(
                        gradient: Gradient(colors: [Theme.warning, Theme.warning.opacity(0.7)]),
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 2
                )
        )
        .padding(.horizontal, 20)
    }
}

struct SummaryCard: View {
    let dishes: [AnalysisResult.MenuDish]

    var safeDishes: Int {
        dishes.filter { $0.safe }.count
    }

    var unsafeDishes: Int {
        dishes.count - safeDishes
    }

    var body: some View {
        VStack(spacing: 20) {
            Text("Scan Results")
                .font(Typography.h4)
                .foregroundColor(Theme.textPrimary)

            HStack(spacing: 40) {
                // Safe dishes
                VStack(spacing: 10) {
                    ZStack {
                        Circle()
                            .fill(Theme.success.opacity(0.15))
                            .frame(width: 70, height: 70)

                        Image(systemName: "checkmark.circle.fill")
                            .font(Typography.display)
                            .foregroundColor(Theme.success)
                    }

                    Text("\(safeDishes)")
                        .font(Typography.display)
                        .foregroundColor(Theme.textPrimary)

                    Text("Safe Dishes")
                        .font(Typography.bodySmall)
                        .fontWeight(.semibold)
                        .foregroundColor(Theme.textTertiary)
                }

                // Divider
                Rectangle()
                    .fill(Theme.textMuted.opacity(0.3))
                    .frame(width: 2, height: 80)

                // Unsafe dishes
                VStack(spacing: 10) {
                    ZStack {
                        Circle()
                            .fill(Theme.error.opacity(0.15))
                            .frame(width: 70, height: 70)

                        Image(systemName: "exclamationmark.circle.fill")
                            .font(Typography.display)
                            .foregroundColor(Theme.error)
                    }

                    Text("\(unsafeDishes)")
                        .font(Typography.display)
                        .foregroundColor(Theme.textPrimary)

                    Text("Caution")
                        .font(Typography.bodySmall)
                        .fontWeight(.semibold)
                        .foregroundColor(Theme.textTertiary)
                }
            }
        }
        .padding(.vertical, 24)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: Spacing.radiusMD)
                .fill(Theme.surfaceBase)
                .shadow(color: .black.opacity(0.3), radius: 16, x: 0, y: 8)
        )
        .padding(.horizontal, 20)
    }
}

struct DishCard: View {
    let dish: AnalysisResult.MenuDish
    let isSelected: Bool
    let onToggleSelection: () -> Void
    @State private var isExpanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            // Header with dish name and status
            HStack(spacing: 14) {
                // Selection checkbox
                Button(action: onToggleSelection) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 8)
                            .strokeBorder(isSelected ? Theme.primary : Theme.textMuted, lineWidth: 2)
                            .background(
                                RoundedRectangle(cornerRadius: 8)
                                    .fill(isSelected ? Theme.primary : Theme.surfaceSecondary)
                            )
                            .frame(width: 28, height: 28)

                        if isSelected {
                            Image(systemName: "checkmark")
                                .font(.system(size: 16, weight: .bold))
                                .foregroundColor(.white)
                        }
                    }
                }

                // Status icon
                ZStack {
                    Circle()
                        .fill(((dish.safe ?? false) ? Theme.success : Theme.error).opacity(0.15))
                        .frame(width: 40, height: 40)

                    Image(systemName: (dish.safe ?? false) ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                        .font(Typography.h3)
                        .foregroundColor((dish.safe ?? false) ? Theme.success : Theme.error)
                }

                // Dish name
                VStack(alignment: .leading, spacing: 5) {
                    Text(dish.dish ?? "Unknown Dish")
                        .font(Typography.bodyLarge)
                        .fontWeight(.bold)
                        .foregroundColor(Theme.textPrimary)
                        .lineLimit(2)

                    HStack(spacing: 6) {
                        Circle()
                            .fill((dish.safe ?? false) ? Theme.success : Theme.error)
                            .frame(width: 6, height: 6)

                        Text((dish.safe ?? false) ? "Safe for you" : "Contains restrictions")
                            .font(Typography.bodySmall)
                            .fontWeight(.semibold)
                            .foregroundColor((dish.safe ?? false) ? Theme.success : Theme.error)
                    }
                }

                Spacer()

                // Expand/collapse button
                Button(action: {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                        isExpanded.toggle()
                    }
                    HapticManager.shared.trigger(.impactLight)
                }) {
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(Typography.buttonLarge)
                        .fontWeight(.bold)
                        .foregroundColor(Theme.textTertiary)
                        .frame(width: 32, height: 32)
                        .background(Circle().fill(Theme.surfaceSecondary))
                }
            }

            // CO2 Estimate
            if let co2 = dish.estimatedCO2 {
                HStack(spacing: 8) {
                    Image(systemName: "leaf.fill")
                        .font(Typography.bodySmall)
                        .fontWeight(.bold)
                        .foregroundColor(Theme.primary)

                    Text("Rough Estimate:")
                        .font(Typography.bodySmall)
                        .fontWeight(.semibold)
                        .foregroundColor(Theme.textTertiary)

                    Text("~\(String(format: "%.0f", co2))g CO₂")
                        .font(Typography.bodySmall)
                        .fontWeight(.bold)
                        .foregroundColor(Theme.textPrimary)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(
                    Capsule()
                        .fill(Theme.primary.opacity(0.1))
                )
            }

            // Warnings (if unsafe)
            if !(dish.safe ?? true) && !(dish.warnings ?? []).isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 6) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(Typography.bodySmall)
                            .fontWeight(.bold)
                            .foregroundColor(Theme.warning)

                        Text("Warnings:")
                            .font(Typography.bodySmall)
                            .fontWeight(.bold)
                            .foregroundColor(Theme.textPrimary)
                    }

                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(dish.warnings ?? [], id: \.self) { warning in
                            HStack(spacing: 8) {
                                Circle()
                                    .fill(Theme.error)
                                    .frame(width: 5, height: 5)

                                Text(warning)
                                    .font(Typography.bodySmall)
                                    .foregroundColor(Theme.textSecondary)
                            }
                        }
                    }
                    .padding(.leading, 4)
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: 10)
                        .fill(Theme.warning.opacity(0.15))
                )
            }

            // Expanded ingredients list
            if isExpanded {
                Divider()
                    .background(Theme.textMuted.opacity(0.3))
                    .padding(.vertical, 4)

                VStack(alignment: .leading, spacing: 10) {
                    Text("Typical Ingredients:")
                        .font(Typography.bodySmall)
                        .fontWeight(.bold)
                        .foregroundColor(Theme.textPrimary)

                    if #available(iOS 16.0, *) {
                        FlowLayout(spacing: 8) {
                            ForEach(dish.ingredients ?? [], id: \.self) { ingredient in
                                Text(ingredient)
                                    .font(Typography.bodySmall)
                                    .foregroundColor(Theme.textSecondary)
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 7)
                                    .background(
                                        Capsule()
                                            .fill(Theme.surfaceSecondary)
                                    )
                            }
                        }
                    } else {
                        VStack(alignment: .leading, spacing: 6) {
                            ForEach(dish.ingredients ?? [], id: \.self) { ingredient in
                                Text(ingredient)
                                    .font(Typography.bodySmall)
                                    .foregroundColor(Theme.textSecondary)
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 7)
                                    .background(
                                        Capsule()
                                            .fill(Theme.surfaceSecondary)
                                    )
                            }
                        }
                    }
                }
            }
        }
        .padding(18)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Theme.surfaceBase)
                .shadow(color: .black.opacity(0.2), radius: 12, x: 0, y: 6)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .strokeBorder(
                    isSelected ?
                        LinearGradient(
                            gradient: Gradient(colors: [Theme.primary, Theme.primaryDark]),
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ) :
                        LinearGradient(
                            gradient: Gradient(colors: [Color.clear, Color.clear]),
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                    lineWidth: isSelected ? 2.5 : 0
                )
        )
    }
}

// FlowLayout is defined in PreferencesView.swift and shared across views

#Preview {
    MenuAnalysisView(result: AnalysisResult(
        productName: "Restaurant Menu Analysis",
        overallScore: 7.5,
        isSafe: true,
        confidence: 0.7,
        confidenceFactors: ["Menu analysis based on typical ingredients"],
        violations: [],
        warnings: ["Always verify ingredients with restaurant staff"],
        cautionWarnings: [],
        ingredients: ["tomato", "basil", "mozzarella"],
        detectedAllergens: [],
        detectionEvidence: [],
        healthScore: 5.0,
        environmentalScore: 5.0,
        co2Emissions: 0,
        waterUsage: 0,
        animalImpact: "Unknown",
        landUse: "Unknown",
        nutritionalHighlights: [],
        healthConcerns: [],
        healthBenefits: [],
        recommendations: [],
        alternatives: [],
        environmentalBreakdown: [],
        isRestaurantMenu: true,
        menuDishes: [
            AnalysisResult.MenuDish(dish: "Margherita Pizza", ingredients: ["dough", "tomato", "mozzarella", "basil"], safe: false, warnings: ["mozzarella (dairy)"], estimatedCO2: 1200),
            AnalysisResult.MenuDish(dish: "Garden Salad", ingredients: ["lettuce", "tomato", "cucumber", "olive oil"], safe: true, warnings: [], estimatedCO2: 350),
            AnalysisResult.MenuDish(dish: "Pasta Alfredo", ingredients: ["pasta", "cream", "butter", "parmesan"], safe: false, warnings: ["cream (dairy)", "butter (dairy)", "parmesan (dairy)"], estimatedCO2: 1800)
        ]
    ))
}
