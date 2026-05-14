//
//  TasteProfileView.swift
//  Ethica
//
//  View to display user's learned taste preferences
//

import SwiftUI

struct TasteProfileView: View {
    @State private var tasteProfile: TasteProfile?
    @State private var isLoading = true

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.backgroundPrimary.ignoresSafeArea()

                if isLoading {
                    ProgressView("Loading your taste profile...")
                        .foregroundColor(.white)
                } else if let profile = tasteProfile {
                    ScrollView {
                        VStack(spacing: 24) {
                            // Header Summary
                            profileSummaryCard(profile: profile)

                            // Taste Preferences
                            tastePreferencesCard(profile: profile)

                            // Texture Preferences
                            texturePreferencesCard(profile: profile)

                            // Category Preferences
                            categoryPreferencesCard(profile: profile)

                            // Confidence & Data
                            dataQualityCard(profile: profile)
                        }
                        .padding()
                    }
                } else {
                    emptyStateView()
                }
            }
            .navigationTitle("Your Taste Profile")
            .navigationBarTitleDisplayMode(.large)
        }
        .onAppear {
            loadTasteProfile()
        }
    }

    // MARK: - Profile Summary Card

    @ViewBuilder
    func profileSummaryCard(profile: TasteProfile) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "fork.knife.circle.fill")
                .font(.system(size: 60))
                .foregroundColor(Theme.primary)

            Text(profile.profileSummary)
                .font(Typography.body)
                .foregroundColor(Theme.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)

            HStack(spacing: Spacing.lg) {
                VStack(spacing: Spacing.xs) {
                    Text("\(profile.totalScansAnalyzed)")
                        .font(Typography.h1)
                        .foregroundColor(Theme.primary)
                    Text("Products Scanned")
                        .font(Typography.caption)
                        .foregroundColor(Theme.textSecondary)
                }

                Divider()
                    .frame(height: 40)
                    .background(Theme.textSecondary.opacity(0.3))

                VStack(spacing: Spacing.xs) {
                    Text("\(Int(profile.confidence * 100))%")
                        .font(Typography.h1)
                        .foregroundColor(Theme.success)
                    Text("Confidence")
                        .font(Typography.caption)
                        .foregroundColor(Theme.textSecondary)
                }
            }
            .padding(.top, 8)
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Theme.surfaceBase)
                .shadow(color: Color.black.opacity(0.3), radius: 10)
        )
    }

    // MARK: - Taste Preferences Card

    @ViewBuilder
    func tastePreferencesCard(profile: TasteProfile) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Image(systemName: "mouth.fill")
                    .foregroundColor(Theme.warning)
                Text("Taste Preferences")
                    .font(Typography.h3)
                    .foregroundColor(Theme.textPrimary)
                Spacer()
            }

            VStack(spacing: 12) {
                preferenceBar(label: "Sweet", value: profile.sweetnessPreference, icon: "🍬", color: .pink)
                preferenceBar(label: "Salty", value: profile.saltyPreference, icon: "🧂", color: .blue)
                preferenceBar(label: "Savory", value: profile.savoryPreference, icon: "🍖", color: .brown)
                preferenceBar(label: "Sour", value: profile.sourPreference, icon: "🍋", color: .yellow)
                preferenceBar(label: "Bitter", value: profile.bitterPreference, icon: "☕", color: Color(white: 0.4))
                preferenceBar(label: "Spicy", value: profile.spicyPreference, icon: "🌶️", color: .red)
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Theme.surfaceBase)
                .shadow(color: Color.black.opacity(0.3), radius: 10)
        )
    }

    // MARK: - Texture Preferences Card

    @ViewBuilder
    func texturePreferencesCard(profile: TasteProfile) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Image(systemName: "hand.tap.fill")
                    .foregroundColor(Theme.accent)
                Text("Texture Preferences")
                    .font(Typography.h3)
                    .foregroundColor(Theme.textPrimary)
                Spacer()
            }

            VStack(spacing: 12) {
                preferenceBar(label: "Crunchy", value: profile.crunchyPreference, icon: "🥖", color: .orange)
                preferenceBar(label: "Creamy", value: profile.creamyPreference, icon: "🍦", color: Color(white: 0.9))
                preferenceBar(label: "Chewy", value: profile.chewyPreference, icon: "🍬", color: .green)
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Theme.surfaceBase)
                .shadow(color: Color.black.opacity(0.3), radius: 10)
        )
    }

    // MARK: - Category Preferences Card

    @ViewBuilder
    func categoryPreferencesCard(profile: TasteProfile) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Image(systemName: "square.grid.2x2.fill")
                    .foregroundColor(Theme.info)
                Text("Product Categories")
                    .font(Typography.h3)
                    .foregroundColor(Theme.textPrimary)
                Spacer()
            }

            VStack(spacing: 12) {
                preferenceBar(label: "Meat Alternatives", value: profile.meatAlternativesPreference, icon: "🌱", color: .green)
                preferenceBar(label: "Dairy Alternatives", value: profile.dairyAlternativesPreference, icon: "🥛", color: Color(white: 0.9))
                preferenceBar(label: "Processed Foods", value: profile.processedFoodsPreference, icon: "📦", color: .gray)
                preferenceBar(label: "Organic Products", value: profile.organicPreference, icon: "🌿", color: .green)
                preferenceBar(label: "Local Products", value: profile.localPreference, icon: "🏡", color: .brown)
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Theme.surfaceBase)
                .shadow(color: Color.black.opacity(0.3), radius: 10)
        )
    }

    // MARK: - Data Quality Card

    @ViewBuilder
    func dataQualityCard(profile: TasteProfile) -> some View {
        VStack(spacing: 16) {
            HStack {
                Image(systemName: "chart.bar.doc.horizontal.fill")
                    .foregroundColor(Theme.warning)
                Text("Profile Quality")
                    .font(Typography.h3)
                    .foregroundColor(Theme.textPrimary)
                Spacer()
            }

            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("Data Points:")
                        .foregroundColor(Theme.textSecondary)
                    Spacer()
                    Text("\(profile.totalScansAnalyzed) scans")
                        .foregroundColor(.white)
                        .fontWeight(.semibold)
                }

                HStack {
                    Text("Confidence Level:")
                        .foregroundColor(Theme.textSecondary)
                    Spacer()
                    Text(confidenceLabel(profile.confidence))
                        .foregroundColor(confidenceColor(profile.confidence))
                        .fontWeight(.semibold)
                }

                HStack {
                    Text("Last Updated:")
                        .foregroundColor(Theme.textSecondary)
                    Spacer()
                    Text(RelativeDateTimeFormatter().localizedString(for: profile.lastUpdated, relativeTo: Date()))
                        .foregroundColor(.white)
                        .fontWeight(.semibold)
                }
            }
            .font(Typography.bodySmall)

            if profile.confidence < 0.5 {
                Text("Keep scanning products to improve your taste profile accuracy!")
                    .font(Typography.caption)
                    .foregroundColor(Theme.warning)
                    .padding(Spacing.md)
                    .background(
                        RoundedRectangle(cornerRadius: Spacing.radiusXS)
                            .fill(Theme.warning.opacity(0.1))
                    )
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Theme.surfaceBase)
                .shadow(color: Color.black.opacity(0.3), radius: 10)
        )
    }

    // MARK: - Helper Views

    @ViewBuilder
    func preferenceBar(label: String, value: Double, icon: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(icon)
                    .font(.system(size: 18))
                Text(label)
                    .font(Typography.bodySmall)
                    .foregroundColor(Theme.textPrimary)
                Spacer()
                Text("\(Int(value))%")
                    .font(Typography.caption)
                    .fontWeight(.bold)
                    .foregroundColor(color)
            }

            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    // Background
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Theme.textMuted.opacity(0.2))
                        .frame(height: 8)

                    // Fill
                    RoundedRectangle(cornerRadius: 4)
                        .fill(color)
                        .frame(width: geometry.size.width * (value / 100), height: 8)
                }
            }
            .frame(height: 8)
        }
    }

    // MARK: - Empty State

    @ViewBuilder
    func emptyStateView() -> some View {
        VStack(spacing: 20) {
            Image(systemName: "fork.knife.circle")
                .font(.system(size: 80))
                .foregroundColor(Theme.primary.opacity(0.5))

            Text("Building Your Taste Profile")
                .font(Typography.h1)
                .foregroundColor(Theme.textPrimary)

            Text("Scan more products to help us learn your taste preferences and suggest better alternatives")
                .font(Typography.body)
                .foregroundColor(Theme.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
        }
    }

    // MARK: - Helper Functions

    private func loadTasteProfile() {
        isLoading = true

        Task {
            let profile = await TasteProfileService.shared.getTasteProfile()
            await MainActor.run {
                self.tasteProfile = profile
                self.isLoading = false
            }
        }
    }

    private func confidenceLabel(_ confidence: Double) -> String {
        switch confidence {
        case 0..<0.3: return "Low"
        case 0.3..<0.6: return "Medium"
        case 0.6..<0.8: return "High"
        default: return "Very High"
        }
    }

    private func confidenceColor(_ confidence: Double) -> Color {
        switch confidence {
        case 0..<0.3: return Theme.warning
        case 0.3..<0.6: return Theme.warning
        case 0.6..<0.8: return Theme.success
        default: return Theme.success
        }
    }
}

// MARK: - Preview

struct TasteProfileView_Previews: PreviewProvider {
    static var previews: some View {
        TasteProfileView()
    }
}
