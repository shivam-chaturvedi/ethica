//
//  TermsOfServiceView.swift
//  Ethica
//
//  Terms of Service for App Store compliance and legal protection
//

import SwiftUI

struct TermsOfServiceView: View {
    @Environment(\.dismiss) var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Text("Terms of Service")
                        .font(.largeTitle)
                        .fontWeight(.bold)
                        .padding(.bottom, 10)

                    Text("Last Updated: \(formattedDate())")
                        .font(.caption)
                        .foregroundColor(Theme.textSecondary)

                    Text("By using Ethica, you agree to these terms. Please read carefully.")
                        .font(.subheadline)
                        .foregroundColor(Theme.textSecondary)
                        .padding(.bottom, 10)

                    Group {
                        sectionHeader("1. Acceptance of Terms")
                        sectionText("""
                        By downloading, installing, or using the Ethica app, you agree to be bound by these Terms of Service. If you do not agree to these terms, do not use the app.
                        """)
                    }

                    Group {
                        sectionHeader("2. Description of Service")
                        sectionText("""
                        Ethica provides:
                        • Product ingredient analysis using AI
                        • Dietary restriction and allergen checking
                        • Environmental impact assessment
                        • Alternative product recommendations
                        • Restaurant menu analysis

                        The service is provided "AS IS" without warranties of any kind.
                        """)
                    }

                    Group {
                        sectionHeader("⚠️ 3. Important Disclaimers")
                        disclaimerBox("""
                        CRITICAL - READ CAREFULLY:

                        • NOT MEDICAL ADVICE: Ethica is an informational tool only. It is NOT a substitute for professional medical, dietary, or nutritional advice.

                        • AI MAY MAKE ERRORS: Our AI analysis may contain mistakes, miss ingredients, or provide incorrect information. ALWAYS verify ingredients yourself if you have severe allergies.

                        • LIFE-THREATENING ALLERGIES: If you have severe, life-threatening allergies (anaphylaxis risk), DO NOT rely solely on Ethica. Always read product labels yourself and consult your doctor.

                        • NO GUARANTEE OF ACCURACY: While we strive for accuracy, we cannot guarantee that our analysis is 100% correct.

                        • DIETARY/RELIGIOUS RESTRICTIONS: Our dietary compatibility checks (Jain, Halal, Kosher, etc.) are automated and may not meet all interpretations or standards. Consult religious authorities for definitive guidance.

                        • ENVIRONMENTAL DATA: CO2 and environmental impact figures are estimates based on scientific averages and may not reflect actual product footprints.

                        USE AT YOUR OWN RISK. Always verify critical information yourself.
                        """)
                    }

                    Group {
                        sectionHeader("4. User Responsibilities")
                        sectionText("""
                        You agree to:
                        • Use Ethica only for personal, non-commercial purposes
                        • Verify critical information (allergens, dietary restrictions) yourself
                        • Not rely solely on Ethica for medical or health decisions
                        • Consult a doctor or dietitian for medical advice
                        • Report inaccurate results to help us improve
                        • Not abuse the service or attempt to overload our servers
                        • Not reverse-engineer or copy our technology
                        """)
                    }

                    Group {
                        sectionHeader("5. Limitation of Liability")
                        sectionText("""
                        TO THE MAXIMUM EXTENT PERMITTED BY LAW:

                        • We are NOT liable for allergic reactions, health issues, or any harm resulting from use of Ethica
                        • We are NOT liable for inaccurate product information
                        • We are NOT liable for decisions made based on our recommendations
                        • Our total liability is limited to the amount you paid for the app (if any)

                        You use Ethica at your own risk.
                        """)
                    }

                    Group {
                        sectionHeader("6. Product Information Sources")
                        sectionText("""
                        Ethica aggregates data from:
                        • OpenFoodFacts (community database)
                        • UPC Item Database
                        • Google Vision AI
                        • Google Gemini AI
                        • User-submitted photos

                        We are not responsible for errors in third-party databases.
                        """)
                    }

                    Group {
                        sectionHeader("7. Intellectual Property")
                        sectionText("""
                        • Ethica's software, design, and algorithms are proprietary
                        • Product photos you scan remain your property
                        • You grant us a license to process your photos for analysis
                        • You may not copy, modify, or redistribute our software
                        """)
                    }

                    Group {
                        sectionHeader("8. Termination")
                        sectionText("""
                        We may terminate or suspend your access to Ethica at any time if you:
                        • Violate these terms
                        • Abuse the service (excessive API calls, hacking attempts)
                        • Engage in illegal activity

                        You may stop using Ethica at any time by deleting the app.
                        """)
                    }

                    Group {
                        sectionHeader("9. Changes to Terms")
                        sectionText("""
                        We may update these Terms of Service at any time. Continued use of Ethica after changes means you accept the new terms. We will notify you of significant changes through the app.
                        """)
                    }

                    Group {
                        sectionHeader("10. Governing Law")
                        sectionText("""
                        These terms are governed by the laws of [Your Jurisdiction]. Any disputes will be resolved in the courts of [Your Jurisdiction].
                        """)
                    }

                    Group {
                        sectionHeader("11. Contact")
                        sectionText("""
                        Questions about these terms? Contact us:

                        Email: support@ethica-app.com
                        Address: [Your Company Address]
                        """)
                    }

                    Text("By continuing to use Ethica, you acknowledge that you have read, understood, and agree to these Terms of Service.")
                        .font(.footnote)
                        .foregroundColor(Theme.textSecondary)
                        .padding(.top, 20)
                        .padding(.bottom, 40)
                }
                .padding()
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }

    private func sectionHeader(_ text: String) -> some View {
        Text(text)
            .font(.headline)
            .fontWeight(.semibold)
            .padding(.top, 10)
    }

    private func sectionText(_ text: String) -> some View {
        Text(text)
            .font(.body)
            .foregroundColor(Theme.textPrimary)
    }

    private func disclaimerBox(_ text: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(text)
                .font(.body)
                .foregroundColor(Theme.textPrimary)
        }
        .padding()
        .background(Theme.error.opacity(0.1))
        .cornerRadius(10)
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Theme.error.opacity(0.3), lineWidth: 2)
        )
    }

    private func formattedDate() -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .long
        return formatter.string(from: Date())
    }
}

#Preview {
    TermsOfServiceView()
}
