//
//  NutritionComparisonView.swift
//  Ethica
//
//  Nutrition comparison component for alternative products
//

import SwiftUI

struct NutritionComparisonView: View {
    let currentNutrition: AnalysisResult.NutritionFacts?
    let alternativeNutrition: AnalysisResult.NutritionFacts?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header
            HStack {
                Image(systemName: "chart.bar.fill")
                    .font(.system(size: 14))
                    .foregroundColor(Theme.primary)
                Text("Nutrition Comparison")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundColor(.white)
                Spacer()
                Text("per serving")
                    .font(.system(size: 11))
                    .foregroundColor(Theme.textSecondary)
            }

            if currentNutrition != nil && alternativeNutrition != nil {
                VStack(spacing: 6) {
                    nutritionRow(
                        label: "Calories",
                        current: currentNutrition?.calories,
                        alternative: alternativeNutrition?.calories,
                        unit: "kcal",
                        lowerIsBetter: true
                    )

                    nutritionRow(
                        label: "Protein",
                        current: currentNutrition?.protein,
                        alternative: alternativeNutrition?.protein,
                        unit: "g",
                        lowerIsBetter: false
                    )

                    nutritionRow(
                        label: "Sugar",
                        current: currentNutrition?.sugar,
                        alternative: alternativeNutrition?.sugar,
                        unit: "g",
                        lowerIsBetter: true
                    )

                    nutritionRow(
                        label: "Fat",
                        current: currentNutrition?.fat,
                        alternative: alternativeNutrition?.fat,
                        unit: "g",
                        lowerIsBetter: true
                    )

                    nutritionRow(
                        label: "Fiber",
                        current: currentNutrition?.fiber,
                        alternative: alternativeNutrition?.fiber,
                        unit: "g",
                        lowerIsBetter: false
                    )

                    nutritionRow(
                        label: "Sodium",
                        current: currentNutrition?.sodium,
                        alternative: alternativeNutrition?.sodium,
                        unit: "mg",
                        lowerIsBetter: true
                    )
                }
            } else {
                HStack(spacing: 8) {
                    Image(systemName: "info.circle")
                        .font(.system(size: 12))
                        .foregroundColor(Theme.textSecondary)
                    Text("Detailed nutrition data not available")
                        .font(.system(size: 12))
                        .foregroundColor(Theme.textSecondary)
                }
                .padding(.vertical, 8)
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Theme.primary.opacity(0.08))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Theme.primary.opacity(0.2), lineWidth: 1)
                )
        )
    }

    @ViewBuilder
    func nutritionRow(label: String, current: Double?, alternative: Double?, unit: String, lowerIsBetter: Bool) -> some View {
        if let curr = current, let alt = alternative {
            HStack(spacing: 8) {
                // Label
                Text(label)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(Theme.textPrimary)
                    .frame(width: 70, alignment: .leading)

                // Current value
                Text(String(format: "%.1f%@", curr, unit))
                    .font(.system(size: 12))
                    .foregroundColor(Theme.textSecondary)
                    .frame(width: 60, alignment: .trailing)

                // Arrow
                Image(systemName: "arrow.right")
                    .font(.system(size: 10))
                    .foregroundColor(Theme.textSecondary)

                // Alternative value
                Text(String(format: "%.1f%@", alt, unit))
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.white)
                    .frame(width: 60, alignment: .trailing)

                Spacer()

                // Delta percentage
                let delta = ((alt - curr) / curr) * 100
                let isImprovement = lowerIsBetter ? delta < 0 : delta > 0

                HStack(spacing: 2) {
                    Image(systemName: isImprovement ? "arrow.down.circle.fill" : "arrow.up.circle.fill")
                        .font(.system(size: 10))
                    Text("\(abs(Int(delta)))%")
                        .font(.system(size: 11, weight: .bold))
                }
                .foregroundColor(isImprovement ? Theme.success : Theme.error)
                .frame(width: 50, alignment: .trailing)
            }
        }
    }
}

// Preview
struct NutritionComparisonView_Previews: PreviewProvider {
    static var previews: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            NutritionComparisonView(
                currentNutrition: AnalysisResult.NutritionFacts(
                    calories: 250,
                    protein: 8,
                    carbs: 45,
                    sugar: 22,
                    fat: 12,
                    fiber: 2,
                    sodium: 480
                ),
                alternativeNutrition: AnalysisResult.NutritionFacts(
                    calories: 180,
                    protein: 15,
                    carbs: 30,
                    sugar: 5,
                    fat: 8,
                    fiber: 8,
                    sodium: 320
                )
            )
            .padding()
        }
    }
}
