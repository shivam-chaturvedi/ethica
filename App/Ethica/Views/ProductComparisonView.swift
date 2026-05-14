//
//  ProductComparisonView.swift
//  Ethica
//
//  Created by Claude on 2026-02-05
//  Premium product comparison UI with swipeable hero cards
//

import SwiftUI

struct ProductComparisonView: View {
    let currentProduct: AnalysisResult
    let alternatives: [AnalysisResult.Alternative]
    @State private var selectedIndex = 0
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack {
            // Background
            Theme.backgroundPrimary
                .ignoresSafeArea()

            VStack(spacing: 20) {
                // Header
                HStack {
                    Button(action: { dismiss() }) {
                        Image(systemName: "chevron.left")
                            .font(.title3)
                            .foregroundColor(Theme.primary)
                    }

                    Spacer()

                    VStack(spacing: 4) {
                        Text("Better Alternatives")
                            .font(.title2.bold())
                            .foregroundColor(Theme.textPrimary)

                        Text("\(alternatives.count) options available")
                            .font(.caption)
                            .foregroundColor(Theme.textTertiary)
                    }

                    Spacer()

                    // Placeholder for symmetry
                    Image(systemName: "chevron.left")
                        .font(.title3)
                        .opacity(0)
                }
                .padding(.horizontal)
                .padding(.top, 10)

                // Swipeable cards
                if alternatives.isEmpty {
                    // No alternatives - show message
                    VStack(spacing: 16) {
                        Image(systemName: "magnifyingglass")
                            .font(.system(size: 48))
                            .foregroundColor(Theme.textTertiary)

                        Text("No Alternatives Available")
                            .font(.title3.bold())
                            .foregroundColor(Theme.textPrimary)

                        Text("We couldn't find better alternatives for this product at the moment.")
                            .font(.subheadline)
                            .foregroundColor(Theme.textSecondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 40)

                        Button(action: { dismiss() }) {
                            Text("Go Back")
                                .font(.subheadline.bold())
                                .foregroundColor(.white)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 14)
                                .background(Theme.primary)
                                .cornerRadius(12)
                        }
                        .padding(.horizontal, 40)
                        .padding(.top, 20)
                    }
                    .frame(maxHeight: .infinity)
                } else {
                    TabView(selection: $selectedIndex) {
                        // Current product card (shown first for comparison)
                        ComparisonCard(
                            product: currentProduct,
                            isCurrent: true,
                            rank: nil
                        )
                        .tag(0)

                        // Alternative cards with rankings
                        ForEach(Array(alternatives.enumerated()), id: \.offset) { index, alt in
                            ComparisonCard(
                                currentProduct: currentProduct,
                                alternative: alt,
                                isCurrent: false,
                                rank: getRank(for: index)
                            )
                            .tag(index + 1)
                        }
                    }
                    .tabViewStyle(.page(indexDisplayMode: .always))
                    .indexViewStyle(.page(backgroundDisplayMode: .always))
                    .frame(height: 580)  // Fixed height for stability - increased for better spacing
                }
            }
        }
    }

    func getRank(for index: Int) -> AlternativeRank {
        switch index {
        case 0: return .topPick
        case 1: return .runnerUp
        default: return .goodChoice
        }
    }
}

enum AlternativeRank {
    case topPick, runnerUp, goodChoice

    var badge: String {
        switch self {
        case .topPick: return "🏆 TOP PICK"
        case .runnerUp: return "🥈 RUNNER-UP"
        case .goodChoice: return "✅ GOOD CHOICE"
        }
    }

    var badgeColor: Color {
        switch self {
        case .topPick: return Theme.success
        case .runnerUp: return Theme.warning
        case .goodChoice: return Theme.info
        }
    }
}

struct ComparisonCard: View {
    var product: AnalysisResult? = nil
    var currentProduct: AnalysisResult? = nil
    var alternative: AnalysisResult.Alternative? = nil
    let isCurrent: Bool
    let rank: AlternativeRank?

    var body: some View {
        VStack(spacing: 0) {
                // Badge - Current Product or Rank
                HStack {
                    Spacer()
                    if isCurrent {
                        Text("📦 YOUR PRODUCT")
                            .font(.caption.bold())
                            .foregroundColor(.white)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(Theme.warning)
                            .cornerRadius(12)
                    } else if let rank = rank {
                        Text(rank.badge)
                            .font(.caption.bold())
                            .foregroundColor(.white)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(rank.badgeColor)
                            .cornerRadius(12)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 20)

                // Product image (large)
                if let imageURL = alternative?.imageURL, let url = URL(string: imageURL) {
                    AsyncImage(url: url) { phase in
                        switch phase {
                        case .success(let image):
                            image
                                .resizable()
                                .scaledToFit()
                        case .failure, .empty:
                            productPlaceholderIcon
                        @unknown default:
                            EmptyView()
                        }
                    }
                    .frame(width: 120, height: 120)
                    .cornerRadius(16)
                    .padding(.top, 8)
                } else {
                    productPlaceholderIcon
                        .padding(.top, 8)
                }

                // Product name + brand
                VStack(spacing: 6) {
                    if let brand = alternative?.brand {
                        Text(brand)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(Theme.textTertiary)
                            .lineLimit(1)
                    }
                    Text(alternative?.name ?? product?.productName ?? "Current Product")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundColor(Theme.textPrimary)
                        .multilineTextAlignment(.center)
                        .lineLimit(3)
                        .fixedSize(horizontal: false, vertical: true)
                        .minimumScaleFactor(0.9)
                }
                .padding(.horizontal, 20)
                .padding(.top, 12)
                .frame(minHeight: 60)

                // CO2 Savings Badge (if better than current)
                if let alt = alternative, let savings = calculateCO2Savings(alt) {
                    HStack(spacing: 6) {
                        Image(systemName: "leaf.fill")
                            .foregroundColor(Theme.success)
                        Text("\(Int(savings))% LESS CO2")
                            .font(.subheadline.bold())
                            .foregroundColor(Theme.success)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(Theme.success.opacity(0.15))
                    .cornerRadius(12)
                    .padding(.top, 12)
                }

                // Reason (why this alternative is better)
                if let reason = alternative?.reason, !reason.isEmpty {
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: "sparkles")
                            .font(.system(size: 12))
                            .foregroundColor(Theme.primary)
                            .padding(.top, 2)

                        Text(reason)
                            .font(.system(size: 12))
                            .foregroundColor(Theme.textPrimary)
                            .multilineTextAlignment(.leading)
                            .lineLimit(4)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(12)
                    .background(
                        RoundedRectangle(cornerRadius: 10)
                            .fill(Theme.primary.opacity(0.08))
                            .overlay(
                                RoundedRectangle(cornerRadius: 10)
                                    .stroke(Theme.primary.opacity(0.15), lineWidth: 1)
                            )
                    )
                    .padding(.horizontal, 20)
                    .padding(.top, 12)
                }

                // Score bars - only show for current product, or if alternative has real data
                if isCurrent {
                    // Show actual scores for current product
                    VStack(spacing: 12) {
                        ScoreBar(
                            label: "Health",
                            score: product?.healthScore ?? 0,
                            color: Theme.healthScoreColor(product?.healthScore ?? 0)
                        )

                        ScoreBar(
                            label: "Environment",
                            score: product?.environmentalScore ?? 50,
                            color: Theme.success
                        )
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 16)
                    
                    // Show CO2 and Water for current product too
                    VStack(spacing: 12) {
                        if let co2 = product?.co2Emissions, co2 > 0 {
                            HStack {
                                Image(systemName: "cloud.fill")
                                    .foregroundColor(Theme.warning)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Carbon Footprint")
                                        .font(.caption)
                                        .foregroundColor(Theme.textSecondary)
                                    Text(String(format: "%.1f kg CO₂", co2))
                                        .font(.subheadline.bold())
                                        .foregroundColor(Theme.textPrimary)
                                }
                                Spacer()
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 10)
                            .background(Theme.surfaceSecondary)
                            .cornerRadius(10)
                        }
                        
                        if let water = product?.waterUsage, water > 0 {
                            HStack {
                                Image(systemName: "drop.fill")
                                    .foregroundColor(Theme.warning)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Water Usage")
                                        .font(.caption)
                                        .foregroundColor(Theme.textSecondary)
                                    Text(String(format: "%.0f L", water))
                                        .font(.subheadline.bold())
                                        .foregroundColor(Theme.textPrimary)
                                }
                                Spacer()
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 10)
                            .background(Theme.surfaceSecondary)
                            .cornerRadius(10)
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 12)
                } else if let alt = alternative {
                    // For alternatives: show scores in nice cards (matching ResultsView style)
                    VStack(spacing: 14) {
                        // Score cards row
                        HStack(spacing: 10) {
                            // Health Score
                            scoreCard(
                                title: "Health",
                                score: alt.healthScore,
                                icon: "heart.fill",
                                color: alt.healthScore.map { scoreColor($0) } ?? Theme.textMuted
                            )

                            // Environmental Score
                            scoreCard(
                                title: "Environment",
                                score: alt.environmentalScore,
                                icon: "leaf.fill",
                                color: alt.environmentalScore.map { scoreColor($0) } ?? Theme.textMuted
                            )

                            // Ethics Score
                            scoreCard(
                                title: "Ethics",
                                score: alt.ethicsScore,
                                icon: "star.fill",
                                color: alt.ethicsScore.map { scoreColor($0) } ?? Theme.textMuted
                            )
                        }

                        // Impact stats (CO2 & Water) - compact pills
                        HStack(spacing: 10) {
                            if let co2 = alt.estimatedCO2, co2 > 0 {
                                impactPill(
                                    icon: "cloud.fill",
                                    value: String(format: "%.1f kg CO₂", co2),
                                    color: Theme.success
                                )
                            }

                            if let water = alt.estimatedWater, water > 0 {
                                impactPill(
                                    icon: "drop.fill",
                                    value: "\(Int(water))L",
                                    color: Theme.info
                                )
                            }
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 16)
                }

                // Data source indicator
                if let source = alternative?.dataSource {
                    HStack(spacing: 4) {
                        Image(systemName: getSourceIcon(source))
                            .font(.caption2)
                        Text(getSourceLabel(source))
                            .font(.caption2)
                    }
                    .foregroundColor(Theme.textMuted)
                    .padding(.top, 12)
                }

                Spacer(minLength: 20)

                // CTA button for alternatives
                if let alt = alternative {
                    if let link = alt.link, let url = URL(string: link) {
                        Button(action: {
                            UIApplication.shared.open(url)
                        }) {
                            HStack {
                                Text("View Product")
                                Image(systemName: "arrow.right")
                            }
                            .font(.subheadline.bold())
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(Theme.gradientHero)
                            .cornerRadius(12)
                        }
                        .padding(.horizontal, 20)
                        .padding(.bottom, 20)
                    } else {
                        // No link available - show search button
                        Button(action: {
                            let searchQuery = (alt.brand ?? "") + " " + alt.name
                            let encoded = searchQuery.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
                            if let url = URL(string: "https://www.amazon.com/s?k=\(encoded)") {
                                UIApplication.shared.open(url)
                            }
                        }) {
                            HStack {
                                Text("Search on Amazon")
                                Image(systemName: "magnifyingglass")
                            }
                            .font(.subheadline.bold())
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(Theme.primary)
                            .cornerRadius(12)
                        }
                        .padding(.horizontal, 20)
                        .padding(.bottom, 20)
                    }
                }
            }
            .padding(.vertical, 20)
            .frame(maxWidth: .infinity)
            .background(
            ZStack {
                RoundedRectangle(cornerRadius: 24)
                    .fill(isCurrent ? Theme.error.opacity(0.05) : Theme.success.opacity(0.05))

                RoundedRectangle(cornerRadius: 24)
                    .strokeBorder(
                        isCurrent ? Theme.error.opacity(0.3) : Theme.success.opacity(0.3),
                        lineWidth: 2
                    )
            }
        )
        .shadow(color: Color.black.opacity(0.1), radius: 20, x: 0, y: 10)
        .padding(.horizontal, 20)
    }
    
    private var productPlaceholderIcon: some View {
        ZStack {
            Circle()
                .fill(isCurrent ? Theme.warning.opacity(0.15) : Theme.success.opacity(0.15))
                .frame(width: 100, height: 100)
            Image(systemName: isCurrent ? "shippingbox.fill" : "leaf.fill")
                .font(.system(size: 40))
                .foregroundColor(isCurrent ? Theme.warning : Theme.success)
        }
        .frame(width: 120, height: 120)
    }

    func calculateCO2Savings(_ alt: AnalysisResult.Alternative) -> Double? {
        guard let currentCO2 = currentProduct?.co2Emissions,
              let altCO2 = alt.estimatedCO2,
              currentCO2 > 0 else { return nil }

        let savings = ((currentCO2 - altCO2) / currentCO2) * 100
        return savings > 0 ? savings : nil
    }

    func getSourceIcon(_ source: String) -> String {
        switch source.lowercased() {
        case "openfoodfacts": return "network"
        case "ai_estimate": return "sparkles"
        default: return "info.circle"
        }
    }

    func getSourceLabel(_ source: String) -> String {
        switch source.lowercased() {
        case "openfoodfacts": return "OpenFoodFacts data"
        case "ai_estimate": return "AI estimated"
        default: return "Cached data"
        }
    }

    // Helper view for score cards (matching ResultsView style)
    private func scoreCard(title: String, score: Double?, icon: String, color: Color) -> some View {
        VStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(color)

            if let score = score {
                Text("\(Int(score))")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundColor(.white)
            } else {
                Text("--")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundColor(Theme.textMuted)
            }

            Text(title)
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(Theme.textSecondary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Theme.surfaceSecondary)
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(color.opacity(score != nil ? 0.3 : 0.1), lineWidth: 1)
                )
        )
    }

    // Helper function for score colors
    private func scoreColor(_ score: Double) -> Color {
        switch score {
        case 80...100: return Theme.success
        case 60..<80: return Theme.warning
        case 40..<60: return Theme.warning.opacity(0.8)
        default: return Theme.error
        }
    }

    // Helper view for impact pills
    private func impactPill(icon: String, value: String, color: Color) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(color)
            Text(value)
                .font(.system(size: 12, weight: .bold))
                .foregroundColor(.white)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            Capsule()
                .fill(color.opacity(0.15))
                .overlay(
                    Capsule()
                        .stroke(color.opacity(0.3), lineWidth: 1)
                )
        )
    }
}

struct ScoreBar: View {
    let label: String
    let score: Double
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(label)
                    .font(.caption)
                    .foregroundColor(Theme.textSecondary)
                Spacer()
                Text("\(Int(score))")
                    .font(.caption.bold())
                    .foregroundColor(Theme.textPrimary)
            }

            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    // Background
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.white.opacity(0.1))

                    // Filled portion
                    RoundedRectangle(cornerRadius: 4)
                        .fill(color)
                        .frame(width: geometry.size.width * (score / 100))
                        .animation(.spring(response: 0.6, dampingFraction: 0.7), value: score)
                }
            }
            .frame(height: 8)
        }
    }
}
