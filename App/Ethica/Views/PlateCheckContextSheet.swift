//
//  PlateCheckContextSheet.swift
//  Ethica
//
//  Premium context sheet for collecting restaurant info before plate analysis
//

import SwiftUI

struct PlateCheckContextSheet: View {
    let image: UIImage?
    let onAnalyze: (String, String, String) -> Void
    let onCancel: () -> Void

    @State private var restaurantName = ""
    @State private var dishName = ""
    @State private var cuisineType = ""
    @State private var selectedCuisineIndex = 0

    private let cuisineTypes = ["", "Italian", "Indian", "Mexican", "Asian", "Mediterranean", "Middle Eastern", "American", "French", "Japanese", "Thai", "Chinese", "Other"]

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.backgroundPrimary.ignoresSafeArea()

                ScrollView(.vertical, showsIndicators: false) {
                    VStack(spacing: Spacing.lg) {
                        // Image preview card
                        if let image = image {
                            imagePreview(image)
                                .slideInFromBottom(delay: 0.05)
                        }

                        // Context form card
                        contextForm
                            .slideInFromBottom(delay: 0.1)

                        Spacer(minLength: Spacing.lg)

                        // Action buttons
                        actionButtons
                            .slideInFromBottom(delay: 0.15)
                    }
                    .padding(Spacing.screenHorizontal)
                }
            }
            .navigationTitle("Plate Check")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button(action: onCancel) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 24))
                            .foregroundColor(Theme.textMuted)
                    }
                }
            }
        }
    }

    // MARK: - Image Preview

    private func imagePreview(_ uiImage: UIImage) -> some View {
        ZStack(alignment: .bottomLeading) {
            Image(uiImage: uiImage)
                .resizable()
                .scaledToFill()
                .frame(maxWidth: .infinity)
                .frame(height: 220)
                .clipped()
                .cornerRadius(Spacing.radiusLG)
                .overlay(
                    // Gradient overlay at bottom for text readability
                    LinearGradient(
                        colors: [.clear, .clear, Color.black.opacity(0.5)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    .cornerRadius(Spacing.radiusLG)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: Spacing.radiusLG)
                        .stroke(Color.white.opacity(0.1), lineWidth: 1)
                )
                .shadow(color: Color.black.opacity(0.3), radius: 15, y: 8)

            // Camera badge
            HStack(spacing: 6) {
                Image(systemName: "camera.fill")
                    .font(.system(size: 11, weight: .semibold))
                Text("Your plate")
                    .font(.system(size: 12, weight: .semibold))
            }
            .foregroundColor(.white)
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(.ultraThinMaterial)
            .cornerRadius(Spacing.radiusPill)
            .padding(Spacing.sm + 4)
        }
    }

    // MARK: - Context Form

    private var contextForm: some View {
        GlassCard(variant: .secondary) {
            VStack(alignment: .leading, spacing: Spacing.lg) {
                // Section header
                VStack(alignment: .leading, spacing: 4) {
                    Text("Add Context")
                        .font(Typography.h3)
                        .foregroundColor(Theme.textPrimary)
                    Text("Optional — helps improve accuracy")
                        .textStyleCaption(color: Theme.textMuted)
                }

                // Restaurant name
                formField(
                    label: "RESTAURANT NAME",
                    placeholder: "e.g., Olive Garden",
                    text: $restaurantName,
                    icon: "mappin.circle.fill"
                )

                // Dish name
                formField(
                    label: "DISH NAME",
                    placeholder: "e.g., Margherita Pizza",
                    text: $dishName,
                    icon: "fork.knife.circle.fill"
                )

                // Cuisine type
                VStack(alignment: .leading, spacing: Spacing.sm) {
                    Text("CUISINE TYPE")
                        .textStyleOverline(color: Theme.textMuted)

                    HStack(spacing: 10) {
                        Image(systemName: "globe.americas.fill")
                            .font(.system(size: 15))
                            .foregroundColor(Theme.accent)
                            .frame(width: 20)

                        Picker("Cuisine", selection: $selectedCuisineIndex) {
                            ForEach(0..<cuisineTypes.count, id: \.self) { index in
                                Text(cuisineTypes[index].isEmpty ? "Not specified" : cuisineTypes[index])
                                    .tag(index)
                            }
                        }
                        .pickerStyle(.menu)
                        .tint(Theme.accent)
                        .onChange(of: selectedCuisineIndex) { _, newValue in
                            cuisineType = cuisineTypes[newValue]
                        }

                        Spacer()
                    }
                    .padding(14)
                    .background(Theme.surfaceBase)
                    .cornerRadius(Spacing.radiusSM)
                    .overlay(
                        RoundedRectangle(cornerRadius: Spacing.radiusSM)
                            .stroke(Color.white.opacity(0.06), lineWidth: 1)
                    )
                }
            }
        }
    }

    private func formField(
        label: String,
        placeholder: String,
        text: Binding<String>,
        icon: String
    ) -> some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            Text(label)
                .textStyleOverline(color: Theme.textMuted)

            HStack(spacing: 10) {
                Image(systemName: icon)
                    .font(.system(size: 15))
                    .foregroundColor(Theme.accent)
                    .frame(width: 20)

                TextField(placeholder, text: text)
                    .font(.system(size: 16))
                    .foregroundColor(Theme.textPrimary)
            }
            .padding(14)
            .background(Theme.surfaceBase)
            .cornerRadius(Spacing.radiusSM)
            .overlay(
                RoundedRectangle(cornerRadius: Spacing.radiusSM)
                    .stroke(Color.white.opacity(0.06), lineWidth: 1)
            )
        }
    }

    // MARK: - Action Buttons

    private var actionButtons: some View {
        VStack(spacing: Spacing.sm + 4) {
            // Primary: Analyze
            Button(action: {
                HapticManager.shared.trigger(.impactMedium)
                onAnalyze(restaurantName, dishName, cuisineType)
            }) {
                HStack(spacing: 10) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 16, weight: .semibold))
                    Text("Analyze Plate")
                        .font(Typography.buttonLarge)
                }
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .background(Theme.gradientAccent)
                .cornerRadius(Spacing.radiusMD)
                .shadow(color: Theme.accent.opacity(0.3), radius: 12, y: 4)
            }
            .buttonPressAnimation()

            // Secondary: Cancel
            Button(action: onCancel) {
                Text("Cancel")
                    .font(Typography.button)
                    .foregroundColor(Theme.textMuted)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(Theme.surfaceSecondary)
                    .cornerRadius(Spacing.radiusMD)
                    .overlay(
                        RoundedRectangle(cornerRadius: Spacing.radiusMD)
                            .stroke(Color.white.opacity(0.05), lineWidth: 1)
                    )
            }
        }
    }
}
