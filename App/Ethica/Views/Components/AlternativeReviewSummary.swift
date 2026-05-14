//
//  AlternativeReviewSummary.swift
//  Ethica
//
//  Compact review summary for alternative cards
//

import SwiftUI

struct AlternativeReviewSummary: View {
    let productName: String
    @State private var reviewSummary: ProductReviewSummary?
    @State private var isLoading = true

    var body: some View {
        Group {
            if isLoading {
                HStack {
                    ProgressView()
                        .tint(Theme.textSecondary)
                        .scaleEffect(0.7)
                    Text("Loading reviews...")
                        .font(.caption)
                        .foregroundColor(Theme.textSecondary)
                }
                .padding(.vertical, 8)
            } else if let summary = reviewSummary, summary.totalReviews > 0 {
                HStack(spacing: 12) {
                    // Star rating
                    HStack(spacing: 2) {
                        ForEach(1...5, id: \.self) { star in
                            Image(systemName: Double(star) <= summary.averageRating ? "star.fill" : "star")
                                .font(.system(size: 12))
                                .foregroundColor(Double(star) <= summary.averageRating ? Theme.warning : Theme.textMuted)
                        }
                    }

                    // Average rating
                    Text(summary.formattedAverageRating)
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(.white)

                    // Review count
                    Text("(\(summary.totalReviews) \(summary.totalReviews == 1 ? "review" : "reviews"))")
                        .font(.caption)
                        .foregroundColor(Theme.textSecondary)

                    Spacer()

                    // Write review button
                    Image(systemName: "pencil.circle.fill")
                        .font(.system(size: 16))
                        .foregroundColor(Theme.primary)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Theme.warning.opacity(0.08))
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(Theme.warning.opacity(0.2), lineWidth: 1)
                        )
                )
            }
        }
        .onAppear {
            loadReviewSummary()
        }
    }

    private func loadReviewSummary() {
        isLoading = true

        Task {
            do {
                let summary = try await ReviewService.shared.getReviewSummary(productName: productName)
                await MainActor.run {
                    self.reviewSummary = summary
                    self.isLoading = false
                }
            } catch {
                AppLogger.error("❌ Error loading review summary: \(error)")
                await MainActor.run {
                    self.isLoading = false
                }
            }
        }
    }
}

// MARK: - Preview

struct AlternativeReviewSummary_Previews: PreviewProvider {
    static var previews: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            VStack(spacing: 16) {
                AlternativeReviewSummary(productName: "Beyond Burger")
                    .padding()
            }
        }
    }
}
