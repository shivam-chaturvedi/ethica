//
//  ReportIssueView.swift
//  Ethica
//
//  Allow users to report incorrect AI analysis
//

import SwiftUI

struct ReportIssueView: View {
    let analysisResult: AnalysisResult
    @Environment(\.dismiss) var dismiss
    @State private var selectedIssueType: IssueType = .other
    @State private var description = ""
    @State private var expectedValue = ""
    @State private var isSubmitting = false
    @State private var showSuccess = false
    @State private var errorMessage: String?

    enum IssueType: String, CaseIterable, Identifiable {
        case allergenMissed = "Missed an allergen"
        case allergenFalsePositive = "Flagged allergen incorrectly"
        case dietaryWrong = "Dietary compatibility incorrect"
        case co2Wrong = "CO2/environmental data wrong"
        case healthScoreWrong = "Health score seems off"
        case alternativesIrrelevant = "Alternatives not helpful"
        case other = "Other issue"

        var id: String { self.rawValue }

        var icon: String {
            switch self {
            case .allergenMissed: return "exclamationmark.triangle.fill"
            case .allergenFalsePositive: return "xmark.circle.fill"
            case .dietaryWrong: return "leaf.circle.fill"
            case .co2Wrong: return "cloud.fill"
            case .healthScoreWrong: return "heart.fill"
            case .alternativesIrrelevant: return "arrow.triangle.2.circlepath"
            case .other: return "questionmark.circle.fill"
            }
        }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.backgroundPrimary
                    .ignoresSafeArea()

                ScrollView {
                    VStack(spacing: Spacing.lg) {
                        // Issue Type Section
                        VStack(alignment: .leading, spacing: Spacing.sm) {
                            Text("What's wrong with this analysis?")
                                .font(Typography.h3)
                                .foregroundColor(Theme.textPrimary)

                            VStack(spacing: Spacing.xs) {
                                ForEach(IssueType.allCases) { type in
                                    Button {
                                        selectedIssueType = type
                                        HapticManager.shared.trigger(.selectionChanged)
                                    } label: {
                                        HStack(spacing: Spacing.sm) {
                                            Image(systemName: type.icon)
                                                .font(.system(size: 16))
                                                .foregroundColor(selectedIssueType == type ? Theme.primary : Theme.textMuted)
                                                .frame(width: 24)

                                            Text(type.rawValue)
                                                .font(Typography.body)
                                                .foregroundColor(selectedIssueType == type ? Theme.textPrimary : Theme.textSecondary)

                                            Spacer()

                                            if selectedIssueType == type {
                                                Image(systemName: "checkmark.circle.fill")
                                                    .foregroundColor(Theme.primary)
                                            }
                                        }
                                        .padding(Spacing.sm)
                                        .background(
                                            RoundedRectangle(cornerRadius: Spacing.radiusXS)
                                                .fill(selectedIssueType == type ? Theme.primary.opacity(0.1) : Theme.surfaceSecondary)
                                        )
                                        .overlay(
                                            RoundedRectangle(cornerRadius: Spacing.radiusXS)
                                                .strokeBorder(selectedIssueType == type ? Theme.primary.opacity(0.3) : Color.clear, lineWidth: 1)
                                        )
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                        .padding(Spacing.cardPadding)
                        .background(Theme.surfaceBase)
                        .clipShape(RoundedRectangle(cornerRadius: Spacing.radiusMD))

                        // Description Section
                        VStack(alignment: .leading, spacing: Spacing.sm) {
                            Text("Description")
                                .font(Typography.h3)
                                .foregroundColor(Theme.textPrimary)

                            ZStack(alignment: .topLeading) {
                                TextEditor(text: $description)
                                    .font(Typography.body)
                                    .foregroundColor(Theme.textPrimary)
                                    .scrollContentBackground(.hidden)
                                    .frame(minHeight: 100)

                                if description.isEmpty {
                                    Text("Example: 'This product contains milk but wasn't flagged for dairy allergy'")
                                        .font(Typography.body)
                                        .foregroundColor(Theme.textMuted)
                                        .padding(.top, 8)
                                        .padding(.leading, 5)
                                        .allowsHitTesting(false)
                                }
                            }
                            .padding(Spacing.sm)
                            .background(Theme.surfaceSecondary)
                            .clipShape(RoundedRectangle(cornerRadius: Spacing.radiusXS))

                            Text("Please provide as much detail as possible to help us improve.")
                                .font(Typography.caption)
                                .foregroundColor(Theme.textTertiary)
                        }
                        .padding(Spacing.cardPadding)
                        .background(Theme.surfaceBase)
                        .clipShape(RoundedRectangle(cornerRadius: Spacing.radiusMD))

                        // Expected Value Section
                        VStack(alignment: .leading, spacing: Spacing.sm) {
                            Text("What did you expect? (Optional)")
                                .font(Typography.h3)
                                .foregroundColor(Theme.textPrimary)

                            TextField("Example: Should be marked as 'Not Vegan'", text: $expectedValue)
                                .font(Typography.body)
                                .foregroundColor(Theme.textPrimary)
                                .padding(Spacing.sm)
                                .background(Theme.surfaceSecondary)
                                .clipShape(RoundedRectangle(cornerRadius: Spacing.radiusXS))

                            Text("Help us understand what the correct result should be.")
                                .font(Typography.caption)
                                .foregroundColor(Theme.textTertiary)
                        }
                        .padding(Spacing.cardPadding)
                        .background(Theme.surfaceBase)
                        .clipShape(RoundedRectangle(cornerRadius: Spacing.radiusMD))

                        // Product Info Section
                        VStack(alignment: .leading, spacing: Spacing.sm) {
                            Text("Product Info")
                                .font(Typography.h3)
                                .foregroundColor(Theme.textPrimary)

                            HStack {
                                Text("Product")
                                    .foregroundColor(Theme.textSecondary)
                                Spacer()
                                Text(analysisResult.productName)
                                    .foregroundColor(Theme.textTertiary)
                            }
                            .font(Typography.body)

                            if let barcode = analysisResult.sourceBarcode {
                                HStack {
                                    Text("Barcode")
                                        .foregroundColor(Theme.textSecondary)
                                    Spacer()
                                    Text(barcode)
                                        .font(.system(.caption, design: .monospaced))
                                        .foregroundColor(Theme.textTertiary)
                                }
                            }
                        }
                        .padding(Spacing.cardPadding)
                        .background(Theme.surfaceBase)
                        .clipShape(RoundedRectangle(cornerRadius: Spacing.radiusMD))

                        // Error Message
                        if let error = errorMessage {
                            Text(error)
                                .font(Typography.body)
                                .foregroundColor(Theme.error)
                                .padding(Spacing.cardPadding)
                                .background(Theme.error.opacity(0.1))
                                .clipShape(RoundedRectangle(cornerRadius: Spacing.radiusSM))
                        }

                        // Submit Button
                        Button(action: {
                            submitReport()
                        }) {
                            HStack(spacing: Spacing.sm) {
                                if isSubmitting {
                                    ProgressView()
                                        .tint(.white)
                                } else {
                                    Image(systemName: "paperplane.fill")
                                }
                                Text(isSubmitting ? "Submitting..." : "Submit Report")
                                    .font(Typography.h3)
                            }
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding(Spacing.md)
                            .background(
                                RoundedRectangle(cornerRadius: Spacing.radiusSM)
                                    .fill(description.isEmpty || isSubmitting ? Theme.textMuted : Theme.primary)
                            )
                        }
                        .disabled(description.isEmpty || isSubmitting)
                    }
                    .padding(Spacing.screenHorizontal)
                    .padding(.top, Spacing.md)
                }
            }
            .navigationTitle("Report Issue")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                    .foregroundColor(Theme.primary)
                }
            }
            .alert("Thank You!", isPresented: $showSuccess) {
                Button("OK") {
                    dismiss()
                }
            } message: {
                Text("Your report has been submitted. We'll review it to improve our accuracy.")
            }
        }
    }

    private func submitReport() {
        isSubmitting = true
        errorMessage = nil

        Task {
            do {
                // Save to Supabase instead
                if let accessToken = AuthenticationService.shared.authToken, !accessToken.isEmpty {
                    let userId = AuthenticationService.shared.currentUserId
                    let supabasePayload: [String: Any] = [
                        "user_id": userId as Any,
                        "barcode": analysisResult.sourceBarcode as Any,
                        "product_name": analysisResult.productName,
                        "issue_type": issueTypeToBackend(selectedIssueType),
                        "description": description,
                        "expected": expectedValue.isEmpty ? nil as Any? : expectedValue,
                        "actual": (analysisResult.isSafe ? "Safe" : "Not Safe") + " - " + analysisResult.detectedAllergens.joined(separator: ", "),
                        "created_at": ISO8601DateFormatter().string(from: Date())
                    ]
                    try await SupabaseAPI.shared.insertRow(accessToken: accessToken, table: "issue_reports", payload: supabasePayload)
                }

                await MainActor.run {
                    isSubmitting = false
                    showSuccess = true
                }

            } catch {
                await MainActor.run {
                    isSubmitting = false
                    if let message = UserFacingError.message(from: error) {
                        errorMessage = "Failed to submit report: \(message)"
                    } else {
                        errorMessage = nil
                    }
                }
            }
        }
    }

    private func issueTypeToBackend(_ type: IssueType) -> String {
        switch type {
        case .allergenMissed: return "allergen_missed"
        case .allergenFalsePositive: return "allergen_false_positive"
        case .dietaryWrong: return "dietary_wrong"
        case .co2Wrong: return "co2_wrong"
        case .healthScoreWrong: return "health_score_wrong"
        case .alternativesIrrelevant: return "alternatives_irrelevant"
        case .other: return "other"
        }
    }
}

// Preview disabled: AnalysisResult.sample not available
// #Preview {
//     ReportIssueView(analysisResult: AnalysisResult.sample)
// }
