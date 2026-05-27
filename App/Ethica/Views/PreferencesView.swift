//
//  PreferencesView.swift
//  Ethica
//
//  Updated to match web design exactly

import SwiftUI

struct PreferencesView: View {
    @ObservedObject var preferencesManager: PreferencesManager
    var onComplete: (() -> Void)? // Optional callback for onboarding completion
    @Environment(\.presentationMode) var presentationMode
    @ObservedObject private var authService = AuthenticationService.shared
    @State private var showingLogoutAlert = false
    @State private var showingDeleteDataAlert = false
    @State private var isDeletingData = false
    @State private var deleteDataMessage: String?
    @State private var showingDeleteAccountAlert = false
    @State private var isDeletingAccount = false
    @State private var deleteAccountMessage: String?
    
    let dietOptions = [
        (id: "vegan", emoji: "🌱", name: "Vegan"),
        (id: "vegetarian", emoji: "🥚", name: "Vegetarian"),
        (id: "jain", emoji: "🕉️", name: "Jain"),
        (id: "halal", emoji: "☪️", name: "Halal"),
        (id: "kosher", emoji: "✡️", name: "Kosher"),
        (id: "pescatarian", emoji: "🐟", name: "Pescatarian")
    ]
    
    let allergenOptions = [
        (id: "gluten", emoji: "🌾", name: "Gluten"),
        (id: "dairy", emoji: "🥛", name: "Dairy"),
        (id: "nuts", emoji: "🥜", name: "Nuts"),
        (id: "soy", emoji: "🫘", name: "Soy"),
        (id: "eggs", emoji: "🥚", name: "Eggs"),
        (id: "shellfish", emoji: "🦐", name: "Shellfish"),
        (id: "peanuts", emoji: "🥜", name: "Peanuts"),
        (id: "treenuts", emoji: "🌰", name: "Tree Nuts"),
        (id: "fish", emoji: "🐟", name: "Fish"),
        (id: "sesame", emoji: "🫓", name: "Sesame")
    ]
    
    @State private var customDiet = ""
    @State private var customAllergen = ""
    
    var body: some View {
        ZStack {
            // Dark theme background
            Theme.backgroundPrimary
                .ignoresSafeArea()
                .accessibilityHidden(true)
            
            ScrollView {
                LazyVStack(spacing: Spacing.lg) {
                    // Header
                    VStack(spacing: 8) {
                        Text("🌿 Ethica")
                            .font(Typography.h1)
                            .foregroundColor(Theme.textPrimary)
                            .accessibilityLabel("Ethica")
                            .accessibilityAddTraits(.isHeader)

                        Text("Customize your dietary preferences & allergens")
                            .font(Typography.body)
                            .foregroundColor(Theme.textSecondary)
                            .multilineTextAlignment(.center)
                    }
                    .padding(.top, 8)

                    // Dietary Preferences Section
                    GlassCard.primary {
                    VStack(alignment: .leading, spacing: 16) {
                        Text("🥗 Dietary Preferences")
                            .font(Typography.h4)
                            .foregroundColor(Theme.primary)
                            .accessibilityLabel("Dietary Preferences")
                            .accessibilityAddTraits(.isHeader)

                            // Grid of diet buttons
                            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                                ForEach(dietOptions, id: \.id) { option in
                                    DietToggleButton(
                                        emoji: option.emoji,
                                        name: option.name,
                                        isSelected: preferencesManager.preferences.selectedDiets.contains(option.id)
                                    ) {
                                        preferencesManager.toggleDiet(option.id)
                                    }
                                }
                            }
                            
                            // Custom Diet Input
                            CustomInputSection(
                                title: "Add Custom Diet:",
                                placeholder: "e.g., Paleo, Keto, Low-FODMAP",
                                text: $customDiet,
                                tags: Array(preferencesManager.preferences.selectedDiets).sorted().map { $0.capitalized },
                                onAdd: {
                                    let trimmed = customDiet.trimmingCharacters(in: .whitespacesAndNewlines)
                                    if !trimmed.isEmpty {
                                        preferencesManager.toggleDiet(trimmed)
                                        customDiet = ""
                                    }
                                },
                                onRemove: { tag in
                                    preferencesManager.toggleDiet(tag)
                                }
                            )
                        }
                    }

                    // Allergen Preferences Section
                    GlassCard.primary {
                        VStack(alignment: .leading, spacing: 16) {
                            Text("⚠️ Allergen Preferences")
                                .font(Typography.h4)
                                .foregroundColor(Theme.warning)
                                .accessibilityLabel("Allergen Preferences")
                                .accessibilityAddTraits(.isHeader)

                            // Grid of allergen buttons
                            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                                ForEach(allergenOptions, id: \.id) { option in
                                    DietToggleButton(
                                        emoji: option.emoji,
                                        name: option.name,
                                        isSelected: preferencesManager.preferences.selectedAllergens.contains(option.id.lowercased())
                                    ) {
                                        preferencesManager.toggleAllergen(option.id)
                                    }
                                }
                            }
                            
                            // Custom Allergen Input
                            CustomInputSection(
                                title: "Add Custom Allergen:",
                                placeholder: "e.g., Sesame, Sulfites",
                                text: $customAllergen,
                                tags: Array(preferencesManager.preferences.selectedAllergens).sorted().map { $0.capitalized },
                                onAdd: {
                                    let trimmed = customAllergen.trimmingCharacters(in: .whitespacesAndNewlines)
                                    if !trimmed.isEmpty {
                                        preferencesManager.toggleAllergen(trimmed)
                                        customAllergen = ""
                                    }
                                },
                                onRemove: { tag in
                                    preferencesManager.toggleAllergen(tag)
                                }
                            )
                        }
                    }

                    // May-Contain Strictness Section
                    GlassCard.secondary {
                        VStack(alignment: .leading, spacing: 16) {
                            Text("\u{1F3ED} Cross-Contamination Sensitivity")
                                .font(Typography.h4)
                                .foregroundColor(Theme.warning)
                                .accessibilityLabel("Cross-Contamination Sensitivity")
                                .accessibilityAddTraits(.isHeader)

                            Text("How should we handle \"may contain\" warnings?")
                                .font(Typography.bodySmall)
                                .foregroundColor(Theme.textTertiary)
                                .multilineTextAlignment(.center)
                                .frame(maxWidth: .infinity)

                            VStack(spacing: 12) {
                                // Relaxed option
                                Button(action: {
                                    withAnimation(.spring(response: 0.3)) {
                                        preferencesManager.preferences.mayContainSafe = true
                                    }
                                }) {
                                    HStack(alignment: .top, spacing: 14) {
                                        ZStack {
                                            Circle()
                                                .stroke(preferencesManager.preferences.mayContainSafe ? Theme.primary : Theme.textMuted, lineWidth: 2)
                                                .frame(width: 22, height: 22)
                                            if preferencesManager.preferences.mayContainSafe {
                                                Circle()
                                                    .fill(Theme.primary)
                                                    .frame(width: 12, height: 12)
                                            }
                                        }
                                        .padding(.top, 2)
                                        .accessibilityHidden(true)

                                        VStack(alignment: .leading, spacing: 6) {
                                            HStack(spacing: 8) {
                                                Image(systemName: "info.circle.fill")
                                                    .font(Typography.body)
                                                    .foregroundColor(Theme.info)
                                                    .accessibilityHidden(true)
                                                Text("Relaxed \u{2014} Show as Warning")
                                                    .font(Typography.button)
                                                    .foregroundColor(Theme.textPrimary)
                                            }
                                            Text("May-contain items appear as cautions but won\u{2019}t mark the product unsafe")
                                                .font(Typography.caption)
                                                .foregroundColor(Theme.textTertiary)
                                                .fixedSize(horizontal: false, vertical: true)
                                                .lineSpacing(2)
                                        }
                                        Spacer()
                                    }
                                    .padding(14)
                                    .background(
                                        RoundedRectangle(cornerRadius: 12)
                                            .fill(preferencesManager.preferences.mayContainSafe ? Theme.primary.opacity(0.08) : Theme.surfaceSecondary)
                                    )
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 12)
                                            .stroke(preferencesManager.preferences.mayContainSafe ? Theme.primary.opacity(0.5) : Theme.textMuted.opacity(0.5), lineWidth: preferencesManager.preferences.mayContainSafe ? 2 : 1)
                                    )
                                }
                                .buttonStyle(.plain)
                                .accessibilityElement(children: .combine)
                                .accessibilityLabel("Relaxed, show as warning. May-contain items appear as cautions but won't mark the product unsafe")
                                .accessibilityAddTraits(preferencesManager.preferences.mayContainSafe ? [.isSelected] : [])
                                .accessibilityHint(preferencesManager.preferences.mayContainSafe ? "Currently selected" : "Double tap to select relaxed mode")

                                // Strict option
                                Button(action: {
                                    withAnimation(.spring(response: 0.3)) {
                                        preferencesManager.preferences.mayContainSafe = false
                                    }
                                }) {
                                    HStack(alignment: .top, spacing: 14) {
                                        ZStack {
                                            Circle()
                                                .stroke(!preferencesManager.preferences.mayContainSafe ? Theme.primary : Theme.textMuted, lineWidth: 2)
                                                .frame(width: 22, height: 22)
                                            if !preferencesManager.preferences.mayContainSafe {
                                                Circle()
                                                    .fill(Theme.primary)
                                                    .frame(width: 12, height: 12)
                                            }
                                        }
                                        .padding(.top, 2)
                                        .accessibilityHidden(true)

                                        VStack(alignment: .leading, spacing: 6) {
                                            HStack(spacing: 8) {
                                                Image(systemName: "exclamationmark.shield.fill")
                                                    .font(Typography.body)
                                                    .foregroundColor(Theme.error)
                                                    .accessibilityHidden(true)
                                                Text("Strict \u{2014} Treat as Unsafe")
                                                    .font(Typography.button)
                                                    .foregroundColor(Theme.textPrimary)
                                            }
                                            Text("Products with may-contain warnings for your allergens/diet will be marked as unsafe")
                                                .font(Typography.caption)
                                                .foregroundColor(Theme.textTertiary)
                                                .fixedSize(horizontal: false, vertical: true)
                                                .lineSpacing(2)
                                        }
                                        Spacer()
                                    }
                                    .padding(14)
                                    .background(
                                        RoundedRectangle(cornerRadius: 12)
                                            .fill(!preferencesManager.preferences.mayContainSafe ? Theme.error.opacity(0.08) : Theme.surfaceSecondary)
                                    )
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 12)
                                            .stroke(!preferencesManager.preferences.mayContainSafe ? Theme.error.opacity(0.5) : Theme.textMuted.opacity(0.5), lineWidth: !preferencesManager.preferences.mayContainSafe ? 2 : 1)
                                    )
                                }
                                .buttonStyle(.plain)
                                .accessibilityElement(children: .combine)
                                .accessibilityLabel("Strict, treat as unsafe. Products with may-contain warnings for your allergens or diet will be marked as unsafe")
                                .accessibilityAddTraits(!preferencesManager.preferences.mayContainSafe ? [.isSelected] : [])
                                .accessibilityHint(!preferencesManager.preferences.mayContainSafe ? "Currently selected" : "Double tap to select strict mode")
                            }

                            // Current mode indicator
                            HStack(spacing: 8) {
                                Image(systemName: preferencesManager.preferences.mayContainSafe ? "info.circle.fill" : "exclamationmark.shield.fill")
                                    .font(Typography.caption)
                                    .foregroundColor(preferencesManager.preferences.mayContainSafe ? Theme.info : Theme.error)
                                    .accessibilityHidden(true)
                                Text(preferencesManager.preferences.mayContainSafe
                                     ? "Currently: Warnings only (relaxed)"
                                     : "Currently: Marked unsafe (strict)")
                                    .font(Typography.caption)
                                    .foregroundColor(Theme.textMuted)
                            }
                            .frame(maxWidth: .infinity)
                            .accessibilityElement(children: .combine)
                        }
                    }

                    // GMO Preference Section
                    GlassCard.secondary {
                        VStack(alignment: .leading, spacing: 16) {
                            Text("\u{1F9EC} GMO Preferences")
                                .font(Typography.h4)
                                .foregroundColor(Theme.primary)
                                .accessibilityLabel("GMO Preferences")
                                .accessibilityAddTraits(.isHeader)

                            Text("How should we handle products with GMO ingredients?")
                                .font(Typography.bodySmall)
                                .foregroundColor(Theme.textTertiary)
                                .multilineTextAlignment(.center)
                                .frame(maxWidth: .infinity)

                            VStack(spacing: 10) {
                                // No preference (informational)
                                Button(action: {
                                    withAnimation(AnimationSystem.springResponsive) {
                                        preferencesManager.preferences.avoidGMO = false
                                    }
                                }) {
                                    HStack(spacing: 12) {
                                        Image(systemName: "info.circle.fill")
                                            .font(.system(size: 20))
                                            .foregroundColor(Theme.info)
                                            .accessibilityHidden(true)
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text("No Preference")
                                                .font(Typography.button)
                                                .foregroundColor(Theme.textPrimary)
                                            Text("GMO info shown for reference only")
                                                .font(Typography.caption)
                                                .foregroundColor(Theme.textMuted)
                                        }
                                        Spacer()
                                        Image(systemName: !preferencesManager.preferences.avoidGMO ? "checkmark.circle.fill" : "circle")
                                            .foregroundColor(!preferencesManager.preferences.avoidGMO ? Theme.primary : Theme.textMuted)
                                            .font(.system(size: 22))
                                    }
                                    .padding(14)
                                    .background(
                                        RoundedRectangle(cornerRadius: 12)
                                            .fill(!preferencesManager.preferences.avoidGMO ? Theme.info.opacity(0.08) : Theme.surfaceSecondary)
                                    )
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 12)
                                            .stroke(!preferencesManager.preferences.avoidGMO ? Theme.info.opacity(0.5) : Theme.textMuted.opacity(0.5), lineWidth: !preferencesManager.preferences.avoidGMO ? 2 : 1)
                                    )
                                }
                                .buttonStyle(.plain)
                                .accessibilityElement(children: .combine)
                                .accessibilityLabel("No preference. GMO information shown for reference only")
                                .accessibilityAddTraits(!preferencesManager.preferences.avoidGMO ? [.isSelected] : [])

                                // Avoid GMO (flag as unsafe)
                                Button(action: {
                                    withAnimation(AnimationSystem.springResponsive) {
                                        preferencesManager.preferences.avoidGMO = true
                                    }
                                }) {
                                    HStack(spacing: 12) {
                                        Image(systemName: "exclamationmark.triangle.fill")
                                            .font(.system(size: 20))
                                            .foregroundColor(Theme.warning)
                                            .accessibilityHidden(true)
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text("Avoid GMO")
                                                .font(Typography.button)
                                                .foregroundColor(Theme.textPrimary)
                                            Text("GMO products flagged as unsafe")
                                                .font(Typography.caption)
                                                .foregroundColor(Theme.textMuted)
                                        }
                                        Spacer()
                                        Image(systemName: preferencesManager.preferences.avoidGMO ? "checkmark.circle.fill" : "circle")
                                            .foregroundColor(preferencesManager.preferences.avoidGMO ? Theme.warning : Theme.textMuted)
                                            .font(.system(size: 22))
                                    }
                                    .padding(14)
                                    .background(
                                        RoundedRectangle(cornerRadius: 12)
                                            .fill(preferencesManager.preferences.avoidGMO ? Theme.warning.opacity(0.08) : Theme.surfaceSecondary)
                                    )
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 12)
                                            .stroke(preferencesManager.preferences.avoidGMO ? Theme.warning.opacity(0.5) : Theme.textMuted.opacity(0.5), lineWidth: preferencesManager.preferences.avoidGMO ? 2 : 1)
                                    )
                                }
                                .buttonStyle(.plain)
                                .accessibilityElement(children: .combine)
                                .accessibilityLabel("Avoid GMO. Products with GMO ingredients flagged as unsafe")
                                .accessibilityAddTraits(preferencesManager.preferences.avoidGMO ? [.isSelected] : [])
                            }

                            // Current mode indicator
                            HStack(spacing: 8) {
                                Image(systemName: preferencesManager.preferences.avoidGMO ? "exclamationmark.triangle.fill" : "info.circle.fill")
                                    .font(Typography.caption)
                                    .foregroundColor(preferencesManager.preferences.avoidGMO ? Theme.warning : Theme.info)
                                    .accessibilityHidden(true)
                                Text(preferencesManager.preferences.avoidGMO
                                     ? "Currently: GMO flagged as unsafe"
                                     : "Currently: GMO informational only")
                                    .font(Typography.caption)
                                    .foregroundColor(Theme.textMuted)
                            }
                            .frame(maxWidth: .infinity)
                            .accessibilityElement(children: .combine)
                        }
                    }

                    // Alternative Product Priorities Section
                    GlassCard.primary {
                        VStack(alignment: .leading, spacing: 16) {
                            Text("⚖️ Alternative Product Priorities")
                                .font(Typography.h4)
                                .foregroundColor(Theme.primary)
                                .accessibilityLabel("Alternative Product Priorities")
                                .accessibilityAddTraits(.isHeader)

                            Text("What matters most when we suggest alternatives?")
                                .font(Typography.bodySmall)
                                .foregroundColor(Theme.textTertiary)
                                .multilineTextAlignment(.center)
                                .frame(maxWidth: .infinity)

                            VStack(spacing: 20) {
                                // Health priority slider
                                VStack(alignment: .leading, spacing: 8) {
                                    HStack {
                                        Image(systemName: "heart.fill")
                                            .foregroundColor(Theme.error.opacity(0.8))
                                            .accessibilityHidden(true)
                                        Text("Health")
                                            .font(Typography.button)
                                            .foregroundColor(Theme.textPrimary)
                                        Spacer()
                                        Text("\(Int(preferencesManager.preferences.healthPriority))%")
                                            .font(Typography.button)
                                            .foregroundColor(Theme.primary)
                                    }
                                    .accessibilityElement(children: .combine)
                                    Slider(value: Binding(
                                        get: { preferencesManager.preferences.healthPriority },
                                        set: { newValue in
                                            preferencesManager.preferences.adjustPriority(changed: "health", newValue: newValue)
                                        }
                                    ), in: 0...100, step: 5)
                                        .accentColor(Theme.primary)
                                        .accessibilityLabel("Health priority")
                                        .accessibilityValue("\(Int(preferencesManager.preferences.healthPriority)) percent")
                                }

                                // Environment priority slider
                                VStack(alignment: .leading, spacing: 8) {
                                    HStack {
                                        Image(systemName: "leaf.fill")
                                            .foregroundColor(Theme.primaryLight)
                                            .accessibilityHidden(true)
                                        Text("Environment")
                                            .font(Typography.button)
                                            .foregroundColor(Theme.textPrimary)
                                        Spacer()
                                        Text("\(Int(preferencesManager.preferences.environmentPriority))%")
                                            .font(Typography.button)
                                            .foregroundColor(Theme.primary)
                                    }
                                    .accessibilityElement(children: .combine)
                                    Slider(value: Binding(
                                        get: { preferencesManager.preferences.environmentPriority },
                                        set: { newValue in
                                            preferencesManager.preferences.adjustPriority(changed: "environment", newValue: newValue)
                                        }
                                    ), in: 0...100, step: 5)
                                        .accentColor(Theme.primary)
                                        .accessibilityLabel("Environment priority")
                                        .accessibilityValue("\(Int(preferencesManager.preferences.environmentPriority)) percent")
                                }

                                // Ethics priority slider
                                VStack(alignment: .leading, spacing: 8) {
                                    HStack {
                                        Image(systemName: "checkmark.seal.fill")
                                            .foregroundColor(Theme.info)
                                            .accessibilityHidden(true)
                                        Text("Ethics & Certifications")
                                            .font(Typography.button)
                                            .foregroundColor(Theme.textPrimary)
                                        Spacer()
                                        Text("\(Int(preferencesManager.preferences.ethicsPriority))%")
                                            .font(Typography.button)
                                            .foregroundColor(Theme.primary)
                                    }
                                    .accessibilityElement(children: .combine)
                                    Slider(value: Binding(
                                        get: { preferencesManager.preferences.ethicsPriority },
                                        set: { newValue in
                                            preferencesManager.preferences.adjustPriority(changed: "ethics", newValue: newValue)
                                        }
                                    ), in: 0...100, step: 5)
                                        .accentColor(Theme.primary)
                                        .accessibilityLabel("Ethics and certifications priority")
                                        .accessibilityValue("\(Int(preferencesManager.preferences.ethicsPriority)) percent")
                                }

                                // Total indicator
                                let total = Int(preferencesManager.preferences.healthPriority +
                                               preferencesManager.preferences.environmentPriority +
                                               preferencesManager.preferences.ethicsPriority)
                                Text("Total: \(total)%")
                                    .font(Typography.bodySmall)
                                    .foregroundColor(total == 100 ? Theme.primary : Theme.warning)
                                    .frame(maxWidth: .infinity, alignment: .center)
                                    .accessibilityLabel("Priority total: \(total) percent\(total != 100 ? ", should equal 100 percent" : "")")
                            }
                            .padding(.vertical, 8)
                        }
                    }

                    // Save/Continue Button
                    PrimaryButton.primary(onComplete != nil ? "Continue" : "Save Changes") {
                        if let complete = onComplete {
                            complete()
                        } else {
                            presentationMode.wrappedValue.dismiss()
                        }
                    }
                    .padding(.top, 8)
                        .accessibilityLabel(onComplete != nil ? "Continue to next step" : "Save changes to preferences")
                        .accessibilityHint(onComplete != nil ? "Double tap to continue with onboarding" : "Double tap to save and go back")
                        
                        // Data Management Section (only show when not in onboarding)
                        if onComplete == nil {
                            VStack(alignment: .leading, spacing: 12) {
                                Text("🔒 Privacy & Data")
                                    .font(Typography.h4)
                                    .foregroundColor(Theme.textMuted)
                                    .accessibilityLabel("Privacy and Data")
                                    .accessibilityAddTraits(.isHeader)
                                
                                // Clear Scan History Button
                                Button(action: {
                                    showingDeleteDataAlert = true
                                }) {
                                    HStack {
                                        Image(systemName: "trash.circle.fill")
                                            .font(Typography.h3)
                                            .foregroundColor(Theme.error)
                                            .accessibilityHidden(true)

                                        VStack(alignment: .leading, spacing: 4) {
                                            Text("Clear Scan History")
                                                .font(Typography.button)
                                                .foregroundColor(Theme.error)
                                            Text("Remove all scan history and cached data")
                                                .font(Typography.bodySmall)
                                                .foregroundColor(Theme.textTertiary)
                                        }
                                        
                                        Spacer()
                                        
                                        if isDeletingData {
                                            ProgressView()
                                                .tint(Theme.error)
                                        }
                                    }
                                    .padding()
                                    .background(
                                        RoundedRectangle(cornerRadius: 12)
                                            .fill(Theme.surfaceSecondary)
                                    )
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 12)
                                            .stroke(Theme.error.opacity(0.2), lineWidth: 1)
                                    )
                                }
                                .disabled(isDeletingData)
                                .buttonPressAnimation()
                                .accessibilityLabel("Clear scan history")
                                .accessibilityHint("Removes all scan history and cached data")

                                // Delete Account Button (Apple Guideline 5.1.1)
                                Button(action: {
                                    showingDeleteAccountAlert = true
                                }) {
                                    HStack {
                                        Image(systemName: "person.crop.circle.badge.minus")
                                            .font(Typography.h3)
                                            .foregroundColor(Theme.error)
                                            .accessibilityHidden(true)

                                        VStack(alignment: .leading, spacing: 4) {
                                            Text("Delete Account")
                                                .font(Typography.button)
                                                .foregroundColor(Theme.error)
                                            Text("Permanently delete your account and all associated data")
                                                .font(Typography.bodySmall)
                                                .foregroundColor(Theme.textTertiary)
                                        }

                                        Spacer()

                                        if isDeletingAccount {
                                            ProgressView()
                                                .tint(Theme.error)
                                        }
                                    }
                                    .padding()
                                    .background(
                                        RoundedRectangle(cornerRadius: 12)
                                            .fill(Theme.surfaceSecondary)
                                    )
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 12)
                                            .stroke(Theme.error.opacity(0.2), lineWidth: 1)
                                    )
                                }
                                .disabled(isDeletingAccount)
                                .buttonPressAnimation()
                                .accessibilityLabel("Delete account")
                                .accessibilityHint("Permanently deletes your account, including all data and sign-in credentials")
                            }
                            .padding(.vertical, 8)
                        }
                        
                        // Logout Button (only show when not in onboarding)
                        if onComplete == nil {
                            Button(action: {
                                showingLogoutAlert = true
                            }) {
                                HStack {
                                    Image(systemName: "rectangle.portrait.and.arrow.right")
                                        .font(Typography.bodySmall)
                                        .accessibilityHidden(true)
                                    Text("Sign Out")
                                        .font(Typography.button)
                                }
                                .foregroundColor(Theme.error)
                                .frame(maxWidth: .infinity)
                                .padding()
                                .background(Theme.surfaceSecondary)
                                .clipShape(RoundedRectangle(cornerRadius: 12))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 12)
                                        .stroke(Theme.error.opacity(0.3), lineWidth: 1)
                                )
                            }
                            .padding(.top, 4)
                            .accessibilityLabel("Sign out")
                            .accessibilityHint("Double tap to sign out of your account")
                        }
                        
                    // Footer
                    Text("Made with 💚 for conscious consumers")
                        .font(Typography.caption)
                        .foregroundColor(Theme.textTertiary)
                        .padding(.top, 8)
                        .accessibilityLabel("Made with love for conscious consumers")
                }
                .padding(.horizontal, Spacing.screenHorizontal)
                .padding(.vertical, Spacing.screenVertical)
            }
        }
        .alert("Clear Scan History", isPresented: $showingDeleteDataAlert) {
            Button("Cancel", role: .cancel) { }
            Button("Clear History", role: .destructive) {
                Task {
                    isDeletingData = true
                    HistoryService.shared.clearAllHistory()

                    let networkService = NetworkService.shared
                    let userId = AuthenticationService.shared.currentUserId ?? "anonymous"
                    do {
                        try await networkService.deleteUserData(userId: userId)
                    } catch {
                        // Local data already deleted, backend failure is non-critical
                    }

                    isDeletingData = false
                    deleteDataMessage = "Your scan history has been cleared"
                }
            }
        } message: {
            Text("This will permanently delete all your scan history and impact data. Your account will not be affected.")
        }
        .alert("History Cleared", isPresented: .init(
            get: { deleteDataMessage != nil },
            set: { if !$0 { deleteDataMessage = nil } }
        )) {
            Button("OK") { deleteDataMessage = nil }
        } message: {
            Text(deleteDataMessage ?? "")
        }
        .alert("Delete Account", isPresented: $showingDeleteAccountAlert) {
            Button("Cancel", role: .cancel) { }
            Button("Delete My Account", role: .destructive) {
                Task {
                    isDeletingAccount = true
                    do {
                        try await authService.deleteAccount()
                        isDeletingAccount = false
                        deleteAccountMessage = "Your account has been permanently deleted."
                    } catch let error as NSError {
                        isDeletingAccount = false
                        if error.code == 17014 {
                            // Firebase: requires recent login
                            deleteAccountMessage = "For security, please sign out and sign back in, then try again."
                        } else {
                            deleteAccountMessage = "Failed to delete account. Please try again later."
                        }
                    }
                }
            }
        } message: {
            Text("This will permanently delete your account, all scan history, and all associated data. This action cannot be undone.")
        }
        .alert("Account Deletion", isPresented: .init(
            get: { deleteAccountMessage != nil },
            set: { if !$0 { deleteAccountMessage = nil } }
        )) {
            Button("OK") { deleteAccountMessage = nil }
        } message: {
            Text(deleteAccountMessage ?? "")
        }
        .alert("Sign Out", isPresented: $showingLogoutAlert) {
            Button("Cancel", role: .cancel) { }
            Button("Sign Out", role: .destructive) {
                handleLogout()
            }
        } message: {
            Text("Are you sure you want to sign out? Your preferences will be saved.")
        }
        .navigationTitle("Settings")
    }
    
    private func handleLogout() {
        do {
            try authService.signOut()
        } catch {
            AppLogger.debug("Error signing out: \(error.localizedDescription)")
        }
    }
}

// Diet Toggle Button Component
struct DietToggleButton: View {
    let emoji: String
    let name: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Text(emoji)
                    .font(Typography.body)
                    .accessibilityHidden(true)
                Text(name)
                    .font(Typography.bodySmall)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 11)
            .padding(.horizontal, 14)
            .background(
                isSelected ? Theme.primary : Theme.surfaceSecondary
            )
            .foregroundColor(isSelected ? .white : Theme.textTertiary)
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(
                        isSelected ? Color.clear : Theme.textMuted.opacity(0.5),
                        lineWidth: 1
                    )
            )
        }
        .accessibilityLabel("\(name), \(isSelected ? "selected" : "not selected")")
        .accessibilityHint("Double tap to \(isSelected ? "deselect" : "select")")
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }
}

// Custom Input Section Component
struct CustomInputSection: View {
    let title: String
    let placeholder: String
    @Binding var text: String
    let tags: [String]
    let onAdd: () -> Void
    let onRemove: (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(Typography.bodySmall)
                .foregroundColor(Theme.textSecondary)

            HStack(spacing: 8) {
                // Placeholder overlay so placeholder color is visible and text is dark
                ZStack(alignment: .leading) {
                    if text.isEmpty {
                        Text(placeholder)
                            .foregroundColor(Theme.textTertiary)
                            .padding(10)
                            .font(Typography.bodySmall)
                            .accessibilityHidden(true)
                    }

                    TextField("", text: $text)
                        .padding(10)
                        .foregroundColor(Theme.textPrimary)
                        .font(Typography.bodySmall)
                        .accessibilityLabel(title.replacingOccurrences(of: ":", with: ""))
                        .accessibilityHint(placeholder)
                }
                .background(Theme.surfaceSecondary)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Theme.textMuted.opacity(0.5), lineWidth: 1)
                )

                Button(action: onAdd) {
                    Text("➕ Add")
                        .font(Typography.bodySmall)
                        .foregroundColor(.white)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .background(Theme.primary)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                }
                .accessibilityLabel("Add")
                .accessibilityHint("Double tap to add the entered item")
            }

            // Custom tags display
            if !tags.isEmpty {
                if #available(iOS 16.0, *) {
                    PreferencesFlowLayout(spacing: 8) {
                        ForEach(tags, id: \.self) { tag in
                            HStack(spacing: 6) {
                                Text(tag.capitalized)
                                    .font(Typography.caption)
                                    .foregroundColor(Theme.primary)
                                Button(action: { onRemove(tag) }) {
                                    Text("×")
                                        .font(Typography.buttonLarge)
                                        .foregroundColor(Theme.error)
                                }
                                .accessibilityLabel("Remove \(tag.capitalized)")
                                .accessibilityHint("Double tap to remove \(tag.capitalized)")
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(Theme.surfaceSecondary)
                            .clipShape(RoundedRectangle(cornerRadius: 16))
                            .overlay(
                                RoundedRectangle(cornerRadius: 16)
                                    .stroke(Theme.primary, lineWidth: 1)
                            )
                            .accessibilityElement(children: .combine)
                            .accessibilityLabel("\(tag.capitalized), selected")
                            .accessibilityHint("Double tap to remove")
                        }
                    }
                } else {
                    // Fallback for iOS 15
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(tags, id: \.self) { tag in
                            Text(tag)
                                .font(Typography.bodySmall)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                                .background(Theme.primary.opacity(0.2))
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                                .accessibilityLabel("\(tag.capitalized), selected")
                        }
                    }
                }
            }
        }
        .padding(14)
        .background(Theme.surfaceSecondary)
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }
}

// FlowLayout for custom tags
@available(iOS 16.0, *)
struct PreferencesFlowLayout: Layout {
    var spacing: CGFloat = 8
    
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let result = FlowResult(
            in: proposal.replacingUnspecifiedDimensions().width,
            subviews: subviews,
            spacing: spacing
        )
        return result.size
    }
    
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = FlowResult(
            in: bounds.width,
            subviews: subviews,
            spacing: spacing
        )
        for (index, subview) in subviews.enumerated() {
            subview.place(at: CGPoint(x: bounds.minX + result.positions[index].x, y: bounds.minY + result.positions[index].y), proposal: .unspecified)
        }
    }
    
    struct FlowResult {
        var size: CGSize = .zero
        var positions: [CGPoint] = []
        
        init(in maxWidth: CGFloat, subviews: Subviews, spacing: CGFloat) {
            var x: CGFloat = 0
            var y: CGFloat = 0
            var lineHeight: CGFloat = 0
            
            for subview in subviews {
                let size = subview.sizeThatFits(.unspecified)
                
                if x + size.width > maxWidth && x > 0 {
                    x = 0
                    y += lineHeight + spacing
                    lineHeight = 0
                }
                
                positions.append(CGPoint(x: x, y: y))
                lineHeight = max(lineHeight, size.height)
                x += size.width + spacing
            }
            
            self.size = CGSize(width: maxWidth, height: y + lineHeight)
        }
    }
}
