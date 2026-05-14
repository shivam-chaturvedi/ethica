//
//  AlternativeComparisonCard.swift
//  Ethica
//
//  Created on 02/11/2026
//
import SwiftUI

struct AlternativeComparisonCard: View {
	let alternative: AnalysisResult.Alternative
	let currentProduct: AnalysisResult

	private var healthDelta: Int? {
		guard let altHealth = alternative.healthScore else { return nil }
		return Int(altHealth - currentProduct.healthScore)
	}

	private var co2Delta: Double? {
		guard let altCO2 = alternative.estimatedCO2 else { return nil }
		guard currentProduct.co2Emissions > 0 else { return nil }
		return ((currentProduct.co2Emissions - altCO2) / currentProduct.co2Emissions) * 100
	}

	private var waterDelta: Double? {
		guard let altWater = alternative.estimatedWater else { return nil }
		guard currentProduct.waterUsage > 0 else { return nil }
		return ((currentProduct.waterUsage - altWater) / currentProduct.waterUsage) * 100
	}

	var body: some View {
		VStack(alignment: .leading, spacing: 16) {
			// Header: Product name + image + confidence badge
			HStack(spacing: 12) {
				// Product image (cached for performance)
				if let imageURL = alternative.imageURL, let url = URL(string: imageURL) {
					CachedAsyncImage(url: url) { phase in
						switch phase {
						case .success(let image):
							image
								.resizable()
								.scaledToFit()
								.frame(width: 60, height: 60)
								.cornerRadius(8)
						case .failure(_):
							Image(systemName: "photo")
								.foregroundColor(Theme.textSecondary)
								.frame(width: 60, height: 60)
						case .empty:
							ProgressView()
								.frame(width: 60, height: 60)
						@unknown default:
							Image(systemName: "photo")
								.foregroundColor(Theme.textSecondary)
								.frame(width: 60, height: 60)
						}
					}
				} else {
					Image(systemName: "star.fill")
						.font(.system(size: 30))
						.foregroundColor(Theme.warning)
						.frame(width: 60, height: 60)
				}

				VStack(alignment: .leading, spacing: 4) {
					if let brand = alternative.brand {
						Text(brand)
							.font(.caption)
							.foregroundColor(Theme.textSecondary)
					}
					Text(alternative.name)
						.font(.headline)
						.lineLimit(2)

					// Confidence badge
					if let dataSource = alternative.dataSource {
						HStack(spacing: 4) {
							Image(systemName: dataSource == "openfoodfacts" ? "checkmark.circle.fill" : "waveform")
							Text(dataSource == "openfoodfacts" ? "Verified" : "Estimated")
								.font(.caption2)
						}
						.foregroundColor(dataSource == "openfoodfacts" ? Theme.success : Theme.warning)
					}
				}

				Spacer()
			}

			// Score comparison bars
			VStack(spacing: 12) {
				// Health comparison
				if let delta = healthDelta {
					ScoreComparisonBar(
						label: "Health",
						currentValue: currentProduct.healthScore,
						newValue: alternative.healthScore ?? 0,
						delta: Double(delta),
						unit: "",
						icon: "heart.fill",
						color: Theme.error
					)
				}

				// CO2 comparison
				if let delta = co2Delta {
					ScoreComparisonBar(
						label: "CO2 Emissions",
						currentValue: currentProduct.co2Emissions,
						newValue: alternative.estimatedCO2 ?? 0,
						delta: -delta, // Negative because lower is better
						unit: "kg",
						icon: "leaf.fill",
						color: Theme.success
					)
				}

				// Water comparison
				if let delta = waterDelta {
					ScoreComparisonBar(
						label: "Water Usage",
						currentValue: currentProduct.waterUsage,
						newValue: alternative.estimatedWater ?? 0,
						delta: -delta,
						unit: "L",
						icon: "drop.fill",
						color: Theme.info
					)
				}
			}

			// Price comparison
			if let price = alternative.price {
				HStack {
					Image(systemName: "dollarsign.circle.fill")
						.foregroundColor(Theme.success)

					VStack(alignment: .leading, spacing: 2) {
						Text("Price")
							.font(.caption.bold())

						HStack(spacing: 8) {
							Text(String(format: "$%.2f", price))
								.font(.caption2.bold())

							if let source = alternative.priceSource {
								Text(source == "openfoodfacts" ? "Verified" : "Estimated")
									.font(.caption2)
									.foregroundColor(Theme.textSecondary)
							}
						}
					}

					Spacer()
				}
				.padding(.vertical, 8)
			}

			// Nutrition comparison (if available)
			if alternative.nutrition != nil {
				NutritionComparisonView(
					currentNutrition: nil, // Will be added in Task 2.4
					alternativeNutrition: alternative.nutrition
				)
			}

			// Reason/explanation
			if let reason = alternative.reason {
				Text(reason)
					.font(.subheadline)
					.foregroundColor(Theme.textSecondary)
					.lineLimit(3)
			}

			// Buy button
			if let link = alternative.link, let url = URL(string: link) {
				Button(action: {
					// Log interaction
					HistoryService.shared.logAlternativeInteraction(
						alternativeName: alternative.name,
						alternativeBrand: alternative.brand,
						originalProduct: currentProduct.productName,
						action: "clicked"
					)

					// Open link
					UIApplication.shared.open(url)
				}) {
					HStack {
						Text("View Product")
						Image(systemName: "arrow.right")
					}
					.font(.subheadline.bold())
					.foregroundColor(.white)
					.frame(maxWidth: .infinity)
					.padding(.vertical, 12)
					.background(Theme.success)
					.cornerRadius(8)
				}
			}
		}
		.padding()
		.background(Theme.surfaceBase)
		.cornerRadius(12)
		.shadow(radius: 4)
		.swipeActions(edge: .trailing, allowsFullSwipe: false) {
			Button(role: .destructive) {
				// Log dismissal
				HistoryService.shared.logAlternativeInteraction(
					alternativeName: alternative.name,
					alternativeBrand: alternative.brand,
					originalProduct: currentProduct.productName,
					action: "dismissed"
				)
			} label: {
				Label("Not Interested", systemImage: "xmark.circle")
			}
		}
	}
}

struct ScoreComparisonBar: View {
	let label: String
	let currentValue: Double
	let newValue: Double
	let delta: Double
	let unit: String
	let icon: String
	let color: Color

	var body: some View {
		VStack(alignment: .leading, spacing: 4) {
			HStack {
				Image(systemName: icon)
					.foregroundColor(color)
				Text(label)
					.font(.caption.bold())
				Spacer()
				Text("\(delta > 0 ? "+" : "")\(Int(delta))%")
					.font(.caption.bold())
					.foregroundColor(delta > 0 ? Theme.success : delta < 0 ? Theme.error : Theme.textMuted)
			}

			HStack(spacing: 8) {
				Text(String(format: "%.1f%@", currentValue, unit))
					.font(.caption2)
					.foregroundColor(Theme.textSecondary)

				Image(systemName: "arrow.right")
					.font(.caption2)
					.foregroundColor(Theme.textSecondary)

				Text(String(format: "%.1f%@", newValue, unit))
					.font(.caption2.bold())
					.foregroundColor(color)
			}
		}
	}
}
