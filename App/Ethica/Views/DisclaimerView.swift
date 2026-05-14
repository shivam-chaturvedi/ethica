//
//  DisclaimerView.swift
//  Ethica
//
//  Critical safety disclaimer shown on first launch
//

import SwiftUI

struct DisclaimerView: View {
    @Binding var hasAcceptedDisclaimer: Bool
    @State private var hasScrolledToBottom = false
    @State private var showPrivacyPolicy = false
    @State private var showTermsOfService = false

    var body: some View {
        ZStack {
            // Background - dark themed
            Theme.backgroundPrimary
                .ignoresSafeArea()

            VStack(spacing: 0) {
                // Header
                VStack(spacing: Spacing.sm) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 60))
                        .foregroundColor(Theme.warning)
                        .accessibilityHidden(true)

                    Text("Important Safety Notice")
                        .font(Typography.h1)
                        .foregroundColor(Theme.textPrimary)
                        .accessibilityAddTraits(.isHeader)

                    Text("Please read carefully before using Ethica")
                        .font(Typography.bodySmall)
                        .foregroundColor(Theme.textTertiary)
                }
                .padding(.top, Spacing.xl)
                .padding(.bottom, Spacing.lg)

                // Scrollable content
                ScrollViewReader { proxy in
                    ScrollView {
                        VStack(alignment: .leading, spacing: Spacing.lg) {
                            disclaimerSection(
                                icon: "cross.case.fill",
                                title: "Not Medical Advice",
                                text: "Ethica is an informational tool only. It is NOT a substitute for professional medical, dietary, or nutritional advice. Always consult a doctor or registered dietitian for health decisions."
                            )

                            disclaimerSection(
                                icon: "exclamationmark.octagon.fill",
                                title: "AI May Make Errors",
                                text: "Our AI analysis may contain mistakes, miss ingredients, or provide incorrect information. If you have severe allergies, ALWAYS verify ingredients yourself by reading product labels."
                            )

                            disclaimerSection(
                                icon: "allergens",
                                title: "Life-Threatening Allergies",
                                text: "If you have severe, life-threatening allergies (anaphylaxis risk), DO NOT rely solely on Ethica. Always read product labels yourself, consult your allergist, and carry your EpiPen."
                            )

                            disclaimerSection(
                                icon: "leaf.fill",
                                title: "Dietary & Religious Restrictions",
                                text: "Our dietary compatibility checks (Jain, Halal, Kosher, Vegan, etc.) are automated and may not meet all interpretations or standards. For strict religious adherence, consult religious authorities."
                            )

                            disclaimerSection(
                                icon: "globe.americas.fill",
                                title: "Environmental Estimates",
                                text: "CO2 and environmental impact figures are estimates based on scientific averages. Actual product footprints may vary."
                            )

                            disclaimerSection(
                                icon: "checkmark.shield.fill",
                                title: "Always Verify",
                                text: "Use Ethica as a helpful guide, but always verify critical information yourself. We cannot guarantee 100% accuracy."
                            )

                            Divider()
                                .background(Theme.textMuted)
                                .padding(.vertical, Spacing.sm)

                            VStack(alignment: .leading, spacing: Spacing.sm) {
                                Text("By continuing, you agree to:")
                                    .font(Typography.h3)
                                    .foregroundColor(Theme.textPrimary)

                                bulletPoint("Use Ethica at your own risk")
                                bulletPoint("Verify all critical information yourself")
                                bulletPoint("Not hold Ethica liable for any health issues or allergic reactions")
                                bulletPoint("Our Privacy Policy and Terms of Service")
                            }
                            .padding(Spacing.md)
                            .background(Theme.surfaceSecondary)
                            .clipShape(RoundedRectangle(cornerRadius: Spacing.radiusSM))

                            HStack {
                                Button("Privacy Policy") {
                                    showPrivacyPolicy = true
                                }
                                .font(Typography.caption)
                                .foregroundColor(Theme.primary)

                                Spacer()

                                Button("Terms of Service") {
                                    showTermsOfService = true
                                }
                                .font(Typography.caption)
                                .foregroundColor(Theme.primary)
                            }
                            .padding(.horizontal, Spacing.md)

                            // Bottom marker for scroll detection
                            Color.clear
                                .frame(height: 1)
                                .id("bottom")
                                .onAppear {
                                    hasScrolledToBottom = true
                                }
                        }
                        .padding(Spacing.screenHorizontal)
                    }
                    .onAppear {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                            withAnimation {
                                proxy.scrollTo("bottom", anchor: .bottom)
                            }
                        }
                    }
                }

                // Accept button
                VStack(spacing: Spacing.sm) {
                    Button(action: {
                        withAnimation {
                            hasAcceptedDisclaimer = true
                            UserDefaults.standard.set(true, forKey: "hasAcceptedDisclaimer")
                        }
                    }) {
                        HStack {
                            Image(systemName: hasScrolledToBottom ? "checkmark.circle.fill" : "arrow.down.circle.fill")
                            Text(hasScrolledToBottom ? "I Understand & Agree" : "Scroll to Accept")
                        }
                        .font(Typography.h3)
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(Spacing.md)
                        .background(hasScrolledToBottom ? Theme.success : Theme.textMuted)
                        .clipShape(RoundedRectangle(cornerRadius: Spacing.radiusSM))
                    }
                    .disabled(!hasScrolledToBottom)
                    .accessibilityLabel(hasScrolledToBottom ? "Accept disclaimer" : "Scroll down to read the full disclaimer")

                    if !hasScrolledToBottom {
                        Text("Please read the entire disclaimer")
                            .font(Typography.caption)
                            .foregroundColor(Theme.textTertiary)
                    }
                }
                .padding(Spacing.md)
                .background(Theme.backgroundPrimary)
            }
        }
        .sheet(isPresented: $showPrivacyPolicy) {
            PrivacyPolicyView()
                .premiumSheet()
        }
        .sheet(isPresented: $showTermsOfService) {
            TermsOfServiceView()
                .premiumSheet()
        }
    }

    private func disclaimerSection(icon: String, title: String, text: String) -> some View {
        HStack(alignment: .top, spacing: Spacing.sm) {
            Image(systemName: icon)
                .font(Typography.h2)
                .foregroundColor(Theme.warning)
                .frame(width: 30)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: Spacing.xs) {
                Text(title)
                    .font(Typography.h3)
                    .foregroundColor(Theme.textPrimary)

                Text(text)
                    .font(Typography.body)
                    .foregroundColor(Theme.textSecondary)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private func bulletPoint(_ text: String) -> some View {
        HStack(alignment: .top, spacing: Spacing.sm) {
            Text("•")
                .font(Typography.body)
                .foregroundColor(Theme.textTertiary)
            Text(text)
                .font(Typography.body)
                .foregroundColor(Theme.textSecondary)
        }
    }
}

#Preview {
    DisclaimerView(hasAcceptedDisclaimer: .constant(false))
}
