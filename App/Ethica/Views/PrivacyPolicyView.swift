//
//  PrivacyPolicyView.swift
//  Ethica
//
//  Privacy Policy for App Store compliance
//

import SwiftUI

struct PrivacyPolicyView: View {
    @Environment(\.dismiss) var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Text("Privacy Policy")
                        .font(.largeTitle)
                        .fontWeight(.bold)
                        .padding(.bottom, 10)

                    Text("Last Updated: \(formattedDate())")
                        .font(.caption)
                        .foregroundColor(Theme.textSecondary)

                    Group {
                        sectionHeader("1. Information We Collect")
                        sectionText("""
                        Ethica collects the following information to provide our service:

                        • Product Photos: Images you scan are sent to our servers for analysis and then deleted within 24 hours
                        • Scan History: Products you've scanned, stored locally on your device
                        • Preferences: Your dietary restrictions and allergen preferences
                        • Usage Data: Anonymous analytics about app usage to improve our service

                        We DO NOT collect:
                        • Personal identification information (name, email, phone)
                        • Location data
                        • Payment information
                        • Contacts or photos unrelated to product scanning
                        """)
                    }

                    Group {
                        sectionHeader("2. How We Use Your Information")
                        sectionText("""
                        We use the information we collect to:

                        • Analyze product ingredients and provide health/environmental insights
                        • Improve AI accuracy through machine learning
                        • Provide personalized recommendations based on your preferences
                        • Monitor app performance and fix bugs

                        We will NEVER:
                        • Sell your data to third parties
                        • Use your images for advertising
                        • Share your scan history with anyone
                        • Track your location or shopping habits
                        """)
                    }

                    Group {
                        sectionHeader("3. Data Storage and Security")
                        sectionText("""
                        • Scan History: Stored locally on your device only
                        • Product Photos: Temporarily stored on secure Google Cloud servers (deleted within 24 hours)
                        • Analysis Results: Cached anonymously for performance (no link to your identity)
                        • Encryption: All data transmission uses HTTPS encryption
                        """)
                    }

                    Group {
                        sectionHeader("4. Third-Party Services")
                        sectionText("""
                        Ethica uses the following third-party services:

                        • Google Cloud Vision: For OCR and image analysis
                        • Google Gemini AI: For ingredient analysis
                        • OpenFoodFacts: For barcode lookup (open database)
                        • Firebase: For authentication and analytics

                        These services have their own privacy policies and may collect anonymous usage data.
                        """)
                    }

                    Group {
                        sectionHeader("5. Your Rights")
                        sectionText("""
                        You have the right to:

                        • Delete your scan history at any time (Settings > Clear History)
                        • Request deletion of any data we've collected about you
                        • Opt out of analytics tracking
                        • Export your scan history

                        To exercise these rights, contact us at: support@ethica-app.com
                        """)
                    }

                    Group {
                        sectionHeader("6. Children's Privacy")
                        sectionText("""
                        Ethica is not intended for children under 13. We do not knowingly collect information from children under 13. If you believe we have collected information from a child under 13, please contact us immediately.
                        """)
                    }

                    Group {
                        sectionHeader("7. Changes to This Policy")
                        sectionText("""
                        We may update this Privacy Policy from time to time. We will notify you of significant changes through the app or via email if you've provided one.
                        """)
                    }

                    Group {
                        sectionHeader("8. Contact Us")
                        sectionText("""
                        If you have questions about this Privacy Policy, please contact:

                        Email: support@ethica-app.com
                        Address: [Your Company Address]
                        """)
                    }
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

    private func formattedDate() -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .long
        return formatter.string(from: Date())
    }
}

#Preview {
    PrivacyPolicyView()
}
