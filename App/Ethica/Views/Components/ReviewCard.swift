//
//  ReviewCard.swift
//  Ethica
//
//  Component to display a single product review
//

import SwiftUI

struct ReviewCard: View {
    let review: ProductReview
    @State private var userVote: Bool? = nil
    @State private var helpfulCount: Int
    @State private var notHelpfulCount: Int

    init(review: ProductReview) {
        self.review = review
        self._helpfulCount = State(initialValue: review.helpfulCount)
        self._notHelpfulCount = State(initialValue: review.notHelpfulCount)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header: User name + timestamp
            HStack {
                if let userName = review.userName {
                    Text(userName)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.white)
                } else {
                    Text("Anonymous")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(Theme.textSecondary)
                }

                Spacer()

                Text(review.formattedTimestamp)
                    .font(.caption)
                    .foregroundColor(Theme.textSecondary)
            }

            // Overall Rating
            HStack(spacing: 4) {
                ForEach(1...5, id: \.self) { star in
                    Image(systemName: Double(star) <= review.rating ? "star.fill" : "star")
                        .font(.system(size: 14))
                        .foregroundColor(Double(star) <= review.rating ? Theme.warning : Theme.textMuted)
                }

                Text(String(format: "%.1f", review.rating))
                    .font(.caption)
                    .foregroundColor(Theme.textSecondary)
                    .padding(.leading, 4)
            }

            // Review Text
            if let reviewText = review.review, !reviewText.isEmpty {
                Text(reviewText)
                    .font(.system(size: 14))
                    .foregroundColor(Theme.textPrimary)
                    .lineLimit(nil)
            }

            // Detailed Ratings
            if review.tasteRating != nil || review.valueRating != nil || review.availabilityRating != nil {
                VStack(spacing: 6) {
                    if let taste = review.tasteRating {
                        DetailedRatingRow(label: "Taste", rating: taste)
                    }

                    if let value = review.valueRating {
                        DetailedRatingRow(label: "Value", rating: value)
                    }

                    if let availability = review.availabilityRating {
                        DetailedRatingRow(label: "Availability", rating: availability)
                    }
                }
                .padding(.top, 4)
            }

            // Alternative Badge
            if review.isAlternative, let original = review.originalProduct {
                HStack(spacing: 4) {
                    Image(systemName: "arrow.triangle.branch")
                        .font(.caption2)
                    Text("Alternative to \(original)")
                        .font(.caption2)
                }
                .foregroundColor(Theme.primary)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Theme.primary.opacity(0.1))
                )
            }

            // Helpful Votes
            HStack(spacing: 16) {
                Text("Was this review helpful?")
                    .font(.caption)
                    .foregroundColor(Theme.textSecondary)

                Spacer()

                HStack(spacing: 12) {
                    // Helpful button
                    Button(action: { voteHelpful(true) }) {
                        HStack(spacing: 4) {
                            Image(systemName: userVote == true ? "hand.thumbsup.fill" : "hand.thumbsup")
                                .font(.caption)
                            Text("\(helpfulCount)")
                                .font(.caption)
                        }
                        .foregroundColor(userVote == true ? Theme.success : Theme.textSecondary)
                    }

                    // Not helpful button
                    Button(action: { voteHelpful(false) }) {
                        HStack(spacing: 4) {
                            Image(systemName: userVote == false ? "hand.thumbsdown.fill" : "hand.thumbsdown")
                                .font(.caption)
                            Text("\(notHelpfulCount)")
                                .font(.caption)
                        }
                        .foregroundColor(userVote == false ? Theme.error : Theme.textSecondary)
                    }
                }
            }
            .padding(.top, 4)
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Theme.surfaceBase)
        )
        .onAppear {
            loadUserVote()
        }
    }

    // MARK: - Helper Views

    @ViewBuilder
    func DetailedRatingRow(label: String, rating: Double) -> some View {
        HStack(spacing: 8) {
            Text(label)
                .font(.caption)
                .foregroundColor(Theme.textSecondary)
                .frame(width: 80, alignment: .leading)

            HStack(spacing: 2) {
                ForEach(1...5, id: \.self) { star in
                    Image(systemName: Double(star) <= rating ? "star.fill" : "star")
                        .font(.system(size: 10))
                        .foregroundColor(Double(star) <= rating ? Theme.warning : Theme.textMuted)
                }
            }

            Text(String(format: "%.1f", rating))
                .font(.caption2)
                .foregroundColor(Theme.textSecondary)
        }
    }

    // MARK: - Actions

    private func loadUserVote() {
        userVote = try? ReviewService.shared.getUserVote(reviewId: review.id)
    }

    private func voteHelpful(_ isHelpful: Bool) {
        Task {
            do {
                // If clicking the same vote, it will toggle off
                let previousVote = userVote

                if previousVote == isHelpful {
                    // Toggle off
                    userVote = nil
                    if isHelpful {
                        helpfulCount -= 1
                    } else {
                        notHelpfulCount -= 1
                    }
                } else if previousVote != nil {
                    // Switching vote
                    userVote = isHelpful
                    if isHelpful {
                        helpfulCount += 1
                        notHelpfulCount -= 1
                    } else {
                        helpfulCount -= 1
                        notHelpfulCount += 1
                    }
                } else {
                    // New vote
                    userVote = isHelpful
                    if isHelpful {
                        helpfulCount += 1
                    } else {
                        notHelpfulCount += 1
                    }
                }

                try await ReviewService.shared.voteOnReview(reviewId: review.id, isHelpful: isHelpful)
            } catch {
                AppLogger.error("❌ Error voting on review: \(error)")
            }
        }
    }
}

// MARK: - Review Summary Component

struct ReviewSummaryCard: View {
    let summary: ProductReviewSummary
    @State private var showAllReviews = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Header
            HStack {
                Image(systemName: "star.bubble.fill")
                    .font(.system(size: 18))
                    .foregroundColor(Theme.warning)
                Text("Customer Reviews")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundColor(.white)
                Spacer()
            }

            if summary.totalReviews > 0 {
                // Overall Rating
                HStack(spacing: 16) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(summary.formattedAverageRating)
                            .font(.system(size: 48, weight: .bold))
                            .foregroundColor(.white)

                        HStack(spacing: 4) {
                            ForEach(1...5, id: \.self) { star in
                                Image(systemName: Double(star) <= summary.averageRating ? "star.fill" : "star")
                                    .font(.system(size: 16))
                                    .foregroundColor(Double(star) <= summary.averageRating ? Theme.warning : Theme.textMuted)
                            }
                        }

                        Text("\(summary.totalReviews) reviews")
                            .font(.caption)
                            .foregroundColor(Theme.textSecondary)
                    }

                    Spacer()

                    // Rating distribution
                    VStack(alignment: .trailing, spacing: 4) {
                        ForEach([5, 4, 3, 2, 1], id: \.self) { stars in
                            HStack(spacing: 8) {
                                Text("\(stars)★")
                                    .font(.caption2)
                                    .foregroundColor(Theme.textSecondary)

                                GeometryReader { geometry in
                                    ZStack(alignment: .leading) {
                                        RoundedRectangle(cornerRadius: 2)
                                            .fill(Theme.textMuted.opacity(0.2))
                                            .frame(height: 4)

                                        RoundedRectangle(cornerRadius: 2)
                                            .fill(Theme.warning)
                                            .frame(
                                                width: geometry.size.width * CGFloat((summary.ratingPercentages[stars] ?? 0) / 100),
                                                height: 4
                                            )
                                    }
                                }
                                .frame(width: 80, height: 4)

                                Text("\(Int(summary.ratingPercentages[stars] ?? 0))%")
                                    .font(.caption2)
                                    .foregroundColor(Theme.textSecondary)
                                    .frame(width: 30, alignment: .trailing)
                            }
                        }
                    }
                }

                // Detailed Ratings Averages
                if summary.averageTasteRating != nil || summary.averageValueRating != nil || summary.averageAvailabilityRating != nil {
                    VStack(spacing: 8) {
                        if let taste = summary.averageTasteRating {
                            DetailedAverageRow(label: "Taste", rating: taste)
                        }

                        if let value = summary.averageValueRating {
                            DetailedAverageRow(label: "Value", rating: value)
                        }

                        if let availability = summary.averageAvailabilityRating {
                            DetailedAverageRow(label: "Availability", rating: availability)
                        }
                    }
                    .padding(.top, 8)
                }

                // Top Reviews
                if !summary.topReviews.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Top Reviews")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(.white)
                            .padding(.top, 8)

                        ForEach(summary.topReviews.prefix(showAllReviews ? 10 : 3)) { review in
                            ReviewCard(review: review)
                        }

                        if summary.topReviews.count > 3 {
                            Button(action: { showAllReviews.toggle() }) {
                                Text(showAllReviews ? "Show Less" : "Show All \(summary.totalReviews) Reviews")
                                    .font(.caption)
                                    .foregroundColor(Theme.primary)
                            }
                        }
                    }
                }
            } else {
                Text("No reviews yet. Be the first to review!")
                    .font(.subheadline)
                    .foregroundColor(Theme.textSecondary)
                    .padding(.vertical, 8)
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Theme.primary.opacity(0.08))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Theme.primary.opacity(0.2), lineWidth: 1)
                )
        )
    }

    @ViewBuilder
    func DetailedAverageRow(label: String, rating: Double) -> some View {
        HStack(spacing: 12) {
            Text(label)
                .font(.caption)
                .foregroundColor(Theme.textSecondary)
                .frame(width: 80, alignment: .leading)

            HStack(spacing: 3) {
                ForEach(1...5, id: \.self) { star in
                    Image(systemName: Double(star) <= rating ? "star.fill" : "star")
                        .font(.system(size: 12))
                        .foregroundColor(Double(star) <= rating ? Theme.warning : Theme.textMuted)
                }
            }

            Text(String(format: "%.1f", rating))
                .font(.caption)
                .foregroundColor(.white)
        }
    }
}

// MARK: - Preview

struct ReviewCard_Previews: PreviewProvider {
    static var previews: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            VStack(spacing: 16) {
                ReviewCard(review: ProductReview(
                    id: "1",
                    productName: "Beyond Burger",
                    productBrand: "Beyond Meat",
                    barcode: nil,
                    userId: "user_1",
                    userName: "Sarah J.",
                    rating: 5.0,
                    review: "Absolutely love this! Tastes just like real meat but better for the environment. Highly recommend!",
                    timestamp: Date().addingTimeInterval(-86400 * 2),
                    isAlternative: true,
                    originalProduct: "Beef Burger",
                    helpfulCount: 24,
                    notHelpfulCount: 2,
                    tasteRating: 5.0,
                    valueRating: 4.0,
                    availabilityRating: 4.0
                ))

                ReviewCard(review: ProductReview(
                    id: "2",
                    productName: "Beyond Burger",
                    productBrand: "Beyond Meat",
                    barcode: nil,
                    userId: "user_2",
                    userName: "Mike R.",
                    rating: 4.0,
                    review: "Pretty good, but a bit pricey.",
                    timestamp: Date().addingTimeInterval(-86400 * 5),
                    isAlternative: false,
                    originalProduct: nil,
                    helpfulCount: 8,
                    notHelpfulCount: 1,
                    tasteRating: nil,
                    valueRating: 3.0,
                    availabilityRating: nil
                ))
            }
            .padding()
        }
    }
}
